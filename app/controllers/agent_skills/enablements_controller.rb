# Sets the desired enabled state of an authorized workspace skill.
class AgentSkills::EnablementsController < ApplicationController
  include AgentSkillScoped
  before_action :set_scoped_agent_skill

  # @return [void] Redirects to the originating list after enabling the skill
  def create
    update_enablement(true)
  end

  # @return [void] Redirects to the originating list after disabling the skill
  def destroy
    update_enablement(false)
  end

  private
    def update_enablement(enabled)
      if @agent_skill.update(enabled: enabled)
        redirect_to skill_workspace_index_path, notice: t(enabled ? "nosia.skills.now_enabled" : "nosia.skills.now_disabled"), status: :see_other
      else
        redirect_to skill_workspace_index_path, alert: @agent_skill.errors.full_messages.to_sentence.presence || t("nosia.skills_workspace.action_failed"), status: :see_other
      end
    end
end
