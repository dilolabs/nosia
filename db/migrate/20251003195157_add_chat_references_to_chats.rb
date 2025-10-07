class AddChatReferencesToChats < ActiveRecord::Migration[8.0]
  def change
    add_reference :chats, :chat, null: true, foreign_key: true
  end
end
