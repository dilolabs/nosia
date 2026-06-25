module Api
  module V1
    class AgentSkillsController < ApplicationController
      before_action :set_account

      def index
        @agent_skills = current_account.agent_skills.order(priority: :desc, created_at: :asc)
        render json: @agent_skills, status: :ok
      end

      def create
        @agent_skill = current_account.agent_skills.new(agent_skill_params)

        if @agent_skill.save
          render json: @agent_skill, status: :created
        else
          render json: { errors: @agent_skill.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def show
        @agent_skill = current_account.agent_skills.find(params[:id])
        render json: @agent_skill, status: :ok
      end

      def update
        @agent_skill = current_account.agent_skills.find(params[:id])

        if @agent_skill.update(agent_skill_params)
          render json: @agent_skill, status: :ok
        else
          render json: { errors: @agent_skill.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @agent_skill = current_account.agent_skills.find(params[:id])
        @agent_skill.destroy
        head :no_content
      end

      private

      def set_account
        @account = Current.account
      end

      def agent_skill_params
        params.require(:agent_skill).permit(
          :name, :description, :execution_mode, :trigger_mode,
          :requires_rag_context, :enabled, :priority, :skill_content
        )
      end
    end
  end
end
