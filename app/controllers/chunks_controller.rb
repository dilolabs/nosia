class ChunksController < ApplicationController
  include ChatAccountScoped

  def show
    account = params.key?(:chat_id) ? authorized_chat(params[:chat_id]).account : required_chat_account
    @chunk = account.chunks.without_notes.find(params[:id])
  end
end
