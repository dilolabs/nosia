class AddAccountToAgentSkillExecutions < ActiveRecord::Migration[8.0]
  def change
    add_reference :agent_skill_executions, :account, null: false, foreign_key: true
  end
end
