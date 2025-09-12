module Sources
  class WebsitesController < ApplicationController
    before_action :set_website, only: %i[ show edit update destroy ]

    # GET /websites or /websites.json
    def index
      @websites = Website.all.order(:url)
    end

    # GET /websites/1 or /websites/1.json
    def show
    end

    # GET /websites/new
    def new
      @website = Website.new
    end

    # GET /websites/1/edit
    def edit
    end

    # POST /websites or /websites.json
    def create
      @website = Website.new(website_params)

      respond_to do |format|
        if @website.save
          CrawlWebsiteUrlsJob.perform_later(@website.id)
          format.html { redirect_to sources_website_url(@website), notice: "Website was successfully created." }
          format.json { render :show, status: :created, location: @website }
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
          format.html { redirect_to sources_website_url(@website), notice: "Website was successfully updated." }
          format.json { render :show, status: :ok, location: @website }
        else
          format.html { render :edit, status: :unprocessable_entity }
          format.json { render json: @website.errors, status: :unprocessable_entity }
        end
      end
    end

    # DELETE /websites/1 or /websites/1.json
    def destroy
      @website.destroy!

      respond_to do |format|
        format.html { redirect_to sources_websites_url, notice: "Website was successfully destroyed." }
        format.json { head :no_content }
      end
    end

    private
    # Use callbacks to share common setup or constraints between actions.
    def set_website
      @website = Website.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def website_params
      params.require(:website).permit(:account_id, :data, :url)
    end
  end
end
