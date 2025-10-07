class ChunksController < ApplicationController
  def show
    @chunk = Current.account.chunks.find(params[:id])
  end
end
