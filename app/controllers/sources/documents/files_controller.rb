class Sources::Documents::FilesController < ApplicationController
  include AccountScoped
  include DocumentFileStreaming

  def show
    account = member_account(request.path_parameters.fetch(:account_id))
    document = account.documents.with_attached_file.find(params[:document_id])
    raise ActiveRecord::RecordNotFound unless document.file.attached?

    stream_private_file(document.file.blob)
  end
end
