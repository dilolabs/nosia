# frozen_string_literal: true

require "faraday"
require "faraday/net_http"

module McpOutbound
  class Adapter < Faraday::Adapter::NetHttp
    def call(env)
      scope = McpOutbound.current!
      attempt = scope.capture(env)
      super(env).tap { |response| scope.observe(attempt, response) }
    end

    def net_http_connection(env)
      scope = McpOutbound.current!
      uri, address = McpOutbound.destination!(env.url, https_only: scope.https_only?)
      scope.admit!(env)

      # Keep the original hostname for TLS and Host, but connect directly to
      # the validated IP. An explicit nil disables Net::HTTP's environment proxy.
      Net::HTTP.new(uri.hostname, uri.port, nil).tap { |http| http.ipaddr = address.to_s }
    end
  end
end
