# frozen_string_literal: true

module Accounts
  class SystemPromptsController < ApplicationController
    before_action :set_account
    before_action :set_system_prompt, only: :update

    def show
      @system_prompt = default_or_existing_prompt
    end

    def edit
      @system_prompt = default_or_existing_prompt
    end

    def update
      if @system_prompt.update(system_prompt_params)
        redirect_to account_system_prompt_path(@account), notice: t("nosia.prompts.updated")
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def set_account
      @account = Current.user.accounts.find(params[:account_id])
    end

    # Only the update action may write; show and edit render the shipped
    # default for accounts that never customized their prompt.
    def set_system_prompt
      @system_prompt = @account.create_default_system_prompt!(user: nil)
    end

    def default_or_existing_prompt
      @account.prompts.find_by(name: "system_prompt", user: nil) ||
        @account.prompts.new(name: "system_prompt", content: Prompts.system_prompt)
    end

    def system_prompt_params
      params.require(:prompt).permit(:content)
    end
  end
end
