module Chat::Completionable
  extend ActiveSupport::Concern

  def complete_with_nosia(question, model: nil, temperature: nil, top_k: nil, top_p: nil, max_tokens: nil, &block)
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
    self.with_instructions(system_prompt) if messages.empty?

    chunks = self.similarity_search(question)
    question = self.augmented_prompt(question, chunks:) if chunks.any?

    self.ask(question) do |chunk|
      if block_given?
        yield chunk
      elsif chunk.content && !chunk.content.blank?
        message = self.messages.last
        message.broadcast_append_chunk(chunk.content)
      end
    end

    message = self.messages.last
    if chunks.any? && !self.answer_relevance(self.messages.last.content, question:)
      message.update(content: "I'm sorry, but I couldn't find relevant information to answer your question based on the provided context.")
    else
      message.update(similar_chunk_ids: chunks.pluck(:id))
    end

    message
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
    ENV["RAG_SYSTEM_TEMPLATE"]
  end
end
