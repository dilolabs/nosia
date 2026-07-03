class AddTokenCountersToChats < ActiveRecord::Migration[8.0]
  def change
    add_column :chats, :input_tokens_count, :integer, default: 0, null: false
    add_column :chats, :output_tokens_count, :integer, default: 0, null: false
  end
end
