class AddStepToMessage < ActiveRecord::Migration[8.0]
  def change
    add_column :messages, :step, :string, default: "default"
  end
end
