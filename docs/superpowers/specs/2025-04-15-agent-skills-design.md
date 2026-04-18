# Agent Skills Implementation - Design Specification

**Date:** 2025-04-15  
**Status:** Draft  
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
- Combined triggering: explicit invocation, LLM auto-detection, and MCP tool discovery
- Configurable RAG context access per skill

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
- [ ] Ruby skills follow a standardized pattern (inherit from `Skills::Base`)
- [ ] Skills integrate with existing Chat/Bot completion flow
- [ ] Manual update only (no auto-versioning)

### 2.2 Non-Goals

- [ ] Integration with agentskills.io registry (manual upload only)
- [ ] Git repository support for skills
- [ ] Automatic skill updates or version checking
- [ ] Sandboxed execution for Ruby skills (run in-process with controlled API)
- [ ] Multi-language skill support (Ruby only for complex skills)
- [ ] Skill marketplace or sharing between accounts

---

## 3. Architecture

### 3.1 High-Level Overview

```
┌─────────────────┐     ┌──────────────┐     ┌─────────────────┐
│   User Request  │────▶│ Skill Router │────▶│ Skill Executor │
└─────────────────┘     └──────────────┘     └────────┬────────┘
                                                     │
                    ┌────────────────────────────────────┼────────────────────────────────────┐
                    │                                        │                            │
                    ▼                                        ▼                            ▼
           ┌─────────────────┐             ┌───────────────┐            ┌─────────────────┐
           │  LLM execution   │             │ Ruby execution │            │ MCP tool bridge │
           │ (prompt inject)  │             │ (in-process)   │            │    (future)      │
           └─────────────────┘             └───────────────┘            └─────────────────┘
```

### 3.2 Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        User Interface                                │
├─────────────────────────────────────────────────────────────────┤
│  Web UI: Skills Management (#index, #new, #create, #show)        │
│  - Upload SKILL.md and related files                              │
│  - Enable/disable skills                                         │
│  - Configure trigger modes                                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        API Layer                                   │
├─────────────────────────────────────────────────────────────────┤
│  Api::V1::SkillsController                                        │
│  - REST endpoints for skill management                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Domain Models                                  │
├─────────────────────────────────────────────────────────────────┤
│  Skill (AR)                                                         │
│  - account_id, name, description, execution_mode, trigger_mode    │
│  - requires_rag_context, enabled, priority, metadata (jsonb)     │
│  - has_many_attached :files (Active Storage)                      │
│  - has_one_attached :skill_md                                      │
│                                                                     │
│  skill/parser.rb                                                     │
│  - Parses SKILL.md format (YAML frontmatter + Markdown body)     │
│                                                                     │
│  skill.executor.rb                                                  │
│  - LLMExecutor: Injects skill instructions into LLM prompt      │
│  - RubyExecutor: Calls Ruby skill class methods                  │
│                                                                     │
│  skill/detector.rb                                                  │
│  - Detects which skills to trigger based on query/notice          │
│                                                                     │
│  skill/registry.rb (optional future)                               │
│  - In-memory cache of loaded skills per account                   │
│                                                                     │
│  Chat::Skillable (Concern)                                          │
│  - Mixin for Chat model                                           │
│  - complete_with_skills() method                                  │
│                                                                     │
│  Skills::Base                                                       │
│  - Base class for Ruby skills                                     │
│  - Provides access to context, RAG, LLM                            │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┴─────────────────────┐
        │                                       │
        ▼                                       ▼
   ┌─────────────────┐                  ┌─────────────────┐
   │ Ruby Skill      │                  │ LLM Integration │
   │ Implementation  │                  │ (RubyLLM)       │
   │                 │                  │                 │
   │ app/models/     │◄─────────────────┤ Existing        │
   │ skills/         │                  │ Chat infrastructure│
   └─────────────────┘                  └─────────────────┘
```

### 3.3 Data Flow

**User submits chat message:**
1. `MessagesController#create` receives request
2. Creates user message, queues `ChatResponseJob`
3. `ChatResponseJob` calls `chat.complete_with_skills(query)`

**In `complete_with_skills`:**
1. `Skill::Detector.detect(chat, query)` identifies relevant skills
2. For each skill:
   - Build context with chat, user, query, skill, options
   - `Skill::Executor.execute(skill, context: context)` 
3. LLMExecutor: Injects skill instructions, calls LLM
4. RubyExecutor: Instantiates skill class, calls `#call`
5. Results formatted as messages and added to chat
6. If no skills triggered, fall back to `complete_with_nosia`

---

## 4. Data Model

### 4.1 Database Schema

#### Migration: Create Skills Table

```ruby
# db/migrate/[timestamp]_create_skills.rb
class CreateSkills < ActiveRecord::Migration[8.0]
  def change
    create_table :skills do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :execution_mode, null: false, default: "llm" # llm, ruby, mcp
      t.string :trigger_mode, null: false, default: "explicit" # explicit, auto, mcp, combined
      t.jsonb :metadata, default: {} # parsed YAML frontmatter from SKILL.md
      t.boolean :requires_rag_context, default: false
      t.boolean :enabled, default: true
      t.integer :priority, default: 0
      t.timestamps
    end

    add_index :skills, [:account_id, :name], unique: true
    add_index :skills, [:account_id, :enabled]
    add_index :skills, [:account_id, :execution_mode]
    add_index :skills, [:account_id, :trigger_mode]
  end
end
```

### 4.2 Active Record Model

```ruby
# app/models/skill.rb
class Skill < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  
  has_many_attached :files
  has_one_attached :skill_md
  
  enum :execution_mode, { llm: "llm", ruby: "ruby", mcp: "mcp" }
  enum :trigger_mode, { explicit: "explicit", auto: "auto", mcp: "mcp", combined: "combined" }
  
  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :execution_mode, presence: true
  validates :trigger_mode, presence: true
  validate :validate_skill_md_present, on: :create
  
  after_save :parse_skill_md, if: -> { skill_md_attached? && (skill_md_changed? || skill_md_attached?) }
  
  # Get the Ruby class name for ruby-mode skills
  def ruby_class_name
    "Skills::#{name.camelize}"
  end
  
  # Check if Ruby implementation exists
  def ruby_implementation_exists?
    execution_mode == "ruby" && ruby_class_name.safe_constantize.present?
  end
  
  # Check if skill is runnable
  def runnable?
    enabled? && 
      (execution_mode == "llm" || 
       (execution_mode == "ruby" && ruby_implementation_exists?) ||
       (execution_mode == "mcp" && mcp_server_configured?))
  end
  
  # Get the instructions for LLM-mode skills
  def instructions
    metadata["instructions"] || parsed_content
  end
  
  # Get parsed content from SKILL.md
  def parsed_content
    @parsed_content ||= skill_md_attached? ? skill_md.download : ""
  rescue => e
    Rails.logger.error "Failed to read skill content: #{e.message}"
    ""
  end
  
  private
  
  def validate_skill_md_present
    errors.add(:skill_md, "must be attached") unless skill_md.attached?
  end
  
  def parse_skill_md
    Skill::Parser.new(self).parse
  end
  
  def mcp_server_configured?
    # Future: link to MCP server
    false
  end
end
```

### 4.3 Skill Parser

```ruby
# app/models/skill/parser.rb
module Skill
  class Parser
    def initialize(skill)
      @skill = skill
    end
    
    def parse
      return unless @skill.skill_md.attached?
      
      content = @skill.skill_md.download
      yaml_content, markdown_body = split_frontmatter(content)
      
      metadata = parse_yaml(yaml_content)
      
      @skill.update!(
        metadata: metadata,
        description: metadata["description"] || markdown_body.split("\n").first,
        name: metadata["name"] || @skill.name # Allow override via YAML
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
      return {} unless yaml_content
      YAML.safe_load(yaml_content) || {}
    rescue Psych::SyntaxError => e
      Rails.logger.error "Invalid YAML in SKILL.md for skill ##{@skill.id}: #{e.message}"
      {}
    end
  end
end
```

---

## 5. Execution Subsystem

### 5.1 Executor (Main Router)

```ruby
# app/models/skill/executor.rb
module Skill
  class Executor
    class << self
      def execute(skill, context:)
        new(skill, context).call
      end
    end
    
    def initialize(skill, context)
      @skill = skill
      @context = context.with_indifferent_access
    end
    
    def call
      raise "Skill is not runnable" unless @skill.runnable?
      
      case @skill.execution_mode.to_sym
      when :llm
        LLMExecutor.new(@skill, @context).call
      when :ruby
        RubyExecutor.new(@skill, @context).call
      when :mcp
        MCPExecutor.new(@skill, @context).call
      end
    end
  end
  
  # LLM Execution - Injects skill instructions into the prompt
  class LLMExecutor
    def initialize(skill, context)
      @skill = skill
      @context = context
    end
    
    def call
      chat = @context[:chat]
      instructions = build_instructions
      
      # Save original instructions to restore later
      original_instructions = chat.instance_variable_get(:@instructions)
      
      begin
        chat.with_instructions(instructions, replace: false) do
          chat.ask(@context[:query])
        end
      ensure
        # Restore original instructions
        chat.instance_variable_set(:@instructions, original_instructions) if original_instructions
      end
    end
    
    private
    
    def build_instructions
      parts = []
      parts << "## Skill: #{@skill.name}"
      parts << ""
      parts << "**Description:** #{@skill.description}"
      parts << ""
      
      if @skill.metadata["when_to_use"]
        parts << "**When to use:** #{@skill.metadata['when_to_use']}"
        parts << ""
      end
      
      parts << "**Instructions:**"
      parts << (@skill.instructions || "No additional instructions provided.")
      parts << ""
      
      parts.join("\n")
    end
  end
  
  # Ruby Execution - Calls Ruby class methods
  class RubyExecutor
    def initialize(skill, context)
      @skill = skill
      @context = context
    end
    
    def call
      klass = @skill.ruby_class_name.safe_constantize
      raise "Ruby skill class not found: #{@skill.ruby_class_name}" unless klass
      
      # Validate class inherits from Skills::Base
      unless klass < Skills::Base
        raise "Ruby skill must inherit from Skills::Base: #{@skill.ruby_class_name}"
      end
      
      # Add skill to context for access
      context_with_skill = @context.merge(skill: @skill)
      
      # Execute with timeout
      execute_with_timeout do
        klass.new(context_with_skill).call
      end
    end
    
    private
    
    def execute_with_timeout(&block)
      timeout = ENV.fetch("AGENT_SKILLS_TIMEOUT", 30).to_i
      Timeout.timeout(timeout, &block)
    rescue Timeout::Error
      raise "Skill execution timed out after #{timeout} seconds"
    end
  end
end
```

### 5.2 Ruby Skill Base Class

```ruby
# app/models/skills/base.rb
module Skills
  class Base
    attr_reader :context
    
    def initialize(context = {})
      @context = context.with_indifferent_access
    end
    
    def call
      raise NotImplementedError, "#{self.class.name} must implement #call"
    end
    
    # Convenience accessors
    delegate :chat, :user, :account, :query, :message, :skill, to: :context
    delegate :id, :name, :description, :metadata, to: :skill, prefix: :skill
    
    # Access to RAG context if configured
    def rag_context
      @rag_context ||= skill.requires_rag_context ? extract_rag_context : {}
    end
    
    # Execute a query against the LLM with skill context
    def ask(prompt, **options)
      chat.ask(prompt, **options)
    end
    
    # Execute with custom instructions
    def with_instructions(instructions, **options, &block)
      chat.with_instructions(instructions, **options, &block)
    end
    
    # Log a message
    def log(message, level: :info)
      Rails.logger.public_send(level, "[Skill:#{skill_name}] #{message}")
    end
    
    private
    
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
# app/models/skill/detector.rb
module Skill
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
      enabled_skills = @chat.account.skills.where(enabled: true).to_a
      
      detected = []
      
      # Check explicit triggers first (highest priority)
      detected += detect_explicit_trigger(enabled_skills)
      
      # Check auto triggers
      detected += detect_auto_trigger(enabled_skills)
      
      # Check MCP triggers (if applicable)
      detected += detect_mcp_trigger(enabled_skills)
      
      # Deduplicate by ID and sort by priority (descending)
      detected.uniq { |s| s.id }.sort_by { |s| -s.priority }
    end
    
    private
    
    # User typed /skill-name or @skill-name
    def detect_explicit_trigger(skills)
      return [] if @query.blank?
      
      # Check for /command pattern
      if @query =~ /\A\/(\w[\w\-]*)\s*/
        skill_name = $1
        matching = skills.select do |s|
          s.name.casecmp(skill_name).zero? || 
          s.name.parameterize == skill_name
        end
        return matching if matching.any?
      end
      
      # Check for @mention pattern
      if @query =~ /@(\w[\w\-]*)\b/
        skill_name = $1
        skills.select do |s|
          s.name.casecmp(skill_name).zero? || 
          s.name.parameterize == skill_name
        end
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
          "- #{s.name}: #{s.metadata['description'] || s.description}"
        end.join("\n")
        
        prompt = <<~PROMPT
          Analyze the user query below and determine which skill(s) from the available skills 
          would be most helpful to answer it. Only trigger skills that are directly relevant.
          
          User query: "#{@query}"
          
          Available skills:
          #{skill_prompts}
          
          Respond with a JSON array of skill names that should be triggered.
          Return an empty array [] if no skills are relevant.
          ONLY respond with valid JSON, nothing else.
        PROMPT
        
        response = guard_chat.ask(prompt)
        parse_skill_names(response.content)
      end
    end
    
    def detect_mcp_trigger(skills)
      skills.select do |s|
        s.trigger_mode.in?(%w[mcp combined]) && 
        s.execution_mode == "mcp" &&
        s.runnable?
      end
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
    
    def parse_skill_names(json_string)
      return [] unless json_string
      
      skill_names = JSON.parse(json_string.strip)
      @chat.account.skills.where(name: skill_names, enabled: true).to_a
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse skill trigger response: #{e.message}"
      []
    end
  end
end
```

---

## 7. Chat Integration

### 7.1 Skillable Concern

```ruby
# app/models/chat/skillable.rb
module Chat::Skillable
  extend ActiveSupport::Concern
  
  included do
    has_many :skill_executions, dependent: :destroy
  end
  
  # Main entry point - complete with skills enabled
  def complete_with_skills(question, **options)
    # Detect which skills should be triggered
    skills = Skill::Detector.detect(self, question)
    
    if skills.any?
      skill_results = execute_skills(skills, question, options)
      
      if skill_results.any?
        # Create messages from skill results
        skill_messages = format_skill_results(skill_results)
        skill_messages.each do |msg|
          messages.create!(msg.merge(
            skill_execution: true,
            metadata: (msg[:metadata] || {}).merge(skill_names: skills.map(&:name))
          ))
        end
        
        # Return the last skill result as the primary response
        return skill_messages.last
      end
    end
    
    # No skills triggered or skills returned nil, use normal completion
    complete_with_nosia(question, **options)
  end
  
  # Execute all detected skills
  def execute_skills(skills, query, options)
    skills.map do |skill|
      context = build_skill_context(query, skill, options)
      Skill::Executor.execute(skill, context: context)
    end
  end
  
  private
  
  def build_skill_context(query, skill, options)
    {
      chat: self,
      user: user,
      account: account,
      query: query,
      skill: skill,
      options: options,
      messages: messages.to_a,
      current_message: messages.last
    }
  end
  
  def format_skill_results(results)
    results.map.with_index do |result, index|
      case result
      when Hash
        {
          role: result[:role] || "assistant",
          content: result[:content],
          response_number: messages.count + index
        }.merge(result.except(:role, :content))
      when String
        {
          role: "assistant",
          content: result,
          response_number: messages.count + index
        }
      when Message
        result.as_json(only: [:role, :content, :response_number])
      else
        {
          role: "assistant",
          content: result.to_s,
          response_number: messages.count + index
        }
      end
    end
  end
  
  # Override to check for skill invocation first
  def complete_with_nosia(question, **options)
    # Check if this might be a skill invocation
    skills = Skill::Detector.detect(self, question)
    
    if skills.any? && skills.all? { |s| s.trigger_mode == "explicit" }
      # Only explicit skills matched - but maybe they should handle it
      # This gives skills a chance to respond
      skill_results = execute_skills(skills, question, options)
      return skill_results.last if skill_results.any?
    end
    
    super
  end
end
```

### 7.2 Chat Model Update

```ruby
# app/models/chat.rb
class Chat < ApplicationRecord
  include AnswerRelevance
  include AugmentedPrompt
  include Completionable
  include ContextRelevance
  include ModelContextProtocol
  include SimilaritySearch
  include Skillable  # <-- Add this line
  
  acts_as_chat
  broadcasts_to ->(chat) { [ chat, "messages" ] }
  
  belongs_to :account
  belongs_to :chat, optional: true
  belongs_to :user
  has_many :chats, dependent: :destroy
  has_many :messages, dependent: :destroy
  has_many :skill_executions, dependent: :destroy
  
  scope :root, -> { where(chat_id: nil) }
  
  # ... existing methods
end
```

---

## 8. Controllers

### 8.1 Web Controller

```ruby
# app/controllers/skills_controller.rb
class SkillsController < ApplicationController
  before_action :set_account
  before_action :set_skill, only: [:show, :edit, :update, :destroy, :toggle]
  before_action :authorize_skill, only: [:edit, :update, :destroy, :toggle]
  
  # GET /skills
  def index
    @skills = @account.skills.order(priority: :desc, created_at: :asc)
  end
  
  # GET /skills/new
  def new
    @skill = @account.skills.new
  end
  
  # POST /skills
  def create
    @skill = @account.skills.new(skill_params)
    
    if @skill.save
      redirect_to skills_path, notice: t(".created")
    else
      render :new
    end
  end
  
  # GET /skills/:id
  def show
  end
  
  # GET /skills/:id/edit
  def edit
  end
  
  # PATCH /skills/:id
  def update
    if @skill.update(skill_params)
      redirect_to skills_path, notice: t(".updated")
    else
      render :edit
    end
  end
  
  # DELETE /skills/:id
  def destroy
    @skill.destroy
    redirect_to skills_path, notice: t(".destroyed")
  end
  
  # PATCH /skills/:id/toggle
  def toggle
    @skill.update!(enabled: !@skill.enabled)
    redirect_to skills_path, notice: t(".toggled")
  end
  
  private
  
  def set_account
    @account = Current.account
  end
  
  def set_skill
    @skill = @account.skills.find(params[:id])
  end
  
  def authorize_skill
    authorize @skill
  end
  
  def skill_params
    params.require(:skill).permit(
      :name, :description, :execution_mode, :trigger_mode,
      :requires_rag_context, :enabled, :priority,
      files: [], skill_md: []
    )
  end
end
```

### 8.2 API Controller

```ruby
# app/controllers/api/v1/skills_controller.rb
module Api
  module V1
    class SkillsController < ApplicationController
      before_action :set_account
      
      # GET /api/v1/skills
      def index
        @skills = current_account.skills.order(priority: :desc, created_at: :asc)
        render json: @skills, status: :ok
      end
      
      # POST /api/v1/skills
      def create
        @skill = current_account.skills.new(skill_params)
        
        if @skill.save
          render json: @skill, status: :created
        else
          render json: { errors: @skill.errors.full_messages }, status: :unprocessable_entity
        end
      end
      
      # GET /api/v1/skills/:id
      def show
        @skill = current_account.skills.find(params[:id])
        render json: @skill, status: :ok
      end
      
      # PATCH /api/v1/skills/:id
      def update
        @skill = current_account.skills.find(params[:id])
        
        if @skill.update(skill_params)
          render json: @skill, status: :ok
        else
          render json: { errors: @skill.errors.full_messages }, status: :unprocessable_entity
        end
      end
      
      # DELETE /api/v1/skills/:id
      def destroy
        @skill = current_account.skills.find(params[:id])
        @skill.destroy
        head :no_content
      end
      
      private
      
      def set_account
        @account = Current.account
      end
      
      def skill_params
        params.require(:skill).permit(
          :name, :description, :execution_mode, :trigger_mode,
          :requires_rag_context, :enabled, :priority
        )
      end
    end
  end
end
```

---

## 9. Views

### 9.1 Index View

```erb
<!-- app/views/skills/index.html.erb -->
<div class="container mx-auto px-4 py-8">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold">Agent Skills</h1>
    <%= link_to "Upload Skill", new_skill_path, class: "btn btn-primary" %>
  </div>
  
  <% if @skills.any? %>
    <div class="grid gap-4">
      <% @skills.each do |skill| %>
        <%= render "skill_card", skill: skill %>
      <% end %>
    </div>
  <% else %>
    <div class="alert alert-info">
      <p>No skills uploaded yet. Upload your first skill to get started!</p>
    </div>
  <% end %>
</div>
```

### 9.2 Skill Card Partial

```erb
<!-- app/views/skills/_skill_card.html.erb -->
<div class="card" id="<%= dom_id(skill) %>">
  <div class="card-header flex justify-between items-center">
    <div class="flex items-center gap-4">
      <div>
        <h3 class="font-semibold"><%= skill.name %></h3>
        <p class="text-sm text-gray-500"><%= skill.execution_mode %> | <%= skill.trigger_mode %></p>
      </div>
    </div>
    <div class="flex gap-2">
      <%= button_to toggle_skill_path(skill), method: :patch, class: "btn btn-sm #{skill.enabled? ? 'btn-success' : 'btn-secondary'}" do %>
        <%= skill.enabled? ? "Enabled" : "Disabled" %>
      <% end %>
      <%= link_to "Edit", edit_skill_path(skill), class: "btn btn-sm btn-outline" %>
      <%= button_to "Delete", skill_path(skill), method: :delete, class: "btn btn-sm btn-danger", form: { data: { turbo_confirm: "Are you sure?" } } do %>
        Delete
      <% end %>
    </div>
  </div>
  <div class="card-body">
    <p><%= simple_format(skill.description) %></p>
    <div class="mt-4 text-sm">
      <p><strong>Files:</strong> <%= skill.files.count + (skill.skill_md.attached? ? 1 : 0) %></p>
      <% if skill.metadata.present? %>
        <p><strong>Tags:</strong> <%= skill.metadata["tags"]&.join(", ") || "None" %></p>
      <% end %>
    </div>
  </div>
</div>
```

### 9.3 New/Edit Form

```erb
<!-- app/views/skills/_form.html.erb -->
<%= form_with model: skill, class: "space-y-4" do |f| %>
  <% if skill.errors.any? %>
    <div class="alert alert-danger">
      <h4><%= pluralize(skill.errors.count, "error") %> prevented this skill from being saved:</h4>
      <ul>
        <% skill.errors.each do |error| %>
          <li><%= error.full_message %></li>
        <% end %>
      </ul>
    </div>
  <% end %>
  
  <div class="field">
    <%= f.label :skill_md, "SKILL.md File (Required)" %>
    <%= f.file_field :skill_md, accept: ".md" %>
    <% if skill.skill_md.attached? %>
      <p class="text-sm text-gray-500 mt-1">Current: <%= skill.skill_md.filename %></p>
    <% end %>
    <p class="help-text">Upload the main SKILL.md file defining this skill</p>
  </div>
  
  <div class="field">
    <%= f.label :files, "Additional Files" %>
    <%= f.file_field :files, multiple: true %>
    <% if skill.files.attached? %>
      <div class="mt-2 text-sm text-gray-500">
        Currently attached: <%= skill.files.count %> file(s)
      </div>
    <% end %>
    <p class="help-text">scripts/, references/, assets/, or other supporting files</p>
  </div>
  
  <div class="field">
    <%= f.label :execution_mode %>
    <%= f.select :execution_mode, 
          options_for_select(Skill.execution_modes.map { |k,v| [k.humanize, k] }, skill.execution_mode),
          { include_blank: false } %>
    <p class="help-text">
      <strong>LLM:</strong> Prompt injection only. <strong>Ruby:</strong> Requires a matching class in app/models/skills/
    </p>
  </div>
  
  <div class="field">
    <%= f.label :trigger_mode %>
    <%= f.select :trigger_mode, 
          options_for_select(Skill.trigger_modes.map { |k,v| [k.humanize, k] }, skill.trigger_mode),
          { include_blank: false } %>
    <p class="help-text">How this skill is triggered during conversations</p>
  </div>
  
  <div class="field">
    <%= f.label :requires_rag_context %>
    <%= f.check_box :requires_rag_context %>
    <p class="help-text">This skill needs access to documents/chunks for RAG</p>
  </div>
  
  <div class="field">
    <%= f.label :priority %>
    <%= f.number_field :priority, in: 0..100, step: 1 %>
    <p class="help-text">Higher priority skills are tried first (0-100)</p>
  </div>
  
  <div class="field">
    <%= f.label :enabled %>
    <%= f.check_box :enabled %>
    <p class="help-text">Disable to prevent this skill from being triggered</p>
  </div>
  
  <div class="actions">
    <%= f.submit skill.persisted? ? "Update Skill" : "Upload Skill", class: "btn btn-primary" %>
    <% if skill.persisted? %>
      <%= link_to "Cancel", skills_path, class: "btn btn-outline" %>
    <% end %>
  </div>
<% end %>
```

---

## 10. Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # Web UI for skill management
  resources :skills, only: [:index, :new, :create, :show, :edit, :update, :destroy] do
    member do
      patch :toggle
    end
  end
  
  # API endpoints
  namespace :api do
    namespace :v1 do
      resources :skills, only: [:index, :create, :show, :update, :destroy]
    end
  end
  
  # Existing routes...
end
```

---

## 11. Job Updates

### 11.1 Chat Response Job

```ruby
# app/jobs/chat_response_job.rb
class ChatResponseJob < ApplicationJob
  queue_as :real_time
  
  def perform(chat_id, content, user_message_id = nil)
    Rails.logger.info "=== ChatResponseJob started for chat ##{chat_id} ==="
    chat = Chat.find(chat_id)
    user_message = user_message_id ? Message.find(user_message_id) : nil
    Rails.logger.info "User message: #{user_message&.id} - Content: #{content[0..100]}..."
    
    # Use skill-aware completion if enabled
    if ENV.fetch("AGENT_SKILLS_ENABLED", "true") == "true"
      result = chat.complete_with_skills(content, user_message: user_message)
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

## 12. Security

### 12.1 File Upload Security

```ruby
# app/models/concerns/skill/security.rb
module Skill
  module Security
    extend ActiveSupport::Concern
    
    included do
      FILE_ALLOWLIST = %w[.md .markdown .txt .yaml .yml .json .rb].freeze
      MAX_FILE_SIZE = ENV.fetch("AGENT_SKILLS_MAX_FILE_SIZE", 1_048_576).to_i # 1MB
      MAX_TOTAL_SIZE = 10 * MAX_FILE_SIZE # 10MB
    end
  end
  
  class Validator
    include Skill::Security
    
    def self.validate_upload(files)
      total_size = files.sum(&:size)
      return [false, "Total size exceeds #{MAX_TOTAL_SIZE / 1_048_576}MB"] if total_size > MAX_TOTAL_SIZE
      
      files.each do |file|
        extension = File.extname(file.filename.to_s).downcase
        unless FILE_ALLOWLIST.include?(extension)
          return [false, "File type '#{extension}' not allowed"]
        end
        return [false, "File '#{file.filename}' exceeds #{MAX_FILE_SIZE / 1_048_576}MB"] if file.size > MAX_FILE_SIZE
      end
      
      [true, nil]
    end
  end
end
```

### 12.2 Ruby Skill Validation

```ruby
# app/models/skills/base.rb (additions)
module Skills
  class Base
    # Class-level validation when skills are loaded
    def self.validate!
      return true unless name.start_with?("Skills::")
      
      unless ancestors.include?(Skills::Base)
        raise "Skill #{name} must inherit from Skills::Base"
      end
      
      unless instance_methods(false).include?(:call)
        raise "Skill #{name} must implement #call"
      end
      
      true
    end
  end
end

# Validate all skills on startup (optional)
# In config/initializers/skills.rb:
if Rails.env.development? || Rails.env.test?
  Dir.glob(Rails.root.join("app/models/skills/**/*.rb")).each do |file|
    require_dependency file
  end
  
  Skills::Base.descendants.each(&:validate!)
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
```

### 13.2 Environment Variables

```bash
# Required: None (has sensible defaults)

# Optional:
AGENT_SKILLS_ENABLED=true           # Enable/disable the feature (default: true)
AGENT_SKILLS_MAX_FILE_SIZE=1048576  # Max file size in bytes (1MB default)
AGENT_SKILLS_TIMEOUT=30              # Ruby skill timeout in seconds (30 default)
AGENT_SKILLS_REQUIRES_APPROVAL=false # Require admin approval for new skills
```

---

## 14. Testing Strategy

### 14.1 Unit Tests

**`test/models/skill_test.rb`**
- Validations (name presence, mode enums, account scoping)
- File attachment requirements
- Parser integration
- Metadata extraction from SKILL.md

**`test/models/skill/executor_test.rb`**
- LLMExecutor: prompt injection
- RubyExecutor: class instantiation and method calling
- Error handling for missing classes

**`test/models/skill/detector_test.rb`**
- Explicit trigger detection (`/skill-name`, `@skill-name`)
- Auto trigger detection (mock LLM responses)
- Skill sorting by priority

**`test/models/chat/skillable_test.rb`**
- `complete_with_skills` routing
- Skill result formatting
- Fallback to `complete_with_nosia`

### 14.2 Integration Tests

**`test/integration/skills_flow_test.rb`**
- Full flow: upload skill → trigger via chat → verify response
- Ruby skill execution in context
- LLM skill injection

### 14.3 System Tests

**`test/system/skills_test.rb`**
- UI upload flow
- Skill management CRUD
- Skill triggering from chat

---

## 15. Deployment & Rollout

### 15.1 Migration Plan

**Phase 1: Core Infrastructure (Week 1-2)**
- Create Skill model + migration
- Implement Parser
- Add Skillable concern (LLM-only mode)
- Create basic upload UI
- Add explicit trigger detection

**Phase 2: Ruby Skills (Week 3-4)**
- Implement Skills::Base
- Add RubyExecutor
- Create example Ruby skills
- Add security validations
- Documentation for skill authors

**Phase 3: Advanced Features (Week 5-6)**
- Auto-trigger detection
- MCP bridge (optional)
- Improved error handling
- Performance optimizations

### 15.2 Feature Flag

Use `AGENT_SKILLS_ENABLED` environment variable to:
- Disable the feature entirely (for troubleshooting)
- Roll out to specific accounts first
- Gradual deployment

### 15.3 Monitoring

Add logging for:
- Skill uploads (with account info)
- Skill executions (with timing, success/failure)
- Trigger detection results

```ruby
# In Skill::Executor
Rails.logger.info "[AgentSkills] Executing skill=#{skill.name} mode=#{skill.execution_mode} account=#{skill.account_id}"

# In Skill::Detector
Rails.logger.debug "[AgentSkills] Detected skills=#{detected.map(&:name).join(", ")} query=#{query[0..50]}"
```

---

## 16. Example Skills

### 16.1 LLM-Driven Skill (SKILL.md only)

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

## Instructions

You are a document summarization expert. When invoked, analyze the provided document chunks and create a comprehensive but concise summary.

1. Identify the main topics and key points from the documents
2. Group related information together
3. Preserve important details, numbers, and names
4. Note any contradictions or gaps in the source material
5. Format the summary with clear section headers

## Output Format

Always respond with:
- An overview paragraph
- A bulleted list of key points
- A "Sources" section listing the document names

## Examples

**User:** Summarize the Q1 report
**Assistant:** [Provides structured summary based on retrieved chunks]
```

### 16.2 Ruby-Based Skill

```ruby
# app/models/skills/document_summarizer.rb
module Skills
  class DocumentSummarizer < Base
    def call
      chunks = rag_context[:chunks]
      
      return { content: "No documents found matching your query.", role: "assistant" } if chunks.empty?
      
      # Group chunks by source
      by_source = chunks.group_by { |c| c[:source] }
      
      summaries = by_source.map do |source, source_chunks|
        content = source_chunks.map { |c| c[:content] }.join("\n\n")
        summarize_content(content, source)
      end
      
      formatted_response = format_response(summaries, by_source.keys)
      
      { content: formatted_response, role: "assistant" }
    end
    
    private
    
    def summarize_content(content, source)
      with_instructions(summarization_prompt(source)) do
        ask("Please summarize the following content from source '#{source}':\n\n#{content[0..4000]}")
      end.content
    end
    
    def summarization_prompt(source)
      <<~PROMPT
        You are a document summarization assistant. Create a concise summary of the provided content.
        Focus on: main points, key data, important names, dates, and conclusions.
        Source: #{source}
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

---

## 17. Open Questions & Decisions Log

| Date | Question | Decision | Rationale |
|------|---------|----------|-----------|
| 2025-04-15 | Skill execution model | Hybrid LLM + Ruby | Balances simplicity and power |
| 2025-04-15 | Skill scoping | Account-scoped only | Consistent with Nosia's architecture |
| 2025-04-15 | Upload mechanism | Manual via web UI | Simplest for MVP |
| 2025-04-15 | Trigger mechanism | Combined (explicit + auto + mcp) | Maximum flexibility |
| 2025-04-15 | RAG access | Configurable per skill | Skills can opt-in to context |
| 2025-04-15 | Versioning | Manual updates only | Keep it simple for now |
| 2025-04-15 | MCP integration | Future enhancement | Focus on core first |

---

## 18. Future Enhancements

### High Priority
1. **Skill registry integration** - Browse and install from agentskills.io
2. **Git repository support** - Pull skills from GitHub/GitLab
3. **Skill dependencies** - Skills that depend on other skills
4. **Skill testing framework** - Test skills in isolation

### Medium Priority
1. **Skill versioning** - Track versions, enable rollback
2. **Skill sharing** - Share skills between accounts (with permissions)
3. **Public skill catalog** - Nosia-hosted skill directory
4. **Usage analytics** - Track which skills are used most

### Low Priority
1. **Sandboxed execution** - Run skills in containers for security
2. **Multi-language skills** - Support Python, Node.js, etc.
3. **Skill marketplace** - Monetization for skill authors
4. **AI skill generation** - Generate skills from natural language descriptions

---

## 19. Appendix

### 19.1 Glossary

| Term | Definition |
|------|------------|
| Agent Skills | Modular capabilities for AI agents, defined by agentskills.io |
| SKILL.md | Standard format for defining skills (YAML frontmatter + Markdown) |
| LLM-Driven | Skills executed by injecting instructions into the LLM prompt |
| Ruby-Driven | Skills implemented as Ruby classes |
| Trigger Mode | How a skill is invoked (explicit, auto, mcp, combined) |
| RAG Context | Documents and chunks accessible to the skill |

### 19.2 References

- [agentskills.io](https://agentskills.io) - Official Agent Skills website
- [SKILL.md Format Specification](https://agentskills.io/what-are-skills) - SKILL.md format details
- [Nosia Architecture](https://github.com/nosia-ai/nosia/blob/main/docs/ARCHITECTURE.md) - Nosia's architecture
- [Nosia Principles](https://github.com/nosia-ai/nosia/blob/main/docs/PRINCIPLES.md) - Guiding principles

---

## 20. Approval

**Designer:** Mistral Vibe  
**Date:** 2025-04-15  

**Approvers:**
- [ ] @cbledev ( nosia core maintainer)
- [ ] @nosia-team (team review)

**Approval Date:** ___________

**Implementation Start Date:** ___________

---

*This document is a living specification. Updates should be recorded in the Decisions Log (Section 17).*
