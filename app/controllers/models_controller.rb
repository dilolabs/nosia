class ModelsController < ApplicationController
  def index
    @models = RubyLLM.models.all
  end

  def show
    unless params[:id] == "model" && params[:model_id].is_a?(String) && params[:model_id].present? &&
        params[:provider].is_a?(String) && params[:provider].present?
      raise ActiveRecord::RecordNotFound
    end

    @model = RubyLLM.models.find(params[:model_id], provider: params[:provider])
  rescue RubyLLM::ModelNotFoundError
    raise ActiveRecord::RecordNotFound
  end

  def refresh
    RubyLLM.models.refresh
    redirect_to models_path, notice: t("nosia.models.refreshed")
  end
end
