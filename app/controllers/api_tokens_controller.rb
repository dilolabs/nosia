# frozen_string_literal: true

class ApiTokensController < ApplicationController
  def index
    @api_tokens = Current.user.api_tokens
  end

  def create
    account = Current.user.accounts.find(api_token_params[:account_id])

    @api_token = Current.user.api_tokens.new(
      account:,
      name: api_token_params[:name]
    )

    if @api_token.save
      redirect_to api_tokens_path
    else
      redirect_to api_tokens_path, alert: "An error occured."
    end
  end

  def destroy
    @api_token = Current.user.api_tokens.find(params[:id])
    @api_token.destroy
    redirect_to api_tokens_path
  end

  private

  def api_token_params
    params.require(:api_token).permit(:account_id, :name)
  end
end
