class ChatResponseJob < ApplicationJob
  queue_as :real_time

  # Transient provider/network failures deserve another shot. Anything else
  # propagates: Solid Queue marks the execution failed and Mission Control
  # surfaces it, instead of a swallow-rescue hiding dead chats as successes.
  retry_on Faraday::TimeoutError, Faraday::ConnectionFailed,
    wait: :polynomially_longer, attempts: 3

  around_perform do |job, operation|
    chat = Chat.find(job.arguments.first)
    ActsAsTenant.with_tenant(chat.account) { operation.call }
  end

  def perform(chat_id, content, user_message_id = nil)
    Rails.logger.info "=== ChatResponseJob started for chat ##{chat_id} ==="
    chat = Chat.find(chat_id)
    user_message = user_message_id ? Message.find(user_message_id) : nil

    # Drop any blank assistant message left by a previous failed/empty generation.
    # ruby_llm would serialize it into this request's history and the provider
    # rejects nil content ("invalid message content type: <nil>"), which would
    # otherwise block every further response in this chat.
    chat.purge_blank_assistant_messages!

    # Wait for any sources attached to the user message to finish indexing so
    # retrieval can find them; collect the ones that failed or timed out so the
    # model can be warned instead of hallucinating over them.
    excluded = if user_message
      wait_result = chat.wait_for_attached_sources!(user_message)
      wait_result[:failed] + wait_result[:timed_out]
    else
      []
    end

    if Rails.application.config.agent_skills.enabled
      result = chat.complete_with_agent_skills(content, user_message: user_message, excluded_sources: excluded)
    else
      result = chat.complete_with_nosia(content, user_message: user_message, excluded_sources: excluded)
    end
    Rails.logger.info "=== ChatResponseJob completed. Result: #{result&.id} ==="
  ensure
    # Unlock the composer and clear any stuck thinking animation, whether the
    # completion succeeded or raised. The controller set generating=true on submit.
    chat&.finish_generation!
  end
end
