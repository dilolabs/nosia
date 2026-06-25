module Chat::AgentSkillable
  extend ActiveSupport::Concern

  included do
    has_many :agent_skill_executions, dependent: :destroy
  end

  def complete_with_agent_skills(question, **options)
    skills = AgentSkill::Detector.detect(self, question)

    if skills.any?
      skill_results = execute_skills(skills, question, options)

      if skill_results.any?
        skill_messages = format_skill_results(skill_results, skills)
        skill_messages.each do |msg|
          messages.create!(msg.merge(
            agent_skill_execution: true,
            metadata: (msg[:metadata] || {}).merge(agent_skill_names: skills.map(&:name))
          ))
        end
        return skill_messages.last
      end
    end

    complete_with_nosia(question, **options)
  end

  private

  def execute_skills(skills, query, options)
    results = []
    skills.each do |skill|
      begin
        context = { chat: self, user: user, account: account, query: query, agent_skill: skill, options: options }
        result = AgentSkill::Executor.execute(skill, context: context)
        results << result
      rescue => e
        Rails.logger.error "[AgentSkills] Skill #{skill.name} failed: #{e.message}"
        results << nil
      end
    end
    results.compact
  end

  def format_skill_results(results, skills)
    base_count = Message.where(chat_id: id).count
    results.map.with_index do |result, index|
      case result
      when Hash
        { role: result[:role] || "assistant", content: result[:content],
          response_number: base_count + index,
          metadata: (result[:metadata] || {}).merge(agent_skill_names: skills.map(&:name)) }
      when String
        { role: "assistant", content: result, response_number: base_count + index,
          metadata: { agent_skill_names: skills.map(&:name) } }
      else
        { role: "assistant", content: result.to_s, response_number: base_count + index,
          metadata: { agent_skill_names: skills.map(&:name) } }
      end
    end
  end
end
