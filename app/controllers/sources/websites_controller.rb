module Sources
  class WebsitesController < ApplicationController
    include SourceScoped

    before_action :verify_scoped_source_account, only: %i[ create update ]
    before_action :set_website, only: %i[ show edit update destroy ]
    before_action :require_scoped_source_html, only: %i[ create update ]

    # GET /websites or /websites.json
    def index
      redirect_to source_index_path(type: "website")
    end

    # GET /websites/1 or /websites/1.json
    def show
    end

    # GET /websites/new
    def new
      @website = source_account.websites.new
    end

    # GET /websites/1/edit
    def edit
    end

    # POST /websites or /websites.json
    def create
      @website = source_filing_account(:website).websites.new(website_params)

      respond_to do |format|
        if @website.save
          CrawlWebsiteUrlJob.perform_later(@website.id)
          format.html { redirect_to source_response_path(@website), notice: t("nosia.sources.websites.created") }
          format.json { render :show, status: :created, location: source_response_path(@website) }
        else
          format.html { render :new, status: :unprocessable_entity }
          format.json { render json: @website.errors, status: :unprocessable_entity }
        end
      end
    end

    # PATCH/PUT /websites/1 or /websites/1.json
    def update
      respond_to do |format|
        if @website.update(website_params)
          CrawlWebsiteUrlJob.perform_later(@website.id)
          format.html { redirect_to source_response_path(@website), notice: t("nosia.sources.websites.updated") }
          format.json { render :show, status: :ok, location: @website }
        else
          format.html { render :edit, status: :unprocessable_entity }
          format.json { render json: @website.errors, status: :unprocessable_entity }
        end
      end
    end

    # POST /websites/1/retry
    def retry
      website = source_account.websites.find(params[:id])
      website.mark_pending!
      CrawlWebsiteUrlJob.perform_later(website.id)
      redirect_to source_index_path(type: "website"), notice: t("nosia.sources.websites.retrying")
    end

    # DELETE /websites/1 or /websites/1.json
    def destroy
      @website.destroy!

      respond_to do |format|
        format.html { redirect_to source_index_path(type: "website"), notice: t("nosia.sources.websites.destroyed") }
        format.json { head :no_content }
      end
    end

    private
    # Use callbacks to share common setup or constraints between actions.
    def set_website
      @website = source_account.websites.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def website_params
      params.require(:website).permit(:data, :url)
    end
  end
end
