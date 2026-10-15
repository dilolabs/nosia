class MessagesController < ApplicationController
  include ChatAccountScoped

  before_action :set_chat

  def create
    return unless content.present?

    # Create the user message immediately for instant display, stamping any
    # sources attached in the composer so the indexing gate can wait on them.
    sources = @chat.source_attributes(
      website_ids: params.dig(:message, :attached_website_ids),
      document_ids: params.dig(:message, :attached_document_ids)
    )
    @user_message = @chat.messages.create!(sources.merge(role: "user", content: content))

    # Lexxy emits lexxy:insert-link only on paste, so a typed URL never reaches
    # /chat_sources. Extract http(s) URLs from the saved content and attach them
    # as Website sources before completion runs — the indexing gate waits on them.
    @user_message.attach_website_sources_from_content!(@chat.account)

    # Lock the composer for the duration of this generation. The create turbo_stream
    # response renders the form busy from this flag; the job's ensure clears it.
    @chat.start_generation!

    ChatResponseJob.perform_later(@chat.id, @user_message.content, @user_message.id)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @chat }
    end
  end

  private
    def set_chat
      @chat = authorized_chat(params[:chat_id])
    end

    def content
      params[:message][:content]
    end
end
