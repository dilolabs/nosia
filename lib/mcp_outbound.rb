# frozen_string_literal: true

require "ipaddr"
require "uri"

module McpOutbound
  class Blocked < UrlGuard::Blocked; end

  NONPUBLIC_IPV4 = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12
    192.0.0.0/24 192.0.2.0/24 192.88.99.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24
    203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
  ].map { IPAddr.new(it).freeze }.freeze

  # Allow IPv6 global unicast only, excluding special-purpose allocations
  # within it (including protocol assignments, 6to4, and documentation).
  GLOBAL_UNICAST_IPV6 = IPAddr.new("2000::/3").freeze
  SPECIAL_IPV6 = %w[
    2001::/23 2001:db8::/32 2002::/16 2620:4f:8000::/48 3fff::/20
  ].map { IPAddr.new(it).freeze }.freeze

  class Scope
    def initialize(https_only:)
      @https_only = https_only != false
    end

    def https_only?
      @https_only
    end

    def admit!(_env)
    end

    def capture(_env)
    end

    def observe(_attempt, _response)
    end
  end

  class << self
    def destination!(url, https_only:)
      uri = checked_uri!(url, https_only: https_only)
      addresses = UrlGuard.resolve(uri.hostname).map { |ip| ip.ipv4_mapped? ? ip.native : ip }
      raise Blocked, "host does not resolve" if addresses.empty?
      raise Blocked, "host resolves to a nonpublic address" unless addresses.all? { public_ip?(it) }

      [ uri, addresses.first ]
    end

    def with(scope)
      previous = Fiber[:nosia_mcp_outbound_scope]
      Fiber[:nosia_mcp_outbound_scope] = scope
      yield
    ensure
      Fiber[:nosia_mcp_outbound_scope] = previous
    end

    def current!
      Fiber[:nosia_mcp_outbound_scope] || raise(Blocked, "missing MCP outbound scope")
    end

    private
      def checked_uri!(url, https_only:)
        raw = url.to_s
        uri = URI.parse(raw)
        https = uri.is_a?(URI::HTTPS)
        http = uri.is_a?(URI::HTTP) && uri.scheme == "http"
        raise Blocked, "scheme not allowed" unless https || (http && https_only == false)
        raise Blocked, "host missing" if uri.hostname.to_s.empty?
        raise Blocked, "port not allowed" unless (1..65535).cover?(uri.port)
        # URI discards empty userinfo; also check the unparsed authority.
        raise Blocked, "userinfo not allowed" if uri.userinfo || raw.match?(%r{\Ahttps?://[^/?#]*@}i)
        raise Blocked, "fragment not allowed" if uri.fragment

        uri
      rescue URI::Error
        raise Blocked, "invalid URL", cause: nil
      end

      def public_ip?(ip)
        if ip.ipv4?
          NONPUBLIC_IPV4.none? { it.include?(ip) }
        else
          GLOBAL_UNICAST_IPV6.include?(ip) && SPECIAL_IPV6.none? { it.include?(ip) }
        end
      end
  end
end
