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
    connection = Faraday.new(url: ENV["DOCLING_SERVE_BASE_URL"]) do |faraday|
      faraday.options.timeout = 600
      faraday.options.open_timeout = 10
    end

    base64_string = Base64.strict_encode64(self.file.download)
    filename = self.file.filename.to_s

    request_body = {
      file_sources: [
        {
          base64_string:,
          filename:
        }
      ]
    }

    response = connection.post do |request|
      request.url "/v1alpha/convert/file"
      request.headers["Content-Type"] = "application/json"
      request.headers["Accept"] = "application/json"
      request.body = request_body.to_json
    end

    return unless response.success?
    parsed_response = JSON.parse(response.body)
    self.content = parsed_response.dig("document", "md_content")
    self.save!
  end
end
