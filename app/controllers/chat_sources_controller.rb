class ChatSourcesController < ApplicationController
  def create
    if url_param.present?
      website = Website.find_or_create_by_url!(Current.account, url_param)
      render json: {
        id: website.id,
        title: website.title,
        url: website.url,
        index_status: website.index_status
      }
    elsif blob_signed_id.present?
      document = Document.create_from_blob!(Current.account, blob_signed_id)
      render json: {
        id: document.id,
        filename: document.file.filename.to_s,
        index_status: document.index_status
      }
    else
      render json: { error: "url or blob_signed_id is required" }, status: :bad_request
    end
  end

  private

  def url_param
    params[:url]
  end

  def blob_signed_id
    params[:blob_signed_id]
  end
end
