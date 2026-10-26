require "test_helper"
require_relative "../support/agent_skills_workspace_fixtures"

# Verifies contextual Skills forms, retained inputs, and linked validation errors.
class AgentSkillsWorkspaceFormsTest < ActionDispatch::IntegrationTest
  include AgentSkillsWorkspaceFixtures

  setup { sign_in_overview }

  test "new and edit forms have contextual actions and native labeled grouped controls" do
    first = workspace_skill(:skills_first)
    second = workspace_skill(:skills_second)
    [ [ new_agent_skill_path, agent_skills_path, false ],
      [ edit_agent_skill_path(first), agent_skill_path(first), true ],
      [ new_account_agent_skill_path(@second), account_agent_skills_path(@second), false ],
      [ edit_account_agent_skill_path(@second, second), account_agent_skill_path(@second, second), true ] ].each do |path, action, editing|
      before = workspace_records
      get path
      assert_response :success
      assert_select "main h1", count: 1
      assert_select "form[data-skill-form][action='#{action}'][data-controller~='form-errors'][data-controller~='html-form']"
      assert_select "textarea#agent_skill_skill_content[rows='20']"
      assert_select "textarea[required]", count: editing ? 0 : 1
      assert_select "[data-skill-saved-identity]", count: editing ? 1 : 0
      assert_select "input[name='agent_skill[name]'], textarea[name='agent_skill[description]'], select[name='agent_skill[account_id]']", count: 0
      assert_select "details[data-skill-advanced]:not([open]) input#agent_skill_priority"
      assert_select "input#agent_skill_enabled, select#agent_skill_execution_mode, select#agent_skill_trigger_mode", count: 3
      assert_select "[data-form-errors-target='summary']", count: 0
      assert_select "#drawer-right, #accordion-right-actions", count: 0
      assert_equal before, workspace_records
    end
  end

  test "invalid create retains source and controls despite parser RAG precedence" do
    source = "---\nname: 1bad\nrequires_rag_context: true\n---\n</textarea><script>unsafe()</script>\nKeep **this**."
    [ agent_skills_path, account_agent_skills_path(@second) ].each do |path|
      before = workspace_records
      post path, params: { agent_skill: { skill_content: source, priority: 101,
        execution_mode: "ruby", trigger_mode: "combined", enabled: "0", requires_rag_context: "0" } }
      assert_response :unprocessable_entity
      assert_select "textarea#agent_skill_skill_content", text: source
      assert_select "[data-skills-workspace] script", count: 0
      assert_select "form[data-skill-form][action='#{path}']"
      assert_select "details[data-skill-advanced][open]"
      assert_select "input#agent_skill_priority[value='101'][aria-invalid='true'][aria-describedby='agent_skill_priority_help agent_skill_priority_error']"
      assert_select "input#agent_skill_requires_rag_context[checked], input#agent_skill_enabled[checked]", count: 0
      assert_select "select#agent_skill_execution_mode option[value='ruby'][selected]"
      assert_select "select#agent_skill_trigger_mode option[value='combined'][selected]"
      assert_select "[data-form-errors-target='summary'][role='alert'][tabindex='-1'] a[href='#agent_skill_skill_content']"
      assert_select "[data-form-errors-target='summary'] ul[role='list']"
      assert_select "[data-form-errors-target='summary'] a[href='#agent_skill_priority']"
      assert_select "#agent_skill_skill_content_error", text: /Name/
      assert_equal before, workspace_records
    end
  end

  test "failed edit preserves submitted source and saved identity without writes" do
    skill = workspace_skill(:skills_second)
    before = workspace_records
    source = workspace_source("changed-frontmatter")
    patch account_agent_skill_path(@second, skill), params: { agent_skill: { skill_content: source, priority: 101 } }
    assert_response :unprocessable_entity
    assert_select "textarea", text: source
    assert_select "[data-skill-saved-identity]", text: /#{Regexp.escape(skill.name)}/
    assert_select "form[action='#{account_agent_skill_path(@second, skill)}']"
    assert_equal before, workspace_records
    patch account_agent_skill_path(@second, skill), params: { agent_skill: { skill_content: "", priority: 12 } }
    assert_redirected_to account_agent_skills_path(@second)
    assert_equal "", skill.reload.skill_content
  end

  test "base errors remain escaped summary text and do not invent an input target" do
    skill = workspace_skill(:skills_second)
    skill.errors.add(:base, "<script>unsafe()</script>")
    form = ActionView::Helpers::FormBuilder.new(:agent_skill, skill, controller.view_context, {})
    html = ApplicationController.render(partial: "agent_skills/form_errors", locals: { form: form })
    fragment = Nokogiri::HTML.fragment(html)
    assert_select fragment, "[role='alert'] li", text: "<script>unsafe()</script>"
    assert_select fragment, "script, li a", count: 0
    get "/accounts/#{@second.id}/agent_skills/not-a-skill"
    assert_response :not_found
  end
end
