module Chat::Completionable
  extend ActiveSupport::Concern

  def complete_with_nosia(content, model: nil, temperature: nil, top_k: nil, top_p: nil, max_tokens: nil, &block)
    options = default_options.merge(
      {
        model:,
        temperature:,
        top_k:,
        top_p:,
        max_tokens:
      }.compact_blank
    )

    complete_with_cloud(content, model: options[:model], temperature: options[:temperature], top_p: options[:top_p], max_tokens: options[:max_tokens], &block)
  end

  def complete_with_cloud(question, model:, temperature:, top_p:, max_tokens:, &block)
    self.assume_model_exists = true
    self.with_model(ENV["LLM_MODEL"], provider: :openai)
    self.with_temperature(temperature)
    self.with_instructions(system_prompt) if messages.empty?

    original_question = question.dup
    chunks = self.search(question)
    question = prompt(question, chunks:) if chunks.any?

    self.ask(question) do |chunk|
      if chunk.content && !chunk.content.blank?
        message = self.messages.last
        message.broadcast_append_chunk(chunk.content)
      end
    end

    if chunks.any? && !self.answer_relevance(self.messages.last.content, question:)
      Rails.logger.info("Answer deemed irrelevant, retrying without context.")
      self.ask(original_question) do |chunk|
        if chunk.content && !chunk.content.blank?
          message = self.messages.last
          message.broadcast_append_chunk(chunk.content)
        end
      end
    else
      message = self.messages.last
      message.update(similar_chunk_ids: chunks.pluck(:id))
      self
    end
  end

  private

  def answer_relevance(answer, question:)
    self.assume_model_exists = true
    self.with_model(ENV["LLM_MODEL"], provider: :openai)
    self.with_temperature(0.0)
    self.with_instructions("Determine if the provided answer is relevant to the question. Respond with 'true' or 'false'.")

    response = nil
    self.ask("Answer: #{answer}\n\nQuestion: #{question}\n\nIs the answer relevant to the question?") do |chunk|
      response = chunk.content
    end

    response.to_s.strip.downcase == "true"
  rescue => e
    Rails.logger.error("Error determining answer relevance: #{e.message}")
    false
  end

  def context_relevance(context, question:)
    self.assume_model_exists = true
    self.with_model(ENV["LLM_MODEL"], provider: :openai)
    self.with_temperature(0.0)
    self.with_instructions("Determine if the provided context is relevant to answer the question. Respond with 'true' or 'false'.")

    response = nil
    self.ask("Context: #{context}\n\nQuestion: #{question}\n\nIs the context relevant to answer the question?") do |chunk|
      response = chunk.content
    end

    response.to_s.strip.downcase == "true"
  rescue => e
    Rails.logger.error("Error determining context relevance: #{e.message}")
    false
  end

  def default_options
    {
      max_tokens: ENV.fetch("LLM_MAX_TOKENS", 1_024).to_i,
      model: ENV.fetch("LLM_MODEL", nil),
      temperature: ENV.fetch("LLM_TEMPERATURE", 0.1).to_f,
      top_k: ENV.fetch("LLM_TOP_K", 40).to_f,
      top_p: ENV.fetch("LLM_TOP_P", 0.9).to_f
    }
  end

  def prompt(question, chunks:)
    context = chunks.map { |chunk| chunk.context }.join("\n\n")

    "<context>#{context}</context>#{question}"
  end

  def retrieval_fetch_k
    ENV.fetch("RETRIEVAL_FETCH_K", 4)
  end

  def search(question)
    chunks = account.chunks.search_by_similarity(question, limit: retrieval_fetch_k)
    chunks.each do |chunk|
      return chunk if self.context_relevance(chunk.context, question:)
    end
  end

  def system_prompt
    ENV.fetch("RAG_SYSTEM_TEMPLATE", "You are Nosia. You are a helpful assistant.")
  end
end
