class AgentSkillExecution < ApplicationRecord
  acts_as_tenant :account

  belongs_to :agent_skill
  belongs_to :chat
  belongs_to :message, optional: true

  enum :status, { pending: "pending", completed: "completed", failed: "failed", timed_out: "timed_out" }
  enum :execution_mode, { llm: "llm", ruby: "ruby" }

  validates :agent_skill, presence: true
  validates :chat, presence: true
  validates :execution_mode, presence: true
end
