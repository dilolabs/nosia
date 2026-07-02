# frozen_string_literal: true

class SystemPromptsController < ApplicationController
  before_action :set_system_prompt, only: %i[show edit update destroy]

  def index
    Current.user.accounts.each { |account| account.create_default_system_prompt!(user: nil) }
    @system_prompts = Prompt.where(account: Current.user.accounts, name: "system_prompt").order(:account_id)
  end

  def show
  end

  def edit
  end

  def update
    if @system_prompt.update(system_prompt_params)
      redirect_to system_prompt_path(@system_prompt), notice: "System prompt was successfully updated."
    else
      render :show
    end
  end

  def destroy
    @system_prompt.destroy
    redirect_to system_prompts_path, notice: "System prompt was successfully deleted."
  end

  private

  def set_system_prompt
    @system_prompt = Prompt.where(account: Current.user.accounts, name: "system_prompt").find(params[:id])
  end

  def system_prompt_params
    params.require(:prompt).permit(:account_id, :content)
  end
end
