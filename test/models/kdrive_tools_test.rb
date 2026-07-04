require "test_helper"
require "faraday/adapter/test"

class KdriveToolsTest < ActiveSupport::TestCase
  def stubs; @stubs ||= Faraday::Adapter::Test::Stubs.new; end

  def connection
    Faraday.new(url: Kdrive::ApiClient::BASE_URL) do |f|
      f.request :url_encoded
      f.adapter :test, stubs
    end
  end

  def auth; { token: "t", drive_id: "12" }; end

  setup do
    Kdrive.default_connection = connection
  end

  teardown do
    Kdrive.default_connection = nil
  end

  test "search_files returns a Response with structured results" do
    stubs.get("/3/drive/12/files/search") do |env|
      [ 200, {}, '{"result":"success","data":[{"id":"f1","name":"report.pdf"}]}' ]
    end
    response = KdriveTools::SearchFilesTool.call(query: "report", server_context: auth)
    assert_kind_of MCP::Tool::Response, response
    assert_match(/Found/, response.content.first[:text])
    assert_equal [ { "id" => "f1", "name" => "report.pdf" } ], response.structured_content
  end

  test "list_folder returns a Response" do
    stubs.get("/3/drive/12/files/1/files") do |env|
      [ 200, {}, '{"result":"success","data":[{"id":"f1","name":"doc.txt"}]}' ]
    end
    response = KdriveTools::ListFolderTool.call(server_context: auth)
    assert_kind_of MCP::Tool::Response, response
  end

  test "get_file inlines a text-able file's bounded content" do
    stubs.get("/2/drive/12/files/77") do |env|
      [ 200, {}, '{"result":"success","data":{"id":"77","name":"note.txt","size":42,"content_type":"text/plain"}}' ]
    end
    stubs.get("/2/drive/12/files/77/download") do |env|
      [ 200, { "Content-Type" => "text/plain" }, "hello world" ]
    end
    response = KdriveTools::GetFileTool.call(file_id: "77", server_context: auth)
    assert_kind_of MCP::Tool::Response, response
    assert_match(/hello world/, response.content.first[:text])
  end

  test "get_file returns metadata-only for a binary file" do
    stubs.get("/2/drive/12/files/88") do |env|
      [ 200, {}, '{"result":"success","data":{"id":"88","name":"img.png","size":99999,"content_type":"image/png"}}' ]
    end
    response = KdriveTools::GetFileTool.call(file_id: "88", server_context: auth)
    assert_match(/binary|too large|metadata/i, response.content.first[:text])
  end
end
