module AgentSkillScoped
  extend ActiveSupport::Concern
  include AccountScoped
  include AgentSkillsWorkspaceHelper

  included do
    around_action :with_agent_skill_account
  end

  private
    def with_agent_skill_account
      @scoped_skill_account = request.path_parameters.key?(:account_id)
      @account = if @scoped_skill_account
        member_account(validated_skill_path_id(request.path_parameters.fetch(:account_id)))
      else
        Current.account
      end

      if @account
        ActsAsTenant.with_tenant(@account) { yield }
      elsif controller_path == "agent_skills" && %w[index new].include?(action_name)
        render "agent_skills/setup", formats: [ :html ]
      else
        head :not_found
      end
    end

    def validated_skill_path_id(id)
      if id.is_a?(String) && id.match?(/\A[0-9]+\z/)
        id
      else
        raise ActiveRecord::RecordNotFound
      end
    end

    def set_scoped_agent_skill
      id = request.path_parameters[:agent_skill_id] || request.path_parameters[:id]
      @agent_skill = @account.agent_skills.find(validated_skill_path_id(id))
    end
end
