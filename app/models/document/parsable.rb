module Document::Parsable
  extend ActiveSupport::Concern

  def parse
    content_type = self.file.blob.content_type

    if content_type.start_with?("text/")
      parse_text
    elsif ENV["DOCLING_SERVE_BASE_URL"].present?
      parse_with_docling
    elsif content_type.eql?("application/pdf")
      parse_pdf
    end
  end

  def parse!
    parse
    save!
  end

  def parse_pdf
    self.file.blob.open do |io|
      reader = ::PDF::Reader.new(io)
      self.content = reader.pages.map(&:text).join("\n\n")
    end
  end

  def parse_text
    self.file.blob.open do |io|
      self.content = io.read
    end
  end

  def parse_with_docling
    return unless ENV["DOCLING_SERVE_BASE_URL"].present?

    connection = Faraday.new(url: ENV["DOCLING_SERVE_BASE_URL"])

    request_body = {
      options: {
        to_formats: [ "md" ],
        image_export_mode: "placeholder",
        table_mode: "accurate",
        do_picture_description: true
      },
      sources: [
        {
          kind: "file",
          base64_string: Base64.strict_encode64(self.file.download),
          filename: self.file.filename.to_s
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
    self.content = json.dig("document", "md_content")
    self.save!
  end
end
