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

    # Attacher les serveurs MCP sélectionnés au chat
    if params[:mcp_server_ids].present?
      mcp_server_ids = params[:mcp_server_ids].reject(&:blank?)
      mcp_server_ids.each do |server_id|
        mcp_server = Current.account.mcp_servers.find_by(id: server_id)
        @chat.add_mcp_server(mcp_server) if mcp_server
      end
    end

    # Créer immédiatement le message utilisateur pour affichage instantané
    @user_message = @chat.messages.create!(role: "user", content: prompt)

    # Lancer le job en arrière-plan avec l'ID du message créé
    ChatResponseJob.perform_later(@chat.id, prompt, @user_message.id)

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
