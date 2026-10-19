class ChatsController < ApplicationController
  include ChatAccountScoped

  before_action :set_chat, only: [ :show, :destroy, :stop ]

  def show
    @message = @chat.messages.build
  end

  # Signals the streaming worker to abort at the next chunk and unlocks the
  # composer immediately. Chunks received before the flag lands are kept as
  # the partial answer.
  def stop
    @chat.stop_generation!
    redirect_to @chat
  end

  def new
    @chat = Current.user.chats.new(account: selected_chat_account(params[:account_id]))
    @selected_model = params[:model]
  end

  def create
    account = required_chat_account(params.dig(:chat, :account_id))
    return unless prompt.present?

    @chat = Current.user.chats.new(account: account, model: model,
      provider: :openai, assume_model_exists: true)
    sources = @chat.source_attributes(
      website_ids: params.dig(:chat, :attached_website_ids),
      document_ids: params.dig(:chat, :attached_document_ids)
    )
    servers = @chat.selected_mcp_servers(params[:mcp_server_ids])

    Chat.transaction do
      @chat.save!
      servers.each { |server| @chat.add_mcp_server(server) }
      @user_message = @chat.messages.create!(sources.merge(role: "user", content: prompt))
      @user_message.attach_website_sources_from_content!(@chat.account)
      @chat.start_generation!
    end

    ChatResponseJob.perform_later(@chat.id, @user_message.content, @user_message.id)
    redirect_to @chat
  end

  def destroy
    @chat.destroy
    redirect_to root_path
  end

  private

  def set_chat
    @chat = authorized_chat(params[:id])
  end

  def model
    params[:chat][:model].presence || ENV["LLM_MODEL"]
  end

  def prompt
    params[:chat][:prompt]
  end
end
