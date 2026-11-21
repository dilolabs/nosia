module Chat::ContextRelevance
  extend ActiveSupport::Concern

  # A Note excerpt is supplied at the wire boundary, not saved in the guard chat.
  # @yieldreturn [String, nil] The current authorized excerpt, if still available.
  def context_relevance(context, question:)
    model = ENV["GUARD_MODEL"].presence
    return true unless model

    chat = self.chats.create!(account: self.account, user: self.user, model:, provider: :openai, assume_model_exists: true)
    chat.with_model(model, provider: :openai, assume_model_exists: true)
    chat.with_temperature(0.0)
    chat.with_instructions(Prompts.context_relevance_guard)
    if block_given?
      chat.before_request do |payload|
        context = yield
        if context
          payload.fetch(:messages).last[:content] = context_relevance_input(context, question)
        end
      end
      response = chat.ask(context_relevance_input(nil, question))
    else
      response = chat.ask(context_relevance_input(context, question))
    end
    (!block_given? || context.present?) && response.content.to_s.strip == "0"
  rescue => e
    Rails.logger.error("Error determining context relevance: #{e.message}")
    false
  end

  private
    def context_relevance_input(context, question)
      "Context: #{context}\n\nUser query: #{question}\n\nAnswer (0 or 1):"
    end
end
