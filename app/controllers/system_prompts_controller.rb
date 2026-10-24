# frozen_string_literal: true

class SystemPromptsController < ApplicationController
  include AccountScoped

  before_action :set_system_prompt, only: %i[show edit update destroy]
  before_action :require_shared_prompt_owner, only: [ :edit, :update, :destroy ]

  def index
    @system_prompts = Prompt.where(account: Current.user.accounts, name: "system_prompt").order(:account_id)
  end

  def show
  end

  def edit
  end

  def update
    if @system_prompt.update(system_prompt_params)
      redirect_to system_prompt_path(@system_prompt), notice: t("nosia.prompts.updated")
    else
      render :show, status: :unprocessable_entity
    end
  end

  def destroy
    @system_prompt.destroy
    redirect_to system_prompts_path, notice: t("nosia.prompts.deleted")
  end

  private
    def set_system_prompt
      @system_prompt = Prompt.where(account: Current.user.accounts, name: "system_prompt").find(params[:id])
    end

    def require_shared_prompt_owner
      if @system_prompt.user_id.nil?
        @account = @system_prompt.account
        require_account_owner
      end
    end

    def system_prompt_params
      params.require(:prompt).permit(:content)
    end
end
