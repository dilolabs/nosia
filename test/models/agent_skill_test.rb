require "test_helper"

class AgentSkillTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "test5@example.com", password: "testpassword123")
    @account = Account.create!(name: "Test Account 5", owner: @user)
    ActsAsTenant.current_tenant = @account
  end

  test "name validation presence" do
    agent_skill = @account.agent_skills.build(name: nil, execution_mode: "llm", trigger_mode: "explicit")
    assert_not agent_skill.valid?
    assert_includes agent_skill.errors[:name], "can't be blank"
  end

  test "name format validation" do
    agent_skill = @account.agent_skills.build(name: "123invalid", execution_mode: "llm", trigger_mode: "explicit")
    assert_not agent_skill.valid?
    assert agent_skill.errors[:name].any? { |e| e.include?("must start with a letter") }
  end

  test "valid name format" do
    agent_skill = @account.agent_skills.build(name: "valid-name", execution_mode: "llm", trigger_mode: "explicit")
    assert agent_skill.errors[:name].empty?
  end

  test "execution_mode enum" do
    agent_skill = @account.agent_skills.build(name: "test", execution_mode: "llm", trigger_mode: "explicit")
    assert agent_skill.llm?
    agent_skill.execution_mode = "ruby"
    assert agent_skill.ruby?
  end

  test "trigger_mode enum" do
    agent_skill = @account.agent_skills.build(name: "test", execution_mode: "llm", trigger_mode: "explicit")
    assert agent_skill.explicit?
    agent_skill.trigger_mode = "auto"
    assert agent_skill.auto?
    agent_skill.trigger_mode = "combined"
    assert agent_skill.combined?
  end

  test "ruby_class_name generation" do
    agent_skill = @account.agent_skills.build(name: "document_summarizer", execution_mode: "ruby", trigger_mode: "explicit")
    assert_equal "AgentSkills::DocumentSummarizer", agent_skill.ruby_class_name
  end

  test "priority validation" do
    agent_skill = @account.agent_skills.build(name: "test", execution_mode: "llm", trigger_mode: "explicit", priority: 150)
    assert_not agent_skill.valid?
    assert agent_skill.errors[:priority].include?("must be less than or equal to 100")
  end

  test "runnable? for llm mode when enabled" do
    agent_skill = @account.agent_skills.build(name: "test", execution_mode: "llm", trigger_mode: "explicit", enabled: true)
    assert agent_skill.runnable?
  end

  test "runnable? for ruby mode without implementation" do
    agent_skill = @account.agent_skills.build(name: "test", execution_mode: "ruby", trigger_mode: "explicit", enabled: true)
    assert_not agent_skill.runnable?
  end

  test "explicitly_invocable includes explicit and combined enabled skills only" do
    explicit = @account.agent_skills.create!(name: "explicit-skill", execution_mode: "llm", trigger_mode: "explicit", enabled: true, skill_content: "---\nname: explicit-skill\n---\nbody")
    combined = @account.agent_skills.create!(name: "combined-skill", execution_mode: "llm", trigger_mode: "combined", enabled: true, skill_content: "---\nname: combined-skill\n---\nbody")
    @account.agent_skills.create!(name: "auto-skill", execution_mode: "llm", trigger_mode: "auto", enabled: true, skill_content: "---\nname: auto-skill\n---\nbody")
    @account.agent_skills.create!(name: "disabled-skill", execution_mode: "llm", trigger_mode: "explicit", enabled: false, skill_content: "---\nname: disabled-skill\n---\nbody")

    invocable = @account.agent_skills.explicitly_invocable
    assert_includes invocable, explicit
    assert_includes invocable, combined
    assert_equal %w[combined-skill explicit-skill], invocable.map(&:name).sort
  end
end
