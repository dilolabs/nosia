require_relative "../../lib/nosia/native_stack"

if Nosia::NativeStack.enabled?
  origin = Nosia::NativeStack.origin
  raise Nosia::NativeStack::ConfigurationError, "Native inference API key is required" if ENV.fetch("AI_API_KEY", "").empty?
  Rails.application.configure do
    # Use booleans, since the string "false" would be truthy in Ruby.
    config.assume_ssl = false
    config.force_ssl = false
    config.hosts = [ "127.0.0.1" ]
    config.action_cable.allowed_request_origins = [ origin.to_s.delete_suffix("/") ]
    config.action_cable.url = "ws://127.0.0.1:#{origin.port}/cable"
    config.public_file_server.enabled = true
    config.action_mailer.default_url_options = { host: origin.host, port: origin.port, protocol: "http" }
    routes.default_url_options = { host: origin.host, port: origin.port, protocol: "http" }
    config.session_store :cookie_store, key: "_nosia_native_session", httponly: true, same_site: :lax, secure: false
  end
end
