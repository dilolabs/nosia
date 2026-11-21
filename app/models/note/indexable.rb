# Prepares embeddings for the current text and publishes them as one generation.
module Note::Indexable
  extend ActiveSupport::Concern

  # A provider error or unusable response, with no remote text in the message.
  class EmbeddingError < StandardError; end

  included do
    enum :embedding_status, { empty: "empty", pending: "pending", ready: "ready", failed: "failed" },
      prefix: :embedding
  end

  class_methods do
    # Invalidates every nonempty note, including hidden notes, during the native
    # embedding-space reset. Call in the same transaction, before locking chunks.
    # @return [void]
    def invalidate_embedding_space
      in_batches do |batch|
        ids = batch.pluck(:id, :title, :body_text).filter_map do |id, title, body_text|
          id if Note::Indexable.embedding_input(title, body_text).present?
        end
        where(id: ids).update_all("embedding_generation = embedding_generation + 1, indexed_generation = NULL, embedding_status = 'pending'") if ids.any?
      end
    end

    # Rebuilds active Note generations synchronously for offline native maintenance.
    # @return [void]
    # @raise [EmbeddingError] If any active generation remains incomplete.
    def rebuild_active_embeddings
      Account.find_each do |account|
        active = active_in(account.id)
        active.embedding_failed.update_all(embedding_status: "pending")
        active.embedding_pending.find_each { |note| note.index_now(note.embedding_generation) }
        if active.where(embedding_status: %w[pending failed]).exists?
          raise EmbeddingError, "Incomplete note embedding reconstruction"
        end
      end
    end
  end

  # @api private
  def self.embedding_input(title, body_text)
    [ title.strip, body_text.strip ].select { |text| text.match?(/[^\p{Space}\p{Cc}\p{Cf}]/u) }.join("\n\n")
  end

  # Prepares vectors without locks, then replaces the published index if still current.
  # @param generation [Integer] The scheduled embedding generation.
  # @return [Note, nil] The note, or nil when it is already ineligible at the start.
  # @raise [EmbeddingError] If the provider cannot supply usable vectors.
  # @raise [Note::Unavailable] If the note is removed during preparation.
  def index_now(generation)
    return unless persisted? && id == id_in_database

    snapshot = self.class.uncached do
      self.class.active_in(account_id_in_database).find_by(id:, embedding_status: "pending", embedding_generation: generation)
    end
    return unless snapshot

    prepared = prepare_embeddings(snapshot.embedding_input)
    with_locked_note(lock_record: true) do |locked_account|
      if indexable_generation?(generation)
        # SQL bind logging would include the text being written to chunks.
        self.class.logger.silence do
          publish_embeddings(locked_account, generation, prepared)
        end
      end
    end
  end

  # Marks a current, active pending generation as failed after the final attempt.
  # @param generation [Integer] The exhausted generation.
  # @return [Note, nil] The note, or nil if it no longer exists.
  def mark_index_failed(generation)
    with_locked_note(lock_record: true) do
      update!(embedding_status: :failed) if indexable_generation?(generation)
    end
  rescue Note::Unavailable
    nil
  end

  # Schedules another attempt for a failed active note without changing its generation.
  # @return [Note, nil] The note, or nil if it no longer exists.
  def retry_index
    resume_indexing_in("failed")
  end

  # Resumes pending or failed indexing after an ancestor folder has been restored.
  # @return [Note, nil] The note, or nil if it no longer exists.
  def resume_indexing
    resume_indexing_in("pending", "failed")
  end

  protected
    def embedding_input
      Note::Indexable.embedding_input(title, body_text)
    end

  private
    def assign_embedding_generation(previous_input)
      input = embedding_input
      return false if input == previous_input

      self.embedding_generation += 1
      self.embedding_status = input.empty? ? :empty : :pending
      self.indexed_generation = nil if embedding_empty?
      true
    end

    def apply_embedding_change
      if embedding_empty?
        chunks.destroy_all
      else
        index_later(embedding_generation)
      end
    end

    def index_later(generation)
      note_id = id
      ActiveRecord.after_all_transactions_commit do
        Note::IndexJob.set(wait: 30.seconds).perform_later(note_id, generation)
      end
    end

    def prepare_embeddings(input)
      splitter = Baran::RecursiveCharacterTextSplitter.new(
        chunk_size: ENV.fetch("CHUNK_SIZE", "512").to_i,
        chunk_overlap: ENV.fetch("CHUNK_OVERLAP", "128").to_i
      )
      parts = splitter.chunks(input)
      raise EmbeddingError, "Note has no embeddable chunks" if parts.empty?

      parts.map do |part|
        text = part.fetch(:text)
        result = embed_part(text)
        unless result.respond_to?(:vectors) && result.respond_to?(:tokens) && usable_vector?(result.vectors)
          raise EmbeddingError, "Embedding provider returned an unusable result"
        end
        [ text, result ]
      end
    end

    def embed_part(text)
      Chunk.embed_text(text, private_input: true)
    rescue RubyLLM::Error, Faraday::ParsingError
      raise EmbeddingError, "Embedding provider request failed", cause: nil
    rescue NoMethodError, TypeError, ArgumentError => error
      # RubyLLM 2.2 can raise these when parsing or instrumenting a malformed result.
      raise unless error.backtrace_locations.first&.absolute_path&.start_with?("#{Gem.loaded_specs.fetch("ruby_llm").full_gem_path}/")

      raise EmbeddingError, "Embedding provider returned a malformed response", cause: nil
    end

    def usable_vector?(vector)
      return false unless vector.is_a?(Array) && vector.size == Chunk.embedding_dimensions
      return false unless vector.all? { |value| value.is_a?(Float) || value.is_a?(Integer) }

      # pgvector stores single-precision values. Reject overflow and vectors that
      # become zero when cast, since zero vectors have no cosine similarity.
      stored = vector.pack("f*").unpack("f*")
      stored.all?(&:finite?) && stored.any?(&:nonzero?)
    end

    def indexable_generation?(generation)
      embedding_pending? && embedding_generation == generation && active_for_indexing?
    end

    def active_for_indexing?
      self.class.active_in(account_id).exists?(id:)
    end

    def publish_embeddings(owner, generation, prepared)
      chunks.destroy_all
      prepared.each.with_index(1) do |(text, result), position|
        chunks.create!(account: owner, content: text, prepared_embedding_result: result,
          metadata: { "position" => position, "note_generation" => generation })
      end
      update!(indexed_generation: generation, embedding_status: :ready)
    end

    def resume_indexing_in(*statuses)
      with_locked_note do
        resume_pending_index if statuses.include?(embedding_status) && active_for_indexing?
      end
    rescue Note::Unavailable
      nil
    end

    def resume_pending_index
      update!(embedding_status: :pending) if embedding_failed?
      index_later(embedding_generation) if embedding_pending?
    end
end
