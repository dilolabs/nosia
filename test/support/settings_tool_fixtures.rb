require_relative "account_experience_fixtures"

module SettingsToolFixtures
  extend ActiveSupport::Concern
  include AccountExperienceFixtures

  included do
    setup do
      @shared = experience(:prompts, :overview_second_shared)
      @personal = experience(:prompts, :overview_second_personal)
      @own_token = experience(:api_tokens, :overview_second_token)
      @other_token = experience(:api_tokens, :overview_member_token)
      @outsider = experience(:users, :overview_outsider)
      @no_account = experience(:users, :overview_no_account)
    end
  end
end
