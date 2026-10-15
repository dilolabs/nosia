module AgentSkillsHelper
  # JSON payload of the account's slash-invocable skills, consumed by the
  # `composer` Stimulus controller to power the "/" typeahead palette. Accepts an
  # explicit account so partials broadcast from a job (no request-scoped Current)
  # can pass chat.account; defaults to Current.account for request-context callers.
  # @param account [Account]
  # @return [String] JSON snapshot materialized within this account's tenant
  def agent_skill_autocomplete_data(account = Current.account)
    ActsAsTenant.with_tenant(account) do
      account.agent_skills.explicitly_invocable.map do |skill|
        { name: skill.name, description: skill.description.to_s.truncate(120) }
      end.to_json
    end
  end
end
