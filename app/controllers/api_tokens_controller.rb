# frozen_string_literal: true

class ApiTokensController < ApplicationController
  include AccountScoped

  before_action :set_token_account

  def index
    @api_tokens = token_scope.includes(:account)
    @api_token = Current.user.api_tokens.new(account: @account)
  end

  def create
    params.require(:api_token)
    account = token_filing_account(params.dig(:api_token, :account_id))
    attributes = api_token_params
    @api_token = Current.user.api_tokens.new(account: account, name: attributes[:name])

    if @api_token.save
      # The plaintext token is shown exactly once, via the flash on the next
      # page load; only its digest is stored.
      redirect_to token_index_path, flash: { created_api_token: @api_token.plain_token }
    elsif @account
      @api_tokens = token_scope.includes(:account)
      render :index, status: :unprocessable_entity
    else
      redirect_to api_tokens_path, alert: t("nosia.tokens.error")
    end
  end

  def destroy
    token_scope.find(params[:id]).destroy
    redirect_to token_index_path
  end

  private
    def set_token_account
      @account = member_account(request.path_parameters.fetch(:account_id)) if request.path_parameters.key?(:account_id)
    end

    def token_scope
      @account ? Current.user.api_tokens.where(account: @account) : Current.user.api_tokens
    end

    def token_filing_account(id)
      if @account
        unless id.nil?
          valid_scalar = id.is_a?(String) || id.is_a?(Numeric)
          raise ActiveRecord::RecordNotFound unless valid_scalar && id.to_s == @account.id.to_s
        end
        @account
      else
        member_account(id)
      end
    end

    def token_index_path
      @account ? account_api_tokens_path(@account) : api_tokens_path
    end

    def api_token_params
      params.require(:api_token).permit(:account_id, :name)
    end
end
