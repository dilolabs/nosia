require "test_helper"

class AgentSkills::BaseTest < ActiveSupport::TestCase
  class TestSkill < AgentSkills::Base
    def call
      "test result"
    end
  end

  class MockChat
    attr_reader :user, :account
    def initialize(user:, account:)
      @user = user
      @account = account
    end
    def ask(*)
      "mock response"
    end
    def with_instructions(*, **, &)
      yield if block_given?
    end
  end

  class MockAgentSkill
    attr_reader :requires_rag_context, :name
    def initialize(requires_rag_context: false, name: "test-skill")
      @requires_rag_context = requires_rag_context
      @name = name
    end
  end

  def setup
    @user = User.create!(email: "test3@example.com", password: "testpassword123")
    @account = Account.create!(name: "Test Account 3", owner: @user)
    ActsAsTenant.current_tenant = @account
    @chat = MockChat.new(user: @user, account: @account)
    @agent_skill = MockAgentSkill.new
  end

  test "validates context on initialization" do
    assert_raises(ArgumentError) { TestSkill.new({}) }
  end

  test "validates call method exists" do
    skill = TestSkill.new(chat: @chat, query: "test", agent_skill: @agent_skill)
    assert_equal "test result", skill.call
  end

  test "class validation works" do
    assert AgentSkills::DocumentSummarizer.validate! == true
  end

  test "accesses chat methods through whitelist" do
    skill = TestSkill.new(chat: @chat, query: "test", agent_skill: @agent_skill)
    assert_respond_to skill, :ask
  end

  test "blocks non-whitelisted methods" do
    skill = TestSkill.new(chat: @chat, query: "test", agent_skill: @agent_skill)
    assert_raises(NoMethodError) { skill.some_unknown_method }
  end
end
