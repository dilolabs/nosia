# frozen_string_literal: true

module Accounts
  class SettingsController < ApplicationController
    def show
      @account = Current.user.accounts.find(params[:account_id])
    end
  end
end
