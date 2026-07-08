class ChatsController < ApplicationController
  before_action :set_chat, only: [ :show, :destroy ]

  def show
    @message = @chat.messages.build
  end

  def new
    @chat = Current.user.chats.new
    @selected_model = params[:model]
  end

  def create
    return unless prompt.present?

    @chat = Current.user.chats.create!(account: Current.account, model: model, provider: :openai, assume_model_exists: true)

    # Attach selected MCP servers to the chat
    if params[:mcp_server_ids].present?
      mcp_server_ids = params[:mcp_server_ids].reject(&:blank?)
      mcp_server_ids.each do |server_id|
        mcp_server = Current.account.mcp_servers.find_by(id: server_id)
        @chat.add_mcp_server(mcp_server) if mcp_server
      end
    end

    # Create the user message immediately for instant display, stamping any
    # sources attached in the composer so the indexing gate can wait on them.
    @user_message = @chat.messages.create!(
      role: "user",
      content: prompt,
      attached_website_ids: Array(params[:chat][:attached_website_ids]).compact_blank,
      attached_document_ids: Array(params[:chat][:attached_document_ids]).compact_blank
    )

    # Launch the background job with the persisted markdown content (the
    # before_save from Task 6 has converted the composer HTML to markdown) and
    # the ID of the created message.
    ChatResponseJob.perform_later(@chat.id, @user_message.content, @user_message.id)

    redirect_to @chat
  end

  def destroy
    @chat.destroy
    redirect_to root_path
  end

  private

  def set_chat
    @chat = Current.user.chats.find(params[:id])
  end

  def model
    params[:chat][:model].presence || ENV["LLM_MODEL"]
  end

  def prompt
    params[:chat][:prompt]
  end
end
