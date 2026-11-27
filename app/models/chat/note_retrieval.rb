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

  # Combines authorization and Note visibility in the relation that will be ranked.
  # @param chat [Chat] The saved conversation.
  # @param scope [ActiveRecord::Relation<Chunk>] The caller's search scope.
  # @return [ActiveRecord::Relation<Chunk>] Sources and currently authorized Notes.
  def searchable_chunks(chat, scope:)
    scope.without_notes.or(current_chunks(chat, scope:)).where(account_id: chat.account_id_in_database)
  end

  # Loads all centers, titles, and related passages in one database snapshot.
  # @param chat [Chat] The saved conversation.
  # @param candidates [Array<Chunk>] Ranked Note rows used only to identify the evidence.
  # @param augmented [Boolean] Include up to two positions on either side.
  # @return [Hash{Integer => Array(String, String)}] Current title and excerpt by center ID.
  def current_excerpts(chat, candidates, augmented:)
    return {} if candidates.empty?

    expected = candidates.index_by(&:id)
    rows = Chunk.uncached { excerpt_rows(chat, candidates, augmented:) }
    rows.group_by(&:first).filter_map do |id, passages|
      _, note_id, generation, title = passages.first
      [ id, [ Note.display_title_for(title), passages.map(&:last).join("\n") ] ] if same_generation?(expected.fetch(id), note_id, generation)
    end.to_h
  end

  # Drops excerpts invalidated while the batch was being assembled.
  # @param chat [Chat] The saved conversation.
  # @param candidates [Array<Chunk>] Centers that supplied excerpts.
  # @return [Array<Integer>] Centers still eligible in a single fresh snapshot.
  def current_candidate_ids(chat, candidates)
    return [] if candidates.empty?

    expected = candidates.index_by(&:id)
    Chunk.uncached do
      current_chunks(chat).where(id: expected.keys)
        .pluck(:id, :chunkable_id, Arel.sql("chunks.metadata ->> 'note_generation'")).filter_map do |id, note_id, generation|
          id if same_generation?(expected.fetch(id), note_id, generation)
        end
    end
  end

  private
    def excerpt_rows(chat, candidates, augmented:)
      ids = candidates.map(&:id)
      eligible = current_chunks(chat).select(:id, :account_id, :chunkable_id, :metadata, :content)
      eligible = augmented ? eligible.where(chunkable_id: candidates.map(&:chunkable_id).uniq) : eligible.where(id: ids)

      # Use the same eligible relation for each center and its neighbors, so the
      # range is based on the saved center and never crosses a Note generation.
      excerpts = Chunk.with(eligible_note_passages: eligible).from("eligible_note_passages AS chunks")
        .joins("INNER JOIN eligible_note_passages AS centers ON centers.chunkable_id = chunks.chunkable_id")
        .joins("INNER JOIN notes ON notes.id = chunks.chunkable_id AND notes.account_id = chunks.account_id")
        .where(centers: { id: ids })
      excerpts = if augmented
        excerpts.where("abs((chunks.metadata ->> 'position')::numeric - (centers.metadata ->> 'position')::numeric) <= 2")
      else
        excerpts.where("centers.id = chunks.id")
      end

      excerpts.order(Arel.sql("chunks.metadata -> 'position', chunks.id"))
        .pluck(Arel.sql("centers.id"), Arel.sql("centers.chunkable_id"),
          Arel.sql("centers.metadata ->> 'note_generation'"), Note.arel_table[:title], Chunk.arel_table[:content])
    end

    def same_generation?(candidate, note_id, generation)
      candidate.chunkable_id == note_id && candidate.metadata["note_generation"].to_s == generation
    end

    def current_chunks(chat, scope: Chunk.all)
      scope.current_note_chunks(chat.account_id_in_database).where(current_membership(chat).arel.exists)
    end

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
