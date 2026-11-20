# Owns one native MCP instance and the outbound scope for its lifetime.
class McpServer::Client
  class Error < StandardError; end

  QUIET_LOGGER = Logger.new(File::NULL)

  # @param server [McpServer] An eligible remote connector
  # @param grant [McpAuthorization, nil] Exact owner's grant for an OAuth connector
  # @param credential_store [McpAuthorization::CredentialStore, nil] Override for local grant retirement
  # @param chat_owner_id [Integer, nil] Chat-purpose admission for a persisted owner; nil for workspace
  # @raise [Error] Invalid connector settings
  def initialize(server = nil, grant: nil, credential_store: nil, chat_owner_id: nil)
    if grant && chat_owner_id && (chat_owner_id != grant.user_id || server&.id != grant.mcp_server_id || server.account_id != grant.account_id)
      raise McpAuthorization::Unavailable
    end

    @chat_owner_id = chat_owner_id
    @credential_store = credential_store || (McpAuthorization::CredentialStore.new(grant, chat: chat_owner_id.present?) if grant)
    @scope = if grant
      OauthScope.new(grant, @credential_store)
    elsif server.transport_type == "stdio"
      RequestScope.new(https_only: false, admission: stdio_chat_admission(server))
    else
      StaticHttpScope.new(server, chat_owner_id:)
    end
    @lock = Mutex.new
    @prefix = "mcp_#{grant ? grant.mcp_server_id : server.id}"
    options = { name: @prefix, prefix: @prefix, input_requests: false }
    @native = within(operation: :setup) do
      if grant
        @credential_store.verify_schema!
        url = McpOutbound.endpoint!(grant.endpoint, https_only: true).to_s
        @credential_store.native_key(url)
        context.mcp(**options, url:, oauth: { owner: grant })
      elsif server.transport_type == "stdio"
        argv = stdio_argv(server)
        env = server.env || {}
        scope = @scope
        RubyLLM.mcp(**options, transport: -> { Stdio.new(argv, env:, scope:) })
      else
        url = McpOutbound.endpoint!(@scope.endpoint, https_only: false)
        @headers = @scope.headers
        context.mcp(**options, url: url.to_s, headers: @headers, allow_http: true)
      end
    end
  end

  # Scopes every native call, including a tool call from a separate fiber.
  # @param operation [Symbol] The request purpose used by the OAuth admission policy
  # @return [Object] The block result
  # @raise [Error] A sanitized native request or configuration failure
  def within(operation: :use)
    @lock.synchronize do
      raise Error if @closed

      McpOutbound.with(@scope) do
        if @credential_store
          # Always let the SDK dispose of local state. The outbound scope
          # independently denies a remote close if the grant is no longer usable.
          @credential_store.admit_client! unless operation == :close
          @scope.during_operation(operation) { yield }
        else
          yield
        end
      end
    end
  rescue RubyLLM::CancelledError
    raise
  rescue McpAuthorization::Unavailable, McpAuthorization::InsufficientScope => error
    raise error.class, cause: nil
  rescue StandardError
    if @credential_store
      raise McpAuthorization::Unavailable, cause: nil
    else
      raise Error, I18n.t("nosia.mcp_workspace.remote_failure"), cause: nil
    end
  end

  def authorized? = within(operation: :status) { @native.authorized? }

  # Starts native discovery and registration for a fresh consent attempt.
  # @param redirect_uri [String] The callback on the configured Nosia origin
  # @return [String] The URL to validate before sending the browser to consent
  # @raise [McpAuthorization::Unavailable] Consent could not be started
  def authorization_url(redirect_uri:)
    within(operation: :consent) do
      @credential_store.require_unused_grant!
      Timeout.timeout(30, McpOutbound::Blocked) { @native.authorization_url(redirect_uri:) }
    end
  end

  # @param params [Hash<String, String>] Scalar callback fields from the bound browser
  # @return [RubyLLM::MCP] The native client after storing the authorization
  # @raise [McpAuthorization::Unavailable] Sanitized callback failure
  def authorize(params)
    within(operation: :callback) do
      @native.authorize(params)
    rescue RubyLLM::MCP::Error => error
      if params[:error] == "access_denied" || params["error"] == "access_denied"
        raise McpAuthorization::ConsentRefused if error.respond_to?(:error_code) && error.error_code == "access_denied"
      end
      raise
    end
  end

  # Forgets the local credential without requesting provider-side revocation.
  def deauthorize = within(operation: :retire) { @native.deauthorize }

  # @return [Array<McpServer::RemoteTool>] Tools visible to the model
  def tools
    within do
      native_tools = model_tools
      names = McpServer::ToolNames.new(@prefix, native_tools.map(&:server_name))
      native_tools.map do |tool|
        McpServer::RemoteTool.new(tool, self, name: names.fetch(tool.server_name))
      end
    end
  end

  # @return [Array<RubyLLM::MCP::Prompt>] Prompt metadata, without messages
  def prompts = within { @native.prompts }

  # @return [Array<RubyLLM::MCP::Resource>] Resource metadata; use #resource to read
  def resources = within { @native.resources }

  # @param uri [String] A resource ID on this server, not an HTTP destination
  # @return [RubyLLM::MCP::Resource] The resource read through MCP
  def resource(uri) = within { @native.resource(uri) }

  # Looks up the wire name on this operation's fresh catalog before execution.
  # @param name [String] The name used by the peer, without the chat prefix
  # @param arguments [Hash] JSON arguments from a workspace execution
  # @return [String, Array, Hash, Symbol] Renderable result or :missing_tool
  def call(name, arguments)
    within do
      if model_tools.any? { |tool| tool.server_name == name }
        @scope.while_calling_tool { call_listed_tool(name, arguments) }
      else
        :missing_tool
      end
    end
  end

  # Returns text/structured content with actual native attachments for the model.
  # @param result [RubyLLM::MCP::Result] First-party native result
  # @param server_name [String] The wire name used to look up the current schema
  # @return [String, Array, Hash]
  def output(result, server_name:)
    output_schema = @native_catalog.output_schema_for(server_name)
    if result.error?
      tool_error(result_text(result))
    elsif result.to_h.key?("structuredContent") && !output_schema.nil? && !McpServer::OutputSchema.valid?(output_schema, result.structured)
      { error: I18n.t("nosia.mcp_workspace.invalid_structured_output") }
    elsif !valid_attachment_data?(result)
      execution_error(I18n.t("nosia.mcp_workspace.invalid_attachment_data"))
    elsif result.attachments.empty?
      result_text(result)
    else
      [ result_text(result), *attachments_with_declared_types(result) ]
    end
  end

  # @param text [String] Error text from an executed tool
  # @return [Hash] Generic chat/OAuth error, or a redacted legacy static workspace error
  def tool_error(text)
    return execution_error(I18n.t("nosia.mcp_workspace.tool_call_rejected")) if @credential_store || @chat_owner_id

    safe_text = (@headers || {}).values.grep(String).flat_map { |value| [ value, value.delete_prefix("Bearer ") ] }
      .reject(&:blank?).uniq.sort_by { |value| -value.length }.reduce(text.to_s) { |message, value| message.gsub(value, "[FILTERED]") }
    execution_error(safe_text)
  end

  # Closes the native session within its scope, without masking earlier errors.
  # @return [void]
  def close
    within(operation: :close) do
      @native.close
    ensure
      @closed = true
    end
  rescue Error, RubyLLM::CancelledError
    # Cleanup cannot replace an earlier failure or interrupted completion.
    nil
  end

  private
    def stdio_chat_admission(server)
      return unless @chat_owner_id

      id, account_id, revision = server.id, server.account_id, server.connection_revision
      -> do
        McpServer.uncached do
          saved = McpServer.unscoped.find_by(id:, account_id:, connection_revision: revision, transport_type: "stdio", auth_mode: "static")
          unless saved&.enabled? && saved.ready_for_tools? && AccountUser.exists?(account_id:, user_id: @chat_owner_id)
            raise McpOutbound::Blocked
          end
        end
      end
    end

    def context
      RubyLLM.context do |config|
        config.faraday_adapter = McpOutbound::Adapter
        config.logger = QUIET_LOGGER
        # Faraday still does preliminary proxy discovery; the guarded adapter
        # ignores it and pins the direct socket without changing process ENV.
        config.http_proxy = nil
        if @credential_store
          config.mcp_credential_store = @credential_store
          config.connect_timeout = 5
          config.request_timeout = 10
        end
      end
    end

    def model_tools
      # 2.2.3 exposes the wrapped tools but not their raw definitions. Install
      # the observer on this one native client, not on the SDK class.
      @native_catalog ||= @native.send(:client).extend(ToolCatalog)
      @native.tools.select { |tool| tool.visibility.include?(:model) }
    end

    def call_listed_tool(name, arguments)
      output(@native.call(name, **arguments), server_name: name)
    rescue RubyLLM::MCP::Error => error
      raise unless @scope.tool_protocol_error?(error)

      execution_error(I18n.t("nosia.mcp_workspace.tool_call_rejected"))
    end

    def execution_error(reason)
      { error: "Tool execution error: #{reason}" }
    end

    def result_text(result)
      return JSON.generate(result.structured) if result.to_h.key?("structuredContent")

      Array(result.to_h["content"]).filter_map do |block|
        case block["type"]
        when "text" then block["text"]
        when "resource" then block.dig("resource", "text")
        when "resource_link" then [ block["title"] || block["name"], block["uri"] ].compact.join(": ")
        end
      end.join("\n")
    end

    def attachments_with_declared_types(result)
      media_types = Array(result.to_h["content"]).each_with_object([]) do |block, types|
        case block["type"]
        when "image", "audio" then types << block["mimeType"]
        when "resource"
          resource = block["resource"] || {}
          types << resource["mimeType"] if !resource["text"] && resource["blob"]
        end
      end

      result.attachments.zip(media_types).map do |attachment, mime_type|
        if mime_type.present? && mime_type != attachment.mime_type
          # Native MCP decodes bytes into a StringIO but infers MIME from its
          # filename/bytes. Preserve the declared type for the existing API.
          RubyLLM::Attachment.new(attachment.source, filename: attachment.filename, mime_type:)
        else
          attachment
        end
      end
    end

    def valid_attachment_data?(result)
      # Native decoding is permissive. Check the original fields before
      # handing the native attachment objects to either caller.
      Array(result.to_h["content"]).each do |block|
        case block["type"]
        when "image", "audio"
          Base64.strict_decode64(block["data"])
        when "resource"
          resource = block["resource"] || {}
          Base64.strict_decode64(resource["blob"]) if !resource["text"] && resource.key?("blob")
        end
      end
      true
    rescue ArgumentError, TypeError
      false
    end

    def stdio_argv(server)
      command = server.command
      raise ArgumentError unless server.stdio_executable?

      arguments = Array(server.args)
      if arguments.empty?
        # Open3's single-String overload can invoke shell builtins. Resolve to
        # an absolute executable first, including a catalog's explicit PATH.
        path = (server.env || {}).stringify_keys.fetch("PATH") { ENV.fetch("PATH", "") }
        candidates = command.include?("/") ? [ command ] : path.to_s.split(File::PATH_SEPARATOR, -1).map { |dir| File.join(dir.presence || ".", command) }
        command = candidates.map { |entry| File.expand_path(entry) }.find do |entry|
          McpServer::STDIO_EXECUTABLE.match?(entry) && File.file?(entry) && File.executable?(entry)
        end
        raise ArgumentError unless command
      end
      [ command, *arguments ]
    end
end
