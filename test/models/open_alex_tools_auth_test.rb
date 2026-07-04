require "test_helper"
require "faraday/adapter/test"

class OpenAlexToolsAuthTest < ActiveSupport::TestCase
  test "search_works threads server_context[:api_key] into the ApiClient" do
    received_key = nil
    stubs = Faraday::Adapter::Test::Stubs.new
    stubs.get("/works") do |env|
      received_key = env.params["api_key"]
      [ 200, {}, '{"results":[]}' ]
    end
    connection = Faraday.new(url: "https://api.openalex.org") do |f|
      f.request :url_encoded
      f.adapter :test, stubs
    end

    previous = OpenAlex.default_connection
    OpenAlex.default_connection = connection
    begin
      response = OpenAlexTools::SearchWorksTool.call(query: "einstein", server_context: { api_key: "sekret" })
      assert_equal "sekret", received_key
      assert_kind_of MCP::Tool::Response, response
    ensure
      OpenAlex.default_connection = previous
    end
  end
end
