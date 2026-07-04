require "test_helper"
require "faraday/adapter/test"

class Kdrive::ApiClientTest < ActiveSupport::TestCase
  def stubs; @stubs ||= Faraday::Adapter::Test::Stubs.new; end

  def connection
    Faraday.new(url: Kdrive::ApiClient::BASE_URL) do |f|
      f.request :url_encoded
      f.adapter :test, stubs
    end
  end

  def client(auth = { token: "t", drive_id: "12" }, connection: self.connection)
    Kdrive::ApiClient.new(auth, connection: connection)
  end

  test "search sends the Bearer token and unwraps the data envelope" do
    stubs.get("/3/drive/12/files/search") do |env|
      assert_equal "Bearer t", env.request_headers["Authorization"]
      assert_equal "report", env.params["query"]
      [ 200, {}, '{"result":"success","data":[{"id":"f1","name":"report.pdf"}]}' ]
    end
    data = client.search("report", limit: 20)
    assert_equal [ { "id" => "f1", "name" => "report.pdf" } ], data
    stubs.verify_stubbed_calls
  end

  test "ping lists the root folder (id 1) and returns true on success" do
    stubs.get("/3/drive/12/files/1/files") { |env| [ 200, {}, '{"result":"success","data":[]}' ] }
    assert client.ping
  end

  test "file raises on 404 (wrong drive_id or file id)" do
    stubs.get("/2/drive/12/files/999") { |env| [ 404, {}, '{"result":"error","error":"not found"}' ] }
    err = assert_raises(RuntimeError) { client.file("999") }
    assert_match(/404/, err.message)
  end

  test "raises on a non-success envelope result" do
    stubs.get("/3/drive/12/files/search") { |env| [ 200, {}, '{"result":"error","error":"boom"}' ] }
    assert_raises(RuntimeError) { client.search("x") }
  end
end
