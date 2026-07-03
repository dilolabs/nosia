class CreateTokenUsages < ActiveRecord::Migration[8.0]
  def change
    create_table :token_usages do |t|
      t.references :account, null: false, foreign_key: true
      t.references :chat, foreign_key: true
      t.references :source, polymorphic: true, index: false
      t.string :kind, null: false
      t.string :model_id
      t.integer :input_tokens, default: 0, null: false
      t.integer :output_tokens, default: 0, null: false
      t.integer :cached_tokens, default: 0
      t.integer :cache_creation_tokens, default: 0
      t.integer :thinking_tokens, default: 0
      t.timestamps
    end

    add_index :token_usages, %i[account_id created_at]
    add_index :token_usages, %i[source_type source_id]
    add_index :token_usages, %i[account_id kind]
    add_index :token_usages, %i[account_id model_id]
  end
end
