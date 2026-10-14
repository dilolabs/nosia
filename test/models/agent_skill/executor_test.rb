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
    fake_message = assistant_with_usage(input_tokens: 200, output_tokens: 80)

    # Fake the chat's LLM interaction with plain-Ruby singleton methods (no mock lib).
    def @chat.with_instructions(*args, **kwargs); self; end
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

  test "LLM executor records normalized tokens and a string model from the returned message" do
    message = assistant_with_usage(input_tokens: 200, output_tokens: 80)
    tokens = Struct.new(:input, :output, :cache_read, :cache_write, :thinking).new(200, 80, 15, 5, 3)
    message.define_singleton_method(:tokens) { tokens }
    message.define_singleton_method(:model) { "glm-5.2" }
    %i[input_tokens output_tokens cached_tokens cache_creation_tokens thinking_tokens].each do |reader|
      message.define_singleton_method(reader) { raise "legacy token reader used" }
    end

    @chat.define_singleton_method(:with_instructions) { |*args, **kwargs| self }
    @chat.define_singleton_method(:ask) { |*| message }
    context = { chat: @chat, user: @user, account: @account, query: "q",
                agent_skill: @skill, options: {} }

    assert_difference -> { TokenUsage.where(kind: "agent_skill").count }, 1 do
      assert_equal message, AgentSkill::Executor.execute(@skill, context:)
    end

    usage = TokenUsage.find_by!(kind: "agent_skill")
    assert_equal @account.id, usage.account_id
    assert_equal @chat.id, usage.chat_id
    assert_equal "glm-5.2", usage.model_id
    assert_equal 200, usage.input_tokens
    assert_equal 80, usage.output_tokens
    assert_equal 15, usage.cached_tokens
    assert_equal 5, usage.cache_creation_tokens
    assert_equal 3, usage.thinking_tokens
    assert_kind_of AgentSkillExecution, usage.source
    assert_equal @skill, usage.source.agent_skill
    assert_equal "completed", usage.source.status
  end

  test "LLM executor records output-only usage with zero default input and optional buckets" do
    message = assistant_with_usage(input_tokens: nil, output_tokens: 80)
    @chat.define_singleton_method(:with_instructions) { |*args, **kwargs| self }
    @chat.define_singleton_method(:ask) { |*| message }
    context = { chat: @chat, user: @user, account: @account, query: "q", agent_skill: @skill, options: {} }

    assert_difference -> { TokenUsage.where(kind: "agent_skill").count }, 1 do
      AgentSkill::Executor.execute(@skill, context:)
    end

    usage = TokenUsage.find_by!(kind: "agent_skill")
    assert_equal [ 0, 80, 0, 0, 0 ], usage.attributes.values_at("input_tokens", "output_tokens", "cached_tokens", "cache_creation_tokens", "thinking_tokens")
  end

  test "LLM executor skips unreported usage and nil messages" do
    @chat.define_singleton_method(:with_instructions) { |*args, **kwargs| self }
    message = @chat.messages.create!(role: :assistant, content: "unreported")
    context = { chat: @chat, user: @user, account: @account, query: "q", agent_skill: @skill, options: {} }

    assert_no_difference -> { TokenUsage.count } do
      @chat.define_singleton_method(:ask) { |*| message }
      AgentSkill::Executor.execute(@skill, context:)
      @chat.define_singleton_method(:ask) { |*| nil }
      AgentSkill::Executor.execute(@skill, context:)
    end
  end

  test "LLM instructions append to the real persisted baseline without replacing it" do
    @chat.with_instructions("Keep this baseline")
    @chat.define_singleton_method(:ask) { |*| nil }
    context = { chat: @chat, user: @user, account: @account, query: "q", agent_skill: @skill }

    AgentSkill::Executor.execute(@skill, context: context)

    instructions = @chat.messages.where(role: :system).map(&:content)
    assert_equal 2, instructions.size
    assert_equal "Keep this baseline", instructions.first
    assert_includes instructions.last, "## Agent Skill: summarize"
  end

  test "Ruby skill allowlists expose provider options rather than the removed params API" do
    calls = []
    @chat.define_singleton_method(:with_provider_options) { |**options| calls << options; self }
    skill = AgentSkills::Base.new(chat: @chat, query: "q", agent_skill: @skill)

    AgentSkill::Executor # Load its nested executors before checking their allowlists.
    assert_includes AgentSkill::RubyExecutor::ALLOWED_CHAT_METHODS, :with_provider_options
    assert_not_includes AgentSkill::RubyExecutor::ALLOWED_CHAT_METHODS, :with_params
    assert_respond_to skill, :with_provider_options
    assert_not skill.respond_to?(:with_params)
    assert_same @chat, skill.with_provider_options(max_tokens: 17, top_p: 0.8, top_k: 6)
    assert_equal [ { max_tokens: 17, top_p: 0.8, top_k: 6 } ], calls
    assert_raises(NoMethodError) { skill.with_params(max_tokens: 17) }
  end

  private
    def assistant_with_usage(**tokens)
      message = @chat.messages.create!(role: :assistant, content: "ok")
      message.ruby_llm_usages.create!(chat: @chat, operation: "chat", provider: "openai", model: "glm-5.2", status: "succeeded", **tokens)
      message.reload
    end
end
