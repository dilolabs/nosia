module Chat::AnswerRelevance
  extend ActiveSupport::Concern

  def answer_relevance(answer, question:)
    model = ENV["GUARD_MODEL"].presence
    return true unless model

    chat = self.chats.create!(account: self.account, user: self.user, provider: :openai, assume_model_exists: true)
    chat.assume_model_exists = true
    chat.with_model(model, provider: :openai)
    chat.with_temperature(0.0)
    chat.with_instructions(Prompts.answer_relevance_guard, replace: true)
    response = chat.ask("Answer: #{answer}\n\nUser question: #{question}\n\nAnswer (0 or 1):")
    response.content.to_s.strip.downcase == "0"
  rescue => e
    Rails.logger.error("Error determining answer relevance: #{e.message}")
    false
  end
end
