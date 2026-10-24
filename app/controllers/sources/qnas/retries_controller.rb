# Selects the account-local Q&A and its ingestion job for a retry.
class Sources::Qnas::RetriesController < Sources::RetriesController
  private
    def retry_source
      source_account.qnas.find(params[:qna_id])
    end

    def retry_job
      AddQnaJob
    end
end
