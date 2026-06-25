class ChangeAgentSkillsToTextArea < ActiveRecord::Migration[8.0]
  def up
    add_column :agent_skills, :skill_content, :text

    # Backfill skill_content from existing skill_md attachments
    AgentSkill.find_each do |skill|
      if skill.skill_md.attached?
        skill.update_column(:skill_content, skill.skill_md.blob.download)
      end
    end
  end

  def down
    remove_column :agent_skills, :skill_content
  end
end
