class AgentSkill
  class Parser
    REQUIRED_FIELDS = %w[name description].freeze

    def initialize(agent_skill)
      @agent_skill = agent_skill
    end

    def parse
      return unless @agent_skill.skill_md.attached?

      content = @agent_skill.skill_md.blob.download
      yaml_content, markdown_body = split_frontmatter(content)
      metadata = parse_yaml(yaml_content)

      @agent_skill.metadata = metadata
      @agent_skill.name ||= metadata["name"]
      @agent_skill.description ||= metadata["description"] || markdown_body.split("\n").first
      @agent_skill.execution_mode ||= metadata["execution_mode"] || "llm"
      @agent_skill.trigger_mode ||= metadata["trigger_mode"] || "explicit"
      @agent_skill.requires_rag_context = ActiveModel::Type::Boolean.new.cast(metadata["requires_rag_context"] || @agent_skill.requires_rag_context)
    end

    private

    def split_frontmatter(content)
      return [nil, content] unless content.start_with?("---")
      end_marker_idx = content.index("\n---\n")
      return [nil, content] unless end_marker_idx
      [content[3...end_marker_idx], content[end_marker_idx + 5..-1]]
    end

    def parse_yaml(yaml_content)
      return {} unless yaml_content && !yaml_content.strip.empty?
      Psych.safe_load(yaml_content, permitted_classes: [Date, Time], aliases: true) rescue {}
    rescue Psych::SyntaxError => e
      Rails.logger.error "Invalid YAML in SKILL.md: #{e.message}"
      {}
    end

    def validate_metadata!(metadata)
      return if metadata.blank?
      missing = REQUIRED_FIELDS.select { |f| metadata[f].blank? }
      raise ArgumentError, "SKILL.md missing required fields: #{missing.join(', ')}" if missing.any?

      if metadata["execution_mode"] && !AgentSkill.execution_modes.key?(metadata["execution_mode"])
        raise ArgumentError, "Invalid execution_mode: #{metadata['execution_mode']}"
      end

      if metadata["trigger_mode"] && !AgentSkill.trigger_modes.key?(metadata["trigger_mode"])
        raise ArgumentError, "Invalid trigger_mode: #{metadata['trigger_mode']}"
      end
    end
  end
end
