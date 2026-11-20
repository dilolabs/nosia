class McpServer < ApplicationRecord
  include Configuration
  include CapabilitySnapshot
  include Authorization

  acts_as_tenant :account
  belongs_to :account
  has_many :chat_mcp_sessions, dependent: :destroy

  # Validations
  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :transport_type, presence: true, inclusion: { in: %w[stdio streamable sse local] }
  validates :endpoint, presence: true, if: -> { transport_type == "streamable" && !oauth? }
  validate :supported_transport
  validate :validate_streamable_endpoint, if: -> { transport_type == "streamable" }
  validate :stdio_transport_enabled_for_deployment, if: -> { transport_type == "stdio" }
  validate :validate_stdio_executable, if: -> { transport_type == "stdio" }

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
  scope :ready, -> { where(status: "ready", transport_type: stdio_enabled? ? %w[streamable local stdio] : %w[streamable local]) }
  scope :with_errors, -> { where(status: "error") }

  # Store accessors for JSONB fields
  store_accessor :connection_config, :command, :args, :env, :url, :headers
  store_accessor :auth_config, :token, :api_key
  store_accessor :metadata, :capabilities, :server_info, :tools_cache, :prompts_cache, :resources_cache

  # Callbacks
  before_validation :set_default_status
  before_validation :retire_legacy_sse_override

  # Encrypt sensitive fields
  encrypts :auth_config, :connection_config

  STDIO_EXECUTABLE = %r{\A[a-zA-Z0-9_./+-]+\z}
  STATIC_DIAGNOSTICS_REVISION = %w[updated_at transport_type endpoint auth_config connection_config metadata].freeze

  # Spawning local processes from user-supplied commands is opt-in per
  # deployment: multi-tenant hosts keep MCP_STDIO_ENABLED unset.
  def self.stdio_enabled?
    ActiveModel::Type::Boolean.new.cast(ENV["MCP_STDIO_ENABLED"])
  end

  def local? = transport_type == "local"
  def legacy_sse? = transport_type == "sse"
  def saved_legacy_sse? = attribute_in_database("transport_type") == "sse" && persisted?
  def stdio_executable? = command.is_a?(String) && STDIO_EXECUTABLE.match?(command)
  def effective_endpoint = url || endpoint

  def ready_for_tools? = !oauth? && status_ready? && !legacy_sse? && !stdio_disabled?

  # @return [Hash] A fresh set of headers with explicit static credentials taking precedence
  def static_headers
    saved = (headers || {}).deep_dup
    header, value = if token.present?
      [ "Authorization", "Bearer #{token}" ]
    elsif api_key.present?
      [ "X-API-Key", api_key ]
    end
    if header
      saved.reject! { |key, _| key.to_s.casecmp?(header) }
      saved[header] = value
    end
    saved
  end

  # @return [McpServer::Client, nil] A fresh client, owned and closed by the caller
  def client
    Client.new(self) if auth_mode == "static" && %w[streamable stdio].include?(transport_type) && !stdio_disabled?
  end

  # Runs one workspace operation and closes its connection, even on failure.
  # @yieldparam connection [McpServer::Client]
  def with_client
    connection = client
    yield connection if connection
  ensure
    connection&.close
  end

  # Tests the saved connection without running deployment-disabled processes.
  # @return [Boolean] Whether the connection succeeded
  def test_connection!
    return false if oauth? || legacy_sse? || stdio_disabled?
    return test_local_connection! if local?

    start_time = Time.current
    return false unless write_static_diagnostics(status: "connecting", last_error: nil)

    tools = with_client(&:tools)
    return false unless tools

    write_static_diagnostics(
      status: "ready",
      last_connected_at: Time.current,
      latency_ms: ((Time.current - start_time) * 1000).to_i,
      last_error: nil,
      metadata: (metadata || {}).merge("tools_cache" => tools.map { |tool| { name: tool.server_name, description: tool.description } },
        "last_test_at" => Time.current.iso8601)
    )
  rescue Client::Error
    write_static_diagnostics(status: "error", last_error: I18n.t("nosia.mcp_workspace.remote_failure"),
      metadata: (metadata || {}).merge("last_test_at" => Time.current.iso8601))
    false
  end

  # Lists tool metadata. To invoke a remote tool, use #execute_tool or #with_client.
  def tools
    return [] unless ready_for_tools?

    return local_tools if local?

    capability_snapshot.fetch(:tools).items
  end

  # Lists prompt metadata without fetching messages.
  def prompts
    capability_snapshot.fetch(:prompts).items
  end

  # Lists resource metadata without reading contents.
  def resources
    capability_snapshot.fetch(:resources).items
  end

  # Execute a ready server's tool through RubyLLM's keyword interface.
  # @param tool_name [String] registered tool name
  # @param arguments [Hash] JSON object, never attachment paths or model attributes
  # @param user [User, nil] Explicit acting member for OAuth
  # @return [Hash] success/result or the existing error wrapper
  # @raise [McpServer::Client::Error] Sanitized OAuth failure; caller localizes by type
  def execute_tool(tool_name, arguments = {}, user: nil)
    return execute_oauth_tool(tool_name, arguments, user) if oauth?
    return { error: I18n.t("nosia.mcp.not_ready") } unless ready_for_tools?

    arguments = arguments.to_h.transform_keys(&:to_s)
    result = if local?
      tool = local_tools.find { |entry| entry.name == tool_name }
      tool ? tool.call(**arguments) : :missing_tool
    else
      with_client { |connection| connection.call(tool_name, arguments) }
    end
    tool_execution_result(tool_name, result)
  rescue Client::Error
    raise if oauth?

    { error: I18n.t("nosia.mcp_workspace.remote_failure") }
  end

  # The legacy action must not retire another member's authorization.
  def disconnect!(user: nil)
    if oauth?
      if user
        Account.transaction do
          Account.lock.find(account_id)
          oauth_grant_for(user)&.retire!
        end
      end
    elsif !legacy_sse?
      write_static_diagnostics(status: "disconnected")
    end
  end

  private

  # Lock only the connector and only while checking and writing diagnostics.
  # Configuration edits can acquire the account lock first; never take it here.
  # The timestamp also rejects a saved change that was undone during the test.
  def write_static_diagnostics(values)
    self.class.transaction do
      saved = self.class.unscoped.lock.find_by(id:, account_id:, auth_mode: "static")
      next false unless saved && saved.slice(*STATIC_DIAGNOSTICS_REVISION) == slice(*STATIC_DIAGNOSTICS_REVISION)

      changes = values.merge(updated_at: Time.current)
      if saved.update_columns(changes)
        assign_attributes(saved.reload.slice(*changes.keys))
        clear_attribute_changes(changes.keys)
        true
      else
        false
      end
    end
  end

  def execute_oauth_tool(tool_name, arguments, user)
    result = with_authorized_oauth_client(user) { |connection| connection.call(tool_name, arguments.to_h.transform_keys(&:to_s)) }
    tool_execution_result(tool_name, result)
  end

  def tool_execution_result(tool_name, result)
    if result == :missing_tool
      { error: I18n.t("nosia.mcp.tool_not_found", name: tool_name) }
    else
      { success: true, result: result }
    end
  end

  def set_default_status
    self.status ||= "disconnected"
  end

  def supported_transport
    errors.add(:transport_type, :inclusion) if legacy_sse? && !saved_legacy_sse?
  end

  def retire_legacy_sse_override
    if saved_legacy_sse? && transport_type == "streamable"
      self.url = nil
      self.status = "disconnected"
    end
  end

  def validate_streamable_endpoint
    return if endpoint.blank?

    parsed = McpOutbound.endpoint!(effective_endpoint, https_only: false)
    McpOutbound.check_literal!(parsed)
  rescue McpOutbound::Blocked
    errors.add(:endpoint, :public_host_required)
  end

  def stdio_disabled? = transport_type == "stdio" && !self.class.stdio_enabled?

  def stdio_transport_enabled_for_deployment
    errors.add(:transport_type, :stdio_disabled) if stdio_disabled?
  end

  def validate_stdio_executable
    errors.add(:command, :invalid) unless stdio_executable?
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
    return false unless write_static_diagnostics(status: "connecting", last_error: nil)

    registration = Engines::Registry[metadata["engine"]]
    raise "Unknown engine: #{metadata["engine"]}" unless registration

    registration.health_check.call(auth_config_for_tools)
    latency = ((Time.current - start_time) * 1000).to_i
    write_static_diagnostics(
      status: "ready",
      last_connected_at: Time.current,
      latency_ms: latency,
      last_error: nil,
      metadata: (metadata || {}).merge("last_test_at" => Time.current.iso8601)
    )
  rescue => e
    write_static_diagnostics(
      status: "error",
      last_error: e.message,
      metadata: (metadata || {}).merge("last_test_at" => Time.current.iso8601)
    )
    false
  end

  def encrypt_secrets
    # TODO: Implement secret encryption with Rails credentials or ActiveRecord Encryption
    # For now, just store as-is
  end
end
