class MessagesController < ApplicationController
  before_action :set_chat

  def create
    return unless content.present?

    # Create the user message immediately for instant display, stamping any
    # sources attached in the composer so the indexing gate can wait on them.
    @user_message = @chat.messages.create!(
      role: "user",
      content: content,
      attached_website_ids: Array(params[:message][:attached_website_ids]).compact_blank,
      attached_document_ids: Array(params[:message][:attached_document_ids]).compact_blank
    )

    # Lexxy emits lexxy:insert-link only on paste, so a typed URL never reaches
    # /chat_sources. Extract http(s) URLs from the saved content and attach them
    # as Website sources before completion runs — the indexing gate waits on them.
    @user_message.attach_website_sources_from_content!(Current.account)

    # Queue the job with the persisted markdown content (Task 6 converted the
    # composer HTML to markdown on save) and the created message's ID.
    ChatResponseJob.perform_later(@chat.id, @user_message.content, @user_message.id)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @chat }
    end
  end

  private

  def set_chat
    @chat = Current.user.chats.find(params[:chat_id])
  end

  def content
    params[:message][:content]
  end
end
