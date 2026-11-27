# Indexes one saved note generation with bounded retries for recoverable failures.
class Note::IndexJob < ApplicationJob
  queue_as :default

  retry_on Note::Indexable::EmbeddingError, Note::Indexable::PublicationError, wait: 5.seconds, attempts: 3 do |job|
    note_id, generation = job.arguments
    Note.find_by(id: note_id)&.mark_index_failed(generation)
  end
  discard_on ActiveRecord::RecordNotFound, Note::Unavailable

  # @param note_id [Integer] The saved note ID.
  # @param generation [Integer] The saved text generation to publish.
  # @return [Note, nil] The note or nil when indexing was skipped.
  def perform(note_id, generation)
    Note.find(note_id).index_now(generation)
  end
end
