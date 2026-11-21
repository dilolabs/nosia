# Trusted, turn-local authority to retrieve current Notes for a saved chat.
Chat::NoteRetrieval = Data.define(:kind, :token_id) do
  def self.web
    new(kind: :web, token_id: nil)
  end

  # @param id [Integer] The authenticated API token's id, never a request parameter.
  def self.api(id)
    new(kind: :api, token_id: id)
  end

  # @param chat [Chat] The saved conversation.
  # @return [Boolean] Whether this turn may retrieve Notes at the time of the check.
  def allowed?(chat)
    AccountUser.uncached { current_membership(chat).exists? }
  end

  # Reloads an eligible candidate and, optionally, its nearby published passages.
  # @param chat [Chat] The saved conversation.
  # @param candidate [Chunk] The ranked Note chunk, not a source of excerpt text.
  # @param augmented [Boolean] Include up to two positions on either side.
  # @return [Array(Note, String), nil] The note and fresh text, or nil when unavailable.
  def current_excerpt(chat, candidate, augmented:)
    Chunk.uncached do
      account_id = chat.account_id_in_database
      generation = candidate.metadata.fetch("note_generation")
      note = Note.select(:id, :title).find_by(id: candidate.chunkable_id, account_id:, embedding_generation: generation)
      next unless note

      # Read authorization, active ancestry, and all passages in the same
      # statement. A title edit after the lookup above retires this generation.
      scope = Chunk.current_note_chunks(account_id).where(chunkable_id: note.id)
        .where(current_membership(chat).arel.exists)
        .where("chunks.metadata ->> 'note_generation' = ?", generation.to_s)
      passages = candidate.note_passages(scope, augmented:).pluck(:id, :content)
      [ note, passages.map(&:last).join("\n") ] if passages.any? { |passage_id, _| passage_id == candidate.id }
    end
  end

  private
    def current_membership(chat)
      return AccountUser.none unless chat&.persisted? && %i[web api].include?(kind)

      account_id, user_id = chat.account_id_in_database, chat.user_id_in_database
      saved_chat = Chat.where(id: chat.id_in_database, account_id:, user_id:)
      membership = AccountUser.where(account_id:, user_id:).where(saved_chat.arel.exists)
      if kind == :api
        token = ApiToken.where(id: token_id, account_id:, user_id:)
        membership = membership.where(token.arel.exists)
      end
      membership
    end
end
