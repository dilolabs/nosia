module Chat::Completionable
  extend ActiveSupport::Concern

  def complete_with_nosia(question, model: nil, temperature: nil, top_k: nil, top_p: nil, max_tokens: nil, user_message: nil, &block)
    options = default_options.merge(
      {
        model:,
        temperature:,
        top_k:,
        top_p:,
        max_tokens:
      }.compact_blank
    )

    self.assume_model_exists = true
    self.with_model(options[:model], provider: :openai)
    self.with_params(max_tokens: options[:max_tokens], top_p: options[:top_p], top_k: options[:top_k])
    self.with_temperature(options[:temperature])

    # Add MCP tools if available
    mcp_tools_list = mcp_tools
    if mcp_tools_list.any?
      Rails.logger.info "=== Adding #{mcp_tools_list.size} MCP tools to conversation ==="
      self.with_tools(*mcp_tools_list)
    end

    # If a user message already exists (created in the controller), we use it
    # Otherwise, we create a new one
    if user_message
      Rails.logger.info "=== Using existing user message ##{user_message.id} ==="
    else
      Rails.logger.info "=== Creating a new user message ==="
      user_message = self.messages.create!(role: "user", content: question)
    end

    Rails.logger.info "Messages user before self.ask: #{self.messages.where(role: 'user').pluck(:id, :content).inspect}"

    # Phase 1: Searching for context
    broadcast_thinking_phase("searching", "Searching through your documents...")
    chunks = self.similarity_search(question)

    # Prepare the augmented question with context
    if chunks.any?
      augmented_context = ActiveModel::Type::Boolean.new.cast(ENV["AUGMENTED_CONTEXT"])

      documents = chunks.map.with_index do |chunk, index|
        {
          "doc_id": index + 1,
          "title": chunk.title,
          "text": augmented_context ? chunk.augmented_context : chunk.context,
          "source": chunk.source
        }
      end

      augmented_system_prompt = system_prompt.sub("%{documents}", documents.to_json)

      self.with_instructions(augmented_system_prompt, replace: true)
    else
      self.with_instructions(system_prompt, replace: true)
    end

    # Keep the original user message ID
    original_user_message_id = user_message.id

    # Phase 2: Generating the response
    broadcast_thinking_phase("generating", "Generating response...")

    # self.ask() will create a SECOND user message, but it will not be broadcasted
    # thanks to the logic in broadcast_created which detects duplicates
    self.ask(question) do |chunk|
      if block_given?
        yield chunk
      elsif chunk.content && !chunk.content.blank?
        message = self.messages.last
        message.broadcast_append_chunk(chunk.content)
      end
    end

    # Remove the duplicate user message created by self.ask() to avoid duplicates on reload
    # We look for user messages created AFTER our original message
    Rails.logger.info "Messages user after self.ask: #{self.messages.where(role: 'user').pluck(:id, :content).inspect}"

    duplicate_user_messages = self.messages
      .where(role: "user")
      .where.not(id: original_user_message_id)
      .where("created_at >= ?", user_message.created_at)

    Rails.logger.info "Potential duplicates found: #{duplicate_user_messages.pluck(:id).inspect}"

    duplicate_user_messages.each do |duplicate|
      # Check that it's really a duplicate (same question without context)
      original_q = user_message.question&.strip
      duplicate_q = duplicate.question&.strip

      Rails.logger.info "Comparison: original='#{original_q}' vs duplicate='#{duplicate_q}'"

      if original_q == duplicate_q
        Rails.logger.info "✓ Deleting duplicate user message ##{duplicate.id}"
        duplicate.destroy
      else
        Rails.logger.info "✗ Not an exact duplicate, keeping message ##{duplicate.id}"
      end
    end

    Rails.logger.info "Final user messages: #{self.messages.where(role: 'user').pluck(:id).inspect}"

    message = self.messages.last

    if !self.answer_relevance(self.messages.last.content, question:)
      Rails.logger.info "=== Answer deemed not relevant, adding warning ==="
      warning_text = "\n\n*Note: The answer provided may not be relevant to your question based on the available documents.*"
      message.update(content: message.content + warning_text)
    end

    message.update(similar_chunk_ids: chunks.pluck(:id))

    message
  end

  def broadcast_thinking_phase(phase, message)
    broadcast_update_to self, :messages,
      target: "thinking_animation_content",
      partial: "messages/thinking_animation",
      locals: { phase: phase, message: message }
  end

  private

  def default_options
    {
      max_tokens: ENV["LLM_MAX_TOKENS"].to_i,
      model: ENV["LLM_MODEL"],
      temperature: ENV["LLM_TEMPERATURE"].to_f,
      top_k: ENV["LLM_TOP_K"].to_f,
      top_p: ENV["LLM_TOP_P"].to_f
    }
  end

  def retrieval_fetch_k
    ENV["RETRIEVAL_FETCH_K"].to_i
  end

  def system_prompt
    self.account.system_prompt(user: self.user)
  end
end
