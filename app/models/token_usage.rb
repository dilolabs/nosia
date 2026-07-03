class TokenUsage < ApplicationRecord
  include ActionView::RecordIdentifier

  acts_as_tenant :account

  belongs_to :chat, optional: true
  belongs_to :source, polymorphic: true, optional: true

  enum :kind, { completion: "completion", embedding: "embedding", agent_skill: "agent_skill" }

  validates :kind, presence: true

  after_create :increment_counters
  # Live-refresh the chat totals header when a chat-scoped usage is created
  # (completion / query-embedding / agent-skill). Indexing embeddings have no
  # chat header to refresh (chat nil) — guarded by `if: :chat`.
  after_create_commit :broadcast_token_totals, if: :chat

  def total_tokens
    (input_tokens || 0) + (output_tokens || 0)
  end

  def energy
    @energy ||= GreenIt.energy_kwh(tokens: total_tokens, model_id:, kind:)
  end

  def energy_kwh
    energy[:kwh]
  end

  def co2e_g
    GreenIt.co2e_g(kwh: energy_kwh)
  end

  def used_fallback?
    energy[:fallback]
  end

  private

  def increment_counters
    if chat_id.present?
      Chat.update_counters(chat_id, input_tokens_count: input_tokens, output_tokens_count: output_tokens)
      chat.touch
    end
    Account.update_counters(account_id, input_tokens_count: input_tokens, output_tokens_count: output_tokens)
  end

  def broadcast_token_totals
    broadcast_replace_to [ chat, :token_totals ],
      target: dom_id(chat, :token_totals),
      partial: "chats/token_totals",
      locals: { chat: chat }
  end
end