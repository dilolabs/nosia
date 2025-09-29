module Chat::Completionable
  extend ActiveSupport::Concern

  class_methods do
    def ai_provider
      ENV.fetch("AI_PROVIDER", "ollama")
    end
  end

  # TODO: Refactor
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

    case self.class.ai_provider
    when "ollama"
      complete_with_ollama(content, top_k: options[:top_k], top_p: options[:top_p], &block)
    when "infomaniak"
      complete_with_cloud(content, model: options[:model], temperature: options[:temperature], top_p: options[:top_p], max_tokens: options[:max_tokens], &block)
    else
      raise "Unsupported AI provider: #{self.class.ai_provider}"
    end
  end

  def complete_with_cloud(question, model:, temperature:, top_p:, max_tokens:, &block)
    self.assume_model_exists = true
    self.with_model(ENV['LLM_MODEL'], provider: :openai)
    self.with_temperature(temperature)
    self.with_instructions(system_prompt) if messages.empty?

    search_results = self.search(question)
    question = prompt(question, search_results:) if search_results.any?

    self.ask(question) do |chunk|
      if chunk.content && !chunk.content.blank?
        message = self.messages.last
        message.broadcast_append_chunk(chunk.content)
      end
    end

    message = self.messages.last
    message.update(similar_chunk_ids: search_results.pluck(:id))
  end

  private

  def default_options
    {
      max_tokens: ENV.fetch("LLM_MAX_TOKENS", 1_024).to_i,
      model: ENV.fetch("LLM_MODEL", nil),
      temperature: ENV.fetch("LLM_TEMPERATURE", 0.1).to_f,
      top_k: ENV.fetch("LLM_TOP_K", 40).to_f,
      top_p: ENV.fetch("LLM_TOP_P", 0.9).to_f
    }
  end

  def prompt(question, search_results:)
    context = search_results.map do |retrieved_chunk|
      retrieved_chunk.context
    end.join("\n\n")

    "<context>#{context}</context>#{question}"
  end

  def retrieval_fetch_k
    ENV.fetch("RETRIEVAL_FETCH_K", 4)
  end

  def search(question)
    account.chunks.search_by_similarity(question, limit: retrieval_fetch_k)
  end

  def system_prompt
    ENV.fetch("RAG_SYSTEM_TEMPLATE", "You are Nosia. You are a helpful assistant.")
  end
end
