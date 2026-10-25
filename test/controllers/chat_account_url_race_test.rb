require "test_helper"
require "active_job/test_helper"

class ChatAccountUrlRaceTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  # Both connections need committed fixtures and real outer commits/rollbacks.
  self.use_transactional_tests = false
  self.fixture_paths = [ Rails.root.join("test/support/fixtures/chat_accounts") ]
  set_fixture_class ruby_llm_models: "RubyLLM::ActiveRecord::Model"
  fixtures :users, :accounts, :account_users, :ruby_llm_models

  setup do
    @prior_registry_defined = RubyLLM::Models.instance_variable_defined?(:@instance)
    @prior_registry = RubyLLM::Models.instance_variable_get(:@instance)
    @prior_tenant = ActsAsTenant.current_tenant
    @prior_adapter = ActiveJob::Base.queue_adapter
    ActsAsTenant.current_tenant = nil
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    @fixture_users = users(:picker_owner, :picker_outsider, :picker_no_account)
    @fixture_accounts = accounts(:picker_first, :picker_second, :picker_foreign)
    @user = users(:picker_owner)
    @account = accounts(:picker_second)
    @url = "https://chat-url-race.example/page"
    assert_equal "PostgreSQL", Website.connection.adapter_name
    assert_not Website.connection.transaction_open?
  end

  teardown do
    ActsAsTenant.without_tenant do
      @fixture_accounts&.each(&:destroy!)
      @fixture_users&.each(&:destroy!)
      RubyLLM::ActiveRecord::Model.where(id: ruby_llm_models(:picker_model).id).delete_all
    end
  ensure
    begin
      clear_enqueued_jobs
      ActiveRecord::FixtureSet.reset_cache
      ActiveJob::Base.queue_adapter = @prior_adapter
      ActsAsTenant.current_tenant = @prior_tenant
      Current.reset
    ensure
      # RubyLLM has no public registry reset; do not retain its fixture-only catalog.
      if @prior_registry_defined
        RubyLLM::Models.instance_variable_set(:@instance, @prior_registry)
      elsif RubyLLM::Models.instance_variable_defined?(:@instance)
        RubyLLM::Models.remove_instance_variable(:@instance)
      end
    end
  end

  test "concurrent typed URL registration preserves the new chat transaction" do
    post login_url, params: { email: @user.email, password: "picker-password-123" }
    assert_response :redirect

    assert_difference({ -> { Chat.count } => 1, -> { Message.count } => 1,
      -> { @account.websites.count } => 1 }) do
      with_competing_registration do
        post chats_url, params: { chat: { account_id: @account.id,
          prompt: "Compare #{@url}, then #{@url}.", model: "picker-test-model" } }
      end
    end

    chat = @user.chats.sole
    message = chat.messages.sole
    assert_redirected_to chat_url(chat)
    assert_equal @account, chat.account
    assert_equal accounts(:picker_first), @user.first_account
    assert_predicate chat, :generating?
    assert_equal "user", message.role
    assert_equal [ @winner_id.to_s ], message.attached_website_ids
    assert_equal [ @winner_id ], @account.websites.where(url: @url).pluck(:id)
    assert_predicate Website.find(@winner_id), :pending?
    assert_enqueued_jobs 1, only: ChatResponseJob
    assert_enqueued_with job: ChatResponseJob, args: [ chat.id, message.content, message.id ]
    assert_winner_crawl_only
  end

  test "rolling back the race loser chat does not publish another crawl" do
    assert_no_difference [ -> { Chat.count }, -> { Message.count } ] do
      with_competing_registration do
        Chat.transaction do
          chat = @user.chats.create!(account: @account, model: "picker-test-model",
            provider: :openai, assume_model_exists: true)
          message = chat.messages.create!(role: "user", content: @url)
          message.attach_website_sources_from_content!(@account)
          assert_equal [ @winner_id.to_s ], message.reload.attached_website_ids
          assert_winner_crawl_only
          raise ActiveRecord::Rollback
        end
      end
    end

    assert_equal [ @winner_id ], @account.websites.where(url: @url).pluck(:id)
    assert_winner_crawl_only
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "concurrent URL registration also recovers outside an outer transaction" do
    found = nil
    with_competing_registration do
      found = Website.find_or_create_by_url!(@account, @url)
    end

    assert_equal @winner_id, found.id
    assert_equal [ @winner_id ], @account.websites.where(url: @url).pluck(:id)
    assert_winner_crawl_only
  end

  def after_teardown
    super
  ensure
    if instance_variable_defined?(:@prior_registry_defined)
      assert_equal @prior_registry_defined, RubyLLM::Models.instance_variable_defined?(:@instance), "Race fixtures must not initialize the shared registry"
      assert_same @prior_registry, RubyLLM::Models.instance_variable_get(:@instance) if @prior_registry_defined
    end
  end

  private
    def assert_winner_crawl_only
      assert_enqueued_jobs 1, only: CrawlWebsiteUrlJob
      assert_enqueued_with job: CrawlWebsiteUrlJob, args: [ @winner_id ], queue: "background"
    end

    def with_competing_registration
      loser_thread = Thread.current
      loser_pid = Website.connection.select_value("SELECT pg_backend_pid()")
      insert_requested = Queue.new
      insert_finished = Queue.new
      account_id = @account.id
      url = @url
      violations = []
      coordinated = false

      winner = Thread.new do
        Website.connection_pool.with_connection do |connection|
          if insert_requested.pop(timeout: 10) == :insert
            website = Website.find_or_create_by_url!(Account.find(account_id), url)
            insert_finished << [ website.id, connection.select_value("SELECT pg_backend_pid()") ]
          end
        end
      rescue StandardError => error
        insert_finished << error
      ensure
        Current.reset
        ActsAsTenant.current_tenant = nil
      end

      # Observe the real uniqueness validation after its SELECT, but before the
      # loser's INSERT. The other connection commits the winner in that gap.
      observer = lambda do |event|
        next unless Thread.current == loser_thread
        payload = event.payload
        error = payload[:exception_object]
        violations << error.cause if error.is_a?(ActiveRecord::RecordNotUnique)

        if !coordinated && payload[:sql].start_with?('SELECT 1 AS one FROM "websites"') &&
            payload[:binds].any? { |bind| bind.value_for_database == url }
          coordinated = true
          insert_requested << :insert
          result = insert_finished.pop(timeout: 10)
          raise "Timed out waiting for the competing Website insert" unless result
          raise result if result.is_a?(Exception)
          @winner_id, winner_pid = result
          assert_not_equal loser_pid, winner_pid
        end
      end

      ActiveSupport::Notifications.subscribed(observer, "sql.active_record") { yield }
      assert coordinated, "the loser must pass uniqueness validation before the winner inserts"
      assert_equal 1, violations.size, "the database must reject exactly one real duplicate INSERT"
      assert_instance_of PG::UniqueViolation, violations.sole
      assert_not Website.connection.transaction_open?
    ensure
      insert_requested << :stop if winner&.alive?
      if winner && !winner.join(10)
        winner.kill.join
        flunk "Competing Website insert did not terminate"
      end
    end
end
