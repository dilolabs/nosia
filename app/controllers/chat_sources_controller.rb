class ChatSourcesController < ApplicationController
  include ChatAccountScoped

  rescue_from ActiveRecord::RecordInvalid do |error|
    render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def create
    @source_account = source_account

    if url_param.present?
      website = Website.find_or_create_by_url!(@source_account, url_param)
      render json: {
        id: website.id,
        title: website.title,
        url: website.url,
        index_status: website.index_status
      }
    elsif attachable_sgid.present?
      create_document_from_sgid
    else
      render json: { error: "url or attachable_sgid is required" }, status: :bad_request
    end
  end

  private
    def source_account
      if params[:chat_id].present?
        account = authorized_chat(params[:chat_id]).account
        if params[:account_id].present? && params[:account_id].to_s != account.id.to_s
          raise ActiveRecord::RecordNotFound
        end
        account
      else
        required_chat_account(params[:account_id])
      end
    end

    def url_param
      params[:url]
    end

    def attachable_sgid
      params[:attachable_sgid]
    end

    # A bad/expired attachable sgid resolves to nil and is a client input error
    # (400), not a server bug (500). The model raises RecordNotFound; map it here.
    def create_document_from_sgid
      document = Document.create_from_attachable_sgid!(@source_account, attachable_sgid)
      render json: {
        id: document.id,
        filename: document.file.filename.to_s,
        index_status: document.index_status
      }
    rescue ActiveRecord::RecordNotFound
      render json: { error: "invalid attachable sgid" }, status: :bad_request
    end
end
