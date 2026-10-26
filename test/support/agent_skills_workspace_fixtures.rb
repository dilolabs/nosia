require_relative "account_experience_fixtures"

module AgentSkillsWorkspaceFixtures
  extend ActiveSupport::Concern
  include AccountExperienceFixtures

  included do
    setup do
      ActiveRecord::FixtureSet.reset_cache
      @skill_sets = ActiveRecord::FixtureSet.create_fixtures(
        Rails.root.join("test/support/fixtures/agent_skills_workspace").to_s,
        %w[agent_skills agent_skill_executions]
      ).index_by(&:name)
    end
  end

  def workspace_skill(name)
    @skill_sets.fetch("agent_skills").fixtures.fetch(name.to_s).find
  end

  def workspace_execution(name)
    @skill_sets.fetch("agent_skill_executions").fixtures.fetch(name.to_s).find
  end

  def workspace_source(name = "new-skill")
    "---\nname: #{name}\ndescription: Keep this description\n---\n\n# Instructions\nKeep **this** source."
  end

  def workspace_records
    ActsAsTenant.without_tenant do
      [ AgentSkill, AgentSkillExecution, TokenUsage ].to_h do |model|
        [ model.name, model.order(:id).map(&:attributes) ]
      end
    end
  end
end
