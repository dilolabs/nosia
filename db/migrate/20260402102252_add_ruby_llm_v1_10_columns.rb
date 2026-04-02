class AddRubyLlmV110Columns < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:messages, :thinking_text)
      add_column :messages, :thinking_text, :text
    end

    unless column_exists?(:messages, :thinking_signature)
      add_column :messages, :thinking_signature, :text
    end

    unless column_exists?(:messages, :thinking_tokens)
      add_column :messages, :thinking_tokens, :integer
    end

    unless column_exists?(:tool_calls, :thought_signature)
      add_column :tool_calls, :thought_signature, :string
    end
  end
end
