require "test_helper"
require_relative "../support/agent_skills_workspace_fixtures"

# Verifies structured Skills content and escaped, complete authored instructions.
class AgentSkillsWorkspaceContentTest < ActionDispatch::IntegrationTest
  include AgentSkillsWorkspaceFixtures

  setup { sign_in_overview }

  test "structured rows preserve order settings tags counts and contextual actions" do
    get account_agent_skills_path(@second)
    assert_response :success
    assert_select 'ul.n-skills-rows[role="list"]'
    expected = [ :skills_second, :skills_second_later, :skills_second_ruby ].map { |name| workspace_skill(name).id.to_s }
    assert_equal expected, css_select("[data-skill-id]").map { |row| row["data-skill-id"] }
    assert_select "[data-skills-count][data-total='3'][data-enabled='2']"
    expected.each do |id|
      assert_select "[data-skill-id='#{id}']" do
        assert_select "a[href='#{account_agent_skill_path(@second, id)}']"
        assert_select "a[href='#{edit_account_agent_skill_path(@second, id)}']"
        assert_select "form[action='#{account_agent_skill_enablement_path(@second, id)}']"
        assert_select "[data-skill-execution], [data-skill-trigger], [data-skill-priority], [data-skill-rag]", count: 4
        assert_select "form[data-skill-delete]", count: 0
      end
    end
    assert_includes response.body, "original, English"
  end

  test "details keep complete authored content escaped and deletion separate" do
    skill = workspace_skill(:skills_second)
    source = "---\nname: raw-example\n---\n</pre><script>alert('unsafe')</script>\nKeep **literal** instructions."
    skill.update_columns(skill_content: source, description: "Full <strong>description</strong>", metadata: { "tags" => [ "<unsafe>", "English" ] })
    before = workspace_records
    get account_agent_skill_path(@second, skill)
    assert_select "pre[data-skill-source]", text: source
    assert_select "[data-skills-workspace] script", count: 0
    assert_select "[data-skill-description] strong", text: "description"
    assert_select "[data-skill-delete-section] form[action='#{account_agent_skill_path(@second, skill)}'][data-turbo-confirm]"
    confirm = css_select("[data-skill-delete-section] form").first["data-turbo-confirm"]
    assert_includes confirm, skill.name
    assert_includes confirm, @second.name
    assert_includes confirm, "recorded executions"
    assert_equal before, workspace_records
  end

  test "empty account and locale reads are honest and preserve authored values" do
    before = workspace_records
    %w[en fr].each do |locale|
      headers = { "Accept-Language" => locale }
      get account_agent_skills_path(@empty), headers: headers
      assert_select "[data-skills-empty] a[href='#{new_account_agent_skill_path(@empty)}']"
      get account_agent_skills_path(@second), headers: headers
      assert_includes response.body, workspace_skill(:skills_second).description
      refute_match(/translation missing|missing translation/i, response.body)
      get account_agent_skill_path(@second, workspace_skill(:skills_second)), headers: headers
      assert_select "pre", text: workspace_skill(:skills_second).skill_content
    end
    assert_equal before, workspace_records
  end
end
