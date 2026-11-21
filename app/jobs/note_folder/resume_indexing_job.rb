# Resumes indexing in a restored Notes branch without delaying the restore.
class NoteFolder::ResumeIndexingJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  # @param folder_id [Integer] The restored folder ID.
  # @return [void]
  def perform(folder_id)
    NoteFolder.find(folder_id).resume_indexing_now
  end
end
