class McpServer < ApplicationRecord
  include Configuration

  acts_as_tenant :account
  belongs_to :account
  has_many :chat_mcp_sessions, dependent: :destroy

  # Validations
  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :transport_type, presence: true, inclusion: { in: %w[stdio streamable sse local] }
  validates :endpoint, presence: true, if: -> { %w[streamable sse].include?(transport_type) }
  validate :endpoint_must_be_publicly_routable, if: -> { %w[streamable sse].include?(transport_type) }
  validate :stdio_transport_enabled_for_deployment, if: -> { transport_type == "stdio" }

  # Enums
  enum :status, {
    disabled: "disabled",
    disconnected: "disconnected",
    connecting: "connecting",
    ready: "ready",
    error: "error"
  }, prefix: true

  # Scopes
  scope :enabled, -> { where(enabled: true) }
  scope :ready, -> { where(status: "ready") }
  scope :with_errors, -> { where(status: "error") }

  # Store accessors for JSONB fields
  store_accessor :connection_config, :command, :args, :env, :url, :headers
  store_accessor :auth_config, :token, :api_key
  store_accessor :metadata, :capabilities, :server_info, :tools_cache, :prompts_cache, :resources_cache

  # Callbacks
  before_validation :set_default_status

  # Encrypt sensitive fields
  encrypts :auth_config, :connection_config

  def local?
    transport_type == "local"
  end

  # Spawning local processes from user-supplied commands is opt-in per
  # deployment: multi-tenant hosts keep MCP_STDIO_ENABLED unset.
  def self.stdio_enabled?
    ActiveModel::Type::Boolean.new.cast(ENV["MCP_STDIO_ENABLED"])
  end

  # @return [RubyLLM::MCP::Client, nil] Client unless local or blocked by deployment
  def client
    return nil if local? || (transport_type == "stdio" && !self.class.stdio_enabled?)

    @client ||= begin
      config = build_client_config
      RubyLLM::MCP.client(
        name: name,
        transport_type: transport_type.to_sym,
        config: config
      )
    end
  rescue => e
    Rails.logger.error "Failed to create MCP client for #{name}: #{e.message}"
    nil
  end

  # Tests the saved connection without running deployment-disabled processes.
  # @return [Boolean] Whether the connection succeeded
  def test_connection!
    return false if transport_type == "stdio" && !self.class.stdio_enabled?
    return test_local_connection! if local?

    start_time = Time.current
    update!(status: "connecting", last_error: nil)

    begin
      # Initialize client
      mcp_client = client
      return false unless mcp_client

      # List tools to verify connection
      tools = mcp_client.tools

      latency = ((Time.current - start_time) * 1000).to_i

      update!(
        status: "ready",
        last_connected_at: Time.current,
        latency_ms: latency,
        last_error: nil,
        metadata: metadata.merge(
          tools_cache: tools.map { |t| { name: t.name, description: t.description } },
          last_test_at: Time.current.iso8601
        )
      )

      true
    rescue => e
      update!(
        status: "error",
        last_error: e.message,
        metadata: metadata.merge(last_test_at: Time.current.iso8601)
      )
      false
    end
  end

  # Get available tools
  def tools
    return [] unless status_ready?

    return local_tools if local?

    begin
      client&.tools || []
    rescue => e
      Rails.logger.error "Failed to fetch tools from #{name}: #{e.message}"
      []
    end
  end

  # Get available prompts
  def prompts
    return [] unless status_ready?

    begin
      client&.prompts || []
    rescue => e
      Rails.logger.error "Failed to fetch prompts from #{name}: #{e.message}"
      []
    end
  end

  # Get available resources
  def resources
    return [] unless status_ready?

    begin
      client&.resources || []
    rescue => e
      Rails.logger.error "Failed to fetch resources from #{name}: #{e.message}"
      []
    end
  end

  # Execute a ready server's tool through RubyLLM's keyword interface.
  # @param tool_name [String] registered tool name
  # @param arguments [Hash] JSON object, never attachment paths or model attributes
  # @return [Hash] success/result or the existing error wrapper
  def execute_tool(tool_name, arguments = {})
    return { error: I18n.t("nosia.mcp.not_ready") } unless status_ready?

    begin
      tool = tools.find { |t| t.name == tool_name }
      return { error: I18n.t("nosia.mcp.tool_not_found", name: tool_name) } unless tool

      result = tool.call(**arguments.to_h.transform_keys(&:to_s))
      { success: true, result: result }
    rescue => e
      { error: e.message }
    end
  end

  # Disconnect client
  def disconnect!
    @client = nil
    update!(status: "disconnected")
  end

  private

  def set_default_status
    self.status ||= "disconnected"
  end

  def endpoint_must_be_publicly_routable
    return if endpoint.blank?

    candidate = endpoint.match?(%r{\Ahttps?://}i) ? endpoint : "https://#{endpoint}"
    errors.add(:endpoint, :public_host_required) unless UrlGuard.safe?(candidate)
  end

  def stdio_transport_enabled_for_deployment
    unless self.class.stdio_enabled?
      errors.add(:transport_type, :stdio_disabled)
    end
  end

  def build_client_config
    case transport_type
    when "stdio"
      {
        command: command || connection_config["command"],
        args: args || connection_config["args"] || [],
        env: env || connection_config["env"] || {}
      }
    when "streamable", "sse"
      config = {
        url: url || endpoint,
        headers: headers || connection_config["headers"] || {}
      }

      # Add auth headers if present
      if token.present?
        config[:headers]["Authorization"] = "Bearer #{token}"
      elsif api_key.present?
        config[:headers]["X-API-Key"] = api_key
      end

      config
    else
      {}
    end
  end

  def local_tools
    registration = Engines::Registry[metadata["engine"]]
    return [] unless registration

    registration.tool_classes.filter_map do |tool_class|
      Engines::ToolAdapter.for(tool_class, server_context: auth_config_for_tools)
    end
  end

  def auth_config_for_tools
    # auth_config round-trips through JSON (store_accessor + encrypts), so it
    # comes back string-keyed. with_indifferent_access lets tools read either
    # auth[:api_key] or auth["api_key"].
    (auth_config || {}).with_indifferent_access
  end

  def test_local_connection!
    start_time = Time.current
    update!(status: "connecting", last_error: nil)

    registration = Engines::Registry[metadata["engine"]]
    raise "Unknown engine: #{metadata["engine"]}" unless registration

    registration.health_check.call(auth_config_for_tools)
    latency = ((Time.current - start_time) * 1000).to_i
    update!(
      status: "ready",
      last_connected_at: Time.current,
      latency_ms: latency,
      last_error: nil,
      metadata: metadata.merge(last_test_at: Time.current.iso8601)
    )
    true
  rescue => e
    update!(
      status: "error",
      last_error: e.message,
      metadata: metadata.merge(last_test_at: Time.current.iso8601)
    )
    false
  end

  def encrypt_secrets
    # TODO: Implement secret encryption with Rails credentials or ActiveRecord Encryption
    # For now, just store as-is
  end
end
