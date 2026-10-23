# Selects the account-local document and its ingestion job for a retry.
class Sources::Documents::RetriesController < Sources::RetriesController
  private
    def retry_source
      source_account.documents.find(params[:document_id])
    end

    def retry_job
      AddDocumentJob
    end
end
