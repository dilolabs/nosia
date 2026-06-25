# Agent Skills Development Guide

> **For Nosia Users:** This guide explains how to create and use Agent Skills in Nosia.

## Overview

Agent Skills extend Nosia's chat capabilities by allowing you to define custom behaviors that can be triggered during conversations. Skills can be:

- **LLM-driven**: Simple prompt-based behaviors using the LLM
- **Ruby-based**: Complex logic implemented as Ruby classes

## Quick Start

### Creating a Skill

1. **Upload your SKILL.md file** via the web UI:
   - Navigate to Agent Skills in the web interface
   - Click "Upload Skill"
   - Upload your SKILL.md file and any additional files

2. **Define your skill metadata** in the SKILL.md YAML frontmatter:

```markdown
---
name: my-skill
description: A brief description of what this skill does
execution_mode: llm  # or: ruby
trigger_mode: explicit  # or: auto, combined
requires_rag_context: true  # Set to true if skill needs document/chunk access
# Optional fields:
tags:
  - tag1
  - tag2
when_to_use: Use this skill when the user asks about specific topics
---

## Instructions
These are the instructions that will be shown to the LLM when this skill is triggered.
Be specific and clear about what the skill should do.
```

### Triggering a Skill

Once uploaded and enabled, skills can be triggered in several ways:

- **Explicit command**: `/skill-name your query`
- **Mention syntax**: `@skill-name your query`
- **Auto-detection**: (when configured) The system will automatically detect when to use the skill

### Ruby-based Skills

For advanced use cases, create a Ruby class in `app/models/agent_skills/`:

```ruby
module AgentSkills
  class MyCustomSkill < Base
    def call
      # Your custom logic here
      # Access chat via: chat
      # Access user query via: query
      # Access RAG context via: rag_context (if enabled)
      
      # Example: Use the chat's LLM
      response = ask("Please answer: #{query}")
      
      # Return a hash with :content and :role
      { content: response, role: "assistant" }
    end
  end
end
```

#### Available Methods

Ruby skills have access to the following methods:

- `chat` - The current Chat instance
- `query` - The user's query that triggered the skill
- `user` - The current User
- `account` - The current Account
- `agent_skill` - This AgentSkill instance
- `execution` - The current AgentSkillExecution for audit purposes
- `rag_context` - RAG context if `requires_rag_context` is true
- `ask(prompt, **options)` - Ask the LLM a question
- `with_instructions(instructions, **options, &block)` - Set instructions for LLM
- `log(message, level: :info)` - Log a message

#### Method Whitelist

For security, only the following Chat methods are available:
- `ask`
- `with_instructions`
- `with_params`
- `with_temperature`
- `with_model`
- `similarity_search`
- `messages`
- `user`
- `account`

### SKILL.md Format Reference

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| name | string | Yes | - | Skill identifier (alphanumeric, underscore, hyphen only, must start with letter) |
| description | string | Yes | - | Human-readable description |
| execution_mode | string | No | llm | Either "llm" or "ruby" |
| trigger_mode | string | No | explicit | Either "explicit", "auto", or "combined" |
| requires_rag_context | boolean | No | false | Whether skill needs access to documents/chunks |
| tags | array | No | - | Tags for categorization |
| when_to_use | string | No | - | Instructions for when to use this skill (shown to LLM in auto mode) |

### Security Guidelines

1. ** prompts only**: Always sanitize any user input before including it in prompts
2. **Limited chat access**: Ruby skills can only call whitelisted Chat methods
3. **No arbitrary code**: Ruby skills cannot execute arbitrary system commands
4. **File uploads**: Only certain file types are allowed (.md, .markdown, .txt, .yaml, .yml, .json)
5. **Timeout**: Ruby skills have a configurable timeout (default: 30 seconds)

### Configuration

Agent Skills can be configured via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| AGENT_SKILLS_ENABLED | true | Enable/disable Agent Skills feature |
| AGENT_SKILLS_MAX_FILE_SIZE | 1048576 (1MB) | Maximum file size per upload |
| AGENT_SKILLS_TIMEOUT | 30 | Timeout for Ruby skill execution in seconds |
| GUARD_MODEL | - | Model to use for auto-detection (when DETECTOR is enabled) |

### Testing Skills

Test your skill by:

1. Upload it via the web UI
2. Enable it
3. In a chat, trigger it using `/skill-name` or `@skill-name`
4. Check the chat response

For Ruby skills, ensure:
- The class name matches the pattern: `AgentSkills::{NameCamelized}`
- The class inherits from `AgentSkills::Base`
- The class implements a `call` method
- All required context keys are present (chat, query, agent_skill)

### Example Skills

#### Example 1: LLM-based Skill (SKILL.md)

```markdown
---
name: summarizer
description: Summarizes documents and text
execution_mode: llm
trigger_mode: explicit
requires_rag_context: true
---

## Instructions
You are a document summarization assistant. When triggered, you will receive document content and should provide a concise summary.

Focus on:
- Main points
- Key data and metrics
- Important names, dates, and conclusions
- Overall structure

Use markdown formatting for readability. Always cite your source material.
```

Use with: `/summarizer What's in my documents about AI?` or `@summarizer this text...`

#### Example 2: Ruby-based Skill

```ruby
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

### Troubleshooting

- **Skill not triggering**: Check that the skill is enabled and the name matches your trigger
- **Ruby skill not found**: Ensure the class name matches `AgentSkills::{CamelizedName}`
- **Missing context**: Ruby skills must implement the required interface
- **Timeout errors**: Ruby skills must complete within the configured timeout
- **Validation errors**: Check the SKILL.md YAML frontmatter for required fields

### Best Practices

1. **Start simple**: Begin with LLM-based skills before implementing Ruby skills
2. **Test locally**: Test your skill thoroughly before uploading
3. **Use clear names**: Skill names should be descriptive and unique
4. **Set appropriate execution mode**: Use LLM for simple behaviors, Ruby for complex logic
5. **Enable RAG when needed**: Only enable `requires_rag_context` if your skill needs document access
6. **Handle errors gracefully**: Ruby skills should include error handling
7. **Log appropriately**: Use the `log` method for debugging
8. **Document your skills**: Include clear descriptions and usage instructions

## API Reference

### Web Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/agent_skills` | List all skills for the account |
| GET | `/agent_skills/new` | Show upload form |
| POST | `/agent_skills` | Upload a new skill |
| GET | `/agent_skills/:id` | Show skill details |
| GET | `/agent_skills/:id/edit` | Show edit form |
| PATCH/PUT | `/agent_skills/:id` | Update a skill |
| DELETE | `/agent_skills/:id` | Delete a skill |
| PATCH | `/agent_skills/:id/toggle` | Toggle skill enabled/disabled |

### API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/agent_skills` | List all skills (JSON) |
| POST | `/api/v1/agent_skills` | Create a skill (JSON) |
| GET | `/api/v1/agent_skills/:id` | Show skill (JSON) |
| PATCH/PUT | `/api/v1/agent_skills/:id` | Update skill (JSON) |
| DELETE | `/api/v1/agent_skills/:id` | Delete skill (JSON) |

All API endpoints are authenticated and scoped to the current account.

## Migration from Legacy Systems

If you have existing skills from other platforms (like CrewAI, AutoGen, or LangChain), you can migrate them to Nosia:

1. Convert your skill to the SKILL.md format
2. Extract any custom logic into Ruby classes under `app/models/agent_skills/`
3. Ensure your skill follows the naming conventions
4. Upload via the web UI or API

## Contributing

Improvements to the Agent Skills system are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for your changes
4. Submit a pull request

## License

MIT License - see the LICENSE file for details.
