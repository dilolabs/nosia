require "test_helper"
require "timeout"
require_relative "../support/mcp_oauth_fixtures"

class McpAuthorizationConcurrencyTest < ActiveSupport::TestCase
  include McpOauthFixtures

  self.use_transactional_tests = false

  teardown do
    if @oauth_fixtures
      @oauth_fixtures.to_a.reverse_each do |table, fixtures|
        ids = fixtures.values.map { |fixture| fixture["id"] }
        if table == "mcp_servers" && defined?(McpAuthorization)
          McpAuthorization.where(mcp_server_id: ids).find_each(&:retire!)
        end
        table.classify.constantize.unscoped.where(id: ids).delete_all
      end
      key = Digest::SHA256.hexdigest("client:#{NativeMcpOAuthWire::ORIGIN} #{NativeMcpOAuthWire::REDIRECT_URI}")
      native_credentials.where(owner: nil, key: "nosia-mcp-registration:#{key}").delete_all
    end
  end

  { refresh: %i[owner endpoint membership], callback: %i[owner mode membership] }.each do |operation, mutations|
    mutations.each do |mutation|
      test "an in-flight #{operation} cannot restore credentials after #{mutation} invalidation commits" do
        assert_respond_to @server, :begin_oauth_grant_for!
        grant = begin_grant
        @wire.expires_in = 0 if operation == :refresh
        @wire.install(self) do
          _, query = @wire.start(grant)
          grant.client.authorize(@wire.callback(query)) if operation == :refresh
          client = grant.client
          at_exchange, release_exchange, mutating = Array.new(3) { Queue.new }
          @wire.before_reply = ->(path, _) do
            if path == "/token"
              at_exchange << true
              wait_for(release_exchange)
            end
          end
          @wire.expires_in = 3600

          concurrent do |workers|
            exchange = workers.call do
              if operation == :refresh
                client.tools
              else
                client.authorize(@wire.callback(query))
              end
            rescue McpAuthorization::Unavailable
              # Refresh won the token exchange but lost admission to the MCP retry.
              raise unless operation == :refresh
            end
            wait_for(at_exchange)
            invalidation = workers.call do
              Account.find(@team.id).with_lock do
                mutating << true
                case mutation
                when :owner then McpAuthorization.find(grant.id).retire!
                when :endpoint then McpServer.find(@server.id).update!(url: "https://mcp.example.test/changed")
                when :mode then McpServer.find(@server.id).update!(auth_mode: "static")
                when :membership then AccountUser.find(@member.id).destroy!
                end
              end
            end
            wait_for(mutating)
            release_exchange << true
            join(invalidation)
            join(exchange)
          end

          refute native_credentials.exists?(owner: grant)
          before = @wire.methods_requested.dup
          assert_raises(McpAuthorization::Unavailable) { client.tools }
          assert_raises(McpAuthorization::Unavailable) { client.authorize(@wire.callback(query)) }
          assert_equal before, @wire.methods_requested
        end
      end
    end
  end

  test "a newer pending consent supersedes an older state before its callback can exchange" do
    assert_respond_to @server, :begin_oauth_grant_for!
    grant = begin_grant
    @wire.install(self) do
      _, old = @wire.start(grant)
      concurrent do |workers|
        _, newer = join(workers.call { @wire.start(grant.reload) })
        refute_equal old.fetch("state"), newer.fetch("state")
        assert_raises(McpServer::Client::Error) { grant.client.authorize(@wire.callback(old)) }
        assert_empty @wire.token_requests
        grant.client.authorize(@wire.callback(newer))
      end
      assert grant.reload.authorized?
    end
  end

  test "a callback committed during discovery prevents a late consent from writing pending state" do
    assert_respond_to @server, :begin_oauth_grant_for!
    grant = begin_grant
    @wire.install(self) do
      _, old = @wire.start(grant)
      at_metadata, release_metadata = Array.new(2) { Queue.new }
      @wire.before_reply = ->(path, _) do
        if path == NativeMcpOAuthWire::METADATA_PATH
          at_metadata << true
          wait_for(release_metadata)
        end
      end

      concurrent do |workers|
        start = workers.call do
          assert_raises(McpAuthorization::Unavailable) { @wire.start(McpAuthorization.find(grant.id)) }
        end
        wait_for(at_metadata)
        grant.client.authorize(@wire.callback(old))
        release_metadata << true
        join(start)
      end

      assert grant.authorized?
      refute credential(grant).data.key?("pending")
    end
  end

  test "an admitted tool call does not hold locks and its retry cannot follow a committed removal" do
    assert_respond_to @server, :begin_oauth_grant_for!
    grant = begin_grant
    @wire.legacy = true
    @wire.fail_reinitialize = true
    @wire.install(self) do
      @wire.authorize(grant)
      client = grant.client
      client.tools
      at_tool, release_tool = Array.new(2) { Queue.new }
      @wire.before_reply = ->(method, _) do
        if method == "tools/call"
          at_tool << true
          wait_for(release_tool)
        end
      end

      concurrent do |workers|
        call = workers.call do
          error = assert_raises(McpAuthorization::Unavailable) { client.call("lookup", {}) }
          assert_nil error.cause
        end
        wait_for(at_tool)
        @member.destroy!
        release_tool << true
        join(call)
      end

      assert_equal [ "tools/list", "tools/call" ], @wire.methods_requested.last(2)
      refute native_credentials.exists?(owner: grant)
    end
  end

  test "a stale static client cannot retry with its old headers after the OAuth mode switch commits" do
    @server.update!(token: "fixture-static-token")
    wire = NativeMcpWire.new
    wire.legacy = wire.fail_reinitialize = true
    at_tool, release_tool = Array.new(2) { Queue.new }
    original = wire.method(:reply)
    wire.define_singleton_method(:reply) do |env|
      if env.request_headers["Mcp-Method"] == "tools/call"
        at_tool << true
        Timeout.timeout(5) { release_tool.pop }
      end
      original.call(env)
    end

    wire.install(self) do
      client = @server.client
      client.tools
      concurrent do |workers|
        call = workers.call { assert_raises(McpServer::Client::Error) { client.call("lookup", {}) } }
        wait_for(at_tool)
        @server.update!(auth_mode: "oauth")
        release_tool << true
        join(call)
      end
      client.close
    end
    assert_equal [ "server/discover", "initialize", "notifications/initialized", "tools/list", "tools/call" ], wire.methods_requested
  end

  test "an earlier failure cannot mark a credential rotated after refresh unwinds" do
    assert_respond_to @server, :begin_oauth_grant_for!
    grant = begin_grant
    @wire.expires_in = 0
    @wire.install(self) do
      @wire.authorize(grant)
      client = grant.client
      at_marker, release_marker = Array.new(2) { Queue.new }
      original = grant.method(:mark_reconnect_required)
      grant.define_singleton_method(:mark_reconnect_required) do |*args|
        at_marker << true
        Timeout.timeout(5) { release_marker.pop }
        original.call(*args)
      end
      @wire.refresh_response = ->(_) { [ 401, { "Content-Type" => "application/json" }, '{"error":"invalid_grant"}' ] }

      concurrent do |workers|
        failure = workers.call do
          error = assert_raises(McpServer::Client::Error) { client.tools }
          assert_instance_of McpAuthorization::Unavailable, error
        end
        wait_for(at_marker)
        @wire.refresh_response = nil
        @wire.expires_in = 3600
        assert_equal "found", McpAuthorization.find(grant.id).client.tools.first.call
        release_marker << true
        join(failure)
      end

      assert_nil grant.reload.reconnect_required_at
      assert_equal "fixture-access-2", credential(grant).data.fetch("access_token")
    end
  end

  test "a stale membership mutation cannot transfer a grant to a replacement user" do
    stale_member = AccountUser.find(@member.id)
    other = oauth_fixture("accounts", :oauth_other)
    other_server = oauth_fixture("mcp_servers", :oauth_other)
    @team.account_users.find_by!(user: @bob).destroy!
    other.account_users.find_by!(user: @alice).destroy!
    @member.update!(account: other)
    other_server.update!(auth_mode: "oauth")
    grant = other_server.begin_oauth_grant_for!(@alice)
    @wire.install(self) do
      @wire.authorize(grant)
      assert_raises(ActiveRecord::RecordNotFound) { stale_member.update!(user: @bob) }
      assert grant.authorized?
      assert_nil other_server.oauth_grant_for(@bob)
    end
  end

  test "lookup overlapping reassignment never returns the replacement member's grant" do
    original = begin_grant
    @team.account_users.find_by!(user: @bob).destroy!
    at_lookup, release_lookup = Array.new(2) { Queue.new }

    @wire.install(self) do
      @wire.authorize(original)
      concurrent do |workers|
        lookup = workers.call do
          paused = false
          subscriber = ->(event) do
            if !paused && Thread.current[:looking_up_mcp_grant] && event.payload[:sql].match?(/\ASELECT .*"account_users"/)
              paused = true
              at_lookup << true
              wait_for(release_lookup)
            end
          end
          Thread.current[:looking_up_mcp_grant] = true
          ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { @server.oauth_grant_for(@alice) }
        end
        wait_for(at_lookup)
        @member.update!(user: @bob)
        replacement = @server.begin_oauth_grant_for!(@bob)
        @wire.authorize(replacement)
        release_lookup << true

        found = join(lookup)
        refute_equal replacement.id, found&.id
        before = @wire.requests.dup
        assert_raises(McpAuthorization::Unavailable) { (found || original).client.tools }
        assert_equal before, @wire.requests
        assert_equal replacement, @server.oauth_grant_for(@bob)
      end
    end
  end

  test "creating a grant rechecks the connector after taking the account lock" do
    @server.update!(auth_mode: "oauth")
    grant = McpAuthorization.new(account: @team, account_user: @member, mcp_server: @server, endpoint: @server.endpoint)
    validated, release_create = Array.new(2) { Queue.new }
    original = grant.method(:matching_connector_and_membership)
    grant.define_singleton_method(:matching_connector_and_membership) do
      result = original.call
      unless @test_checked
        @test_checked = true
        validated << true
        Timeout.timeout(5) { release_create.pop }
      end
      result
    end

    concurrent do |workers|
      creation = workers.call { grant.save }
      wait_for(validated)
      @server.update!(auth_mode: "static")
      release_create << true
      refute join(creation)
    end
    assert_empty McpAuthorization.where(account_id: @team.id)
  end

  private
    def begin_grant
      @server.update!(auth_mode: "oauth")
      @server.begin_oauth_grant_for!(@alice)
    end

    def concurrent
      threads = []
      parent_pid = ActiveRecord::Base.connection.select_value("SELECT pg_backend_pid()")
      yield ->(&work) do
        Thread.new do
          ActiveRecord::Base.with_connection do |db|
            assert_not_equal parent_pid, db.select_value("SELECT pg_backend_pid()")
            work.call
          end
        end.tap { |thread| threads << thread }
      end
    ensure
      threads.each do |thread|
        if thread.alive?
          thread.kill
          thread.join(5)
        end
      end
    end

    def wait_for(queue)
      Timeout.timeout(5) { queue.pop }
    end

    def join(thread)
      Timeout.timeout(5) { thread.value }
    end
end
