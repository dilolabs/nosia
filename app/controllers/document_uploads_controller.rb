class DocumentUploadsController < ApplicationController
  include ActiveStorage::SetCurrent
  include ChatAccountScoped
  include DocumentFileStreaming

  def create
    account = required_chat_account(params[:account_id])
    attributes = params.expect(blob: [ :filename, :byte_size, :checksum, :content_type ]).to_h.symbolize_keys
    size = Integer(attributes[:byte_size].to_s, exception: false)
    return head :unprocessable_entity unless size&.between?(1, Document::Upload::MAX_BYTES)
    return head :unprocessable_entity unless attributes[:filename].is_a?(String) && attributes[:filename].present? &&
      attributes[:checksum].is_a?(String) && attributes[:checksum].present?

    blob = Document::Upload.create(account:, user: Current.user, attributes: attributes.merge(byte_size: size))
    response.headers["Cache-Control"] = "no-store"
    render json: blob.as_json(only: %i[ filename byte_size content_type ], methods: :attachable_sgid).merge(
      signed_id: blob.signed_id(expires_in: Document::Upload::EXPIRES_IN),
      direct_upload: { url: blob.service_url_for_direct_upload, headers: blob.service_headers_for_direct_upload }
    )
  end

  def show
    blob = ActiveStorage::Blob.find_signed!(params[:signed_id])
    return head :not_found unless Document::Upload.account_for(blob, user: Current.user)

    stream_private_file(blob)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    head :not_found
  end
end
