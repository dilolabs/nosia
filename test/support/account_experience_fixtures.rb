require "active_job/test_helper"
require "active_storage/fixture_set"

module AccountExperienceFixtures
  extend ActiveSupport::Concern
  include ActiveJob::TestHelper

  PASSWORD = "account-experience-password-123".freeze
  TABLES = %w[users accounts account_users ruby_llm_models chats messages documents texts qnas websites prompts api_tokens token_usages active_storage_blobs active_storage_attachments].freeze

  included do
    setup do
      @previous_tenant = ActsAsTenant.current_tenant
      @previous_adapter = ActiveJob::Base.queue_adapter
      ActsAsTenant.current_tenant = nil
      ActiveJob::Base.queue_adapter = :test
      ActiveRecord::FixtureSet.reset_cache
      @experience_sets = ActiveRecord::FixtureSet.create_fixtures(
        Rails.root.join("test/support/fixtures/account_experience").to_s, TABLES,
        { "ruby_llm_models" => "RubyLLM::ActiveRecord::Model", "active_storage_blobs" => "ActiveStorage::Blob", "active_storage_attachments" => "ActiveStorage::Attachment" }
      ).index_by(&:name)
      @user = experience(:users, :overview_owner)
      @member = experience(:users, :overview_member)
      @first = experience(:accounts, :overview_first)
      @second = experience(:accounts, :overview_second)
      @foreign = experience(:accounts, :overview_foreign)
      @empty = experience(:accounts, :overview_empty)
      clear_enqueued_jobs
    end

    teardown do
      clear_enqueued_jobs
      ActiveJob::Base.queue_adapter = @previous_adapter
      ActsAsTenant.current_tenant = @previous_tenant
      Current.reset
      ActiveRecord::FixtureSet.reset_cache
    end
  end

  def experience(table, name)
    @experience_sets.fetch(table.to_s).fixtures.fetch(name.to_s).find
  end

  def sign_in_overview(user = @user)
    delete logout_url if cookies[:session_id]
    post login_url, params: { email: user.email, password: PASSWORD }
    assert_response :redirect
  end
end
