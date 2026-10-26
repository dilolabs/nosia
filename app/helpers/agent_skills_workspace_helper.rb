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

  # @param skill [AgentSkill] An authorized existing skill
  # @return [String] Explicit enable/disable resource URL
  def skill_workspace_enablement_path(skill)
    skills_workspace_scoped? ? account_agent_skill_enablement_path(@account, skill) : agent_skill_enablement_path(skill)
  end

  # @return [String, nil] Localized account scope, escaped by normal ERB
  def skill_workspace_scope
    if @account
      t(skills_workspace_scoped? ? "nosia.workspace.account" : "nosia.workspace.default_account", name: @account.name)
    end
  end

  # @param title [String, nil] Current detail/form title
  # @return [Array<Hash>] Complete breadcrumb for this route family
  def skill_workspace_trail(title: nil)
    trail = if skills_workspace_scoped?
      [ { label: t("nosia.nav.accounts"), path: accounts_path }, { label: @account.name, path: account_path(@account) } ]
    else
      [ { label: t("nosia.nav.home"), path: user_root_path } ]
    end
    trail << { label: t("nosia.skills.title"), path: title ? skill_workspace_index_path : nil }
    trail << { label: title, path: nil } if title
    trail
  end

  # @return [String] Existing composer URL, contextual when a URL account exists
  def skill_workspace_new_chat_path
    skills_workspace_scoped? ? new_chat_path(account_id: @account.id) : new_chat_path
  end

  # @param skill [AgentSkill] Authorized deletion target
  # @return [String] Plain confirmation, never marked HTML-safe
  def skill_workspace_delete_confirmation(skill)
    t("nosia.skills_workspace.delete_confirm", name: skill.name, account: @account.name)
  end
end
