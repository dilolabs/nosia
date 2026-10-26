# Preserves the legacy PATCH toggle behavior for authorized workspace skills.
class AgentSkills::TogglesController < ApplicationController
  include AgentSkillScoped
  before_action :set_scoped_agent_skill

  # @return [void] Redirects to the legacy list after attempting to flip the state
  def update
    if @agent_skill.update(enabled: !@agent_skill.enabled?)
      redirect_to skill_workspace_index_path, notice: t(@agent_skill.enabled? ? "nosia.skills.now_enabled" : "nosia.skills.now_disabled")
    else
      redirect_to skill_workspace_index_path, alert: @agent_skill.errors.full_messages.to_sentence.presence || t("nosia.skills_workspace.action_failed")
    end
  end
end
