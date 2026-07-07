require "test_helper"

class Document::ParsableTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "dp@example.com", password: "testpassword123")
    @account = Account.create!(name: "DP Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @document = @account.documents.new
  end

  test "parse reads text file content into content" do
    @document.file.attach(io: StringIO.new("hello world"), filename: "note.txt", content_type: "text/plain")
    @document.save!

    @document.parse

    assert_equal "hello world", @document.content
  end

  test "parse routes pdfs to pdf-reader extraction even when DOCLING_SERVE_BASE_URL is set" do
    @document.file.attach(io: StringIO.new("%PDF-1.4"), filename: "doc.pdf", content_type: "application/pdf")
    used_pdf_reader = false
    @document.define_singleton_method(:parse_pdf) do
      used_pdf_reader = true
      self.content = "extracted"
      nil
    end

    with_env("DOCLING_SERVE_BASE_URL" => "http://localhost:5001") do
      @document.parse
    end

    assert used_pdf_reader
    assert_equal "extracted", @document.content
  end

  test "parsable concern no longer references Docling" do
    source = File.read(Rails.root.join("app/models/document/parsable.rb"))

    refute_includes source, "DOCLING"
    refute_includes source, "docling"
    refute Document::Parsable.instance_methods.include?(:parse_with_docling)
  end

  private

  def with_env(vars)
    previous = {}
    vars.each { |key, value| previous[key] = ENV[key]; ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end
end
