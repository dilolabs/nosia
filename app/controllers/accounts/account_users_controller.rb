# frozen_string_literal: true

module Accounts
  class AccountUsersController < ApplicationController
    include AccountScoped

    before_action :set_account
    before_action :require_account_owner
    before_action :set_user, only: :create
    before_action :set_account_user, only: :destroy

    def index
      @account_users = @account.account_users.includes(:user)
      @account_user = @account.account_users.new
    end

    def create
      @account_user = @account.account_users.new(user: @user)

      if @account_user.save
        redirect_to account_account_users_path(@account), notice: t("nosia.accounts.user_added")
      else
        redirect_to account_account_users_path(@account), alert: t("nosia.accounts.user_add_failed")
      end
    end

    def destroy
      if @account_user.user_id == @account.owner_id
        redirect_to account_account_users_path(@account), alert: t("nosia.accounts.owner_cannot_remove")
      else
        @account_user.destroy!

        redirect_to account_account_users_path(@account), notice: t("nosia.accounts.user_removed")
      end
    end

    private
      def set_account
        @account = member_account(request.path_parameters.fetch(:account_id))
      end

      def set_user
        @user = User.find_by(email: params[:account_user][:email])
        redirect_to account_account_users_path(@account), alert: t("nosia.accounts.user_not_found") unless @user
      end

      def set_account_user
        @account_user = @account.account_users.find(params[:id])
      end
  end
end
