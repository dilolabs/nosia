require "openssl"
require "socket"

module McpOutboundTls
  private
    def with_tls_peer(cert_hostname, pinned_ip, handler)
      listener = TCPServer.new("127.0.0.1", 0)
      port = listener.addr[1]
      context, store = tls_context(cert_hostname)
      details = []
      context.servername_cb = proc { |_socket, hostname| details << hostname; nil }
      peer = Thread.new do
        Thread.current.report_on_exception = false
        serve_tls_request(listener, context, details, handler)
      end
      original = TCPSocket.method(:open)
      remap = ->(host, requested_port, *args, **options) do
        # Fail before connecting if the adapter ever requests any other socket.
        assert_equal [ pinned_ip, port ], [ host, requested_port ]
        original.call("127.0.0.1", port, *args, **options)
      end

      with_dns(pinned_ip) do |lookups|
        with_stub(TCPSocket, :open, remap) do
          yield "https://#{self.class::HOST}:#{port}/mcp", store, details
        end
        assert_equal [ self.class::HOST ], lookups
      end
      assert peer.join(3), "TLS fixture did not finish"
    ensure
      listener&.close
      peer&.kill&.join if peer&.alive?
    end

    def serve_tls_request(listener, context, details, handler)
      tcp = listener.accept
      socket = OpenSSL::SSL::SSLSocket.new(tcp, context)
      socket.accept
      headers = {}
      while (line = socket.gets) && line != "\r\n"
        name, value = line.split(":", 2)
        headers[name.downcase] = value.strip if value
      end
      details << headers["host"]
      socket.read(headers["content-length"].to_i) if headers["content-length"]
      handler&.call(socket)
    rescue OpenSSL::SSL::SSLError
      raise if handler # The wrong-host test is expected to abort the handshake.
    ensure
      socket&.close
      tcp&.close
    end

    def send_event_stream(socket, events, ack)
      socket.write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n")
      events.each do |event|
        # Split the event terminator across HTTP chunks.
        [ event[0...-1], event[-1] ].each do |chunk|
          socket.write("#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n")
        end
        raise "event not delivered while stream was open" unless ack.pop(timeout: 3) == event
      end
      socket.write("0\r\n\r\n")
    end

    def tls_context(hostname)
      ca_key = OpenSSL::PKey::EC.generate("prime256v1")
      ca = certificate("Test CA", ca_key, serial: 1)
      extensions = OpenSSL::X509::ExtensionFactory.new
      ca.add_extension(extensions.create_extension("basicConstraints", "CA:TRUE", true))
      ca.sign(ca_key, OpenSSL::Digest.new("SHA256"))

      key = OpenSSL::PKey::EC.generate("prime256v1")
      cert = certificate(hostname, key, serial: 2)
      cert.issuer = ca.subject
      cert.add_extension(extensions.create_extension("subjectAltName", "DNS:#{hostname}"))
      cert.sign(ca_key, OpenSSL::Digest.new("SHA256"))

      context = OpenSSL::SSL::SSLContext.new
      context.cert = cert
      context.key = key
      store = OpenSSL::X509::Store.new
      store.add_cert(ca)
      [ context, store ]
    end

    def certificate(name, key, serial:)
      OpenSSL::X509::Certificate.new.tap do |cert|
        cert.version = 2
        cert.serial = serial
        cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=#{name}")
        cert.public_key = key
        cert.not_before = Time.now - 60
        cert.not_after = Time.now + 3600
      end
    end
end
