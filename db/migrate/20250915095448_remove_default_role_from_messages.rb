class RemoveDefaultRoleFromMessages < ActiveRecord::Migration[8.0]
  def change
    change_column_default :messages, :role, nil
  end
end
