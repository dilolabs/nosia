require "test_helper"
require "faraday/adapter/test"
require_relative "../support/mcp_oauth_fixtures"

class ChatMcpOauthTest < ActiveJob::TestCase
  include McpOauthFixtures

  setup do
    @previous_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    @server.update!(auth_mode: "oauth", status: "error", token: "fixture-static-must-not-be-used")
    @chat = @team.chats.create!(user: @alice, model: ENV.fetch("LLM_MODEL"), provider: :openai, assume_model_exists: true)
    @chat.chat_mcp_sessions.create!(mcp_server: @server)
  end

  teardown do
    ActiveJob::Base.queue_adapter = @previous_queue_adapter
  end

  [ false, true ].each do |ambient_session|
    test "a background turn uses only the saved owner's grants #{ambient_session ? 'with a different session' : 'without a session'}" do
      duplicate = oauth_fixture("mcp_servers", :oauth_team_duplicate)
      duplicate.update!(auth_mode: "oauth")
      @chat.chat_mcp_sessions.create!(mcp_server: duplicate)

      @wire.install(self) do
        owner = authorize(@server, @alice)
        authorize(@server, @bob)
        second = authorize(duplicate, @alice)
        foreign = oauth_fixture("mcp_servers", :oauth_other)
        foreign.account.update_column(:created_at, 1.year.ago)
        foreign.account.account_users.grant_to(@bob)
        foreign.update!(auth_mode: "oauth")
        authorize(foreign, @alice)
        token = access_token(owner)
        second_token = access_token(second)
        @wire.requests.clear
        @wire.oauth_requests.clear

        Current.set(session: (Session.new(user: @bob) if ambient_session)) do
          assert_equal foreign.account, Current.account if ambient_session
          ActsAsTenant.with_tenant(foreign.account) do
            with_provider(->(request, index) { tool_turn(request, index, 1, choice: chat_tool_name(@server)) }) do |requests|
              run_turn
              run_turn
              assert_equal 3, requests.size
              assert_equal [ chat_tool_name(@server), chat_tool_name(duplicate) ].sort, tool_names(requests[1]).sort
              assert_equal "found", requests.last.fetch("messages").find { |message| message["role"] == "tool" }.fetch("content")
            end
          end
        end

        assert [ token, second_token ].map { |value| "Bearer #{value}" }.sort == request_bearers.uniq.sort, "unexpected bearer during discovery"
        assert [ "Bearer #{token}" ] == tool_requests.map { |entry| entry[:headers]["Authorization"] }, "unexpected bearer during tool execution"
        catalog_requests = @wire.requests.select { |entry| entry.dig(:rpc, "method") == "tools/list" }
        assert_equal 4, catalog_requests.pluck(:scope).uniq.size, "each connector gets a fresh client per turn"
        assert_same catalog_requests.reverse.find { |entry| entry[:headers]["Authorization"] == "Bearer #{token}" }.fetch(:scope),
          tool_requests.sole.fetch(:scope)
        assert_empty @wire.oauth_requests
        assert_equal "lookup", @wire.last_tool_call.fetch("name")
        assert_equal({ "query" => "fixture" }, @wire.last_tool_call.fetch("arguments"))
        refute @chat.reload.generating?
      end
    end
  end

  [ :disabled, :revoked, :expired, :missing, :membership, :reconnect_required, :peer_unavailable ].each do |state|
    test "#{state} connector is skipped without restarting the job" do
      @wire.install(self) do
        @wire.refresh_token = false if state == :expired
        grant = authorize(@server, @alice) unless state == :missing
        authorize(@server, @bob) if state == :missing
        case state
        when :disabled then @server.update!(enabled: false)
        when :revoked then grant.retire!
        when :expired
          row = credential(grant)
          row.update!(data: row.data.merge("expires_at" => 1.hour.ago.to_i))
        when :membership then @member.destroy!
        when :reconnect_required then grant.update!(reconnect_required_at: Time.current)
        when :peer_unavailable then @wire.unavailable_method = "tools/list"
        end
        wire_sizes = [ @wire.requests.size, @wire.oauth_requests.size ]

        with_provider do |requests|
          assert_no_enqueued_jobs(only: ChatResponseJob) { run_turn }
          assert_empty tool_names(requests.sole)
        end

        assert_equal wire_sizes, [ @wire.requests.size, @wire.oauth_requests.size ] unless state == :peer_unavailable
        assert_empty tool_requests
        assert @chat.chat_mcp_sessions.exists?(mcp_server: @server)
      end
    end
  end

  test "a reconnected grant cannot resurrect an already advertised tool in the same turn" do
    @wire.legacy = true
    @wire.install(self) do
      owner = authorize(@server, @alice)
      @phase = -> do
        owner.retire!
        authorize(@server, @alice)
      end

      assert_turn_continues_after_tool_failure
      assert_empty tool_requests
      refute_includes @wire.methods_requested, :delete
      refute @wire.oauth_requests.any? { |request| request[:verb] == :delete }, "a retired session cannot attempt an unauthenticated close"
    end
  end

  [ :disable, :retire ].each do |action|
    test "#{action} during the first call prevents native token recovery" do
      @wire.install(self) do
        grant = authorize(@server, @alice)
        exchanges = @wire.token_requests.size
        attempted = 0
        @wire.mcp_rejection = ->(rpc, _token) do
          if rpc["method"] == "tools/call"
            attempted += 1
            if action == :disable
              @server.update!(enabled: false)
            else
              grant.retire!
            end
            [ 401, { "WWW-Authenticate" => 'Bearer error="invalid_token"' }, NativeMcpWire::PRIVATE_MARKER ]
          end
        end

        assert_turn_continues_after_tool_failure

        assert_equal 1, attempted
        assert_equal exchanges, @wire.token_requests.size
      end
    end
  end

  private
    def authorize(server, member)
      grant = server.begin_oauth_grant_for!(member)
      @wire.authorize(grant)
      grant
    end

    def access_token(grant)
      credential(grant).data.fetch("access_token")
    end

    def request_bearers
      @wire.requests.map { |entry| entry[:headers]["Authorization"] }
    end

    def tool_requests
      @wire.requests.select { |entry| entry[:rpc]["method"] == "tools/call" }
    end

    def chat_tool_name(server)
      "mcp_#{server.id}_lookup"
    end

    def run_turn
      message = @chat.messages.create!(role: "user", content: "Look this up")
      @chat.start_generation!
      ChatResponseJob.perform_now(@chat.id, message.content, message.id)
      assert_equal "Finished.", @chat.messages.assistant.last.content
    end

    def assert_turn_continues_after_tool_failure
      with_provider(->(request, index) { tool_turn(request, index, 0, choice: chat_tool_name(@server)) }) do |requests|
        assert_no_enqueued_jobs(only: ChatResponseJob) { run_turn }
        assert_equal 2, requests.size
        tool_message = requests.last.fetch("messages").find { |message| message["role"] == "tool" }
        assert_equal({ "error" => I18n.t("nosia.mcp_workspace.remote_failure") }, JSON.parse(tool_message.fetch("content")))
      end
    end

    def tool_names(request)
      Array(request["tools"]).map { |tool| tool.dig("function", "name") }
        .each { |name| assert_match(/\A[a-zA-Z0-9_-]{1,64}\z/, name) }
    end

    def tool_turn(request, index, call_at, choice:)
      return unless index == call_at

      assert_includes tool_names(request), choice
      @phase&.call
      { tool_calls: [ { index: 0, id: "call_fixture", type: "function",
                        function: { name: choice, arguments: '{"query":"fixture"}' } } ] }
    end

    # Only the synthetic LLM and retrieval cross a test seam. ChatResponseJob,
    # RubyLLM's stream/tool loop, persistence and native MCP run unmodified.
    def with_provider(tool_response = nil)
      requests = []
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/v1/chat/completions") do |env|
        request = JSON.parse(env.body)
        delta = tool_response&.call(request, requests.size)
        requests << request
        env.status = 200
        [ [ delta || { content: "Finished." }, nil ], [ {}, delta ? "tool_calls" : "stop" ] ].each do |fields, finish_reason|
          data = "data: #{JSON.generate(model: ENV.fetch("LLM_MODEL"), choices: [ { delta: fields, index: 0, finish_reason: } ])}\n\n"
          env.request.on_data.call(data, data.bytesize, env)
        end
        env.request.on_data.call("data: [DONE]\n\n", 14, env)
        [ 200, { "content-type" => "text/event-stream" }, "" ]
      end
      adapter = Class.new(Faraday::Adapter::Test) do
        define_method(:initialize) { |app, **| super(app, stubs, &nil) }
      end
      original = RubyLLM.config.faraday_adapter
      RubyLLM.config.faraday_adapter = adapter
      dimensions = Chunk.columns_hash.fetch("embedding").limit
      embedding = Struct.new(:vectors, :tokens).new(Array.new(dimensions, 0.01), nil)
      with_singleton_replacement(RubyLLM, :embed, ->(*) { embedding }) { yield requests }
    ensure
      RubyLLM.config.faraday_adapter = original
    end
end
