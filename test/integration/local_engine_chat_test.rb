# test/integration/local_engine_chat_test.rb
require "test_helper"
require "faraday/adapter/test"

class LocalEngineChatTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "int@example.com", password: "testpassword123")
    @account = Account.create!(name: "Int Account", owner: @user)
    ActsAsTenant.current_tenant = @account

    stubs = Faraday::Adapter::Test::Stubs.new
    stubs.get("/works") { |env| [ 200, {}, '{"results":[{"id":"W1","title":"Relativity"}]}' ] }
    @connection = Faraday.new(url: "https://api.openalex.org") do |f|
      f.request :url_encoded
      f.adapter :test, stubs
    end
    OpenAlex.default_connection = @connection
  end

  def teardown
    ActsAsTenant.current_tenant = nil
    OpenAlex.default_connection = nil
  end

  test "a ready local OpenAlex server contributes an adapted tool to the chat" do
    server = @account.mcp_servers.create!(
      name: "OpenAlex", transport_type: "local", status: "ready",
      metadata: { engine: "open_alex" }, auth_config: { api_key: "sekret" }
    )
    chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai,
                                  assume_model_exists: true)
    chat.add_mcp_server(server)

    chat.with_mcp_tools do
      adapted = chat.to_llm.tools.fetch(:openalex_search_works)
      assert_match(/Relativity/, adapted.call(query: "einstein"))
    end
    assert_empty chat.to_llm.tools
  end
end
