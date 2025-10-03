module Chat::ContextRelevance
  extend ActiveSupport::Concern

  def context_relevance(context, question:)
    chat = self.chats.create!(account: self.account, user: self.user, model: self.model, provider: :openai, assume_model_exists: true)
    chat.assume_model_exists = true
    chat.with_model(ENV["LLM_MODEL"], provider: :openai)
    chat.with_temperature(0.0)
    chat.with_instructions("Determine if the provided context is relevant to answer the question. Respond with 'true' or 'false'.")

    response = chat.ask("Context: #{context}\n\nQuestion: #{question}\n\nIs the context relevant to answer the question?")
    response.content.to_s.strip.downcase == "true"
  rescue => e
    Rails.logger.error("Error determining context relevance: #{e.message}")
    false
  end
end
