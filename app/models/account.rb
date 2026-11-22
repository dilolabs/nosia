class Account < ApplicationRecord
  include Overview

  belongs_to :owner, class_name: "User"

  before_destroy :prepare_dependent_cleanup, prepend: true

  has_many :account_users, dependent: :destroy do
    def grant_to(users)
      account = proxy_association.owner
      AccountUser.insert_all(Array(users).collect { |user| { account_id: account.id, user_id: user.id } })
    end
  end
  has_many :api_tokens, dependent: :destroy
  has_many :users, through: :account_users, dependent: :destroy
  has_many :chats, dependent: :destroy
  has_many :chunks, dependent: :destroy
  has_many :documents, dependent: :destroy
  has_many :mcp_servers, dependent: :destroy
  has_many :notes, dependent: :destroy
  has_many :note_folders, dependent: :destroy
  has_many :note_imports, dependent: :destroy
  has_many :note_tags, dependent: :destroy
  has_many :prompts, dependent: :destroy
  has_many :qnas, dependent: :destroy
  has_many :texts, dependent: :destroy
  has_many :websites, dependent: :destroy
  has_many :agent_skills, dependent: :destroy
  has_many :token_usages, dependent: :destroy

  # Finds or lazily creates the permanent Notes root for this account.
  # @return [NoteFolder] The account's General folder.
  def general_note_folder
    with_lock do
      note_folders.find_or_create_by!(system_key: NoteFolder::GENERAL_SYSTEM_KEY) do |folder|
        folder.name = "General"
      end
    end
  end

  # Recompute cached token counters from the token_usages event log (drift repair).
  # Rails 8's sum takes a single column, so two queries (small, indexed).
  def recount!
    update!(input_tokens_count: token_usages.sum(:input_tokens) || 0,
            output_tokens_count: token_usages.sum(:output_tokens) || 0)
  end

  def self.create_with_system_prompt!(attributes)
    account = Account.create!(attributes)

    account.account_users.grant_to(account.owner)

    content = Prompts.system_prompt
    account.prompts.create!(name: "system_prompt", content:)
    account.prompts.create!(user: account.owner, name: "system_prompt", content:)

    account
  end

  def augmented_context
    context = []
    context << texts.map(&:context)
    context << qnas.map(&:context)
    context << documents.map(&:context)
    context
  end

  def create_default_system_prompt!(user: nil)
    prompts.where(name: "system_prompt", user:).first_or_create!(
      content: YAML.load_file(Rails.root.join("config", "prompts.yml"))["system_prompt"]
    )
  end

  def default_context
    context = []
    context << texts.map(&:context)
    context
  end

  def system_prompt(user: nil)
    prompt = prompts.find_by(name: "system_prompt", user_id: user&.id)
    prompt ||= prompts.find_by(name: "system_prompt", user_id: nil)
    prompt.present? ? prompt.content : Prompts.system_prompt
  end

  # Environmental impact of this account's token usage: per-model completion
  # energy (top 5) plus embedding energy, with the Comparia fallback flag so
  # the UI can mark estimates.
  def green_it_summary
    by_model = token_usages.where.not(model_id: nil)
      .group(:model_id).sum("(input_tokens + output_tokens)")

    models = by_model.sort_by { |_, tokens| -tokens }.first(5).map do |model_id, tokens|
      impact = GreenIt.energy_kwh(tokens: tokens, model_id: model_id, kind: :completion)
      { model_id:, tokens:, kwh: impact[:kwh], fallback: impact[:fallback] }
    end

    embedding_tokens = token_usages.where(kind: :embedding)
      .sum("(input_tokens + output_tokens)")
    embedding_energy = GreenIt.energy_kwh(tokens: embedding_tokens, model_id: nil, kind: :embedding)

    kwh = models.sum { |entry| entry[:kwh] } + embedding_energy[:kwh]

    {
      models:,
      kwh:,
      co2e_g: GreenIt.co2e_g(kwh:),
      fallback_used: models.any? { |entry| entry[:fallback] }
    }
  end

  private
    def prepare_dependent_cleanup
      Account.lock.find(id)
      notes.reload
      note_folders.reload
      note_imports.reload
      note_tags.reload
      McpAuthorization.uncached { McpAuthorization.where(account_id: id).find_each(&:retire!) }
    end
end
