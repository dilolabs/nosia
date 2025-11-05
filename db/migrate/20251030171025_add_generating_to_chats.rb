class AddGeneratingToChats < ActiveRecord::Migration[8.0]
  def change
    add_column :chats, :generating, :boolean, default: false, null: false
  end
end
