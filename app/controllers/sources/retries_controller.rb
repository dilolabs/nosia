# Restarts ingestion for a source in the authorized route account.
class Sources::RetriesController < ApplicationController
  include SourceScoped

  # Enqueues the source-specific job and redirects to the account's source list.
  # @return [void]
  # @raise [ActiveRecord::RecordNotFound] If account membership or source lookup fails
  def create
    source = retry_source
    source.mark_pending!
    retry_job.perform_later(source.id)
    redirect_to source_index_path(type: source.source_type_key),
      notice: t("nosia.sources.#{source.model_name.collection}.retrying")
  end
end
