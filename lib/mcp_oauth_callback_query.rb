# The callback only accepts scalar OAuth response fields. Take its query out
# of Rails' logging and nested parameter parser before either can see it.
class McpOauthCallbackQuery
  FIELD_NAMES = %w[state code error iss error_description].freeze
  ENV_KEY = "nosia.mcp_oauth_callback_query"
  PATH = %r{\A/+mcp/+oauth/+callback/*\z}

  # @param app [#call] The next Rack middleware or Rails application
  def initialize(app)
    @app = app
  end

  # @param env [Hash] Rack request environment
  # @return [Array] Rack response from the wrapped application
  def call(env)
    if PATH.match?(env["PATH_INFO"])
      env[ENV_KEY] = parse(env.fetch("QUERY_STRING", ""))
      env["QUERY_STRING"] = ""
    end
    @app.call(env)
  ensure
    env.delete(ENV_KEY)
  end

  private
    def parse(query)
      fields = URI.decode_www_form(query).select { |key, _| FIELD_NAMES.include?(key.split("[", 2).first) }
      values = fields.group_by(&:first)
      arguments = values.filter_map { |key, entries| entries.first if FIELD_NAMES.include?(key) && entries.one? }.to_h
      [ arguments, fields.size == arguments.size ]
    rescue ArgumentError
      [ {}, false ]
    end
end
