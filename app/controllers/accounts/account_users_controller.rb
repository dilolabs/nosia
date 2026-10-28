# frozen_string_literal: true

module Accounts
  class AccountUsersController < ApplicationController
    include AccountScoped

    before_action :set_account
    before_action :require_account_owner
    before_action :set_account_user, only: :destroy

    def index
      @account_users = @account.account_users.includes(:user)
      @member_email = ""
    end

    def create
      @member_email = member_params.fetch(:email)
      user = User.find_by(email: @member_email)
      @account_user = @account.account_users.new(user: user)

      if user.nil?
        @member_error = t("nosia.settings_tools.member_unknown")
      elsif @account_user.save
        redirect_to account_account_users_path(@account), notice: t("nosia.accounts.user_added")
      else
        @member_error = t(@account_user.errors.of_kind?(:user, :taken) ? "nosia.settings_tools.member_duplicate" : "nosia.settings_tools.member_failed")
      end

      if @member_error
        @account_users = @account.account_users.includes(:user)
        render :index, status: :unprocessable_entity
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

      def member_params
        input = params[:account_user]
        raise ActionController::ParameterMissing, :account_user unless input.is_a?(ActionController::Parameters)

        permitted = input.permit(:email)
        raise ActionController::ParameterMissing, :email unless permitted[:email].is_a?(String)

        permitted
      end

      def set_account_user
        @account_user = @account.account_users.find(params[:id])
      end
  end
end
