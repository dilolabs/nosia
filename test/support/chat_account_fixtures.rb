require "active_job/test_helper"

module ChatAccountFixtures
  extend ActiveSupport::Concern
  include ActiveJob::TestHelper

  PASSWORD = "picker-password-123".freeze

  included do
    setup do
      @prior_tenant = ActsAsTenant.current_tenant
      @prior_adapter = ActiveJob::Base.queue_adapter
      ActsAsTenant.current_tenant = nil
      ActiveRecord::FixtureSet.reset_cache
      @picker_fixtures = ActiveRecord::FixtureSet.create_fixtures(
        Rails.root.join("test/support/fixtures/chat_accounts").to_s,
        %w[users accounts account_users ruby_llm_models chats websites texts mcp_servers agent_skills prompts],
        { "ruby_llm_models" => "RubyLLM::ActiveRecord::Model" }
      ).index_by(&:name)
      @user = users(:picker_owner)
      @first = accounts(:picker_first)
      @second = accounts(:picker_second)
      @foreign = accounts(:picker_foreign)
      ActiveJob::Base.queue_adapter = :test
      clear_enqueued_jobs
    end

    teardown do
      ActiveJob::Base.queue_adapter = @prior_adapter
      ActsAsTenant.current_tenant = @prior_tenant
      Current.reset
      ActiveRecord::FixtureSet.reset_cache
    end
  end

  %w[users accounts account_users ruby_llm_models chats websites texts mcp_servers agent_skills prompts].each do |table|
    define_method(table) do |name|
      @picker_fixtures.fetch(table).fixtures.fetch(name.to_s).find
    end
  end

  def sign_in_picker_user(user = @user)
    post login_url, params: { email: user.email, password: PASSWORD }
    assert_response :redirect
  end

  def with_singleton_replacement(object, name, replacement)
    own_method = object.singleton_class.instance_methods(false).include?(name)
    original = object.method(name)
    object.define_singleton_method(name, replacement)
    yield
  ensure
    if own_method
      object.define_singleton_method(name, original)
    else
      object.singleton_class.remove_method(name)
    end
  end

  def insert_picker_chunk(account, source, content, vector)
    result = Chunk.insert_all!([ {
      account_id: account.id,
      chunkable_id: source.id,
      chunkable_type: source.class.name,
      content: content,
      embedding: vector,
      metadata: {},
      created_at: Time.current,
      updated_at: Time.current
    } ])
    account.chunks.find(result.rows.first.first)
  end
end
