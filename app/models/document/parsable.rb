module Document::Parsable
  extend ActiveSupport::Concern

  def parse
    content_type = self.file.blob.content_type

    if content_type.start_with?("text/")
      parse_text
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
end
