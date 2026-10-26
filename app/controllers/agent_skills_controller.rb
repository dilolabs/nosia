class AgentSkillsController < ApplicationController
  include AgentSkillScoped
  before_action :set_scoped_agent_skill, only: [ :show, :edit, :update, :destroy, :toggle ]

  def index
    @agent_skills = @account.agent_skills.order(priority: :desc, created_at: :asc)
  end

  def new
    @agent_skill = @account.agent_skills.new
  end

  def create
    @agent_skill = @account.agent_skills.new(agent_skill_params)
    if @agent_skill.save
      redirect_to skill_workspace_index_path, notice: t("nosia.skills.created"), status: :see_other
    else
      @submitted_skill_values = agent_skill_params.to_h
      render :new, status: :unprocessable_entity
    end
  end

  def show
  end

  def edit
  end

  def update
    if @agent_skill.update(agent_skill_params)
      redirect_to skill_workspace_index_path, notice: t("nosia.skills.updated"), status: :see_other
    else
      @submitted_skill_values = agent_skill_params.to_h
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @agent_skill.destroy
      redirect_to skill_workspace_index_path, notice: t("nosia.skills.deleted"), status: :see_other
    else
      redirect_to skill_workspace_index_path, alert: @agent_skill.errors.full_messages.to_sentence.presence || t("nosia.skills_workspace.action_failed"), status: :see_other
    end
  end

  def toggle
    @agent_skill.update!(enabled: !@agent_skill.enabled)
    redirect_to skill_workspace_index_path, notice: t(@agent_skill.enabled? ? "nosia.skills.now_enabled" : "nosia.skills.now_disabled")
  end

  private
    def agent_skill_params
      params.require(:agent_skill).permit(:name, :description, :execution_mode,
        :trigger_mode, :requires_rag_context, :enabled, :priority, :skill_content)
    end
end
