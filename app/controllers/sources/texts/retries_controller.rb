# Selects the account-local text and its ingestion job for a retry.
class Sources::Texts::RetriesController < Sources::RetriesController
  private
    def retry_source
      source_account.texts.find(params[:text_id])
    end

    def retry_job
      AddTextJob
    end
end
