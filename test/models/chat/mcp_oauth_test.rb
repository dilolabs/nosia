require "test_helper"
require_relative "../../support/mcp_oauth_fixtures"

class ChatMcpOAuthTest < ActiveSupport::TestCase
  include McpOauthFixtures

  setup do
    @server.update!(auth_mode: "oauth", status: "error")
    @chat = @alice.chats.new(account: @team)
  end

  test "a ready connector and another member's consent cannot substitute for the chat owner's grant" do
    @server.update!(status: "ready")
    @wire.install(self) do
      @wire.authorize(@server.begin_oauth_grant_for!(@bob))
      @wire.requests.clear
      @wire.oauth_requests.clear
      Current.set(session: Session.new(user: @bob)) do
        assert_raises(ActiveRecord::RecordNotFound) { @chat.selected_mcp_servers([ @server.id ]) }
      end
      assert_empty @wire.requests
      assert_empty @wire.oauth_requests
    end
  end

  test "the owner can select an authorized connector without a shared successful test or network request" do
    @wire.install(self) do
      grant = @server.begin_oauth_grant_for!(@alice)
      @wire.authorize(grant)
      @wire.requests.clear
      @wire.oauth_requests.clear

      assert_equal [ @server ], @chat.selected_mcp_servers([ @server.id ])
      assert_empty @wire.requests
      assert_empty @wire.oauth_requests

      grant.update!(reconnect_required_at: Time.current)
      assert_raises(ActiveRecord::RecordNotFound) { @chat.selected_mcp_servers([ @server.id ]) }
      assert_empty @wire.requests
      assert_empty @wire.oauth_requests
    end
  end

  test "a disabled chat connector keeps the current workspace member's own authorized access" do
    @wire.install(self) do
      @wire.authorize(@server.begin_oauth_grant_for!(@alice))
      bob_grant = @server.begin_oauth_grant_for!(@bob)
      @wire.authorize(bob_grant)
      bob_bearer = "Bearer #{credential(bob_grant).data.fetch('access_token')}"
      @server.update!(enabled: false)
      @wire.requests.clear

      assert_raises(ActiveRecord::RecordNotFound) { @chat.selected_mcp_servers([ @server.id ]) }
      assert_empty @wire.requests

      Current.set(session: Session.new(user: @bob)) do
        assert_equal({ success: true, result: "found" }, @server.execute_tool("lookup", { "query" => "fixture" }, user: Current.user))
      end
      assert @wire.requests.all? { |entry| entry[:headers]["Authorization"] == bob_bearer }, "workspace sent a different owner's bearer"
    end
  end

  test "static HTTP tools already loaded for chat recheck readiness while workspace clients remain independent" do
    static = oauth_fixture("mcp_servers", :oauth_team_duplicate)
    static.update!(status: "ready")
    chat = @alice.chats.create!(account: @team, model: ENV.fetch("LLM_MODEL"), provider: :openai, assume_model_exists: true)
    chat.add_mcp_server(static)
    chat.with_model(chat.model_id, provider: :openai, assume_model_exists: true)

    wire = NativeMcpWire.new
    wire.install(self) do
      chat.with_mcp_tools do
        tool = chat.to_llm.tools.values.sole
        static.update!(enabled: false)
        assert_equal({ error: I18n.t("nosia.mcp_workspace.remote_failure") }, tool.call(query: "fixture"))
        refute_includes wire.methods_requested, "tools/call"
        assert_equal({ success: true, result: "found" }, static.execute_tool("lookup", { "query" => "fixture" }))
      end
    end
  end

  test "static selections retain the untested submission contract, but not disabled and legacy SSE connectors" do
    static = oauth_fixture("mcp_servers", :oauth_team_duplicate)
    refute_includes @chat.mcp_selection.fetch(:servers), static
    assert_equal [ static ], @chat.selected_mcp_servers([ static.id ])

    static.update!(enabled: false)
    assert_raises(ActiveRecord::RecordNotFound) { @chat.selected_mcp_servers([ static.id ]) }

    static.update_columns(enabled: true, transport_type: "sse", status: "ready")
    assert_raises(ActiveRecord::RecordNotFound) { @chat.selected_mcp_servers([ static.id ]) }
  end

  test "stopping a streamed turn clears tools and closes an authorized legacy-protocol session" do
    @wire.legacy = true
    chat = @alice.chats.create!(account: @team, model: ENV.fetch("LLM_MODEL"), provider: :openai, assume_model_exists: true)
    chat.add_mcp_server(@server)
    bound = []
    chat.define_singleton_method(:with_tools) { |*tools| bound.replace(tools.compact) }
    chat.define_singleton_method(:generation_stopped?) { true }
    stub_chat_for_streaming(chat, chunks: [ StreamChunk.new("stopped") ], stub_mcp: false)

    @wire.install(self) do
      @wire.authorize(@server.begin_oauth_grant_for!(@alice))
      assert_nil chat.complete_with_nosia("question")
      assert_empty bound
      assert_equal [ "tools/list", :delete ], @wire.methods_requested.last(2)
    end
  end
end
