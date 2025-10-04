module Website::Crawlable
  extend ActiveSupport::Concern

  def crawl_url!
    return unless ENV["DOCLING_SERVE_BASE_URL"].present?

    connection = Faraday.new(url: ENV["DOCLING_SERVE_BASE_URL"])

    request_body = {
      options: {
        from_formats: [ "html" ],
        to_formats: [ "md" ],
        image_export_mode: "placeholder",
        table_mode: "accurate",
        do_picture_description: true
      },
      sources: [
        {
          kind: "http",
          url: self.url
        }
      ]
    }.to_json

    response = connection.post do |request|
      request.url "/v1/convert/source/async"
      request.headers["Accept"] = "application/json"
      request.headers["Content-Type"] = "application/json"
      request.headers["User-Agent"] = "Nosiabot/0.1"
      request.body = request_body
    end

    return unless response.success?

    json = JSON.parse(response.body)
    task_id = json.dig("task_id")
    task_status = json.dig("task_status")

    while !task_status.in?(%w[success failure])
      response = connection.get do |request|
        request.url "/v1/status/poll/#{task_id}"
        request.headers["Accept"] = "application/json"
        request.headers["User-Agent"] = "Nosiabot/0.1"
      end

      json = JSON.parse(response.body)
      task_status = json.dig("task_status")

      sleep 1
    end

    response = connection.get do |request|
      request.url "/v1/result/#{task_id}"
      request.headers["Accept"] = "application/json"
      request.headers["User-Agent"] = "Nosiabot/0.1"
    end

    return unless response.success?

    json = JSON.parse(response.body)
    self.data = json.dig("document", "md_content")
    self.save!
    self.chunkify!
    self
  end
end
