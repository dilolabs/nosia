module Chat::ContextRelevance
  extend ActiveSupport::Concern

  def context_relevance(context, question:)
    chat = self.chats.create!(account: self.account, user: self.user, model: self.model, provider: :openai, assume_model_exists: true)
    chat.assume_model_exists = true
    model = ENV["GUARD_MODEL"] || ENV["LLM_MODEL"]
    chat.with_model(model, provider: :openai)
    chat.with_temperature(0.0)
    chat.with_instructions("Respond with 'true' if the context is relevant to answer the question, otherwise respond with 'false'. Do not provide any additional information.")

    response = chat.ask("Context: #{context}\n\nQuestion: #{question}\n\nIs the context relevant to answer the question?")
    response.content.to_s.strip.downcase == "true"
  rescue => e
    Rails.logger.error("Error determining context relevance: #{e.message}")
    false
  end
end
