class ChatResponseJob < ApplicationJob
  queue_as :real_time

  def perform(chat_id, content, user_message_id = nil)
    Rails.logger.info "=== ChatResponseJob started for chat ##{chat_id} ==="
    chat = Chat.find(chat_id)
    user_message = user_message_id ? Message.find(user_message_id) : nil
    Rails.logger.info "User message: #{user_message&.id} - Content: #{content[0..100]}..."

    # Wait for any sources attached to the user message to finish indexing so
    # retrieval can find them; collect the ones that failed or timed out so the
    # model can be warned instead of hallucinating over them.
    excluded = if user_message
      wait_result = chat.wait_for_attached_sources!(user_message)
      wait_result[:failed] + wait_result[:timed_out]
    else
      []
    end

    begin
      if Rails.application.config.agent_skills.enabled
        result = chat.complete_with_agent_skills(content, user_message: user_message, excluded_sources: excluded)
      else
        result = chat.complete_with_nosia(content, user_message: user_message, excluded_sources: excluded)
      end
      Rails.logger.info "=== ChatResponseJob completed. Result: #{result&.id} ==="
    ensure
      # Unlock the composer and clear any stuck thinking animation, whether the
      # completion succeeded or raised. The controller set generating=true on submit.
      chat.finish_generation!
    end
  rescue Faraday::TimeoutError => e
    Rails.logger.error "=== ChatResponseJob ERROR: Timeout ==="
    Rails.logger.error e.message
  rescue Faraday::Error => e
    Rails.logger.error "=== ChatResponseJob ERROR: Network error ==="
    Rails.logger.error e.message
  rescue => e
    Rails.logger.error "=== ChatResponseJob ERROR: #{e.class} ==="
    Rails.logger.error e.message
    Rails.logger.error e.backtrace.join("\n")
  end
end
