require "test_helper"
require_relative "../support/agent_skills_workspace_fixtures"

class AgentSkillsWorkspaceStatesTest < ActionDispatch::IntegrationTest
  include AgentSkillsWorkspaceFixtures
  setup { sign_in_overview }

  test "explicit state actions preserve account and desired state without execution" do
    [ [ workspace_skill(:skills_first), nil ], [ workspace_skill(:skills_second), @second ] ].each do |skill, account|
      path = account ? account_agent_skill_enablement_path(account, skill) : agent_skill_enablement_path(skill)
      index = account ? account_agent_skills_path(account) : agent_skills_path
      work_before = [ AgentSkillExecution.count, TokenUsage.count ]
      assert_no_enqueued_jobs do
        2.times do
          delete path
          assert_response :see_other
          assert_redirected_to index
          assert_not skill.reload.enabled?
          delete path
          assert_response :see_other
          assert_redirected_to index
          assert_not skill.reload.enabled?
          post path
          assert_response :see_other
          assert_redirected_to index
          assert skill.reload.enabled?
        end
        post path
        assert_response :see_other
        assert_redirected_to index
        assert skill.reload.enabled?
      end
      assert_equal work_before, [ AgentSkillExecution.count, TokenUsage.count ]
    end
  end

  test "legacy PATCH toggle still flips twice and returns the legacy list" do
    skill = workspace_skill(:skills_first)
    [ false, true ].each do |expected|
      patch toggle_agent_skill_path(skill), params: { account_id: @second.id }
      assert_response :found
      assert_redirected_to agent_skills_path
      assert_equal expected, skill.reload.enabled?
    end
  end

  test "cross-account enablements and legacy foreign toggle cannot mutate" do
    before = workspace_records
    first = workspace_skill(:skills_first)
    post account_agent_skill_enablement_path(@second, first)
    assert_response :not_found
    delete account_agent_skill_enablement_path(@foreign, workspace_skill(:skills_foreign))
    assert_response :not_found
    patch toggle_agent_skill_path(workspace_skill(:skills_second))
    assert_response :not_found
    assert_equal before, workspace_records
  end

  test "known validation failure reports an error without claiming a state change" do
    skill = workspace_skill(:skills_second)
    skill.update_columns(priority: 101)
    before = skill.reload.attributes
    delete account_agent_skill_enablement_path(@second, skill)
    assert_response :see_other
    assert_redirected_to account_agent_skills_path(@second)
    assert flash[:alert].present?
    assert_nil flash[:notice]
    assert_equal before, skill.reload.attributes
  end

  test "deletion removes only the authorized skill and its recorded executions" do
    second = workspace_skill(:skills_second)
    other = workspace_skill(:skills_first).attributes
    other_execution = workspace_execution(:skills_first_execution).attributes
    assert_no_enqueued_jobs do
      assert_difference -> { AgentSkillExecution.count }, -1 do
        delete account_agent_skill_path(@second, second)
      end
    end
    assert_redirected_to account_agent_skills_path(@second)
    assert_not AgentSkill.exists?(second.id)
    assert_equal other, workspace_skill(:skills_first).reload.attributes
    assert_equal other_execution, workspace_execution(:skills_first_execution).reload.attributes
  end
end
