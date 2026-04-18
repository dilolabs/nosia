# Agent Skills Implementation - Design Specification

**Date:** 2025-04-15  
**Status:** Draft (v2 - Addressing Critical Issues)  
**Author:** Mistral Vibe (with input from Nosia team)  
**Approvers:** Pending  

---

## 0. Executive Summary

This document specifies the implementation of **Agent Skills** (agentskills.io) support in Nosia, a self-hosted RAG platform. Agent Skills are modular, reusable capabilities defined in a standardized format (SKILL.md) that extend AI agent functionality.

The selected approach is **Option B: Hybrid LLM + Ruby Modules**, which provides:
- LLM-driven execution for simple, prompt-based skills (no code required)
- Ruby-based execution for complex skills requiring programmatic logic
- Account-scoped skill libraries (consistent with Nosia's multi-tenant architecture)
- Manual upload of SKILL.md files and directories via web UI
- Combined triggering: explicit invocation, LLM auto-detection
- Configurable RAG context access per skill

**CRITICAL CHANGES FROM v1:**
- Renamed `Skill` model to `AgentSkill` to resolve namespace conflict with `Skill::` modules
- Removed MCP execution mode for MVP (deferred to future)
- Added `AgentSkillExecution` model for audit trail
- Fixed `complete_with_nosia` infinite loop risk
- Added Ruby skill file loading specification
- Added input sanitization for LLM prompts
- Replaced `Timeout.timeout` with thread-safe `Concurrent::TimerTask`

---

## 1. Background & Motivation

### 1.1 What are Agent Skills?

Agent Skills (agentskills.io) is an open standard for defining modular AI agent capabilities:
- Skills are packaged as directories with a `SKILL.md` file (YAML frontmatter + Markdown)
- Discoverable and shareable via the agentskills.io registry
- Designed for portability across AI platforms (Claude, GitHub Copilot, VS Code, etc.)

### 1.2 Why Add Skills to Nosia?

Nosia currently provides RAG-based chat with user documents. Agent Skills extend this by:
1. **Enabling new capabilities** - Skills can perform tasks beyond document Q&A (summarization, analysis, generation)
2. **Customization** - Users can add domain-specific skills without modifying Nosia core
3. **Ecosystem leverage** - Tap into the growing library of community skills
4. **Workflows** - Enable multi-step, repeatable processes

### 1.3 Nosia Context

Nosia's architecture principles that guide this design:
- **Majestic Monolith** - Keep it as one codebase, one process, one deploy
- **Rich Domain Models** - Domain logic belongs in models, not services
- **POROs belong in `app/models/`** - plain Ruby objects are models, not services
- **Convention over Configuration** - Follow Rails conventions
- **Multi-tenant isolation** - All data scoped to accounts via `acts_as_tenant`

---

## 2. Goals & Non-Goals

### 2.1 Goals

- [ ] Users can upload SKILL.md files via web UI
- [ ] Skills can be LLM-driven (prompt injection) or Ruby-based
- [ ] Skills are account-scoped and isolated
- [ ] Skills can be triggered explicitly (`/skill-name`) or automatically
- [ ] Skills can optionally access RAG context (documents/chunks)
- [ ] Ruby skills follow a standardized pattern (inherit from `AgentSkills::Base`)
- [ ] Skills integrate with existing Chat completion flow
- [ ] Manual update only (no auto-versioning)
- [ ] execution audit trail via `AgentSkillExecution` model

### 2.2 Non-Goals

- [ ] Integration with agentskills.io registry (manual upload only)
- [ ] Git repository support for skills
- [ ] Automatic skill updates or version checking
- [ ] Sandboxed execution for Ruby skills (run in-process with controlled API)
- [ ] Multi-language skill support (Ruby only for complex skills)
- [ ] Skill marketplace or sharing between accounts
- [ ] MCP-based skills (deferred to future phase)

---

## 3. Architecture

### 3.1 High-Level Overview

```
┌─────────────────┐     ┌──────────────┐     ┌─────────────────┐
│   User Request  │────▶│ Skill Router │────▶│ Skill Executor │
└─────────────────┘     └──────────────┘     └────────┬────────┘
                                                     │
                    ┌────────────────────────────────────┼────────────────────────┐
                    │                                        │                        │
                    ▼                                        ▼                        ▼
           ┌─────────────────┐             ┌───────────────┐         ┌────────────────┐
           │  LLM execution   │             │ Ruby execution │         │ Audit Logging   │
           │ (prompt inject)  │             │ (in-process)   │         │ (AgentSkill     │
           └─────────────────┘             └───────────────┘         │ Execution)     │
                                                                     └────────────────┘
```

### 3.2 Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        User Interface                                │
├─────────────────────────────────────────────────────────────────┤
│  Web UI: Agent Skills Management (#index, #new, #create, #show)  │
│  - Upload SKILL.md and related files                              │
│  - Enable/disable skills                                         │
│  - Configure trigger modes                                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        API Layer                                   │
├─────────────────────────────────────────────────────────────────┤
│  Api::V1::AgentSkillsController                                    │
│  - REST endpoints for skill management                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Domain Models                                  │
├─────────────────────────────────────────────────────────────────┤
│  AgentSkill (AR)                                                    │
│  - account_id, name, description, execution_mode, trigger_mode     │
│  - requires_rag_context, enabled, priority, metadata (jsonb)        │
│  - has_many_attached :files (Active Storage)                      │
│  - has_one_attached :skill_md                                      │
│                                                                     │
│  agent_skill/parser.rb                                              │
│  - Parses SKILL.md format (YAML frontmatter + Markdown body)     │
│  - Validates required fields                                        │
│                                                                     │
│  agent_skill/executor.rb                                           │
│  - LLMExecutor: Injects skill instructions into LLM prompt        │
│  - RubyExecutor: Calls Ruby skill class methods                     │
│                                                                     │
│  agent_skill/detector.rb                                           │
│  - Detects which skills to trigger based on query                  │
│                                                                     │
│  agent_skill/security.rb                                           │
│  - File type validation                                            │
│  - Prompt sanitization                                             │
│                                                                     │
│  Chat::AgentSkillable (Concern)                                    │
│  - Mixin for Chat model                                            │
│  - complete_with_agent_skills() method                             │
│                                                                     │
│  AgentSkills::Base                                                 │
│  - Base class for Ruby skills                                      │
│  - Provides controlled access to context, RAG, LLM                │
│                                                                     │
│  AgentSkillExecution (AR)                                          │
│  - Audit trail for skill executions                                │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┴─────────────────────┐
        │                                       │
        ▼                                       ▼
   ┌─────────────────┐                  ┌─────────────────┐
   │ Ruby Skill      │                  │ LLM Integration │
   │ Implementation  │                  │ (RubyLLM)       │
   │                 │                  │                 │
   │ app/models/    │◄─────────────────┤ Existing        │
   │ agent_skills/  │                  │ Chat infrastructure│
   └─────────────────┘                  └─────────────────┘
```

### 3.3 Data Flow

**User submits chat message:**
1. `MessagesController#create` receives request
2. Creates user message, queues `ChatResponseJob`
3. `ChatResponseJob` calls `chat.complete_with_agent_skills(query)`

**In `complete_with_agent_skills`:**
1. `AgentSkill::Detector.detect(chat, query)` identifies relevant skills
2. For each skill:
   - Build context with chat, user, query, skill, options
   - Create `AgentSkillExecution` record (pending)
   - `AgentSkill::Executor.execute(skill, context: context, execution: execution_record)` 
3. LLMExecutor: Sanitizes and injects skill instructions, calls LLM
4. RubyExecutor: Instantiates skill class, calls `#call` with timeout
5. Update `AgentSkillExecution` with status, result, duration
6. Results formatted as messages and added to chat
7. If no skills triggered, fall back to `complete_with_nosia`

---

## 4. Data Model

### 4.1 Database Schema

#### Migration: Create Agent Skills Table

```ruby
# db/migrate/[timestamp]_create_agent_skills.rb
class CreateAgentSkills < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_skills do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :execution_mode, null: false, default: "llm" # llm, ruby
      t.string :trigger_mode, null: false, default: "explicit" # explicit, auto, combined
      t.jsonb :metadata, default: {} # parsed YAML frontmatter from SKILL.md
      t.boolean :requires_rag_context, default: false
      t.boolean :enabled, default: true
      t.integer :priority, default: 0
      t.timestamps
    end

    add_index :agent_skills, [:account_id, :name], unique: true
    add_index :agent_skills, [:account_id, :enabled]
    add_index :agent_skills, [:account_id, :execution_mode]
    add_index :agent_skills, [:account_id, :trigger_mode]
    add_index :agent_skills, [:name] # For lookups by trigger detection
  end
end
```

#### Migration: Create Agent Skill Executions Table

```ruby
# db/migrate/[timestamp]_create_agent_skill_executions.rb
class CreateAgentSkillExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_skill_executions do |t|
      t.references :agent_skill, null: false, foreign_key: true
      t.references :chat, null: false, foreign_key: true
      t.references :message, null: true, foreign_key: true
      t.string :execution_mode, null: false # llm, ruby
      t.string :status, null: false # pending, completed, failed, timed_out
      t.jsonb :trigger_context, default: {} # query, skill names, detection method
      t.jsonb :input, default: {} # Sanitized input passed to skill
      t.jsonb :output, default: {} # Result from skill execution
      t.text :error_message
      t.integer :duration_ms
      t.timestamps
    end

    add_index :agent_skill_executions, [:chat_id, :created_at]
    add_index :agent_skill_executions, [:agent_skill_id, :created_at]
    add_index :agent_skill_executions, [:status]
    add_index :agent_skill_executions, [:created_at]
  end
end
```

### 4.2 Active Record Model

```ruby
# app/models/agent_skill.rb
class AgentSkill < ApplicationRecord
  extend ActiveModel::Naming
  
  acts_as_tenant :account
  
  has_many_attached :files
  has_one_attached :skill_md
  has_many :agent_skill_executions, dependent: :destroy
  
  enum :execution_mode, { llm: "llm", ruby: "ruby" }
  enum :trigger_mode, { explicit: "explicit", auto: "auto", combined: "combined" }
  
  # Validations
  validates :name, presence: true, 
            uniqueness: { scope: :account_id },
            format: { with: /\A[a-zA-Z][a-zA-Z0-9_-]*\z/, 
                     message: "must start with a letter and contain only alphanumeric, underscore, and hyphen" }
  validates :execution_mode, presence: true
  validates :trigger_mode, presence: true
  validates :priority, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validate :validate_skill_md_present, on: :create
  validate :validate_metadata_present, on: :create
  validate :validate_ruby_implementation, if: -> { execution_mode == "ruby" }
  
  # Callbacks
  after_save :parse_skill_md, if: -> { skill_md_attached? && (skill_md_changed? || skill_md_attached?) }
  
  # Scopes
  scope :runnable, -> { where(enabled: true) }
  scope :by_name, ->(name) { where(name: name) }
  
  # Get the Ruby class name for ruby-mode skills
  def ruby_class_name
    "AgentSkills::#{name.camelize}"
  end
  
  # Check if Ruby implementation exists
  def ruby_implementation_exists?
    execution_mode == "ruby" && ruby_class_name.safe_constantize.present?
  end
  
  # Check if skill is runnable
  def runnable?
    enabled? && 
      (execution_mode == "llm" || 
       (execution_mode == "ruby" && ruby_implementation_exists?))
  end
  
  # Get the instructions for LLM-mode skills
  def instructions
    metadata["instructions"] || parsed_content
  end
  
  # Get sanitized description for display
  def sanitized_description
    AgentSkill::Security.sanitize_text(description.to_s)
  end
  
  # Get sanitized instructions for LLM
  def sanitized_instructions
    AgentSkill::Security.sanitize_prompt(instructions.to_s)
  end
  
  # Get parsed content from SKILL.md
  def parsed_content
    @parsed_content ||= begin
      return "" unless skill_md_attached?
      skill_md.download
    rescue => e
      Rails.logger.error "Failed to read skill content for ##{id}: #{e.message}"
      ""
    end
  end
  
  private
  
  def validate_skill_md_present
    errors.add(:skill_md, "must be attached") unless skill_md.attached?
  end
  
  def validate_metadata_present
    return if metadata.present? && metadata["name"].present?
    errors.add(:skill_md, "must contain valid YAML frontmatter with at least 'name' field")
  end
  
  def validate_ruby_implementation
    return if ruby_implementation_exists?
    errors.add(:base, "Ruby skill class '#{ruby_class_name}' not found. Create it in app/models/agent_skills/")
  end
  
  def parse_skill_md
    AgentSkill::Parser.new(self).parse
  end
end
```

### 4.3 Agent Skill Parser

```ruby
# app/models/agent_skill/parser.rb
module AgentSkill
  class Parser
    REQUIRED_FIELDS = %w[name description].freeze
    
    def initialize(agent_skill)
      @agent_skill = agent_skill
    end
    
    def parse
      return unless @agent_skill.skill_md.attached?
      
      content = @agent_skill.skill_md.download
      yaml_content, markdown_body = split_frontmatter(content)
      
      metadata = parse_yaml(yaml_content)
      
      # Validate required fields
      validate_metadata!(metadata)
      
      @agent_skill.update!(
        metadata: metadata,
        name: metadata["name"] || @agent_skill.name,
        description: metadata["description"] || markdown_body.split("\n").first,
        execution_mode: metadata["execution_mode"] || @agent_skill.execution_mode || "llm",
        trigger_mode: metadata["trigger_mode"] || @agent_skill.trigger_mode || "explicit",
        requires_rag_context: ActiveModel::Type::Boolean.new.cast(metadata["requires_rag_context"] || @agent_skill.requires_rag_context)
      )
    end
    
    private
    
    def split_frontmatter(content)
      return [nil, content] unless content.start_with?("---")
      
      end_marker_idx = content.index("\n---\n")
      return [nil, content] unless end_marker_idx
      
      frontmatter = content[3...end_marker_idx]
      body = content[end_marker_idx + 5..-1]
      [frontmatter, body]
    end
    
    def parse_yaml(yaml_content)
      return {} unless yaml_content && !yaml_content.strip.empty?
      
      errors = []
      metadata = Psych.safe_load(yaml_content, permitted_classes: [Date, Time], permitted_symbols: [], aliases: true) rescue nil
      
      unless metadata.is_a?(Hash)
        errors << "YAML frontmatter must be a mapping (key-value pairs)"
        return { "_parse_errors" => errors }
      end
      
      metadata
    rescue Psych::SyntaxError, Psych::DisallowedClass => e
      Rails.logger.error "Invalid YAML in SKILL.md for agent_skill ##{@agent_skill.id}: #{e.message}"
      { "_parse_errors" => [e.message] }
    end
    
    def validate_metadata!(metadata)
      return if metadata["_parse_errors"]
      
      missing = REQUIRED_FIELDS.select { |f| metadata[f].blank? }
      if missing.any?
        raise ArgumentError, "SKILL.md missing required fields: #{missing.join(', ')}"
      end
      
      # Validate execution_mode if present
      if metadata["execution_mode"] && !AgentSkill.execution_modes.key?(metadata["execution_mode"])
        raise ArgumentError, "Invalid execution_mode: #{metadata['execution_mode']}. Must be one of: #{AgentSkill.execution_modes.keys.join(', ')}"
      end
      
      # Validate trigger_mode if present
      if metadata["trigger_mode"] && !AgentSkill.trigger_modes.key?(metadata["trigger_mode"])
        raise ArgumentError, "Invalid trigger_mode: #{metadata['trigger_mode']}. Must be one of: #{AgentSkill.trigger_modes.keys.join(', ')}"
      end
    end
  end
end
```

---

## 5. Execution Subsystem

### 5.1 Executor (Main Router)

```ruby
# app/models/agent_skill/executor.rb
module AgentSkill
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
        
        execution.update!(
          status: "completed",
          output: format_output(result),
          duration_ms: (Time.current - execution.created_at) * 1000
        )
        
        result
      rescue => e
        execution.update!(
          status: "failed",
          error_message: e.message,
          duration_ms: (Time.current - execution.created_at) * 1000
        )
        raise
      end
    end
    
    private
    
    def create_execution_record
      @context[:execution] || AgentSkillExecution.create!(
        agent_skill: @agent_skill,
        chat: @context[:chat],
        message: @context[:message],
        execution_mode: @agent_skill.execution_mode,
        status: "pending",
        trigger_context: {
          query: @context[:query],
          trigger_method: @context[:trigger_method] || "detected"
        }
      )
    end
    
    def format_output(result)
      case result
      when Hash
        result.except(:chat, :user, :account, :query, :message, :skill)
      when Message
        result.as_json(only: [:role, :content, :metadata])
      else
        { content: result.to_s }
      end
    end
  end
  
  # LLM Execution - Injects sanitized skill instructions into the prompt
  class LLMExecutor
    def initialize(agent_skill, context, execution)
      @agent_skill = agent_skill
      @context = context
      @execution = execution
    end
    
    def call
      chat = @context[:chat]
      instructions = build_sanitized_instructions
      
      # Log the execution
      @execution.update!(input: { instructions: instructions.truncate(1000) })
      
      # Execute with the skill instructions prepended
      chat.with_instructions(instructions, replace: false) do
        chat.ask(@context[:query])
      end
    end
    
    private
    
    def build_sanitized_instructions
      parts = []
      parts << "## Agent Skill: #{AgentSkill::Security.sanitize_text(@agent_skill.name)}"
      parts << ""
      parts << "**Description:** #{AgentSkill::Security.sanitize_text(@agent_skill.description.to_s)}"
      parts << ""
      
      if @agent_skill.metadata["when_to_use"]
        parts << "**When to use:** #{AgentSkill::Security.sanitize_text(@agent_skill.metadata['when_to_use'].to_s)}"
        parts << ""
      end
      
      parts << "**Instructions:**"
      parts << AgentSkill::Security.sanitize_prompt(@agent_skill.instructions.to_s)
      parts << ""
      
      parts.join("\n")
    end
  end
  
  # Ruby Execution - Calls Ruby class methods with controlled access
  class RubyExecutor
    ALLOWED_CHAT_METHODS = %i[
      ask with_instructions with_params with_temperature
      similarity_search augmented_prompt
      messages user account
    ].freeze
    
    def initialize(agent_skill, context, execution)
      @agent_skill = agent_skill
      @context = context
      @execution = execution
    end
    
    def call
      klass = @agent_skill.ruby_class_name.safe_constantize
      raise "Ruby skill class not found: #{@agent_skill.ruby_class_name}" unless klass
      
      # Validate class inherits from AgentSkills::Base
      unless klass < AgentSkills::Base
        raise "Ruby skill must inherit from AgentSkills::Base: #{@agent_skill.ruby_class_name}"
      end
      
      # Add skill and execution to context
      context_with_skill = @context.merge(
        agent_skill: @agent_skill,
        execution: @execution
      )
      
      # Log input
      @execution.update!(input: context_with_skill.except(:chat, :user, :account))
      
      # Execute with timeout using thread-safe mechanism
      execute_with_timeout do
        instance = klass.new(context_with_skill)
        instance.call
      end
    end
    
    private
    
    def execute_with_timeout(&block)
      timeout = Rails.application.config.agent_skills.timeout
      
      # Use Concurrent::TimerTask for thread-safe timeout
      timer = Concurrent::TimerTask.new(timeout: timeout) do
        block.call
      end
      
      timer.execute
      result = timer.wait
      
      unless timer.completed?
        timer.shutdown
        raise "Skill execution timed out after #{timeout} seconds"
      end
      
      result.value
    rescue Concurrent::TimeoutError
      raise "Skill execution timed out after #{timeout} seconds"
    rescue => e
      raise e
    end
  end
end
```

### 5.2 Ruby Skill Base Class

```ruby
# app/models/agent_skills/base.rb
module AgentSkills
  class Base
    attr_reader :context
    
    # Methods that can be called on chat through this skill
    ALLOWED_CHAT_METHODS = %i[
      ask with_instructions with_params with_temperature with_model
      similarity_search
      messages user account
    ].freeze
    
    def initialize(context = {})
      @context = context.with_indifferent_access
      validate_context!
    end
    
    def call
      raise NotImplementedError, "#{self.class.name} must implement #call"
    end
    
    # Convenience accessors with controlled delegation
    delegate :query, :message, :agent_skill, :execution, to: :context
    
    # Controlled access to chat
    def chat
      @context[:chat]
    end
    
    # Controlled access to user
    def user
      @context[:user]
    end
    
    # Controlled access to account
    def account
      @context[:account]
    end
    
    # Access to RAG context if configured
    def rag_context
      @rag_context ||= agent_skill.requires_rag_context ? extract_rag_context : {}
    end
    
    # Execute a query against the LLM
    def ask(prompt, **options)
      chat.ask(prompt, **options)
    end
    
    # Execute with custom instructions
    def with_instructions(instructions, **options, &block)
      chat.with_instructions(instructions, **options, &block)
    end
    
    # Log a message
    def log(message, level: :info)
      Rails.logger.public_send(level, "[AgentSkill:#{skill_name}] #{message}")
    end
    
    # Override method_missing to restrict chat access
    def method_missing(name, *args, **kwargs, &block)
      if ALLOWED_CHAT_METHODS.include?(name)
        chat.public_send(name, *args, **kwargs, &block)
      else
        raise NoMethodError, "Skill cannot call Perl##{name} on chat. Allowed methods: #{ALLOWED_CHAT_METHODS.join(', ')}"
      end
    end
    
    # Override respond_to? to match method_missing
    def respond_to?(name, include_private = false)
      ALLOWED_CHAT_METHODS.include?(name) || super
    end
    
    private
    
    def validate_context!
      required = %i[chat query agent_skill]
      missing = required.select { |k| @context[k].nil? }
      raise ArgumentError, "Missing required context keys: #{missing.join(', ')}" if missing.any?
    end
    
    def extract_rag_context
      # Get relevant chunks for the current query
      chunks = chat.similarity_search(context[:query])
      
      {
        chunks: chunks.as_json(only: [:id, :content, :title, :source, :metadata]),
        documents: extract_documents_from_chunks(chunks)
      }
    end
    
    def extract_documents_from_chunks(chunks)
      source_ids = chunks.map { |c| c.source_id }.compact.uniq
      return [] if source_ids.empty?
      
      # Use document model if available, otherwise return empty
      return [] unless defined?(Document)
      
      Document.where(id: source_ids).as_json(
        only: [:id, :title, :content_type, :metadata]
      )
    rescue => e
      log "Failed to extract documents: #{e.message}", level: :error
      []
    end
    
    def skill_name
      self.class.name.demodulize
    end
  end
end
```

---

## 6. Trigger Detection

### 6.1 Detector

```ruby
# app/models/agent_skill/detector.rb
module AgentSkill
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
      
      detected = []
      
      # Check explicit triggers first (highest priority)
      detected += detect_explicit_trigger(enabled_skills)
      
      # Check auto triggers (only if no explicit triggers found)
      if detected.empty?
        detected += detect_auto_trigger(enabled_skills)
      end
      
      # Deduplicate by ID and sort by priority (descending)
      detected.uniq { |s| s.id }.sort_by { |s| -s.priority }
    end
    
    private
    
    # User typed /skill-name or @skill-name
    def detect_explicit_trigger(skills)
      return [] if @query.blank?
      
      # Check for /command pattern (e.g., /summarize or /summarize-document)
      if @query =~ /\A\/([a-zA-Z][a-zA-Z0-9_-]*)(\s|$)/
        skill_name = $1
        find_skills_by_name(skills, skill_name)
      elsif @query =~ /(?:^|\s)@([a-zA-Z][a-zA-Z0-9_-]*)\b/
        # @mention pattern - can appear anywhere in the query
        skill_name = $1
        find_skills_by_name(skills, skill_name)
      else
        []
      end
    end
    
    # LLM determines which skills to trigger based on query intent
    def detect_auto_trigger(skills)
      auto_skills = skills.select { |s| s.trigger_mode.in?(%w[auto combined]) }
      return [] if auto_skills.empty?
      return [] unless guard_model_available?
      
      create_guard_chat do |guard_chat|
        skill_prompts = auto_skills.map do |s|
          "- #{s.name}: #{s.sanitized_description}"
        end.join("\n")
        
        prompt = <<~PROMPT
          Analyze the user query below and determine which skill(s) from the available skills 
          would be most helpful to answer it. Only trigger skills that are directly relevant.
          
          User query: "#{AgentSkill::Security.sanitize_prompt(@query)}"
          
          Available skills:
          #{skill_prompts}
          
          Respond with a JSON array of skill names that should be triggered.
          Return an empty array [] if no skills are relevant.
          ONLY respond with valid JSON, nothing else.
        PROMPT
        
        response = guard_chat.ask(prompt)
        parse_skill_names(response.content, auto_skills)
      end
    end
    
    def find_skills_by_name(skills, name)
      skills.select do |s|
        s.name.casecmp(name).zero? || s.name.parameterize == name
      end
    end
    
    def detect_mcp_trigger(skills)
      # MCP deferred to future - return empty for now
      []
    end
    
    def guard_model_available?
      ENV["GUARD_MODEL"].present?
    end
    
    def create_guard_chat(&block)
      guard_chat = @chat.chats.create!(
        account: @chat.account,
        user: @chat.user,
        model: ENV["GUARD_MODEL"],
        provider: :openai,
        assume_model_exists: true
      )
      guard_chat.assume_model_exists = true
      
      block.call(guard_chat)
    ensure
      guard_chat&.destroy
    end
    
    def parse_skill_names(json_string, available_skills)
      return [] unless json_string
      
      begin
        skill_names = JSON.parse(json_string.strip)
        return [] unless skill_names.is_a?(Array)
        
        available_skills.select { |s| skill_names.include?(s.name) }
      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse skill trigger response: #{e.message}"
        []
      end
    end
  end
end
```

---

## 7. Chat Integration

### 7.1 AgentSkillable Concern

**CRITICAL FIX:** Removed the `complete_with_nosia` override that caused infinite loop risk. Instead, `complete_with_agent_skills` is a separate method that `ChatResponseJob` calls directly, and it falls back to `complete_with_nosia` only when no skills are triggered.

```ruby
# app/models/chat/agent_skillable.rb
module Chat::AgentSkillable
  extend ActiveSupport::Concern
  
  included do
    has_many :agent_skill_executions, dependent: :destroy
  end
  
  # Main entry point - complete with agent skills enabled
  # This is called by ChatResponseJob instead of complete_with_nosia
  def complete_with_agent_skills(question, **options)
    # Detect which skills should be triggered
    skills = AgentSkill::Detector.detect(self, question)
    
    if skills.any?
      skill_results = execute_skills(skills, question, options)
      
      if skill_results.any?
        # Create messages from skill results
        skill_messages = format_skill_results(skill_results, skills)
        skill_messages.each do |msg|
          messages.create!(msg.merge(
            agent_skill_execution: true,
            metadata: (msg[:metadata] || {}).merge(agent_skill_names: skills.map(&:name))
          ))
        end
        
        # Return the last skill result as the primary response
        return skill_messages.last
      end
    end
    
    # No skills triggered or skills returned nil/empty, use normal completion
    complete_with_nosia(question, **options)
  end
  
  # Execute all detected skills
  def execute_skills(skills, query, options)
    results = []
    
    skills.each do |skill|
      begin
        context = build_skill_context(query, skill, options)
        result = AgentSkill::Executor.execute(skill, context: context)
        results << result
      rescue => e
        # Log error but continue with other skills
        Rails.logger.error "[AgentSkills] Skill #{skill.name} failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        # Return nil to skip this skill's result
        results << nil
      end
    end
    
    results.compact
  end
  
  private
  
  def build_skill_context(query, agent_skill, options)
    {
      chat: self,
      user: user,
      account: account,
      query: query,
      agent_skill: agent_skill,
      options: options,
      messages: messages.to_a,
      current_message: messages.last,
      trigger_method: "detected"
    }
  end
  
  def format_skill_results(results, skills)
    results.map.with_index do |result, index|
      case result
      when Hash
        {
          role: result[:role] || "assistant",
          content: result[:content],
          response_number: messages.count + index,
          metadata: (result[:metadata] || {}).merge(agent_skill_names: skills.map(&:name))
        }.merge(result.except(:role, :content, :metadata))
      when String
        {
          role: "assistant",
          content: result,
          response_number: messages.count + index,
          metadata: { agent_skill_names: skills.map(&:name) }
        }
      when Message
        result.as_json(only: [:role, :content, :response_number, :metadata]).merge(
          metadata: (result.metadata || {}).merge(agent_skill_names: skills.map(&:name))
        )
      else
        {
          role: "assistant",
          content: result.to_s,
          response_number: messages.count + index,
          metadata: { agent_skill_names: skills.map(&:name) }
        }
      end
    end
  end
end
```

**Updated Chat Model:**

```ruby
# app/models/chat.rb
class Chat < ApplicationRecord
  include AnswerRelevance
  include AugmentedPrompt
  include Completionable
  include ContextRelevance
  include ModelContextProtocol
  include SimilaritySearch
  include AgentSkillable  # <-- Add this line (note: was Skillable, now AgentSkillable)
  
  acts_as_chat
  broadcasts_to ->(chat) { [ chat, "messages" ] }
  
  belongs_to :account
  belongs_to :chat, optional: true
  belongs_to :user
  has_many :chats, dependent: :destroy
  has_many :messages, dependent: :destroy
  has_many :agent_skill_executions, dependent: :destroy
  
  scope :root, -> { where(chat_id: nil) }
  
  # ... existing methods
end
```

---

## 8. Security

### 8.1 Security Module

```ruby
# app/models/agent_skill/security.rb
module AgentSkill
  module Security
    extend self
    
    FILE_ALLOWLIST = %w[.md .markdown .txt .yaml .yml .json].freeze
    MAX_FILE_SIZE = ENV.fetch("AGENT_SKILLS_MAX_FILE_SIZE", 1_048_576).to_i # 1MB
    MAX_TOTAL_SIZE = 10 * MAX_FILE_SIZE # 10MB
    
    # Prompt injection patterns to remove
    PROMPT_INJECTION_PATTERNS = [
      /<\|?im\|?\s*start\s*of\s*prompt\s*>/i,
      /<\|?im\|?\s*end\s*of\s*prompt\s*>/i,
      /<\|?im\|?\s*instruction\s*>/i,
     /<\|?user\s*>/i,
      /<\|?assistant\s*>/i,
      /<\|?system\s*>/i,
      /####/,
      /```/,
      /---\s*$/,
      /\n\n\n/,
      /[\[\]]/,
      /\{\|\}/
    ].freeze
    
    # Sanitize text for display
    def sanitize_text(text)
      return "" unless text
      
      # Basic HTML escaping
      text = ActionView::Helpers::TextHelper.strip_tags(text.to_s)
      
      # Limit length
      text[0...10_000]
    end
    
    # Sanitize text for use in LLM prompts
    def sanitize_prompt(text)
      return "" unless text
      
      sanitized = text.to_s
      
      # Remove prompt injection patterns
      PROMPT_INJECTION_PATTERNS.each do |pattern|
        sanitized = sanitized.gsub(pattern, "")
      end
      
      # Normalize whitespace
      sanitized = sanitized.gsub(/[\r\n]+/, " ")
      sanitized = sanitized.gsub(/\s+/, " ")
      sanitized = sanitized.strip
      
      # Limit length to prevent prompt stuffing
      sanitized[0...8000]
    end
    
    # Validate file upload
    def validate_upload(files)
      total_size = files.sum(&:size)
      return [false, "Total size exceeds #{MAX_TOTAL_SIZE / 1_048_576}MB"] if total_size > MAX_TOTAL_SIZE
      
      files.each do |file|
        extension = File.extname(file.filename.to_s).downcase
        unless FILE_ALLOWLIST.include?(extension)
          return [false, "File type '#{extension}' not allowed. Allowed: #{FILE_ALLOWLIST.join(', ')}"]
        end
        return [false, "File '#{file.filename}' exceeds #{MAX_FILE_SIZE / 1_048_576}MB"] if file.size > MAX_FILE_SIZE
      end
      
      [true, nil]
    end
  end
end
```

### 8.2 Model Integration

```ruby
# app/models/agent_skill.rb (add validation)
class AgentSkill < ApplicationRecord
  # ... existing code
  
  validate :validate_uploaded_files
  
  private
  
  def validate_uploaded_files
    return unless skill_md_attached? || files.attached?
    
    all_files = files + [skill_md].compact
    valid, error = AgentSkill::Security.validate_upload(all_files)
    errors.add(:base, error) unless valid
  end
end
```

---

## 9. Controllers

### 9.1 Web Controller

```ruby
# app/controllers/agent_skills_controller.rb
class AgentSkillsController < ApplicationController
  before_action :set_account
  before_action :set_agent_skill, only: [:show, :edit, :update, :destroy, :toggle]
  before_action :authorize_agent_skill, only: [:edit, :update, :destroy, :toggle]
  
  # GET /agent_skills
  def index
    @agent_skills = @account.agent_skills.order(priority: :desc, created_at: :asc)
  end
  
  # GET /agent_skills/new
  def new
    @agent_skill = @account.agent_skills.new
  end
  
  # POST /agent_skills
  def create
    @agent_skill = @account.agent_skills.new(agent_skill_params)
    
    if @agent_skill.save
      redirect_to agent_skills_path, notice: t(".created")
    else
      render :new
    end
  end
  
  # GET /agent_skills/:id
  def show
  end
  
  # GET /agent_skills/:id/edit
  def edit
  end
  
  # PATCH /agent_skills/:id
  def update
    if @agent_skill.update(agent_skill_params)
      redirect_to agent_skills_path, notice: t(".updated")
    else
      render :edit
    end
  end
  
  # DELETE /agent_skills/:id
  def destroy
    @agent_skill.destroy
    redirect_to agent_skills_path, notice: t(".destroyed")
  end
  
  # PATCH /agent_skills/:id/toggle
  def toggle
    @agent_skill.update!(enabled: !@agent_skill.enabled)
    redirect_to agent_skills_path, notice: t(".toggled")
  end
  
  private
  
  def set_account
    @account = Current.account
  end
  
  def set_agent_skill
    @agent_skill = @account.agent_skills.find(params[:id])
  end
  
  def authorize_agent_skill
    authorize @agent_skill
  end
  
  def agent_skill_params
    params.require(:agent_skill).permit(
      :name, :description, :execution_mode, :trigger_mode,
      :requires_rag_context, :enabled, :priority,
      files: [], skill_md: []
    )
  end
end
```

### 9.2 API Controller

```ruby
# app/controllers/api/v1/agent_skills_controller.rb
module Api
  module V1
    class AgentSkillsController < ApplicationController
      before_action :set_account
      
      # GET /api/v1/agent_skills
      def index
        @agent_skills = current_account.agent_skills.order(priority: :desc, created_at: :asc)
        render json: @agent_skills, status: :ok
      end
       
      # POST /api/v1/agent_skills
      def create
        @agent_skill = current_account.agent_skills.new(agent_skill_params)
        
        if @agent_skill.save
          render json: @agent_skill, status: :created
        else
          render json: { errors: @agent_skill.errors.full_messages }, status: :unprocessable_entity
        end
      end
       
      # GET /api/v1/agent_skills/:id
      def show
        @agent_skill = current_account.agent_skills.find(params[:id])
        render json: @agent_skill, status: :ok
      end
       
      # PATCH /api/v1/agent_skills/:id
      def update
        @agent_skill = current_account.agent_skills.find(params[:id])
        
        if @agent_skill.update(agent_skill_params)
          render json: @agent_skill, status: :ok
        else
          render json: { errors: @agent_skill.errors.full_messages }, status: :unprocessable_entity
        end
      end
       
      # DELETE /api/v1/agent_skills/:id
      def destroy
        @agent_skill = current_account.agent_skills.find(params[:id])
        @agent_skill.destroy
        head :no_content
      end
       
      private
       
      def set_account
        @account = Current.account
      end
       
      def agent_skill_params
        params.require(:agent_skill).permit(
          :name, :description, :execution_mode, :trigger_mode,
          :requires_rag_context, :enabled, :priority
        )
      end
    end
  end
end
```

---

## 10. File Structure

**UPDATED** to reflect new naming and organization:

```
app/
├── models/
│   ├── agent_skill.rb                    # ActiveRecord model
│   ├── agent_skill/
│   │   ├── parser.rb                     # Parses SKILL.md format
│   │   ├── executor.rb                   # Routes execution (LLMExecutor, RubyExecutor)
│   │   ├── detector.rb                   # Detects when to trigger skills
│   │   └── security.rb                   # Security validations and sanitization
│   ├── agent_skills/                     # Ruby skill implementations
│   │   ├── base.rb                       # Base class for Ruby skills
│   │   └── document_summarizer.rb       # Example: AgentSkills::DocumentSummarizer
│   └── chat/
│       └── agent_skillable.rb           # Chat concern for skill integration
│
├── models/
│   └── agent_skill_execution.rb         # Audit trail model
│
├── controllers/
│   ├── agent_skills_controller.rb      # Web UI for skill management
│   └── api/v1/
│       └── agent_skills_controller.rb   # API endpoints
│
├── views/agent_skills/                  # Views for skill management
│   ├── index.html.erb
│   ├── new.html.erb
│   ├── edit.html.erb
│   ├── show.html.erb
│   └── _form.html.erb
│
└── jobs/
    └── chat_response_job.rb              # Updated to use complete_with_agent_skills
```

---

## 11. Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # Web UI for skill management
  resources :agent_skills, only: [:index, :new, :create, :show, :edit, :update, :destroy] do
    member do
      patch :toggle
    end
  end
  
  # API endpoints
  namespace :api do
    namespace :v1 do
      resources :agent_skills, only: [:index, :create, :show, :update, :destroy]
    end
  end
  
  # Existing routes...
end
```

---

## 12. Job Updates

### 12.1 Chat Response Job

```ruby
# app/jobs/chat_response_job.rb
class ChatResponseJob < ApplicationJob
  queue_as :real_time
  
  def perform(chat_id, content, user_message_id = nil)
    Rails.logger.info "=== ChatResponseJob started for chat ##{chat_id} ==="
    chat = Chat.find(chat_id)
    user_message = user_message_id ? Message.find(user_message_id) : nil
    Rails.logger.info "User message: #{user_message&.id} - Content: #{content[0..100]}..."
    
    # Use agent skill-aware completion if enabled
    if Rails.application.config.agent_skills.enabled
      result = chat.complete_with_agent_skills(content, user_message: user_message)
    else
      result = chat.complete_with_nosia(content, user_message: user_message)
    end
    
    Rails.logger.info "=== ChatResponseJob completed. Result: #{result&.id} ==="
  rescue Faraday::TimeoutError => e
    Rails.logger.error "=== ChatResponseJob ERROR: Timeout ==="
    Rails.logger.error e.message
  rescue Faraday::Error => e
    Rails.logger.error "=== ChatResponseJob ERROR: Network error ==="
    Rails.logger.error e.message
  rescue => e
    Rails.logger.error "=== ChatResponseJob ERROR: #{e.class} ==="
    Rails.logger.error e.message
    Rails.logger.error e.backtrace.join("\n")
  end
end
```

---

## 13. Configuration

### 13.1 Initializer

```ruby
# config/initializers/agent_skills.rb
Rails.application.config.agent_skills = ActiveSupport::OrderedOptions.new
Rails.application.config.agent_skills.enabled = ENV.fetch("AGENT_SKILLS_ENABLED", "true") == "true"
Rails.application.config.agent_skills.max_file_size = ENV.fetch("AGENT_SKILLS_MAX_FILE_SIZE", "1048576").to_i
Rails.application.config.agent_skills.timeout = ENV.fetch("AGENT_SKILLS_TIMEOUT", "30").to_i
Rails.application.config.agent_skills.requires_approval = ENV.fetch("AGENT_SKILLS_REQUIRES_APPROVAL", "false") == "true"

# Require all skill base classes for eager loading
if Rails.env.development? || Rails.env.test?
  Dir.glob(Rails.root.join("app/models/agent_skills/**/*.rb")).each do |file|
    begin
      require_dependency file
    rescue => e
      Rails.logger.error "Failed to load skill file #{file}: #{e.message}"
    end
  end
  
  # Validate all skills on startup (development only)
  if Rails.env.development?
    AgentSkills::Base.descendants.each do |klass|
      begin
        klass.validate! if klass.respond_to?(:validate!)
      rescue => e
        Rails.logger.error "Skill validation failed for #{klass.name}: #{e.message}"
      end
    end
  end
end
```

### 13.2 Environment Variables

```bash
# Required: None (has sensible defaults)

# Optional:
AGENT_SKILLS_ENABLED=true           # Enable/disable the feature (default: true)
AGENT_SKILLS_MAX_FILE_SIZE=1048576  # Max file size in bytes (1MB default)
AGENT_SKILLS_TIMEOUT=30              # Ruby skill timeout in seconds (30 default)
AGENT_SKILLS_REQUIRES_APPROVAL=false # Require admin approval for new skills (default: false)
```

---

## 14. Migration & Rollout

### 14.1 Migration Plan

**Phase 1: Core Infrastructure (Week 1-2)**
- Create AgentSkill model + migrations
- Create AgentSkillExecution model + migration
- Implement AgentSkill::Parser
- Implement AgentSkill::Security
- Add AgentSkillable concern to Chat (LLM-only mode)
- Create basic upload UI
- Add explicit trigger detection
- Fix all critical issues from spec review

**Phase 2: Ruby Skills (Week 3-4)**
- Implement AgentSkills::Base
- Add RubyExecutor
- Create example Ruby skills in `app/models/agent_skills/`
- Add security validations (method whitelist)
- Documentation for skill authors

**Phase 3: Advanced Features (Week 5-6)**
- Auto-trigger detection using guard model
- Performance optimizations
- Improved error handling and logging
- Add system tests

### 14.2 Feature Flag

Use `Rails.application.config.agent_skills.enabled` to:
- Disable the feature entirely (set `AGENT_SKILLS_ENABLED=false`)
- Roll out to specific accounts first
- Gradual deployment

---

## 15. Testing Strategy

### 15.1 Unit Tests

**`test/models/agent_skill_test.rb`**
- Validations (name presence and format, mode enums, account scoping)
- File attachment requirements
- Parser integration with edge cases
- Metadata extraction and validation from SKILL.md
- `runnable?` method behavior

**`test/models/agent_skill/executor_test.rb`**
- LLMExecutor: prompt injection and sanitization
- RubyExecutor: class instantiation, method calling, timeout
- Error handling for missing classes
- Execution record creation and updates

**`test/models/agent_skill/detector_test.rb`**
- Explicit trigger detection (`/skill-name`, `@skill-name`)
- Regex handling for hyphenated skill names
- Auto trigger detection (mock LLM responses)
- Skill sorting by priority

**`test/models/agent_skill/security_test.rb`**
- File type validation
- Prompt sanitization
- Input length limiting
- Injection pattern removal

**`test/models/chat/agent_skillable_test.rb`**
- `complete_with_agent_skills` routing
- Skill result formatting
- Fallback to `complete_with_nosia`
- Error isolation between skills

**`test/models/agent_skill_execution_test.rb`**
- Record creation on skill execution
- Status updates
- Association validations

### 15.2 Integration Tests

**`test/integration/agent_skills_flow_test.rb`**
- Full flow: upload skill → trigger via chat → verify response
- Ruby skill execution in context
- LLM skill injection
- Audit trail verification

### 15.3 System Tests

**`test/system/agent_skills_test.rb`**
- UI upload flow
- Agent Skill management CRUD
- Skill triggering from chat via `/skill-name`
- Skill triggering from chat via `@skill-name`
- Error display for failed skills

---

## 16. Example Skills

### 16.1 LLM-Driven Skill (SKILL.md only)

**Note:** No `.rb` file needed. The SKILL.md is parsed and its instructions are injected into the LLM prompt.

```markdown
---
name: document-summarizer
description: Summarizes uploaded documents based on user queries
version: 1.0.0
author: Nosia Team
tags:
  - summarization
  - documents
execution_mode: llm
trigger_mode: combined
requires_rag_context: true
---

## When to Use

Use this skill when the user asks for a summary of documents or specific document content.
Used when queries contain words like: summarize, summary, overview, recap, main points.

## Instructions

You are a document summarization expert. When invoked, analyze the provided document chunks 
and create a comprehensive but concise summary.

1. Read all provided document chunks carefully
2. Identify the main topics and key points
3. Group related information together logically
4. Preserve important details: numbers, names, dates, facts
5. Note any contradictions or gaps in the source material
6. Format the summary with clear markdown section headers

## Output Format

Always respond with:

### Summary Overview
[1-2 sentence overview]

### Key Points
- [Bulleted list of main points]
- [Each point on its own line]

### Important Details
[Any critical numbers, names, dates, or facts]

---

### Sources Consulted
[List of document names that informed this summary]

## Examples

**User:** Summarize the Q1 report
**Assistant:** [Provides structured summary based on retrieved chunks]

**User:** What are the main points from the project documentation?
**Assistant:** [Bulleted list of key points from relevant documents]
```

### 16.2 Ruby-Based Skill

**File:** `app/models/agent_skills/document_summarizer.rb`

```ruby
# app/models/agent_skills/document_summarizer.rb
module AgentSkills
  class DocumentSummarizer < Base
    def call
      chunks = rag_context[:chunks]
      
      if chunks.empty?
        return {
          content: "No documents found matching your query.",
          role: "assistant",
          metadata: { source: "document_summarizer", documents_found: 0 }
        }
      end
      
      # Group chunks by source
      by_source = chunks.group_by { |c| c[:source] }
      
      summaries = by_source.map do |source, source_chunks|
        content = source_chunks.map { |c| c[:content] }.join("\n\n")
        summarize_content(content, source)
      end
      
      formatted_response = format_response(summaries, by_source.keys)
      
      {
        content: formatted_response,
        role: "assistant",
        metadata: { source: "document_summarizer", documents_consulted: by_source.keys }
      }
    end
    
    private
    
    def summarize_content(content, source)
      # Trim content to avoid token limits
      trimmed_content = content[0...4000]
      
      summary = with_instructions(summarization_prompt(source)) do
        ask("Please summarize the following content from source '#{source}':\n\n#{trimmed_content}")
      end.content
      
      summary
    end
    
    def summarization_prompt(source)
      <<~PROMPT
        You are a document summarization assistant. Create a concise summary of the provided content.
        Focus on: main points, key data, important names, dates, and conclusions.
        Use markdown formatting.
        Source: #{source}
        Respond only with the summary, no additional commentary.
      PROMPT
    end
    
    def format_response(summaries, sources)
      <<~RESPONSE
        ## Document Summary
        
        #{summaries.join("\n\n---\n\n")}
        
        ---
        
        **Sources Consulted:** #{sources.join(", ")}
      RESPONSE
    end
  end
end
```

**Matching SKILL.md:**

```markdown
---
name: document_summarizer
description: Advanced document summarizer that extracts key information from relevant documents
version: 1.0.0
author: Nosia Team
tags:
  - summarization
  - documents
  - analysis
execution_mode: ruby
trigger_mode: combined
requires_rag_context: true
---

## When to Use

Use this skill when the user requests in-depth summarization or analysis of documents.

## Instructions

This skill is implemented as a Ruby class that:
1. Retrieves relevant document chunks based on the query
2. Groups them by source
3. Uses the LLM to summarize each source
4. Combines results into a formatted response

## Configuration

Requires RAG context access to be enabled.

## Dependencies

None - uses standard Nosia RAG infrastructure.
```

---

## 17. Critical Issues Addressed

Based on the v1 spec review, the following **critical issues** have been resolved in this v2 revision:

| Issue | Resolution | Location |
|-------|------------|----------|
| `Skill` naming conflict | Renamed to `AgentSkill` to avoid conflict with `Skill::` modules | Section 4.2, 4.3, 7.1 |
| Missing `skill_executions` table | Added `AgentSkillExecution` model with migration | Section 4.1, 4.2 |
| Infinite loop in `complete_with_nosia` | Removed override; `complete_with_agent_skills` is separate method | Section 7.1 |
| Ruby skill file loading | Clarified: Ruby skills in `app/models/agent_skills/`, not from uploads | Section 10, 16.2 |
| Parser missing required field validation | Added `validate_metadata!` with REQUIRED_FIELDS check | Section 4.3 |
| No input sanitization for LLM prompts | Added `AgentSkill::Security.sanitize_prompt` | Section 8.1, 5.1 |
| `Timeout.timeout` not thread-safe | Replaced with `Concurrent::TimerTask` | Section 5.1, RubyExecutor |
| Skills namespace confusion | Restructured to `AgentSkill` (model modules) and `AgentSkills` (user code) | Section 10 |

---

## 18. Open Questions & Decisions Log

| Date | Question | Decision | Rationale |
|------|---------|----------|-----------|
| 2025-04-15 | Skill execution model | Hybrid LLM + Ruby | Balances simplicity and power |
| 2025-04-15 | Skill scoping | Account-scoped only | Consistent with Nosia's architecture |
| 2025-04-15 | Upload mechanism | Manual via web UI | Simplest for MVP |
| 2025-04-15 | Trigger mechanism | Combined (explicit + auto) | Maximum flexibility (MCP deferred) |
| 2025-04-15 | RAG access | Configurable per skill | Skills can opt-in to context |
| 2025-04-15 | Versioning | Manual updates only | Keep it simple for now |
| 2025-04-15 | MCP integration | Deferred to future | Focus on core first (v2) |
| 2025-04-15 | Model naming | `AgentSkill` (not `Skill`) | Resolves namespace conflict (v2) |
| 2025-04-15 | Audit trail | Added `AgentSkillExecution` | For debugging and analytics (v2) |
| 2025-04-15 | Thread safety | Use `Concurrent::TimerTask` | Safe for Solid Queue (v2) |

---

## 19. Future Enhancements

### High Priority
1. **Skill registry integration** - Browse and install from agentskills.io
2. **Git repository support** - Pull skills from GitHub/GitLab
3. **MCP-based skills** - Re-add MCP execution mode (was removed for MVP)
4. **Skill dependencies** - Skills that depend on other skills
5. **Skill testing framework** - Test skills in isolation

### Medium Priority
1. **Skill versioning** - Track versions, enable rollback
2. **Skill sharing** - Share skills between accounts (with permissions)
3. **Public skill catalog** - Nosia-hosted skill directory
4. **Usage analytics** - Track which skills are used most
5. **Async skill parsing** - Parse SKILL.md files via background job

### Low Priority
1. **Sandboxed execution** - Run skills in containers for security
2. **Multi-language skills** - Support Python, Node.js, etc.
3. **Skill marketplace** - Monetization for skill authors
4. **AI skill generation** - Generate skills from natural language descriptions

---

## 20. Appendix

### 20.1 Glossary

| Term | Definition |
|------|------------|
| Agent Skills | Modular capabilities for AI agents, defined by agentskills.io |
| SKILL.md | Standard format for defining skills (YAML frontmatter + Markdown) |
| LLM-Driven | Skills executed by injecting instructions into the LLM prompt |
| Ruby-Driven | Skills implemented as Ruby classes |
| Trigger Mode | How a skill is invoked (explicit, auto, combined) |
| RAG Context | Documents and chunks accessible to the skill |
| AgentSkill | The database model for storing skill metadata and files |
| AgentSkills | The namespace for Ruby skill implementations |

### 20.2 References

- [agentskills.io](https://agentskills.io) - Official Agent Skills website
- [SKILL.md Format Specification](https://agentskills.io/what-are-skills) - SKILL.md format details
- [Nosia Architecture](https://github.com/nosia-ai/nosia/blob/main/docs/ARCHITECTURE.md) - Nosia's architecture
- [Nosia Principles](https://github.com/nosia-ai/nosia/blob/main/docs/PRINCIPLES.md) - Guiding principles
- [Concurrent Ruby](https://github.com/ruby-concurrency/concurrent-ruby) - Thread-safe timer implementation

---

## 21. Approval

**Designer:** Mistral Vibe  
**Date:** 2025-04-15  
**Revision:** v2 (Addressing Critical Issues)  

**Approvers:**
- [ ] @nosia-core-maintainer
- [ ] @nosia-team (team review)

**Approval Date:** ___________

**Implementation Start Date:** ___________

---

*This document is a living specification. Updates should be recorded in the Decisions Log (Section 18).*
