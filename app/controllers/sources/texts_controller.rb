module Sources
  class TextsController < ApplicationController
    include SourceScoped

    before_action :verify_scoped_source_account, only: %i[ create update ]
    before_action :set_text, only: %i[ show edit update destroy ]
    before_action :require_scoped_source_html, only: %i[ create update ]

    # GET /texts or /texts.json
    def index
      redirect_to source_index_path(type: "text")
    end

    # GET /texts/1 or /texts/1.json
    def show
    end

    # GET /texts/new
    def new
      @text = source_account.texts.new
    end

    # GET /texts/1/edit
    def edit
    end

    # POST /texts or /texts.json
    def create
      @text = source_filing_account(:text).texts.new(text_params)

      respond_to do |format|
        if @text.save
          AddTextJob.perform_later(@text.id)
          format.html { redirect_to source_response_path(@text), notice: t("nosia.sources.texts.created") }
          format.json { render :show, status: :created, location: source_response_path(@text) }
        else
          format.html { render :new, status: :unprocessable_entity }
          format.json { render json: @text.errors, status: :unprocessable_entity }
        end
      end
    end

    # PATCH/PUT /texts/1 or /texts/1.json
    def update
      respond_to do |format|
        if @text.update(text_params)
          AddTextJob.perform_later(@text.id)
          format.html { redirect_to source_response_path(@text), notice: t("nosia.sources.texts.updated") }
          format.json { render :show, status: :ok, location: @text }
        else
          format.html { render :edit, status: :unprocessable_entity }
          format.json { render json: @text.errors, status: :unprocessable_entity }
        end
      end
    end

    # POST /texts/1/retry
    def retry
      text = source_account.texts.find(params[:id])
      text.mark_pending!
      AddTextJob.perform_later(text.id)
      redirect_to source_index_path(type: "text"), notice: t("nosia.sources.texts.retrying")
    end

    # DELETE /texts/1 or /texts/1.json
    def destroy
      @text.destroy!

      respond_to do |format|
        format.html { redirect_to source_index_path(type: "text"), notice: t("nosia.sources.texts.destroyed") }
        format.json { head :no_content }
      end
    end

    private
    # Use callbacks to share common setup or constraints between actions.
    def set_text
      @text = source_account.texts.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def text_params
      params.require(:text).permit(:data)
    end
  end
end
