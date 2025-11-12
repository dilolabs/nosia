# frozen_string_literal: true

module Accounts
  class SystemPromptsController < ApplicationController
    before_action :set_account
    before_action :set_system_prompt

    def show
    end

    def edit
    end

    def update
      if @system_prompt.update(system_prompt_params)
        redirect_to account_system_prompt_path(@account), notice: "System prompt was successfully updated."
      else
        render :show
      end
    end

    private

    def set_account
      @account = Current.user.accounts.find(params[:account_id])
    end

    def set_system_prompt
      @system_prompt = @account.prompts.find_by!(name: "system_prompt", user_id: nil)
    end

    def system_prompt_params
      params.require(:prompt).permit(:account_id, :content)
    end
  end
end
