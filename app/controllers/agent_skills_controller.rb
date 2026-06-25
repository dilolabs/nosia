class AgentSkillsController < ApplicationController
  before_action :set_account
  before_action :set_agent_skill, only: [ :show, :edit, :update, :destroy, :toggle ]

  def index
    @agent_skills = @account.agent_skills.order(priority: :desc, created_at: :asc)
  end

  def new
    @agent_skill = @account.agent_skills.new
  end

  def create
    @agent_skill = @account.agent_skills.new(agent_skill_params)
    if @agent_skill.save
      redirect_to agent_skills_path, notice: "Agent skill created successfully"
    else
      render :new
    end
  end

  def show
  end

  def edit
  end

  def update
    if @agent_skill.update(agent_skill_params)
      redirect_to agent_skills_path, notice: "Agent skill updated"
    else
      render :edit
    end
  end

  def destroy
    @agent_skill.destroy
    redirect_to agent_skills_path, notice: "Agent skill deleted"
  end

  def toggle
    @agent_skill.update!(enabled: !@agent_skill.enabled)
    redirect_to agent_skills_path, notice: "Agent skill #{@agent_skill.enabled? ? 'enabled' : 'disabled'}"
  end

  private

  def set_account
    @account = Current.account
  end

  def set_agent_skill
    @agent_skill = @account.agent_skills.find(params[:id])
  end

  def agent_skill_params
    params.require(:agent_skill).permit(
      :name, :description, :execution_mode, :trigger_mode,
      :requires_rag_context, :enabled, :priority, :skill_content
    )
  end
end
