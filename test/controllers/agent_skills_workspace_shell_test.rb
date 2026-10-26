require "test_helper"
require_relative "../support/agent_skills_workspace_fixtures"

# Verifies the Skills workspace shell without changing account preferences.
class AgentSkillsWorkspaceShellTest < ActionDispatch::IntegrationTest
  include AgentSkillsWorkspaceFixtures

  setup { sign_in_overview }

  test "list and details have one heading breadcrumb scope and no conversation drawer" do
    [ [ agent_skills_path, "Default account: #{@first.name}" ],
      [ account_agent_skills_path(@second), "Account: #{@second.name}" ],
      [ account_agent_skill_path(@second, workspace_skill(:skills_second)), "Account: #{@second.name}" ] ].each do |path, scope|
      assert_no_enqueued_jobs { get path }
      assert_response :success
      assert_select "[data-skills-workspace] h1", count: 1
      assert_select "main h1", count: 1
      assert_select "[data-workspace-scope]", text: scope
      assert_select ".n-workspace-header nav", count: 1
      assert_select "#accordion-right-actions, #drawer-right, [data-drawer-target]", count: 0
    end
    assert_select ".n-workspace-trail a[href='#{account_agent_skills_path(@second)}']"
    assert_select ".n-workspace-header a[href='#{new_chat_path(account_id: @second.id)}']"
    get settings_path
    assert_select "#accordion-right-actions", count: 1
    get account_path(@second)
    assert_select "a[href='#{account_agent_skills_path(@second)}']"
    assert_equal @first, @user.reload.first_account
  end

  test "Skills feedback is in flow and global toasts are not duplicated" do
    post account_agent_skill_enablement_path(@second, workspace_skill(:skills_second))
    follow_redirect!
    assert_select "[data-skills-feedback][role='status']", text: I18n.t("nosia.skills.now_enabled")
    assert_select "#toast-success, #toast-danger", count: 0
  end
end
