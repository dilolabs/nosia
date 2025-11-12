# frozen_string_literal: true

class AccountsController < ApplicationController
  before_action :set_account, only: [ :edit, :update ]

  def index
    @accounts = Current.user.accounts.order(:name)
  end

  def new
    @account = Current.user.accounts.new
  end

  def edit
  end

  def create
    @account = Current.user.accounts.create_with_system_prompt!(account_params.merge(owner: Current.user))
    redirect_to accounts_path
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
