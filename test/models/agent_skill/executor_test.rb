require "test_helper"

class AgentSkill::ExecutorTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "ae@example.com", password: "testpassword123")
    @account = Account.create!(name: "AE Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
    @skill = @account.agent_skills.create!(name: "summarize", execution_mode: "llm",
                                           trigger_mode: "explicit", skill_content: "summarize",
                                           enabled: true)
  end

  test "LLM executor records an agent_skill TokenUsage from the returned message" do
    model = Model.create!(model_id: "glm-5.2", name: "GLM 5.2", provider: "openai")
    fake_message = @chat.messages.create!(role: :assistant, content: "ok",
                                          input_tokens: 200, output_tokens: 80, model: model)

    # Fake the chat's LLM interaction with plain-Ruby singleton methods (no mock lib).
    def @chat.with_instructions(*); self; end
    def @chat.ask(*); @fake_ask_result; end
    @chat.instance_variable_set(:@fake_ask_result, fake_message)

    context = { chat: @chat, user: @user, account: @account, query: "q",
                agent_skill: @skill, options: {} }

    assert_difference -> { TokenUsage.where(kind: "agent_skill").count }, 1 do
      AgentSkill::Executor.execute(@skill, context:)
    end

    usage = TokenUsage.find_by(kind: "agent_skill")
    assert_equal @chat.id, usage.chat_id
    assert_equal "glm-5.2", usage.model_id
    assert_equal 200, usage.input_tokens
    assert_equal 80, usage.output_tokens
    assert_kind_of AgentSkillExecution, usage.source
  end
end