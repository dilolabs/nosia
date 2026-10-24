require_relative "account_experience_fixtures"

module DashboardFixtures
  extend ActiveSupport::Concern
  include AccountExperienceFixtures

  included do
    setup do
      @report_time = Time.utc(2026, 10, 24, 12)
      ActiveRecord::FixtureSet.reset_cache
      @dashboard_sets = ActiveRecord::FixtureSet.create_fixtures(
        Rails.root.join("test/support/fixtures/dashboard").to_s, [ "token_usages" ]
      ).index_by(&:name)
      @first.update_columns(input_tokens_count: 17, output_tokens_count: 3)
      @second.update_columns(input_tokens_count: 942, output_tokens_count: 103)
      clear_enqueued_jobs
    end
  end

  def dashboard_usage(name)
    @dashboard_sets.fetch("token_usages").fixtures.fetch(name.to_s).find
  end
end
