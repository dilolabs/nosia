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
    elsif attachable_sgid.present?
      document = Document.create_from_attachable_sgid!(Current.account, attachable_sgid)
      render json: {
        id: document.id,
        filename: document.file.filename.to_s,
        index_status: document.index_status
      }
    else
      render json: { error: "url or attachable_sgid is required" }, status: :bad_request
    end
  end

  private

  def url_param
    params[:url]
  end

  def attachable_sgid
    params[:attachable_sgid]
  end
end
