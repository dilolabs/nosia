module Chat::Completionable
  extend ActiveSupport::Concern

  # @param note_access [Chat::NoteRetrieval, nil] Trusted authority supplied only by the turn's entry point.
  def complete_with_nosia(question, model: nil, temperature: nil, top_k: nil, top_p: nil, max_tokens: nil, user_message: nil, excluded_sources: nil, note_access: nil, stream_buffer: Message::StreamBuffer.new)
    excluded_sources ||= []
    options = default_options.merge(
      {
        model:,
        temperature:,
        top_k:,
        top_p:,
        max_tokens:
      }.compact_blank
    )

    self.with_model(options[:model], provider: :openai, assume_model_exists: true)
    self.with_provider_options(max_tokens: options[:max_tokens], top_p: options[:top_p], top_k: options[:top_k])
    self.with_temperature(options[:temperature])

    # Phase 1: Searching for context (phase broadcast now lives in similarity_search,
    # so both the chat path and the agent-skills path get the Searching -> Retrieving
    # sequence consistently).
    chunks = note_access ? similarity_search(question, note_access:) : similarity_search(question)

    # Phase 2: Generating the response
    broadcast_thinking_phase("generating")

    # Process the latest user message
    if block_given?
      # API/SSE path: yield raw chunks to the caller, no turbo broadcasts.
      # (No stop support: the API has no stop endpoint.)
      citation_ids = complete_with_context(chunks, excluded_sources:, note_access:) { |chunk| yield chunk }
    else
      # Chat UI path: coalesce deltas and re-render the full buffer as markdown.
      message = nil
      begin
        citation_ids = complete_with_context(chunks, excluded_sources:, note_access:) do |chunk|
          raise Chat::GenerationStopped if self.generation_stopped?

          message ||= self.messages.last
          if chunk.content && message
            stream_buffer << chunk.content
            message.broadcast_streamed_content(stream_buffer.text) if stream_buffer.flush?
          end
        end
      rescue Chat::GenerationStopped
        Rails.logger.info "=== Generation stopped by user for chat ##{id} ==="
      end

      message&.broadcast_streamed_content(stream_buffer.text) if stream_buffer.any? # final flush

      # A stop aborts before ruby_llm persists the final message; keep what
      # already streamed by writing the buffer into the blank placeholder row.
      if generation_stopped?
        message&.update(content: stream_buffer.text) if stream_buffer.any? && message&.assistant?
        return message
      end
    end

    # Final assistant message is now fully persisted
    message = self.messages.last

    if !self.answer_relevance(self.messages.last.content, question:)
      warning_text = "\n\n*Note: The answer provided may not be relevant to your question based on the available documents.*"
      message.update(content: message.content + warning_text)
    end

    message.update(similar_chunk_ids: citation_ids)

    record_completion_usage!(message)

    message
  end

  def broadcast_thinking_phase(phase)
    broadcast_localized_to :update, self, :messages,
      target: "thinking_animation_content",
      partial: "messages/thinking_animation",
      locals: { phase: phase }
  end

  private

  def complete_with_context(chunks, excluded_sources:, note_access:, &stream)
    with_mcp_tools do
      prompt = system_prompt
      augmented = ActiveModel::Type::Boolean.new.cast(ENV["AUGMENTED_CONTEXT"])
      sources = chunks.reject { |chunk| chunk.try(:note_chunk?) }
      source_passages = sources.to_h do |chunk|
        text = augmented ? chunk.augmented_context : chunk.context
        [ chunk.id, document_passage(title: chunk.title, text:, source: chunk.source) ]
      end
      baseline = prompt_with_passages(prompt, source_passages.values)
      with_instructions(baseline)
      append_excluded_sources_warning(excluded_sources) if excluded_sources.present?
      citation_ids = sources.map(&:id)

      if note_access && sources.size < chunks.size && prompt.include?("%{documents}")
        # RubyLLM invokes this for the initial send and each tool follow-up.
        # Never persist Note excerpts in system messages that another turn can replay.
        apply_note_context = ->(payload) do
          instructions = payload[:messages]&.find { |entry| entry[:role] == "system" && entry[:content] == baseline }
          if instructions
            passages = current_passages(chunks, source_passages, note_access:, augmented:)
            instructions[:content] = prompt_with_passages(prompt, passages.values)
            citation_ids = passages.keys
          end
        end
        with_note_context_hook(apply_note_context) { complete(&stream) }
      else
        complete(&stream)
      end
      citation_ids
    end
  end

  def with_note_context_hook(callback)
    before_request { |payload| Nosia::NoteProviderRequest.refresh_each_attempt(payload, &callback) if callback }
    yield
  ensure
    # The SDK memoizes callbacks on the chat object; leave this one inert after the turn.
    callback = nil
  end

  def current_passages(chunks, source_passages, note_access:, augmented:)
    note_candidates = chunks.select { |chunk| chunk.try(:note_chunk?) }
    note_passages = note_access.current_excerpts(self, note_candidates, augmented:).transform_values do |title, text|
      document_passage(title:, text:)
    end
    included = note_candidates.select { |candidate| note_passages.key?(candidate.id) }
    note_passages.slice!(*note_access.current_candidate_ids(self, included))
    passages = source_passages.merge(note_passages)
    chunks.each_with_object({}) do |chunk, ordered|
      ordered[chunk.id] = passages.fetch(chunk.id) if passages.key?(chunk.id)
    end
  end

  def document_passage(title:, text:, source: "")
    { "title" => title, "text" => text, "source" => source }
  end

  def prompt_with_passages(prompt, passages)
    return prompt if passages.empty?

    documents = passages.map.with_index(1) { |passage, index| { "doc_id" => index }.merge(passage) }
    prompt.sub("%{documents}") { documents.to_json }
  end

  def append_excluded_sources_warning(excluded_sources)
    titles = excluded_sources.filter_map { |source| source.title if source.respond_to?(:title) }
    names = titles.any? ? titles : excluded_sources.map { |source| source.class.name.downcase }
    with_instructions("Note: the following attachments could not be retrieved and were excluded: #{names.join(", ")}.", append: true)
  end

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
