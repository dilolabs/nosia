module AgentSkills
  class Base
    attr_reader :context

    ALLOWED_CHAT_METHODS = %i[
      ask with_instructions with_params with_temperature with_model
      similarity_search messages user account
    ].freeze

    def initialize(context = {})
      @context = context.with_indifferent_access
      validate_context!
    end

    def call
      raise NotImplementedError, "#{self.class.name} must implement #call"
    end

    delegate :query, :message, :agent_skill, :execution, to: :context

    def chat
      @context[:chat]
    end

    def user
      @context[:user]
    end

    def account
      @context[:account]
    end

    def rag_context
      @rag_context ||= agent_skill.requires_rag_context ? extract_rag_context : {}
    end

    def ask(prompt, **options)
      chat.ask(prompt, **options)
    end

    def with_instructions(instructions, **options, &block)
      chat.with_instructions(instructions, **options, &block)
    end

    def log(message, level: :info)
      Rails.logger.public_send(level, "[AgentSkill:#{skill_name}] #{message}")
    end

    def method_missing(name, *args, **kwargs, &block)
      if ALLOWED_CHAT_METHODS.include?(name)
        chat.public_send(name, *args, **kwargs, &block)
      else
        raise NoMethodError, "Skill cannot call ##{name} on chat. Allowed: #{ALLOWED_CHAT_METHODS.join(', ')}"
      end
    end

    def respond_to?(name, include_private = false)
      ALLOWED_CHAT_METHODS.include?(name) || super
    end

    class << self
      def validate!
        return true unless name.start_with?("AgentSkills::")
        unless ancestors.include?(AgentSkills::Base)
          raise "Skill #{name} must inherit from AgentSkills::Base"
        end
        unless instance_methods(false).include?(:call)
          raise "Skill #{name} must implement #call"
        end
        true
      end
    end

    private

    def validate_context!
      required = %i[chat query agent_skill]
      missing = required.select { |k| @context[k].nil? }
      raise ArgumentError, "Missing required context keys: #{missing.join(', ')}" if missing.any?
    end

    def extract_rag_context
      return {} unless defined?(Chunk)
      chunks = chat.similarity_search(context[:query])
      source_ids = chunks.map { |c| c.source_id }.compact.uniq
      return {} if source_ids.empty?

      {
        chunks: chunks.as_json(only: [:id, :content, :title, :source, :metadata]),
        documents: Document.where(id: source_ids).as_json(only: [:id, :title, :content_type, :metadata])
      }
    rescue => e
      log "Failed to extract documents: #{e.message}", level: :error
      {}
    end

    def skill_name
      self.class.name.demodulize
    end
  end
end
