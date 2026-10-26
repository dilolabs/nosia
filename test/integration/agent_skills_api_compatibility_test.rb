require "test_helper"
require_relative "../support/agent_skills_workspace_fixtures"

class AgentSkillsApiCompatibilityTest < ActionDispatch::IntegrationTest
  include AgentSkillsWorkspaceFixtures

  setup do
    Api::V1::ApplicationController::RATE_LIMIT_STORE.clear
    @headers = { "Authorization" => "Bearer overview-second-secret", "Accept-Language" => "fr" }
  end

  teardown { Api::V1::ApplicationController::RATE_LIMIT_STORE.clear }

  test "API retains JSON account scope stored source and English machine fields" do
    get api_v1_agent_skills_path, headers: @headers, as: :json
    assert_response :success
    assert_equal @second.agent_skills.order(priority: :desc, created_at: :asc).pluck(:id), response.parsed_body.map { |row| row.fetch("id") }
    skill = workspace_skill(:skills_second)
    get api_v1_agent_skill_path(skill), headers: @headers, as: :json
    assert_response :success
    assert_equal skill.skill_content, response.parsed_body.fetch("skill_content")
    assert_equal "llm", response.parsed_body.fetch("execution_mode")
    assert_equal @second.id, response.parsed_body.fetch("account_id")
    get api_v1_agent_skill_path(workspace_skill(:skills_first)), headers: @headers, as: :json
    assert_response :not_found
  end

  test "API CRUD keeps accepted fields response statuses and parser precedence" do
    source = workspace_source("api-workspace")
    work_before = [ AgentSkillExecution.count, TokenUsage.count ]
    assert_no_enqueued_jobs do
      post api_v1_agent_skills_path, params: { agent_skill: { skill_content: source, priority: 15, account_id: @foreign.id } }, headers: @headers, as: :json
      assert_response :created
      id = response.parsed_body.fetch("id")
      skill = @second.agent_skills.find(id)
      assert_equal source, skill.skill_content
      patch api_v1_agent_skill_path(skill), params: { agent_skill: { name: "api-renamed", description: "Explicit accepted description", execution_mode: "ruby", trigger_mode: "combined", enabled: false, requires_rag_context: true, priority: 16 } }, headers: @headers, as: :json
      assert_response :success
      assert_equal [ "api-renamed", "Explicit accepted description", "ruby", "combined", false, true, 16 ],
        skill.reload.attributes.values_at("name", "description", "execution_mode", "trigger_mode", "enabled", "requires_rag_context", "priority")
      assert_equal source, skill.skill_content
      delete api_v1_agent_skill_path(skill), headers: @headers, as: :json
      assert_response :no_content
      assert_not @second.agent_skills.exists?(id)
    end
    assert_equal work_before, [ AgentSkillExecution.count, TokenUsage.count ]
  end

  test "invalid API credentials still return unauthorized" do
    get api_v1_agent_skills_path, headers: { "Authorization" => "Bearer not-a-token" }, as: :json
    assert_response :unauthorized
    assert_equal({ "error" => "Unauthorized" }, response.parsed_body)
  end
end
