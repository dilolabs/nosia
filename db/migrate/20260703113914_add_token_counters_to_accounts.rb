class AddTokenCountersToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :input_tokens_count, :integer, default: 0, null: false
    add_column :accounts, :output_tokens_count, :integer, default: 0, null: false
  end
end
