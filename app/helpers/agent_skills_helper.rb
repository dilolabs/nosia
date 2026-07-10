module AgentSkillsHelper
  # JSON payload of the account's slash-invocable skills, consumed by the
  # `composer` Stimulus controller to power the "/" typeahead palette. Accepts an
  # explicit account so partials broadcast from a job (no request-scoped Current)
  # can pass chat.account; defaults to Current.account for request-context callers.
  def agent_skill_autocomplete_data(account = Current.account)
    skills = account.agent_skills.explicitly_invocable.map do |skill|
      { name: skill.name, description: skill.description.to_s.truncate(120) }
    end
    skills.to_json
  end
end
