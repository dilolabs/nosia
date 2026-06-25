module AgentSkillsHelper
  # JSON payload of the account's slash-invocable skills, consumed by the
  # `skill-autocomplete` Stimulus controller to power the "/" typeahead.
  def agent_skill_autocomplete_data
    skills = Current.account.agent_skills.explicitly_invocable.map do |skill|
      { name: skill.name, description: skill.description.to_s.truncate(120) }
    end
    skills.to_json
  end
end
