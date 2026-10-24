# frozen_string_literal: true

module Accounts
  class SystemPromptsController < ApplicationController
    include AccountScoped

    before_action :set_account
    before_action :require_account_owner, only: [ :edit, :update ]

    def show
      @system_prompt = default_or_existing_prompt
    end

    def edit
      @system_prompt = default_or_existing_prompt
    end

    def update
      @system_prompt = default_or_existing_prompt
      if @system_prompt.update(system_prompt_params)
        redirect_to account_system_prompt_path(@account), notice: t("nosia.prompts.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private
      def set_account
        @account = member_account(request.path_parameters.fetch(:account_id))
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
