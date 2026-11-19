# Owns one native MCP instance and the outbound scope for its lifetime.
class McpServer::Client
  class Error < StandardError; end

  QUIET_LOGGER = Logger.new(File::NULL)

  # @param server [McpServer] An eligible remote connector
  # @raise [Error] Invalid connector settings
  def initialize(server)
    @scope = RequestScope.new(https_only: false)
    @lock = Mutex.new
    @prefix = "mcp_#{server.id}"
    options = { name: @prefix, prefix: @prefix, input_requests: false }
    @native = within do
      if server.transport_type == "stdio"
        RubyLLM.mcp(**options, command: stdio_argv(server), env: server.env || {})
      else
        url = McpOutbound.endpoint!(server.effective_endpoint, https_only: false)
        context = RubyLLM.context do |config|
          config.faraday_adapter = McpOutbound::Adapter
          config.logger = QUIET_LOGGER
          # Faraday still does preliminary proxy discovery; the guarded adapter
          # ignores it and pins the direct socket without changing process ENV.
          config.http_proxy = nil
        end
        @headers = server.static_headers
        context.mcp(**options, url: url.to_s, headers: @headers, allow_http: true)
      end
    end
  end

  # Scopes every native call, including a tool call from a separate fiber.
  # @raise [Error] A sanitized native request or configuration failure
  def within(&block)
    @lock.synchronize do
      raise Error if @closed

      McpOutbound.with(@scope, &block)
    end
  rescue RubyLLM::CancelledError
    raise
  rescue StandardError
    raise Error, I18n.t("nosia.mcp_workspace.remote_failure"), cause: nil
  end

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
  # @return [String, Array, Hash]
  def output(result)
    text = result_text(result)

    if result.error?
      tool_error(text)
    elsif result.attachments.empty?
      text
    else
      [ text, *attachments_with_declared_types(result) ]
    end
  end

  # @param text [String] Error text from an executed tool
  # @return [Hash] Existing error wrapper with configured headers redacted
  def tool_error(text)
    safe_text = (@headers || {}).values.grep(String).flat_map { |value| [ value, value.delete_prefix("Bearer ") ] }
      .reject(&:blank?).uniq.sort_by { |value| -value.length }.reduce(text.to_s) { |message, value| message.gsub(value, "[FILTERED]") }
    execution_error(safe_text)
  end

  # Closes the native session within its scope, without masking earlier errors.
  # @return [void]
  def close
    within do
      @native.close
    ensure
      @closed = true
    end
  rescue Error, RubyLLM::CancelledError
    # Cleanup cannot replace an earlier failure or interrupted completion.
    nil
  end

  private
    def model_tools
      @native.tools.select { |tool| tool.visibility.include?(:model) }
    end

    def call_listed_tool(name, arguments)
      output(@native.call(name, **arguments))
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
