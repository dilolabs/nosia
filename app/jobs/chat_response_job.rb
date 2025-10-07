class ChatResponseJob < ApplicationJob
  queue_as :real_time

  def perform(chat_id, content)
    chat = Chat.find(chat_id)
    chat.complete_with_nosia(content)
  end
end
