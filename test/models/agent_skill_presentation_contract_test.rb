require "test_helper"
require_relative "../support/agent_skills_workspace_fixtures"

class AgentSkillPresentationContractTest < ActiveSupport::TestCase
  include AgentSkillsWorkspaceFixtures

  test "new-record defaults and create-only content presence stay intact" do
    skill = @second.agent_skills.new(name: "defaults")
    assert_equal [ "llm", "explicit", true, 0, false ],
      [ skill.execution_mode, skill.trigger_mode, skill.enabled, skill.priority, skill.requires_rag_context ]
    assert_not skill.valid?
    assert skill.errors.include?(:skill_content)
    stored = workspace_skill(:skills_second)
    assert stored.update(skill_content: "")
    assert_equal "", stored.reload.skill_content
  end

  test "frontmatter merges metadata but does not synchronize stored identity and modes" do
    skill = workspace_skill(:skills_second)
    assert_no_enqueued_jobs { assert skill.update(metadata: skill.metadata.merge("retained" => "original")) }
    original = skill.attributes.slice("name", "description", "execution_mode", "trigger_mode")
    source = "---\nname: other-name\ndescription: Other description\nexecution_mode: ruby\ntrigger_mode: auto\ntags: [updated]\n---\nKeep source."
    assert_no_enqueued_jobs { assert skill.update(skill_content: source) }
    assert_equal original, skill.reload.attributes.slice(*original.keys)
    assert_equal source, skill.skill_content
    assert_equal "other-name", skill.metadata.fetch("name")
    assert_equal [ "updated" ], skill.metadata.fetch("tags")
    assert_equal "original", skill.metadata.fetch("retained")
  end

  test "RAG keeps the existing frontmatter fallback and boolean conversion" do
    [ [ true, false, true ], [ false, true, true ], [ "false", true, false ], [ nil, true, true ] ].each do |metadata_value, checked, expected|
      source = "---\n" + { "name" => "rag-probe", "requires_rag_context" => metadata_value }.to_yaml.delete_prefix("---\n") + "---\nBody"
      skill = @second.agent_skills.new(name: "rag-probe", skill_content: source, requires_rag_context: checked)
      assert skill.valid?, skill.errors.full_messages.to_sentence
      assert_equal expected, skill.requires_rag_context
      assert_equal source, skill.skill_content
    end
  end

  test "enabled Ruby without an implementation is not runnable" do
    skill = workspace_skill(:skills_second_ruby)
    assert skill.update(enabled: true)
    assert skill.enabled?
    assert_not skill.runnable?
    assert_includes @second.agent_skills.runnable, skill
  end

  test "validation never rewrites submitted source or persists invalid priority" do
    skill = workspace_skill(:skills_second)
    original = skill.attributes.deep_dup
    source = workspace_source("different-name")
    skill.assign_attributes(skill_content: source, priority: 101)
    assert_not skill.save
    assert_equal source, skill.skill_content
    assert_equal original, skill.reload.attributes
  end
end
