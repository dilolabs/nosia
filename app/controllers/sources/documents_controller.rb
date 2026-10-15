module Sources
  class DocumentsController < ApplicationController
    include ChatAccountScoped

    before_action :set_document, only: %i[ show edit update destroy ]

    # GET /documents or /documents.json
    def index
      redirect_to sources_path(type: "document")
    end

    # GET /documents/1 or /documents/1.json
    def show
    end

    # GET /documents/new
    def new
      @document = Current.account.documents.new
    end

    # GET /documents/1/edit
    def edit
    end

    # POST /documents or /documents.json
    def create
      validate_chat_context_id(params.dig(:document, :account_id))
      account = filing_account(:document) || raise(ChatAccountScoped::MissingAccount)
      upload_id = params.require(:document).permit(:upload_id)[:upload_id]
      @document = Document.create_from_upload(account, document_params, upload_id: upload_id)

      respond_to do |format|
        if @document.persisted?
          format.html { redirect_to sources_document_url(@document), notice: "Document was successfully created." }
          format.json { render :show, status: :created, location: sources_document_url(@document) }
        else
          format.html { render :new, status: :unprocessable_entity }
          format.json { render json: @document.errors, status: :unprocessable_entity }
        end
      end
    end

    # PATCH/PUT /documents/1 or /documents/1.json
    def update
      respond_to do |format|
        if @document.update(document_params)
          AddDocumentJob.perform_later(@document.id)
          format.html { redirect_to sources_document_url(@document), notice: "Document was successfully updated." }
          format.json { render :show, status: :ok, location: sources_document_url(@document) }
        else
          format.html { render :edit, status: :unprocessable_entity }
          format.json { render json: @document.errors, status: :unprocessable_entity }
        end
      end
    end

    # POST /documents/1/retry
    def retry
      document = Current.account.documents.find(params[:id])
      document.mark_pending!
      AddDocumentJob.perform_later(document.id)
      redirect_to sources_path(type: "document"), notice: "Re-indexing document."
    end

    # DELETE /documents/1 or /documents/1.json
    def destroy
      @document.destroy!

      respond_to do |format|
        format.html { redirect_to sources_url, notice: "Document was successfully destroyed." }
        format.json { head :no_content }
      end
    end

    private
    # Use callbacks to share common setup or constraints between actions.
    def set_document
      @document = Current.account.documents.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def document_params
      params.require(:document).permit(:title, :file)
    end
  end
end
