class BackfillTokenUsages < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  # Uses insert_all to bypass TokenUsage callbacks (counter increment + Turbo
  # broadcast) — neither is appropriate during a one-time data migration, and
  # the broadcast would try to render a partial that may not exist yet. Counters
  # are recomputed from the event log via recount! at the end.
  def up
    now = Time.current
    existing_ids = TokenUsage.where(source_type: "Message").pluck(:source_id).to_set
    rows = Message.where(role: 10).where.not(input_tokens: nil).reject do |message|
      existing_ids.include?(message.id)
    end.map do |message|
      {
        account_id: message.chat.account_id,
        chat_id: message.chat_id,
        source_type: "Message",
        source_id: message.id,
        kind: "completion",
        model_id: message.model&.model_id,
        input_tokens: message.input_tokens || 0,
        output_tokens: message.output_tokens || 0,
        cached_tokens: message.cached_tokens || 0,
        cache_creation_tokens: message.cache_creation_tokens || 0,
        thinking_tokens: message.thinking_tokens || 0,
        created_at: now,
        updated_at: now
      }
    end
    TokenUsage.insert_all(rows) unless rows.empty?

    # Repair counters from the now-complete event log.
    Chat.find_each(&:recount!)
    Account.find_each(&:recount!)
  end

  def down
    TokenUsage.where(kind: "completion", source_type: "Message").delete_all
    Chat.find_each(&:recount!)
    Account.find_each(&:recount!)
  end
end
