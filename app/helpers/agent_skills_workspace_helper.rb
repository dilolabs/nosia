module AgentSkillsWorkspaceHelper
  # @return [Boolean] Whether this controller renders the Skills browser workspace
  def agent_skills_workspace_page?
    controller_path == "agent_skills" || controller_path.start_with?("agent_skills/")
  end

  # @return [Boolean] Whether the account came from the authorized URL path
  def skills_workspace_scoped?
    @scoped_skill_account == true
  end

  # @return [String] The originating list URL
  def skill_workspace_index_path
    skills_workspace_scoped? ? account_agent_skills_path(@account) : agent_skills_path
  end

  # @return [String] The originating creation URL
  def skill_workspace_new_path
    skills_workspace_scoped? ? new_account_agent_skill_path(@account) : new_agent_skill_path
  end

  # @param skill [AgentSkill] An authorized existing skill
  # @return [String] Context-preserving details URL
  def skill_workspace_path(skill)
    skills_workspace_scoped? ? account_agent_skill_path(@account, skill) : agent_skill_path(skill)
  end

  # @param skill [AgentSkill] An authorized existing skill
  # @return [String] Context-preserving edit URL
  def skill_workspace_edit_path(skill)
    skills_workspace_scoped? ? edit_account_agent_skill_path(@account, skill) : edit_agent_skill_path(skill)
  end

  # @param skill [AgentSkill] An authorized new or existing skill
  # @return [AgentSkill, Array] Model argument for form_with
  def skill_workspace_form_model(skill)
    skills_workspace_scoped? ? [ @account, skill ] : skill
  end
end
