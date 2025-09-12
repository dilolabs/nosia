# frozen_string_literal: true

class AccountsController < ApplicationController
  before_action :set_account, only: [ :edit, :update ]

  def index
    @accounts = Current.user.accounts
  end

  def edit
  end

  def update
    if @account.update(account_params)
      redirect_to accounts_path, notice: "Account was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def account_params
    params.require(:account).permit(:name, :uid)
  end

  def set_account
    @account = Current.user.accounts.find(params[:id])
  end
end
