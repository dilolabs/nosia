class AgentSkill
  class Executor
    class << self
      def execute(agent_skill, context:)
        new(agent_skill, context).call
      end
    end

    def initialize(agent_skill, context)
      @agent_skill = agent_skill
      @context = context.with_indifferent_access
    end

    def call
      raise "Skill is not runnable" unless @agent_skill.runnable?

      execution = create_execution_record

      begin
        result = case @agent_skill.execution_mode.to_sym
                when :llm
                  LLMExecutor.new(@agent_skill, @context, execution).call
                when :ruby
                  RubyExecutor.new(@agent_skill, @context, execution).call
                end

        execution.update!(status: "completed", output: format_output(result), duration_ms: duration(execution))
        result
      rescue => e
        execution.update!(status: "failed", error_message: e.message, duration_ms: duration(execution))
        raise
      end
    end

    private

    def create_execution_record
      AgentSkillExecution.create!(
        agent_skill: @agent_skill,
        chat: @context[:chat],
        message: @context[:message],
        execution_mode: @agent_skill.execution_mode,
        status: "pending",
        trigger_context: { query: @context[:query], trigger_method: @context[:trigger_method] || "detected" }
      )
    end

    def format_output(result)
      case result
      when Hash then result.except(:chat, :user, :account, :query, :message)
      when Message then result.as_json(only: [:role, :content, :metadata])
      else { content: result.to_s }
      end
    end

    def duration(execution)
      ((Time.current - execution.created_at) * 1000).to_i
    end
  end

  class LLMExecutor
    def initialize(agent_skill, context, execution)
      @agent_skill = agent_skill
      @context = context
      @execution = execution
    end

    def call
      chat = @context[:chat]
      instructions = build_sanitized_instructions

      @execution.update!(input: { instructions: instructions.truncate(1000) })

      chat.with_instructions(instructions, replace: false) { chat.ask(@context[:query]) }
    end

    private

    def build_sanitized_instructions
      parts = ["## Agent Skill: #{AgentSkill::Security.sanitize_text(@agent_skill.name)}"]
      parts << ""
      parts << "**Description:** #{AgentSkill::Security.sanitize_text(@agent_skill.description.to_s)}"
      parts << ""

      if @agent_skill.metadata["when_to_use"]
        parts << "**When to use:** #{AgentSkill::Security.sanitize_text(@agent_skill.metadata['when_to_use'].to_s)}"
        parts << ""
      end

      parts << "**Instructions:**"
      begin
        skill_content = @agent_skill.skill_md.blob.download
      rescue => e
        skill_content = ""
      end
      parts << AgentSkill::Security.sanitize_prompt(skill_content)
      parts << ""
      parts.join("\n")
    end
  end

  class RubyExecutor
    ALLOWED_CHAT_METHODS = %i[ask with_instructions with_params with_temperature with_model
                              similarity_search messages user account].freeze

    def initialize(agent_skill, context, execution)
      @agent_skill = agent_skill
      @context = context
      @execution = execution
    end

    def call
      klass = @agent_skill.ruby_class_name.safe_constantize
      raise "Ruby skill class not found: #{@agent_skill.ruby_class_name}" unless klass
      raise "Must inherit from AgentSkills::Base" unless klass < AgentSkills::Base

      context_with_skill = @context.merge(agent_skill: @agent_skill, execution: @execution)
      @execution.update!(input: context_with_skill.except(:chat, :user, :account))

      execute_with_timeout { klass.new(context_with_skill).call }
    end

    private

    def execute_with_timeout(&block)
      timeout = Rails.application.config.agent_skills.timeout
      timer = Concurrent::TimerTask.new(timeout: timeout, &block)
      timer.execute
      result = timer.wait

      unless timer.completed?
        timer.shutdown
        raise "Skill execution timed out after #{timeout} seconds"
      end

      result.value
    rescue Concurrent::TimeoutError
      raise "Skill execution timed out after #{timeout} seconds"
    end
  end
end
