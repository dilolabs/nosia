require "test_helper"
require "faraday/adapter/test"

class OpenAlex::ApiClientTest < ActiveSupport::TestCase
  def stubs
    @stubs ||= Faraday::Adapter::Test::Stubs.new
  end

  def client(auth = {}, connection: nil)
    OpenAlex::ApiClient.new(auth, connection: connection)
  end

  def connection_with_stubs
    Faraday.new(url: "https://api.openalex.org") do |f|
      f.request :url_encoded
      f.adapter :test, stubs
    end
  end

  test "#get injects api_key from auth into query params" do
    stubs.get("/works") { |env| [ 200, {}, '{"results":[]}' ] }
    response = client({ api_key: "sekret" }, connection: connection_with_stubs).get("/works")
    assert_equal({ "results" => [] }, response)
    stubs.verify_stubbed_calls
  end

  test "#ping returns true on a successful one-row request" do
    stubs.get("/works") { |env| [ 200, {}, '{"results":[{"id":"W1"}]}' ] }
    assert client({}, connection: connection_with_stubs).ping
  end

  test "#get raises on 401" do
    stubs.get("/works") { |env| [ 401, {}, '{"error":"unauthorized"}' ] }
    assert_raises(RuntimeError) do
      client({}, connection: connection_with_stubs).get("/works")
    end
  end

  test "#get retries 429 then succeeds" do
    stubs.get("/works") { |env| [ 429, {}, "" ] }
    stubs.get("/works") { |env| [ 200, {}, '{"results":[]}' ] }
    response = client({}, connection: connection_with_stubs).get("/works")
    assert_equal({ "results" => [] }, response)
  end
end
