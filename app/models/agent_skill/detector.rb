class AgentSkill
  class Detector
    class << self
      def detect(chat, query)
        new(chat, query).detect
      end
    end

    def initialize(chat, query)
      @chat = chat
      @query = query
    end

    def detect
      enabled_skills = @chat.account.agent_skills.where(enabled: true).to_a

      detected = detect_explicit_trigger(enabled_skills)

      if detected.empty?
        detected += detect_auto_trigger(enabled_skills)
      end

      detected.uniq { |s| s.id }.sort_by { |s| -s.priority }
    end

    private

    def detect_explicit_trigger(skills)
      return [] if @query.blank?

      if @query =~ /\A\/([a-zA-Z][a-zA-Z0-9_-]*)(\s|$)/
        find_skills_by_name(skills, $1)
      elsif @query =~ /(?:^|\s)@([a-zA-Z][a-zA-Z0-9_-]*)\b/
        find_skills_by_name(skills, $1)
      else
        []
      end
    end

    def detect_auto_trigger(skills)
      auto_skills = skills.select { |s| s.trigger_mode.in?(%w[auto combined]) }
      return [] if auto_skills.empty? || !guard_model_available?

      create_guard_chat do |guard_chat|
        skill_prompts = auto_skills.map { |s| "- #{s.name}: #{AgentSkill::Security.sanitize_text(s.description.to_s)}" }.join("\n")
        prompt = "Analyze query: \"#{AgentSkill::Security.sanitize_prompt(@query)}\"\n\nAvailable skills:\n#{skill_prompts}\n\nRespond with JSON array of skill names."
        response = guard_chat.ask(prompt)
        parse_skill_names(response.content, auto_skills)
      end
    end

    def find_skills_by_name(skills, name)
      skills.select { |s| s.name.casecmp(name).zero? || s.name.parameterize == name }
    end

    def parse_skill_names(json_string, available_skills)
      return [] unless json_string
      begin
        skill_names = JSON.parse(json_string.strip)
        return [] unless skill_names.is_a?(Array)
        available_skills.select { |s| skill_names.include?(s.name) }
      rescue JSON::ParserError
        []
      end
    end

    def guard_model_available?
      ENV["GUARD_MODEL"].present?
    end

    def create_guard_chat(&block)
      guard_chat = @chat.chats.create!(
        account: @chat.account, user: @chat.user,
        assume_model_exists: true
      )
      block.call(guard_chat)
    ensure
      guard_chat&.destroy
    end
  end
end
