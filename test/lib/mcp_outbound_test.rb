require "test_helper"
require "faraday"
require "net/http"
require_relative "../support/mcp_outbound_tls"

class McpOutboundTest < ActiveSupport::TestCase
  include McpOutboundTls

  HOST = "mcp.example.test"
  IPV4 = "93.184.216.34"
  IPV6 = "2606:4700::1111"
  URL = "https://#{HOST}:8443/mcp?query=1"

  test "static scope does not capture request data" do
    scope = McpOutbound::Scope.new(https_only: true)
    env = Faraday::Env.from(method: :post, body: "request payload")

    assert_nil scope.admit!(env)
    assert_nil scope.capture(env)
    assert_nil scope.observe(nil, Faraday::Response.new)
  end

  test "returns the parsed URI and a validated address for each public IP family" do
    [ IPV4, IPV6, "::ffff:#{IPV4}" ].zip([ IPV4, IPV6, IPV4 ]).each do |answer, expected|
      with_dns(answer) do |lookups|
        assert_equal [ URI(URL), IPAddr.new(expected) ], McpOutbound.destination!(URL, https_only: true)
        assert_equal [ HOST ], lookups
      end
    end
  end

  test "resolves IPv6 literals without the URI brackets" do
    with_dns(IPV6) do |lookups|
      url = URI("https://[#{IPV6}]:8443/mcp")
      assert_equal [ url, IPAddr.new(IPV6) ], McpOutbound.destination!(url, https_only: true)
      assert_equal [ IPV6 ], lookups
    end
  end

  test "requires an explicit policy to permit HTTP" do
    url = "http://#{HOST}/mcp"

    with_dns(IPV4) do |lookups|
      assert_raises(McpOutbound::Blocked) { McpOutbound.destination!(url, https_only: true) }
      assert_raises(McpOutbound::Blocked) { McpOutbound.destination!(url, https_only: nil) }
      assert_empty lookups
      assert_equal [ URI(url), IPAddr.new(IPV4) ], McpOutbound.destination!(url, https_only: false)
    end
  end

  test "rejects malformed URLs, other schemes, userinfo and fragments before DNS" do
    invalid_urls = [
      nil, "not a URL", "/mcp", "https:/mcp", "ftp://#{HOST}/mcp",
      "https://user:password@#{HOST}/mcp", "https://@#{HOST}/mcp",
      "https://#{HOST}/mcp#fragment", "https://#{HOST}/mcp#",
      "https://#{HOST}:0/mcp", "https://#{HOST}:65536/mcp"
    ]

    with_dns(IPV4) do |lookups|
      invalid_urls.each do |url|
        assert_raises(McpOutbound::Blocked) { McpOutbound.destination!(url, https_only: false) }
      end
      assert_empty lookups
    end
  end

  test "validates raw endpoints before Faraday can rewrite userinfo or discard a fragment" do
    with_dns(IPV4) do |lookups|
      raw_base = "https://demo:password@#{HOST}:8443/mcp"
      raw_request = "#{URL}#fragment"

      normalized = connection(raw_base, proxy: "http://127.0.0.1:1")
      assert_nil normalized.url_prefix.userinfo
      assert_match(/\ABasic /, normalized.headers["Authorization"])
      request = normalized.build_request(:get) { |req| req.url(raw_request) }
      assert_equal URI(URL), normalized.build_url(request.path, request.params)

      with_stub(Faraday, :new, ->(*) { flunk "invalid raw endpoint reached Faraday" }) do
        assert_raises(McpOutbound::Blocked) do
          connection(McpOutbound.endpoint!(raw_base, https_only: true))
        end
      end
      assert_raises(McpOutbound::Blocked) do
        normalized.build_request(:get) { |req| req.url(McpOutbound.endpoint!(raw_request, https_only: true)) }
      end

      endpoint = McpOutbound.endpoint!(URL, https_only: true)
      assert_equal URI(URL), endpoint
      guarded = connection(endpoint, proxy: "http://127.0.0.1:1")
      assert_nil guarded.headers["Authorization"]
      assert_equal URI(URL), guarded.build_url
      assert_empty lookups
    end
  end

  test "blocks nonpublic IPv4 and IPv6 including mapped IPv4" do
    answers = %w[
      0.0.0.0 0.1.2.3 10.0.0.1 100.64.1.1 127.0.0.1 169.254.169.254 172.31.0.1
      192.0.0.8 192.0.2.1 192.88.99.1 192.168.1.1 198.18.0.1 198.51.100.1 203.0.113.1
      224.0.0.1 240.0.0.1 255.255.255.255
      :: ::1 ::127.0.0.1 ::ffff:127.0.0.1 ::ffff:169.254.169.254
      64:ff9b::7f00:1 100::1 2001::1 2001:2::1 2001:db8::1 2002:7f00:1::1
      2620:4f:8000::1 3fff::1 4000::1 fc00::1 fe80::1 fec0::1 ff02::1
    ]

    answers.each do |answer|
      with_dns(answer) do
        assert_raises(McpOutbound::Blocked, answer) { McpOutbound.destination!(URL, https_only: true) }
      end
    end
  end

  test "rejects unresolved hosts and any DNS answer containing a nonpublic address" do
    [ [], [ IPV4, "10.0.0.1" ], [ IPV6, "::ffff:10.0.0.1" ] ].each do |answers|
      with_dns(*answers) do
        assert_raises(McpOutbound::Blocked) { McpOutbound.destination!(URL, https_only: true) }
      end
    end
  end

  test "restores the enclosing fiber scope after a nested exception" do
    outer = McpOutbound::Scope.new(https_only: true)
    inner = McpOutbound::Scope.new(https_only: false)
    other_fiber = Fiber.new { McpOutbound.current! }

    result = McpOutbound.with(outer) do
      assert_predicate McpOutbound.current!, :https_only?
      assert_raises(McpOutbound::Blocked) { other_fiber.resume }
      assert_raises(RuntimeError) do
        McpOutbound.with(inner) do
          assert_same inner, McpOutbound.current!
          refute_predicate McpOutbound.current!, :https_only?
          raise "request failed"
        end
      end
      assert_same outer, McpOutbound.current!
      :result
    end

    assert_equal :result, result
    assert_raises(McpOutbound::Blocked) { McpOutbound.current! }
  end

  test "child fibers need their own explicit scope both during and after the parent's scope" do
    parent_scope = McpOutbound::Scope.new(https_only: true)
    child_scope = McpOutbound::Scope.new(https_only: false)
    probe = -> do
      McpOutbound.current!
    rescue McpOutbound::Blocked
      :blocked
    end

    child = McpOutbound.with(parent_scope) do
      fiber = Fiber.new do
        Fiber.yield probe.call
        McpOutbound.with(child_scope) { Fiber.yield McpOutbound.current! }
        probe.call
      end
      assert_equal :blocked, fiber.resume
      assert_same child_scope, fiber.resume
      assert_same parent_scope, McpOutbound.current!
      assert_equal :blocked, Thread.new { probe.call }.value
      fiber
    end

    assert_equal :blocked, child.resume
    assert_equal :blocked, probe.call
  end

  test "fails closed without a scope or with unsafe DNS before constructing a connection" do
    with_stub(Net::HTTP, :new, ->(*) { flunk "unsafe destination reached the HTTP constructor" }) do
      client = connection(URL)
      with_dns(IPV4, "10.0.0.1") do |lookups|
        assert_raises(McpOutbound::Blocked) { client.get }
        assert_empty lookups
        assert_raises(McpOutbound::Blocked) { within_scope { client.get } }
        assert_equal [ HOST ], lookups
      end
    end
  end

  test "does not construct a connection when the scope denies admission" do
    scope = McpOutbound::Scope.new(https_only: true)
    scope.define_singleton_method(:admit!) { |_| raise McpOutbound::Blocked, "admission denied" }

    with_dns(IPV4) do |lookups|
      with_stub(Net::HTTP, :new, ->(*) { flunk "denied request reached the HTTP constructor" }) do
        error = assert_raises(McpOutbound::Blocked) { McpOutbound.with(scope) { connection(URL).get } }
        assert_equal "admission denied", error.message
        assert_equal [ HOST ], lookups
      end
    end
  end

  test "pins one resolution per request without replacing the TLS hostname or enabling retries or proxying" do
    addresses = [ IPV4, IPV6 ].map { IPAddr.new(it) }
    events = []
    resolver = ->(host) { events << [ :dns, host ]; [ addresses.shift || flunk("extra DNS lookup") ] }
    scope = McpOutbound::Scope.new(https_only: true)
    scope.define_singleton_method(:admit!) { |env| events << [ :admit, env.url.hostname ] }
    original = Net::HTTP.method(:new)
    sockets = []
    constructor = ->(*args) do
      events << [ :new, *args ]
      original.call(*args).tap do |http|
        sockets << http
        http.define_singleton_method(:start) { raise Errno::ECONNREFUSED }
      end
    end
    client = connection(URL, proxy: "http://127.0.0.1:1")

    with_stub(UrlGuard, :resolve, resolver) do
      with_stub(Net::HTTP, :new, constructor) do
        McpOutbound.with(scope) do
          2.times { assert_raises(Faraday::ConnectionFailed) { client.get } }
        end
      end
    end

    assert_equal [ [ :dns, HOST ], [ :admit, HOST ], [ :new, HOST, 8443, nil ] ] * 2, events
    assert_equal [ IPV4, IPV6 ], sockets.map(&:ipaddr)
    sockets.each do |http|
      assert http.use_ssl?
      assert_equal OpenSSL::SSL::VERIFY_PEER, http.verify_mode
      assert_equal 0, http.max_retries
      refute http.proxy?
    end
  end

  test "streams complete events over TLS with original SNI and Host while ignoring an environment proxy" do
    events = [ "data: first\n\n", "data: second\n\n" ]
    pending = +""
    delivered = []
    ack = Queue.new
    proxy = { "https_proxy" => "http://127.0.0.1:1", "no_proxy" => "" }
    previous = ENV.to_h.slice(*proxy.keys)
    ENV.update(proxy)

    with_tls_peer(HOST, IPV4, ->(socket) { send_event_stream(socket, events, ack) }) do |url, store, connection_details|
      client = connection(url, ssl: { cert_store: store })
      assert_equal "127.0.0.1", client.proxy.uri.host
      response = within_scope do
        client.get do |request|
          request.options.on_data = ->(chunk, _size, _env) do
            pending << chunk
            while (boundary = pending.index("\n\n"))
              event = pending.slice!(0, boundary + 2)
              delivered << event
              ack << event
            end
          end
        end
      end

      port = URI(url).port
      assert_equal [ HOST, "#{HOST}:#{port}" ], connection_details
      assert_equal [ 200, "text/event-stream", "" ], [ response.status, response.headers["content-type"], response.body ]
      assert_equal events, delivered
      assert_empty pending
    end
  ensure
    proxy.each_key { |key| ENV[key] = previous[key] }
  end

  test "rejects a trusted certificate for the wrong hostname" do
    with_tls_peer("wrong.example.test", IPV4, nil) do |url, store|
      error = assert_raises(Faraday::SSLError) do
        within_scope { connection(url, ssl: { cert_store: store }).get }
      end
      assert_match(/hostname mismatch|does not match/, error.message)
    end
  end

  { verify: false, verify_mode: OpenSSL::SSL::VERIFY_NONE, verify_hostname: false }.each do |key, value|
    test "rejects the wrong TLS hostname even with #{key}: #{value}" do
      with_tls_peer("wrong.example.test", IPV4, nil) do |url, store|
        client = connection(url, ssl: { cert_store: store, key => value })
        error = assert_raises(Faraday::SSLError) { within_scope { client.get } }
        assert_match(/hostname mismatch|does not match/, error.message)
      end
    end
  end

  test "rejects an untrusted certificate even with verification disabled in Faraday options" do
    with_tls_peer(HOST, IPV4, nil) do |url, _store|
      client = connection(url, ssl: { cert_store: OpenSSL::X509::Store.new, verify: false })
      error = assert_raises(Faraday::SSLError) { within_scope { client.get } }
      assert_match(/unable to get local issuer certificate|certificate verify failed/, error.message)
    end
  end

  test "rejects a raw Net::HTTP configuration block when Faraday builds the adapter" do
    client = connection(URL) do |http|
      http.ipaddr = "127.0.0.1"
      http.proxy_from_env = true
      http.max_retries = 2
      http.verify_callback = ->(*) { true }
    end

    error = assert_raises(ArgumentError) { client.app }
    assert_match(/configuration block/, error.message)
  end

  test "returns a redirect without following it and captures request state before Faraday overwrites it" do
    location = "https://redirect.example.test/mcp"
    handler = ->(socket) do
      socket.write("HTTP/1.1 307 Temporary Redirect\r\nLocation: #{location}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    end
    events = []
    scope = McpOutbound::Scope.new(https_only: true)
    scope.define_singleton_method(:capture) { |env| [ env.method, env.body == "request payload" ] }
    scope.define_singleton_method(:observe) { |attempt, response| events << [ attempt, response.status, response.body ] }

    with_tls_peer(HOST, IPV4, handler) do |url, store|
      client = connection(url, ssl: { cert_store: store }, proxy: "http://127.0.0.1:1")
      response = McpOutbound.with(scope) { client.post(nil, +"request payload") }

      assert_equal 307, response.status
      assert_equal location, response.headers["location"]
      assert_equal [ [ [ :post, true ], 307, "" ] ], events
    end
  end

  private
    def with_dns(*answers)
      lookups = []
      resolver = ->(host) { lookups << host; answers.map { IPAddr.new(it) } }
      with_stub(UrlGuard, :resolve, resolver) { yield lookups }
    end

    def with_stub(object, method, replacement)
      original = object.method(method)
      object.define_singleton_method(method) { |*args, **kwargs| replacement.call(*args, **kwargs) }
      yield
    ensure
      object.define_singleton_method(method, original)
    end

    def within_scope(&block)
      McpOutbound.with(McpOutbound::Scope.new(https_only: true), &block)
    end

    def connection(url, **options, &configure)
      # Faraday may consult DNS for no_proxy rules before invoking the adapter.
      # Only the guarded connection's separate UrlGuard lookup is under test.
      resolve_proxy_host = ->(host) { assert_equal HOST, host; IPV4 }
      with_stub(IPSocket, :getaddress, resolve_proxy_host) do
        Faraday.new(url, request: { timeout: 3 }, **options) do |builder|
          builder.adapter McpOutbound::Adapter, &configure
        end
      end
    end
end
