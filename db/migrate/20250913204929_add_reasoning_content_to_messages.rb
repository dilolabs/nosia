class AddReasoningContentToMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :messages, :reasoning_content, :text
  end
end
