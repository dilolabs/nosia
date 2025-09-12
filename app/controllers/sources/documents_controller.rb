module Sources
  class DocumentsController < ApplicationController
    before_action :set_document, only: %i[ show edit update destroy ]

    # GET /documents or /documents.json
    def index
      @documents = Document.all
    end

    # GET /documents/1 or /documents/1.json
    def show
    end

    # GET /documents/new
    def new
      @document = Document.new
    end

    # GET /documents/1/edit
    def edit
    end

    # POST /documents or /documents.json
    def create
      @document = Document.new(document_params)

      respond_to do |format|
        if @document.save
          AddDocumentJob.perform_later(@document.id)
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

    # DELETE /documents/1 or /documents/1.json
    def destroy
      @document.destroy!

      respond_to do |format|
        format.html { redirect_to sources_documents_url, notice: "Document was successfully destroyed." }
        format.json { head :no_content }
      end
    end

    private
    # Use callbacks to share common setup or constraints between actions.
    def set_document
      @document = Document.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def document_params
      permitted = params.require(:document).permit(:account_id, :title, :file)
      permitted = permitted.merge(account: Current.account) unless permitted.has_key?(:account_id)
      permitted
    end
  end
end
