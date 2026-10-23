module Sources
  class QnasController < ApplicationController
    before_action :set_qna, only: %i[ show edit update destroy ]

    # GET /qnas or /qnas.json
    def index
      redirect_to sources_path(type: "qna")
    end

    # GET /qnas/1 or /qnas/1.json
    def show
    end

    # GET /qnas/new
    def new
      @qna = Current.account.qnas.new
    end

    # GET /qnas/1/edit
    def edit
    end

    # POST /qnas or /qnas.json
    def create
      @qna = filing_account(:qna).qnas.new(qna_params)

      respond_to do |format|
        if @qna.save
          AddQnaJob.perform_later(@qna.id)
          format.html { redirect_to sources_qna_url(@qna), notice: t("nosia.sources.qnas.created") }
          format.json { render :show, status: :created, location: sources_qna_url(@qna) }
        else
          format.html { render :new, status: :unprocessable_entity }
          format.json { render json: @qna.errors, status: :unprocessable_entity }
        end
      end
    end

    # PATCH/PUT /qnas/1 or /qnas/1.json
    def update
      respond_to do |format|
        if @qna.update(qna_params)
          AddQnaJob.perform_later(@qna.id)
          format.html { redirect_to sources_qna_url(@qna), notice: t("nosia.sources.qnas.updated") }
          format.json { render :show, status: :ok, location: sources_qna_url(@qna) }
        else
          format.html { render :edit, status: :unprocessable_entity }
          format.json { render json: @qna.errors, status: :unprocessable_entity }
        end
      end
    end

    # POST /qnas/1/retry
    def retry
      qna = Current.account.qnas.find(params[:id])
      qna.mark_pending!
      AddQnaJob.perform_later(qna.id)
      redirect_to sources_path(type: "qna"), notice: t("nosia.sources.qnas.retrying")
    end

    # DELETE /qnas/1 or /qnas/1.json
    def destroy
      @qna.destroy!

      respond_to do |format|
        format.html { redirect_to sources_qnas_url, notice: t("nosia.sources.qnas.destroyed") }
        format.json { head :no_content }
      end
    end

    private
    # Use callbacks to share common setup or constraints between actions.
    def set_qna
      @qna = Current.account.qnas.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def qna_params
      params.require(:qna).permit(:question, :answer)
    end
  end
end
