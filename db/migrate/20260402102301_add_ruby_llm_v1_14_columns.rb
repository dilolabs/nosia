class AddRubyLlmV114Columns < ActiveRecord::Migration[8.0]
  def change
    if column_exists?(:tool_calls, :thought_signature, :string)
      change_column :tool_calls, :thought_signature, :text
    end
  end
end
