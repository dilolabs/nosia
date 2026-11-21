class ChunksController < ApplicationController
  include ChatAccountScoped

  def show
    chat = authorized_chat(params[:chat_id]) if params.key?(:chat_id)
    account = chat ? chat.account : required_chat_account
    include_notes = if chat
      Chat::NoteRetrieval.web.allowed?(chat)
    else
      AccountUser.uncached { AccountUser.exists?(account_id: account.id, user_id: Current.user.id) }
    end
    @chunk = Chunk.uncached do
      account.chunks.with_visible_notes(account_id: account.id, include_notes:).preload(:chunkable).find(params[:id])
    end

    if @chunk.note_chunk?
      raise ActiveRecord::RecordNotFound unless @chunk.chunkable

      redirect_to account_note_path(account, @chunk.chunkable)
    end
  end
end
