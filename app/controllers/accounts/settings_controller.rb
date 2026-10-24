# frozen_string_literal: true

module Accounts
  class SettingsController < ApplicationController
    include AccountScoped

    def show
      account = member_account(request.path_parameters.fetch(:account_id))
      redirect_to account_path(account)
    end
  end
end
