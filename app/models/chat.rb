class Chat < ApplicationRecord
  include ActionView::RecordIdentifier
  include AnswerRelevance
  include AugmentedPrompt
  include Completionable
  include ContextRelevance
  include ModelContextProtocol
  include SimilaritySearch
  include AgentSkillable

  acts_as_chat
  broadcasts_to ->(chat) { [ chat, "messages" ] }

  belongs_to :account
  belongs_to :chat, optional: true
  belongs_to :user
  belongs_to :model, optional: true
  has_many :chats, dependent: :destroy
  has_many :messages, dependent: :destroy
  has_many :token_usages, dependent: :destroy

  scope :root, -> { where(chat_id: nil) }

  # Recompute cached token counters from the token_usages event log (drift repair).
  # Rails 8's sum takes a single column, so two queries (small, indexed).
  def recount!
    update!(input_tokens_count: token_usages.sum(:input_tokens) || 0,
            output_tokens_count: token_usages.sum(:output_tokens) || 0)
  end

  # Per-kind token breakdown: { "completion" => [in, out], ... }
  def token_totals_by_kind
    inputs = token_usages.group(:kind).sum(:input_tokens)
    outputs = token_usages.group(:kind).sum(:output_tokens)
    (inputs.keys | outputs.keys).index_with do |kind|
      [ inputs[kind] || 0, outputs[kind] || 0 ]
    end
  end

  # Bounded poll over a user message's attached sources (websites, documents)
  # until every one reaches a terminal index_status (indexed or failed), or the
  # timeout elapses. Returns { ready:, failed:, timed_out: }. No-op when the
  # message has no attached sources.
  def wait_for_attached_sources!(user_message, timeout: ENV.fetch("CHAT_INDEXING_TIMEOUT", 120).to_i.seconds, step: 1.second)
    sources = user_message.attached_websites + user_message.attached_documents
    return { ready: [], failed: [], timed_out: [] } if sources.empty?

    broadcast_thinking_phase("indexing", "Indexing your attachments...")

    deadline = Time.current + timeout

    loop do
      pending = sources.reject { |source| source.indexed? || source.failed? }
      break if pending.empty? || Time.current >= deadline
      sleep step
      sources = sources.map(&:reload)
    end

    {
      ready:     sources.select { |source| source.indexed? },
      failed:    sources.select { |source| source.failed? },
      timed_out: sources.reject { |source| source.indexed? || source.failed? }
    }
  end

  # Record a TokenUsage for an assistant message produced by a completion,
  # de-duped via the polymorphic source link (idempotent: re-running a
  # completion for the same message does not create a duplicate). Called from
  # Chat::Completionable#complete_with_nosia with the just-completed message.
  def record_completion_usage!(message)
    return if message.nil? || message.input_tokens.nil?
    return if TokenUsage.where(source: message).exists?

    TokenUsage.create!(
      account_id:,
      chat_id: id,
      kind: :completion,
      source: message,
      model_id: message.model&.model_id,
      input_tokens: message.input_tokens || 0,
      output_tokens: message.output_tokens || 0,
      cached_tokens: message.cached_tokens || 0,
      cache_creation_tokens: message.cache_creation_tokens || 0,
      thinking_tokens: message.thinking_tokens || 0
    )
  end

  def first_question
    messages.where(role: "user").order(:created_at).first&.question
  end

  def response_number
    Message.where(chat_id: id).count
  end

  def title
    first_question
  end

  # Mark the chat as actively generating so the composer renders busy. No broadcast —
  # the create response renders the busy form, and a fresh page load mid-generation
  # reads `generating` from the DB (reconnect-safe). Uses update_column to skip this
  # model's broadcasts_to after_update_commit auto-replace (a spurious chat-partial
  # BroadcastJob that is a no-op on the show page, which has no #chat_<id> target).
  def start_generation!
    update_column(:generating, true)
  end

  # Mark generation done and broadcast the composer unlock + a thinking_animation
  # remove (no-op on success where broadcast_created already removed it; cleans up the
  # error-before-bubble case). update_column skips the broadcasts_to auto-replace; the
  # two explicit broadcasts are synchronous so the unlock is immediate.
  def finish_generation!
    update_column(:generating, false)
    broadcast_replace_to [ self, "messages" ],
      target: "#{dom_id(self)}_message_form",
      partial: "messages/form",
      locals: { chat: self }
    broadcast_remove_to self, :messages, target: "thinking_animation"
  end
end
