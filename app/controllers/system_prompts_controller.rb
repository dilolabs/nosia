# frozen_string_literal: true

class SystemPromptsController < ApplicationController
  before_action :set_system_prompt, only: %i[show edit update destroy]

  def index
    @system_prompts = Current.user.prompts
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
    @system_prompt = Current.user.prompts.find(params[:id])
  end

  def system_prompt_params
    params.require(:prompt).permit(:account_id, :content)
  end
end
