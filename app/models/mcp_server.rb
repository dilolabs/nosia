class McpServer < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  has_many :chat_mcp_sessions, dependent: :destroy

  # Validations
  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :transport_type, presence: true, inclusion: { in: %w[stdio streamable sse] }
  validates :endpoint, presence: true, if: -> { %w[streamable sse].include?(transport_type) }

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
  before_save :encrypt_secrets

  # Get MCP client instance
  def client
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

  # Test connection and update status
  def test_connection!
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

  # Execute a tool
  def execute_tool(tool_name, arguments = {})
    return { error: "Server not ready" } unless status_ready?

    begin
      tool = tools.find { |t| t.name == tool_name }
      return { error: "Tool not found: #{tool_name}" } unless tool

      result = tool.call(arguments)
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

  def encrypt_secrets
    # TODO: Implement secret encryption with Rails credentials or ActiveRecord Encryption
    # For now, just store as-is
  end
end
