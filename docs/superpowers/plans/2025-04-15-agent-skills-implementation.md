# Agent Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Agent Skills (agentskills.io) support in Nosia, enabling users to upload SKILL.md files and have LLM-driven or Ruby-based skills that can be triggered during chat conversations.

**Architecture:** Hybrid approach with LLM-driven skills (prompt injection) and Ruby-based skills (in-process execution). Account-scoped with manual upload via web UI. Combined triggering via explicit commands (`/skill-name`), @-mentions (`@skill-name`), and auto-detection.

**Tech Stack:** Ruby on Rails 8, PostgreSQL, Active Storage, Solid Queue, RubyLLM, Concurrent Ruby, RSpec

**Spec Document:** `docs/superpowers/specs/2025-04-15-agent-skills-design.md` (v2)

---

## File Structure Map

This plan will create/modify the following files:

### New Files to Create
```
app/models/agent_skill.rb                           # ActiveRecord model
app/models/agent_skill/parser.rb                    # SKILL.md parser
app/models/agent_skill/executor.rb                  # Execution router
app/models/agent_skill/detector.rb                  # Trigger detection
app/models/agent_skill/security.rb                  # Security utilities
app/models/agent_skill_execution.rb                # Audit trail model
app/models/chat/agent_skillable.rb                 # Chat concern
app/models/agent_skills/base.rb                    # Ruby skill base class
app/controllers/agent_skills_controller.rb         # Web UI controller
app/controllers/api/v1/agent_skills_controller.rb  # API controller
app/views/agent_skills/index.html.erb               # Skill list view
app/views/agent_skills/new.html.erb                # Upload form
app/views/agent_skills/edit.html.erb               # Edit form
app/views/agent_skills/show.html.erb               # Skill detail view
app/views/agent_skills/_form.html.erb               # Form partial
app/views/agent_skills/_skill_card.html.erb        # Skill card partial
config/initializers/agent_skills.rb                # Configuration

# Migrations
 db/migrate/[timestamp]_create_agent_skills.rb
 db/migrate/[timestamp]_create_agent_skill_executions.rb

# Test Files
test/models/agent_skill_test.rb
test/models/agent_skill/parser_test.rb
test/models/agent_skill/executor_test.rb
test/models/agent_skill/detector_test.rb
test/models/agent_skill/security_test.rb
test/models/agent_skill_execution_test.rb
test/models/chat/agent_skillable_test.rb
test/integration/agent_skills_flow_test.rb
test/system/agent_skills_test.rb
```

### Files to Modify
```
app/models/chat.rb                                    # Add AgentSkillable concern
app/jobs/chat_response_job.rb                       # Use complete_with_agent_skills
config/routes.rb                                   # Add agent_skills routes
```

---

## Phase 1: Database & Core Model (Week 1)

### Task 1: Create AgentSkill Model and Migration

**Goal:** Create the database table for storing agent skills metadata and files.

**Files:**
- Create: `db/migrate/[timestamp]_create_agent_skills.rb`
- Create: `app/models/agent_skill.rb`

- [ ] **Step 1: Generate migration**

Run: `bin/rails generate migration CreateAgentSkills`

- [ ] **Step 2: Edit the migration file**

```ruby
# db/migrate/[timestamp]_create_agent_skills.rb
class CreateAgentSkills < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_skills do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :execution_mode, null: false, default: "llm"
      t.string :trigger_mode, null: false, default: "explicit"
      t.jsonb :metadata, default: {}
      t.boolean :requires_rag_context, default: false
      t.boolean :enabled, default: true
      t.integer :priority, default: 0
      t.timestamps
    end

    add_index :agent_skills, [:account_id, :name], unique: true
    add_index :agent_skills, [:account_id, :enabled]
    add_index :agent_skills, [:account_id, :execution_mode]
    add_index :agent_skills, [:account_id, :trigger_mode]
    add_index :agent_skills, [:name]
  end
end
```

- [ ] **Step 3: Create the AgentSkill model**

```ruby
# app/models/agent_skill.rb
class AgentSkill < ApplicationRecord
  extend ActiveModel::Naming
  
  acts_as_tenant :account
  
  has_many_attached :files
  has_one_attached :skill_md
  
  enum :execution_mode, { llm: "llm", ruby: "ruby" }
  enum :trigger_mode, { explicit: "explicit", auto: "auto", combined: "combined" }
  
  validates :name, presence: true, 
            uniqueness: { scope: :account_id },
            format: { with: /\A[a-zA-Z][a-zA-Z0-9_-]*\z/, 
                     message: "must start with a letter and contain only alphanumeric, underscore, and hyphen" }
  validates :execution_mode, presence: true
  validates :trigger_mode, presence: true
  validates :priority, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validate :validate_skill_md_present, on: :create
  validate :validate_metadata_present, on: :create
  
  scope :runnable, -> { where(enabled: true) }
  scope :by_name, ->(name) { where(name: name) }
  
  def ruby_class_name
    "AgentSkills::#{name.camelize}"
  end
  
  def runnable?
    enabled? && 
      (execution_mode == "llm" || 
       (execution_mode == "ruby" && ruby_class_name.safe_constantize.present?))
  end
  
  private
  
  def validate_skill_md_present
    errors.add(:skill_md, "must be attached") unless skill_md.attached?
  end
  
  def validate_metadata_present
    return if metadata.present? && metadata["name"].present?
    errors.add(:skill_md, "must contain valid YAML frontmatter with at least 'name' field")
  end
end
```

- [ ] **Step 4: Run the migration**

Run: `bin/rails db:migrate`
Expected: Successful migration

- [ ] **Step 5: Commit**

```bash
git add db/migrate/[timestamp]_create_agent_skills.rb app/models/agent_skill.rb
git commit -m "feat: add AgentSkill model and migration

- ActiveRecord model with acts_as_tenant
- execution_mode and trigger_mode enums
- File attachments via Active Storage
- Validations for name, modes, priority

Generated by Mistral Vibe.
Co-Authored-By: Mistral Vibe <vibe@mistral.ai>"
```

---

### Task 2: Create AgentSkillExecution Model and Migration

**Goal:** Create audit trail for skill executions.

**Files:**
- Create: `db/migrate/[timestamp]_create_agent_skill_executions.rb`
- Create: `app/models/agent_skill_execution.rb`

- [ ] **Step 1: Generate migration**

Run: `bin/rails generate migration CreateAgentSkillExecutions`

- [ ] **Step 2: Edit the migration file**

```ruby
# db/migrate/[timestamp]_create_agent_skill_executions.rb
class CreateAgentSkillExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_skill_executions do |t|
      t.references :agent_skill, null: false, foreign_key: true
      t.references :chat, null: false, foreign_key: true
      t.references :message, null: true, foreign_key: true
      t.string :execution_mode, null: false
      t.string :status, null: false
      t.jsonb :trigger_context, default: {}
      t.jsonb :input, default: {}
      t.jsonb :output, default: {}
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

- [ ] **Step 3: Create the AgentSkillExecution model**

```ruby
# app/models/agent_skill_execution.rb
class AgentSkillExecution < ApplicationRecord
  acts_as_tenant :account
  
  belongs_to :agent_skill
  belongs_to :chat
  belongs_to :message, optional: true
  
  enum :status, { pending: "pending", completed: "completed", failed: "failed", timed_out: "timed_out" }
  enum :execution_mode, { llm: "llm", ruby: "ruby" }
  
  validates :agent_skill, presence: true
  validates :chat, presence: true
  validates :execution_mode, presence: true
end
```

- [ ] **Step 4: Link AgentSkill to AgentSkillExecution**

Modify: `app/models/agent_skill.rb`

Add after `has_many_attached :files`:
```ruby
  has_many :agent_skill_executions, dependent: :destroy
```

- [ ] **Step 5: Run the migration**

Run: `bin/rails db:migrate`
Expected: Successful migration

- [ ] **Step 6: Commit**

```bash
git add db/migrate/[timestamp]_create_agent_skill_executions.rb app/models/agent_skill_execution.rb app/models/agent_skill.rb
git commit -m "feat: add AgentSkillExecution model for audit trail

- Tracks execution status, input, output, duration
- Linked to AgentSkill, Chat, and Message
- Account-scoped via acts_as_tenant

Generated by Mistral Vibe.
Co-Authored-By: Mistral Vibe <vibe@mistral.ai>"
```

---

### Task 3: Create AgentSkill::Security Module

**Goal:** Implement security utilities for file validation and prompt sanitization.

**Files:**
- Create: `app/models/agent_skill/security.rb`

- [ ] **Step 1: Create security module**

```ruby
# app/models/agent_skill/security.rb
module AgentSkill
  module Security
    extend self
    
    FILE_ALLOWLIST = %w[.md .markdown .txt .yaml .yml .json].freeze
    MAX_FILE_SIZE = ENV.fetch("AGENT_SKILLS_MAX_FILE_SIZE", 1_048_576).to_i
    MAX_TOTAL_SIZE = 10 * MAX_FILE_SIZE
    
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
    
    def sanitize_text(text)
      return "" unless text
      ActionView::Helpers::TextHelper.strip_tags(text.to_s)[0...10_000]
    end
    
    def sanitize_prompt(text)
      return "" unless text
      
      sanitized = text.to_s
      PROMPT_INJECTION_PATTERNS.each { |p| sanitized = sanitized.gsub(p, "") }
      sanitized = sanitized.gsub(/[\r\n]+/, " ").gsub(/\s+/, " ").strip[0...8000]
    end
    
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

- [ ] **Step 2: Integrate validation into AgentSkill model**

Modify: `app/models/agent_skill.rb`

Add after the last validation:
```ruby
  validate :validate_uploaded_files
  
  private
  
  def validate_uploaded_files
    return unless skill_md_attached? || files.attached?
    all_files = files + [skill_md].compact
    valid, error = AgentSkill::Security.validate_upload(all_files)
    errors.add(:base, error) unless valid
  end
```

- [ ] **Step 3: Run tests to verify**

Run: `bin/rails console -e "require './app/models/agent_skill/security'; puts AgentSkill::Security::FILE_ALLOWLIST.inspect"`
Expected: `["".md", ".markdown", ".txt", ".yaml", ".yml", ".json"]`

- [ ] **Step 4: Commit**

```bash
git add app/models/agent_skill/security.rb app/models/agent_skill.rb
git commit -m "feat: add AgentSkill security module

- File type allowlist and validation
- Prompt sanitization for LLM injection prevention
- Integrates with AgentSkill model

Generated by Mistral Vibe.
Co-Authored-By: Mistral Vibe <vibe@mistral.ai>"
```

---

### Task 4: Create AgentSkill::Parser

**Goal:** Parse SKILL.md files and extract metadata.

**Files:**
- Create: `app/models/agent_skill/parser.rb`
- Create: `test/models/agent_skill/parser_test.rb`

- [ ] **Step 1: Create parser module**

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
```

- [ ] **Step 2: Add parser callback to AgentSkill**

Modify: `app/models/agent_skill.rb`

Add after the validations:
```ruby
  after_save :parse_skill_md, if: -> { skill_md_attached? && (skill_md_changed? || skill_md_attached?) }
```

- [ ] **Step 3: Write parser tests**

```ruby
# test/models/agent_skill/parser_test.rb
require "test_helper"

class AgentSkill::ParserTest < ActiveSupport::TestCase
  test "parses valid SKILL.md with frontmatter" do
    agent_skill = AgentSkill.new
    agent_skill.skill_md.attach(
      io: StringIO.new("---\nname: test-skill\ndescription: Test description\n---\n\n# Instructions"),
      filename: "SKILL.md",
      content_type: "text/markdown"
    )
    agent_skill.save!
    
    assert_equal "test-skill", agent_skill.name
    assert_equal "Test description", agent_skill.description
  end
  
  test "parses SKILL.md without frontmatter" do
    agent_skill = AgentSkill.new(name: "manual-name")
    agent_skill.skill_md.attach(
      io: StringIO.new("# Instructions"),
      filename: "SKILL.md",
      content_type: "text/markdown"
    )
    agent_skill.save!
    
    assert_equal "manual-name", agent_skill.name
    assert_equal "# Instructions", agent_skill.description
  end
end
```

- [ ] **Step 4: Run tests**

Run: `bin/rails test test/models/agent_skill/parser_test.rb`
Expected: 2 tests, 2 assertions, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/models/agent_skill/parser.rb app/models/agent_skill.rb test/models/agent_skill/parser_test.rb
git commit -m "feat: add AgentSkill parser for SKILL.md files

- Extracts YAML frontmatter metadata
- Validates required fields
- Handles edge cases (missing frontmatter, invalid YAML)
- Includes unit tests

Generated by Mistral Vibe.
Co-Authored-By: Mistral Vibe <vibe@mistral.ai>"
```

---

## Phase 2: Execution Engine (Week 1-2)

### Task 5: Create AgentSkill::Executor

**Goal:** Implement execution routing between LLM and Ruby modes.

**Files:**
- Create: `app/models/agent_skill/executor.rb`
- Create: `test/models/agent_skill/executor_test.rb`

- [ ] **Step 1: Create executor module**

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
        
        execution.update!(status: "completed", output: format_output(result), duration_ms: duration)
        result
      rescue => e
        execution.update!(status: "failed", error_message: e.message, duration_ms: duration)
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
    
    def duration
      (Time.current - @execution.created_at) * 1000
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
      parts << AgentSkill::Security.sanitize_prompt(@agent_skill.instructions.to_s)
      parts << ""
      parts.join("\n")
    end
  end
  
  class RubyExecutor
    ALLOWED_CHAT_METHODS = %i[ask with_instructions with_params with_temperature similarity_search messages user account].freeze
    
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
```

- [ ] **Step 2: Add concurrent-ruby to Gemfile if not present**

Check if `concurrent-ruby` is in Gemfile. If not:

Run: `bundle add concurrent-ruby`

- [ ] **Step 3: Commit**

```bash
git add app/models/agent_skill/executor.rb Gemfile Gemfile.lock
git commit -m "feat: add AgentSkill executor with LLM and Ruby support

- LLMExecutor for prompt injection mode
- RubyExecutor with thread-safe timeout
- Method whitelist for security
- Audit trail via AgentSkillExecution

Generated by Mistral Vibe.
Co-Authored-By: Mistral Vibe <vibe@mistral.ai>"
```

---

### Task 6: Create AgentSkills::Base

**Goal:** Create base class for Ruby-based skills.

**Files:**
- Create: `app/models/agent_skills/base.rb`
- Create: `test/models/agent_skills/base_test.rb`

- [ ] **Step 1: Create base class**

```ruby
# app/models/agent_skills/base.rb
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
      return {} unless defined?(Document)
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
```

- [ ] **Step 2: Create example skill**

```ruby
# app/models/agent_skills/document_summarizer.rb
module AgentSkills
  class DocumentSummarizer < Base
    def call
      chunks = rag_context[:chunks]
      
      if chunks.empty?
        return { content: "No documents found matching your query.", role: "assistant" }
      end
      
      by_source = chunks.group_by { |c| c[:source] }
      summaries = by_source.map do |source, source_chunks|
        content = source_chunks.map { |c| c[:content] }.join("\n\n")[0...4000]
        with_instructions(summarization_prompt(source)) do
          ask("Please summarize the following content from source '#{source}':\n\n#{content}")
        end.content
      end
      
      { content: format_response(summaries, by_source.keys), role: "assistant" }
    end
    
    private
    
    def summarization_prompt(source)
      <<~PROMPT
        You are a document summarization assistant. Create a concise summary.
        Focus on: main points, key data, important names, dates, conclusions.
        Use markdown formatting. Source: #{source}
        Respond only with the summary.
      PROMPT
    end
    
    def format_response(summaries, sources)
      "## Document Summary\n\n#{summaries.join("\n\n---\n\n")}\n\n---\n\n**Sources:** #{sources.join(", ")}"
    end
  end
end
```

- [ ] **Step 3: Write base class test**

```ruby
# test/models/agent_skills/base_test.rb
require "test_helper"

class AgentSkills::BaseTest < ActiveSupport::TestCase
  class TestSkill < AgentSkills::Base
    def call
      "test result"
    end
  end
  
  test "validates context on initialization" do
    assert_raises(ArgumentError) { TestSkill.new({}) }
  end
  
  test "validates call method exists" do
    assert TestSkill.new(chat: chats(:one), query: "test", agent_skill: agent_skills(:one)).call == "test result"
  end
  
  test "class validation works" do
    assert AgentSkills::DocumentSummarizer.validate! == true
  end
end
```

- [ ] **Step 4: Run tests**

Run: `bin/rails test test/models/agent_skills/base_test.rb`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add app/models/agent_skills/base.rb app/models/agent_skills/document_summarizer.rb test/models/agent_skills/base_test.rb
git commit -m "feat: add AgentSkills base class and example

- Base class with controlled chat access
- Method whitelist for security
- Example DocumentSummarizer skill
- Validation and tests

Generated by Mistral Vibe.
Co-Authored-By: Mistral Vibe <vibe@mistral.ai>"
```

---

### Task 7: Create AgentSkill::Detector

**Goal:** Implement trigger detection for skills.

**Files:**
- Create: `app/models/agent_skill/detector.rb`
- Create: `test/models/agent_skill/detector_test.rb`

- [ ] **Step 1: Create detector module**

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
        skill_prompts = auto_skills.map { |s| "- #{s.name}: #{s.sanitized_description}" }.join("\n")
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
        model: ENV["GUARD_MODEL"], provider: :openai,
        assume_model_exists: true
      )
      guard_chat.assume_model_exists = true
      block.call(guard_chat)
    ensure
      guard_chat&.destroy
    end
  end
end
```

- [ ] **Step 2: Write detector tests**

```ruby
# test/models/agent_skill/detector_test.rb
require "test_helper"

class AgentSkill::DetectorTest < ActiveSupport::TestCase
  test "detects explicit trigger with /command" do
    chat = chats(:one)
    agent_skill = agent_skills(:summarizer)
    
    # Stub chat.account.agent_skills to return our test skill
    AgentSkill.stub(:where, AgentSkill.where(enabled: true)) do |s|
      s.stubs(:to_a).returns([agent_skill])
    end
    
    result = AgentSkill::Detector.detect(chat, "/summarizer test")
    assert_equal [agent_skill], result
  end
  
  test "detects explicit trigger with @mention" do
    chat = chats(:one)
    agent_skill = agent_skills(:summarizer)
    
    AgentSkill.stub(:where, AgentSkill.where(enabled: true)) do |s|
      s.stubs(:to_a).returns([agent_skill])
    end
    
    result = AgentSkill::Detector.detect(chat, "please @summarizer this")
    assert_equal [agent_skill], result
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add app/models/agent_skill/detector.rb test/models/agent_skill/detector_test.rb
git commit -m "feat: add AgentSkill detector for trigger detection

- Explicit triggers via /command and @mention patterns
- Auto-detection via guard model (when configured)
- Handles hyphenated skill names
- Includes unit tests

Generated by Mistral Vibe.
Co-Authored-By: Mistral Vibe <vibe@mistral.ai>"
```

---

## Phase 3: Chat Integration (Week 2)

### Task 8: Create Chat::AgentSkillable Concern

**Goal:** Add skill integration to Chat model.

**Files:**
- Create: `app/models/chat/agent_skillable.rb`
- Modify: `app/models/chat.rb`
- Create: `test/models/chat/agent_skillable_test.rb`

- [ ] **Step 1: Create the concern**

```ruby
# app/models/chat/agent_skillable.rb
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
    results.map.with_index do |result, index|
      case result
      when Hash
        { role: result[:role] || "assistant", content: result[:content],
          response_number: messages.count + index,
          metadata: (result[:metadata] || {}).merge(agent_skill_names: skills.map(&:name)) }
      when String
        { role: "assistant", content: result, response_number: messages.count + index,
          metadata: { agent_skill_names: skills.map(&:name) } }
      else
        { role: "assistant", content: result.to_s, response_number: messages.count + index,
          metadata: { agent_skill_names: skills.map(&:name) } }
      end
    end
  end
end
```

- [ ] **Step 2: Include concern in Chat model**

Modify: `app/models/chat.rb`

Add line after the other includes:
```ruby
  include AgentSkillable
```

And add the association:
```ruby
  has_many :agent_skill_executions, dependent: :destroy
```

- [ ] **Step 3: Write concern tests**

```ruby
# test/models/chat/agent_skillable_test.rb
require "test_helper"

class Chat::AgentSkillableTest < ActiveSupport::TestCase
  test "complete_with_agent_skills falls back to complete_with_nosia when no skills" do
    chat = chats(:one)
    # Mock complete_with_nosia to return a known value
    chat.stub(:complete_with_nosia, Message.new(content: "fallback")) do
      result = chat.complete_with_agent_skills("test query")
      assert_equal "fallback", result.content
    end
  end
end
```

- [ ] **Step 4: Commit**

```bash
git add app/models/chat/agent_skillable.rb app/models/chat.rb test/models/chat/agent_skillable_test.rb
git commit -m "feat: add Chat AgentSkillable concern

- complete_with_agent_skills method
- Skill execution and result formatting
- Fallback to complete_with_nosia
- AgentSkillExecution association

Generated by Mistral Vibe.
Co-Authored-By: Mistral Vibe <vibe@mistral.ai>"
```

---

### Task 9: Update ChatResponseJob

**Goal:** Use agent skills in chat response job.

**Files:**
- Modify: `app/jobs/chat_response_job.rb`

- [ ] **Step 1: Update job to use complete_with_agent_skills**

```ruby
# app/jobs/chat_response_job.rb
class ChatResponseJob < ApplicationJob
  queue_as :real_time
  
  def perform(chat_id, content, user_message_id = nil)
    Rails.logger.info "=== ChatResponseJob started for chat ##{chat_id} ==="
    chat = Chat.find(chat_id)
    user_message = user_message_id ? Message.find(user_message_id) : nil
    Rails.logger.info "User message: #{user_message&.id} - Content: #{content[0..100]}..."
    
    if Rails.application.config.agent_skills.enabled
      result = chat.complete_with_agent_skills(content, user_message: user_message)
    else
      result = chat.complete_with_nosia(content, user_message: user_message)
    end
    
    Rails.logger.info "=== ChatResponseJob completed. Result: #{result&.id} ==="
  rescue => e
    Rails.logger.error "=== ChatResponseJob ERROR: #{e.class} ==="
    Rails.logger.error e.message
    Rails.logger.error e.backtrace.join("\n")
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add app/jobs/chat_response_job.rb
git commit -m "feat: update ChatResponseJob to use agent skills

- Conditional use of complete_with_agent_skills
- Falls back to complete_with_nosia if feature disabled
- Respects AGENT_SKILLS_ENABLED config

Generated by Mistral Vibe.
Co-Authored-By: Mistral Vibe <vibe@mistral.ai>"
```

---

## Phase 4: Configuration & Initializer (Week 2)

### Task 10: Create Configuration and Routes

**Goal:** Add configuration and routing for agent skills.

**Files:**
- Create: `config/initializers/agent_skills.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Create initializer**

```ruby
# config/initializers/agent_skills.rb
Rails.application.config.agent_skills = ActiveSupport::OrderedOptions.new
Rails.application.config.agent_skills.enabled = ENV.fetch("AGENT_SKILLS_ENABLED", "true") == "true"
Rails.application.config.agent_skills.max_file_size = ENV.fetch("AGENT_SKILLS_MAX_FILE_SIZE", "1048576").to_i
Rails.application.config.agent_skills.timeout = ENV.fetch("AGENT_SKILLS_TIMEOUT", "30").to_i

# Eager load agent skills in development
if Rails.env.development? || Rails.env.test?
  Dir.glob(Rails.root.join("app/models/agent_skills/**/*.rb")).each do |file|
    require_dependency file
  end
end
```

- [ ] **Step 2: Add routes**

Modify: `config/routes.rb`

Add after existing routes:
```ruby
  resources :agent_skills, only: [:index, :new, :create, :show, :edit, :update, :destroy] do
    member do
      patch :toggle
    end
  end
  
  namespace :api do
    namespace :v1 do
      resources :agent_skills, only: [:index, :create, :show, :update, :destroy]
    end
  end
```

- [ ] **Step 3: Commit**

```bash
git add config/initializers/agent_skills.rb config/routes.rb
git commit -m "feat: add Agent Skills configuration and routes

- Environment variable configuration
- Web and API routes
- Eager loading for development

Generated by Mistral Vibe.
Co-Authored-By: Mistral Vibe <vibe@mistral.ai>"
```

---

## Phase 5: Controllers & Views (Week 2-3)

### Task 11: Create AgentSkillsController (Web)

**Goal:** Web UI for managing agent skills.

**Files:**
- Create: `app/controllers/agent_skills_controller.rb`
- Create: `app/views/agent_skills/index.html.erb`
- Create: `app/views/agent_skills/new.html.erb`
- Create: `app/views/agent_skills/edit.html.erb`
- Create: `app/views/agent_skills/show.html.erb`
- Create: `app/views/agent_skills/_form.html.erb`
- Create: `app/views/agent_skills/_skill_card.html.erb`

- [ ] **Step 1: Create controller**

```ruby
# app/controllers/agent_skills_controller.rb
class AgentSkillsController < ApplicationController
  before_action :set_account
  before_action :set_agent_skill, only: [:show, :edit, :update, :destroy, :toggle]
  
  def index
    @agent_skills = @account.agent_skills.order(priority: :desc, created_at: :asc)
  end
  
  def new
    @agent_skill = @account.agent_skills.new
  end
  
  def create
    @agent_skill = @account.agent_skills.new(agent_skill_params)
    if @agent_skill.save
      redirect_to agent_skills_path, notice: "Agent skill uploaded successfully"
    else
      render :new
    end
  end
  
  def show
  end
  
  def edit
  end
  
  def update
    if @agent_skill.update(agent_skill_params)
      redirect_to agent_skills_path, notice: "Agent skill updated"
    else
      render :edit
    end
  end
  
  def destroy
    @agent_skill.destroy
    redirect_to agent_skills_path, notice: "Agent skill deleted"
  end
  
  def toggle
    @agent_skill.update!(enabled: !@agent_skill.enabled)
    redirect_to agent_skills_path, notice: "Agent skill #{@agent_skill.enabled? ? 'enabled' : 'disabled'}"
  end
  
  private
  
  def set_account
    @account = Current.account
  end
  
  def set_agent_skill
    @agent_skill = @account.agent_skills.find(params[:id])
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

- [ ] **Step 2: Create index view**

```erb
<!-- app/views/agent_skills/index.html.erb -->
<div class="container mx-auto px-4 py-8">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold">Agent Skills</h1>
    <%= link_to "Upload Skill", new_agent_skill_path, class: "btn btn-primary" %>
  </div>
  
  <% if @agent_skills.any? %>
    <div class="grid gap-4">
      <% @agent_skills.each do |skill| %>
        <%= render "skill_card", skill: skill %>
      <% end %>
    </div>
  <% else %>
    <div class="alert alert-info">
      <p>No agent skills uploaded yet. Upload your first skill to get started!</p>
    </div>
  <% end %>
</div>
```

- [ ] **Step 3: Create skill card partial**

```erb
<!-- app/views/agent_skills/_skill_card.html.erb -->
<div class="card" id="<%= dom_id(skill) %>">
  <div class="card-header flex justify-between items-center">
    <div>
      <h3 class="font-semibold"><%= skill.name %></h3>
      <p class="text-sm text-gray-500"><%= skill.execution_mode %> | <%= skill.trigger_mode %></p>
    </div>
    <div class="flex gap-2">
      <%= button_to toggle_agent_skill_path(skill), method: :patch, 
          class: "btn btn-sm <%= skill.enabled? ? 'btn-success' : 'btn-secondary' %>",
          form: { data: { turbo: false } } do %>
        <%= skill.enabled? ? "Enabled" : "Disabled" %>
      <% end %>
      <%= link_to "Edit", edit_agent_skill_path(skill), class: "btn btn-sm btn-outline" %>
      <%= button_to "Delete", agent_skill_path(skill), method: :delete, 
          class: "btn btn-sm btn-danger", 
          form: { data: { turbo_confirm: "Are you sure?", turbo: false } } do %>
        Delete
      <% end %>
    </div>
  </div>
  <div class="card-body">
    <p><%= simple_format(skill.sanitized_description) %></p>
    <div class="mt-4 text-sm text-gray-500">
      <p><strong>Files:</strong> <%= skill.files.count + (skill.skill_md.attached? ? 1 : 0) %></p>
      <% if skill.metadata["tags"].present? %>
        <p><strong>Tags:</strong> <%= skill.metadata["tags"].join(", ") %></p>
      <% end %>
    </div>
  </div>
</div>
```

- [ ] **Step 4: Create form partial**

```erb
<!-- app/views/agent_skills/_form.html.erb -->
<%= form_with model: agent_skill, class: "space-y-4" do |f| %>
  <% if agent_skill.errors.any? %>
    <div class="alert alert-danger">
      <h4><%= pluralize(agent_skill.errors.count, "error") %> prevented this skill from being saved:</h4>
      <ul>
        <% agent_skill.errors.each do |error| %>
          <li><%= error.full_message %></li>
        <% end %>
      </ul>
    </div>
  <% end %>
  
  <div class="field">
    <%= f.label :skill_md, "SKILL.md File (Required)" %>
    <%= f.file_field :skill_md, accept: ".md,.markdown" %>
    <% if agent_skill.skill_md.attached? %>
      <p class="text-sm text-gray-500 mt-1">Current: <%= agent_skill.skill_md.filename %></p>
    <% end %>
  </div>
  
  <div class="field">
    <%= f.label :files, "Additional Files" %>
    <%= f.file_field :files, multiple: true, accept: ".txt,.yaml,.yml,.json" %>
    <% if agent_skill.files.attached? %>
      <p class="text-sm text-gray-500 mt-1"><%= agent_skill.files.count %> file(s) attached</p>
    <% end %>
  </div>
  
  <div class="field">
    <%= f.label :execution_mode %>
    <%= f.select :execution_mode, options_for_select(AgentSkill.execution_modes.map { |k,v| [k.humanize, k] }, agent_skill.execution_mode), { include_blank: false } %>
    <p class="text-sm text-gray-500 mt-1">
      <strong>LLM:</strong> Prompt injection. <strong>Ruby:</strong> Requires class in app/models/agent_skills/
    </p>
  </div>
  
  <div class="field">
    <%= f.label :trigger_mode %>
    <%= f.select :trigger_mode, options_for_select(AgentSkill.trigger_modes.map { |k,v| [k.humanize, k] }, agent_skill.trigger_mode), { include_blank: false } %>
  </div>
  
  <div class="field">
    <%= f.label :requires_rag_context %>
    <%= f.check_box :requires_rag_context %>
    <p class="text-sm text-gray-500 mt-1">Enable if skill needs document/chunk access</p>
  </div>
  
  <div class="field">
    <%= f.label :priority %>
    <%= f.number_field :priority, in: 0..100, step: 1 %>
    <p class="text-sm text-gray-500 mt-1">Higher priority = tried first (0-100)</p>
  </div>
  
  <div class="field">
    <%= f.label :enabled %>
    <%= f.check_box :enabled %>
  </div>
  
  <div class="actions">
    <%= f.submit agent_skill.persisted? ? "Update Skill" : "Upload Skill", class: "btn btn-primary" %>
    <%= link_to "Cancel", agent_skills_path, class: "btn btn-outline" %>
  </div>
<% end %>
```

- [ ] **Step 5: Create new/edit/show views**

```erb
<!-- app/views/agent_skills/new.html.erb -->
<h1 class="text-2xl font-bold mb-6">Upload Agent Skill</h1>
<%= render "form", agent_skill: @agent_skill %>
```

```erb
<!-- app/views/agent_skills/edit.html.erb -->
<h1 class="text-2xl font-bold mb-6">Edit Agent Skill</h1>
<%= render "form", agent_skill: @agent_skill %>
```

```erb
<!-- app/views/agent_skills/show.html.erb -->
<h1 class="text-2xl font-bold mb-6"><%= @agent_skill.name %></h1>
<div class="card">
  <div class="card-body">
    <p><strong>Description:</strong> <%= simple_format(@agent_skill.sanitized_description) %></p>
    <p><strong>Execution Mode:</strong> <%= @agent_skill.execution_mode %></p>
    <p><strong>Trigger Mode:</strong> <%= @agent_skill.trigger_mode %></p>
    <p><strong>Requires RAG Context:</strong> <%= @agent_skill.requires_rag_context %></p>
    <p><strong>Enabled:</strong> <%= @agent_skill.enabled %></p>
    <p><strong>Priority:</strong> <%= @agent_skill.priority %></p>
    
    <h3 class="mt-4">Files</h3>
    <ul>
      <% if @agent_skill.skill_md.attached? %>
        <li><%= @agent_skill.skill_md.filename %> (SKILL.md)</li>
      <% end %>
      <% @agent_skill.files.each do |file| %>
        <li><%= file.filename %></li>
      <% end %>
    </ul>
    
    <div class="mt-4">
      <%= link_to "Edit", edit_agent_skill_path(@agent_skill), class: "btn btn-outline mr-2" %>
      <%= link_to "Back", agent_skills_path, class: "btn btn-outline" %>
    </div>
  </div>
</div>
```

- [ ] **Step 6: Commit views and controller**

```bash
git add app/controllers/agent_skills_controller.rb app/views/agent_skills/
git commit -m "feat: add Agent Skills web controller and views

- Full CRUD for agent skill management
- Upload form for SKILL.md and additional files
- List view with skill cards
- Toggle enable/disable
- Responsive design

Generated by Mistral Vibe.
Co-Authored-By: Mistral Vibe <vibe@mistral.ai>"
```

---

### Task 12: Create API Controller

**Goal:** REST API endpoints for agent skills management.

**Files:**
- Create: `app/controllers/api/v1/agent_skills_controller.rb`

- [ ] **Step 1: Create API controller**

```ruby
# app/controllers/api/v1/agent_skills_controller.rb
module Api
  module V1
    class AgentSkillsController < ApplicationController
      before_action :set_account
      
      def index
        @agent_skills = current_account.agent_skills.order(priority: :desc, created_at: :asc)
        render json: @agent_skills, status: :ok
      end
       
      def create
        @agent_skill = current_account.agent_skills.new(agent_skill_params)
        
        if @agent_skill.save
          render json: @agent_skill, status: :created
        else
          render json: { errors: @agent_skill.errors.full_messages }, status: :unprocessable_entity
        end
      end
       
      def show
        @agent_skill = current_account.agent_skills.find(params[:id])
        render json: @agent_skill, status: :ok
      end
       
      def update
        @agent_skill = current_account.agent_skills.find(params[:id])
        
        if @agent_skill.update(agent_skill_params)
          render json: @agent_skill, status: :ok
        else
          render json: { errors: @agent_skill.errors.full_messages }, status: :unprocessable_entity
        end
      end
       
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

- [ ] **Step 2: Commit**

```bash
git add app/controllers/api/v1/agent_skills_controller.rb
git commit -m "feat: add API controller for Agent Skills

- REST endpoints: index, create, show, update, destroy
- Account-scoped access
- JSON responses with proper status codes

Generated by Mistral Vibe.
Co-Authored-By: Mistral Vibe <vibe@mistral.ai>"
```

---

## Phase 6: Tests (Week 3)

### Task 13: Complete Test Coverage

**Files:**
- Modify: `test/models/agent_skill_test.rb` (full tests)
- Modify: `test/models/agent_skill_execution_test.rb` (full tests)
- Create: `test/integration/agent_skills_flow_test.rb`
- Create: `test/system/agent_skills_test.rb`

- [ ] **Step 1: Write AgentSkill model tests**

```ruby
# test/models/agent_skill_test.rb
require "test_helper"

class AgentSkillTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:one)
    @agent_skill = @account.agent_skills.build(name: "test-skill", execution_mode: "llm", trigger_mode: "explicit")
    @agent_skill.skill_md.attach(
      io: StringIO.new("---\nname: test-skill\ndescription: Test\n---\n"),
      filename: "SKILL.md",
      content_type: "text/markdown"
    )
  end
  
  test "valid agent skill creation" do
    assert @agent_skill.save
    assert_equal "test-skill", @agent_skill.name
  end
  
  test "name validation" do
    @agent_skill.name = nil
    assert_not @agent_skill.valid?
    assert_equal ["can't be blank"], @agent_skill.errors[:name]
  end
  
  test "name format validation" do
    @agent_skill.name = "123invalid"
    assert_not @agent_skill.valid?
    assert @agent_skill.errors[:name].include?("must start with a letter")
  end
  
  test "skill_md required" do
    @agent_skill.skill_md = nil
    assert_not @agent_skill.valid?
  end
  
  test "execution_mode enum" do
    assert @agent_skill.llm?
    @agent_skill.execution_mode = "ruby"
    assert @agent_skill.ruby?
  end
  
  test "runnable? for llm mode" do
    @agent_skill.save!
    assert @agent_skill.runnable?
  end
  
  test "runnable? for ruby mode without implementation" do
    @agent_skill.execution_mode = "ruby"
    @agent_skill.save!
    assert_not @agent_skill.runnable?
  end
end
```

- [ ] **Step 2: Write integration test**

```ruby
# test/integration/agent_skills_flow_test.rb
require "test_helper"

class AgentSkillsFlowTest < ActionDispatch::IntegrationTest
  def setup
    @account = accounts(:one)
    @user = users(:one)
    login_as(@user)
  end
  
  test "upload and trigger agent skill via web" do
    # Upload skill
    skill_md = fixture_file_upload(Rails.root.join("test/fixtures/files/skills/summarizer.SKILL.md"), "text/markdown")
    post agent_skills_path, params: { agent_skill: { name: "summarizer", skill_md: skill_md } }
    
    assert_response :redirect
    assert AgentSkill.count == 1
    
    # Trigger skill in chat
    chat = @account.chats.create!(user: @user)
    post chat_messages_path(chat), params: { message: { content: "/summarizer test" } }
    
    assert_response :success
    # Verify skill was triggered
    assert chat.agent_skill_executions.count >= 1
  end
end
```

- [ ] **Step 3: Create fixture for testing**

Create: `test/fixtures/files/skills/summarizer.SKILL.md`
```markdown
---
name: summarizer
description: Test summarizer skill
execution_mode: llm
trigger_mode: explicit
---

## Instructions
Summarize the provided content.
```

- [ ] **Step 4: Run all tests**

Run: `bin/rails test`
Expected: All tests pass

- [ ] **Step 5: Commit tests**

```bash
git add test/models/agent_skill_test.rb test/models/agent_skill_execution_test.rb 
git add test/integration/agent_skills_flow_test.rb test/system/agent_skills_test.rb
git add test/fixtures/files/skills/
git commit -m "feat: add comprehensive tests for Agent Skills

- Unit tests for models
- Integration tests for flows
- System tests for UI
- Test fixtures for SKILL.md

Generated by Mistral Vibe.
Co-Authored-By: Mistral Vibe <vibe@mistral.ai>"
```

---

## Final Steps

### Task 14: Documentation

- [ ] **Step 1: Create skill author documentation**

Create: `docs/agent-skills-development.md`

Include:
- SKILL.md format reference
- Ruby skill API documentation
- Security guidelines
- How to test skills locally
- Example skills

- [ ] **Step 2: Update README**

Modify: `README.md`

Add section about Agent Skills feature.

- [ ] **Step 3: Commit documentation**

```bash
git add docs/agent-skills-development.md README.md
git commit -m "docs: add Agent Skills development documentation

- SKILL.md format guide
- Ruby skill API docs
- Security guidelines
- README updates

Generated by Mistral Vibe.
Co-Authored-By: Mistral Vibe <vibe@mistral.ai>"
```

---

### Task 15: Final Verification

- [ ] **Step 1: Run RuboCop**

Run: `bundle exec rubocop`
Fix any issues.

- [ ] **Step 2: Run Brakeman**

Run: `bin/brakeman -z`
Fix any security warnings.

- [ ] **Step 3: Run full test suite**

Run: `bin/rails test`
Expected: All tests pass

- [ ] **Step 4: Run system tests**

Run: `bin/rails test:system`
Expected: All system tests pass

- [ ] **Step 5: Final commit**

```bash
git add .
git commit -m "feat: complete Agent Skills implementation

Complete implementation of Agent Skills feature:
- Data models and migrations
- Execution engine (LLM + Ruby)
- Trigger detection
- Chat integration
- Web UI and API
- Security and validation
- Comprehensive tests
- Documentation

Generated by Mistral Vibe.
Co-Authored-By: Mistral Vibe <vibe@mistral.ai>"
```

---

## Checkpoints & Reviews

### Checkpoint 1: After Phase 1 (Database & Core Model)
- [ ] All database migrations run successfully
- [ ] AgentSkill model passes all validations
- [ ] AgentSkillExecution model works
- [ ] Security module validates correctly

### Checkpoint 2: After Phase 2 (Execution Engine)
- [ ] Parser correctly extracts SKILL.md metadata
- [ ] Executor routes to LLM and Ruby correctly
- [ ] LLMExecutor injects prompts without errors
- [ ] RubyExecutor validates and calls skill classes

### Checkpoint 3: After Phase 3 (Chat Integration)
- [ ] Chat model has AgentSkillable concern
- [ ] complete_with_agent_skills works end-to-end
- [ ] ChatResponseJob uses new completion method

### Checkpoint 4: After Phase 4 (Configuration)
- [ ] Initializer loads correctly
- [ ] Routes work for web and API

### Checkpoint 5: After Phase 5 (Controllers & Views)
- [ ] Web UI uploads skills successfully
- [ ] API endpoints return correct JSON
- [ ] Views render properly

### Checkpoint 6: After Phase 6 (Tests)
- [ ] All unit tests pass
- [ ] Integration tests pass
- [ ] System tests pass

---

## Execution Options

**Plan complete and saved to `docs/superpowers/plans/2025-04-15-agent-skills-implementation.md`.**

Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
