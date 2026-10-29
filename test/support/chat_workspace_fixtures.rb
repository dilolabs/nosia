require_relative "chat_account_fixtures"

module ChatWorkspaceFixtures
  extend ActiveSupport::Concern
  include ChatAccountFixtures

  included do
    setup do
      ActiveRecord::FixtureSet.reset_cache
      @workspace_sets = ActiveRecord::FixtureSet.create_fixtures(
        Rails.root.join("test/support/fixtures/chat_workspace").to_s,
        %w[chats messages token_usages ruby_llm_usages],
        { "ruby_llm_usages" => "RubyLLM::ActiveRecord::Usage" }
      ).index_by(&:name)
      @chat = chats(:picker_second_chat)
      @chat.update_columns(input_tokens_count: 125, output_tokens_count: 24)
    end
  end

  def workspace(table, name)
    @workspace_sets.fetch(table.to_s).fixtures.fetch(name.to_s).find
  end
end
