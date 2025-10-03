module Chat::AnswerRelevance
  extend ActiveSupport::Concern

  def answer_relevance(answer, question:)
    chat = self.chats.create!(account: self.account, user: self.user, model: self.model, provider: :openai, assume_model_exists: true)
    chat.assume_model_exists = true
    chat.with_model(ENV["LLM_MODEL"], provider: :openai)
    chat.with_temperature(0.0)
    chat.with_instructions("Determine if the provided answer is relevant to the question. Respond with 'true' or 'false'.")

    response = chat.ask("Answer: #{answer}\n\nQuestion: #{question}\n\nIs the answer relevant to the question?")
    response.content.to_s.strip.downcase == "true"
  rescue => e
    Rails.logger.error("Error determining answer relevance: #{e.message}")
    false
  end
end
