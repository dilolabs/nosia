module Chat::ContextRelevance
  extend ActiveSupport::Concern

  def context_relevance(context, question:)
    model = ENV["GUARD_MODEL"].presence
    return true unless model

    chat = self.chats.create!(account: self.account, user: self.user, model:, provider: :openai, assume_model_exists: true)
    chat.assume_model_exists = true
    chat.with_model(model, provider: :openai)
    chat.with_temperature(0.0)
    chat.with_instructions(Prompts.context_relevance_guard, replace: true)
    response = chat.ask("Context: #{context}\n\nUser query: #{question}\n\nAnswer (0 or 1):")
    response.content.to_s.strip == "0"
  rescue => e
    Rails.logger.error("Error determining context relevance: #{e.message}")
    false
  end
end
