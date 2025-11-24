class Prompt < ApplicationRecord
  belongs_to :account, optional: true
  belongs_to :user, optional: true

  def full_name
    case name
    when "system_prompt"
      "System Prompt for #{account.name} Account"
    end
  end
end
