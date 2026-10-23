require_relative "chat_account_fixtures"

module LocalizationFixtures
  extend ActiveSupport::Concern
  include ChatAccountFixtures

  included do
    setup do
      @localization_fixtures = ActiveRecord::FixtureSet.create_fixtures(
        Rails.root.join("test/support/fixtures/localization").to_s,
        %w[messages token_usages]
      ).index_by(&:name)
    end
  end

  %w[messages token_usages].each do |table|
    define_method(table) do |name|
      @localization_fixtures.fetch(table).fixtures.fetch(name.to_s).find
    end
  end
end
