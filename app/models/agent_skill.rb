class AgentSkill < ApplicationRecord
  extend ActiveModel::Naming

  acts_as_tenant :account

  has_many_attached :files
  has_one_attached :skill_md

  belongs_to :account

  has_many :agent_skill_executions, dependent: :destroy

  enum :execution_mode, { llm: "llm", ruby: "ruby" }
  enum :trigger_mode, { explicit: "explicit", auto: "auto", combined: "combined" }

  validates :name, presence: true,
            uniqueness: { scope: :account_id },
            format: { with: /\A[a-zA-Z][a-zA-Z0-9_-]*\z/,
                     message: "must start with a letter and contain only alphanumeric, underscore, and hyphen" }
  validates :execution_mode, presence: true
  validates :trigger_mode, presence: true
  validates :priority, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validate :validate_skill_md_present, on: :create
  validate :validate_metadata_present, on: :create

  scope :runnable, -> { where(enabled: true) }
  scope :by_name, ->(name) { where(name: name) }

  def ruby_class_name
    "AgentSkills::#{name.camelize}"
  end

  def runnable?
    enabled? &&
      (execution_mode == "llm" ||
       (execution_mode == "ruby" && ruby_class_name.safe_constantize.present?))
  end

  private

  def validate_skill_md_present
    errors.add(:skill_md, "must be attached") unless skill_md.attached?
  end

  def validate_metadata_present
    return if metadata.present? && metadata["name"].present?
    errors.add(:skill_md, "must contain valid YAML frontmatter with at least 'name' field")
  end
end
