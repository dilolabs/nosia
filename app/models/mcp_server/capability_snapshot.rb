# Discovers capability lists with independent, request-local loading outcomes.
module McpServer::CapabilitySnapshot
  extend ActiveSupport::Concern

  # Holds a loading state (:not_loaded, :loaded, :unavailable) and listed items.
  Result = Data.define(:state, :items)

  # Missing engine metadata does not block remote or not-ready outcomes.
  # @return [Hash<Symbol, Result>] Request-local discovery; never executes content
  def capability_snapshot
    signature = [ ready_for_tools?, status, transport_type, metadata&.[]("engine"), endpoint, connection_config, auth_config ]
    if @capability_snapshot_signature != signature
      @capability_snapshot_signature = signature
      @capability_snapshot = if !ready_for_tools? || local?
        capability_lists(nil)
      else
        with_client { |connection| capability_lists(connection) } || capability_lists(nil)
      end
    end
    @capability_snapshot
  rescue McpServer::Client::Error
    @capability_snapshot = capability_lists(nil)
  end

  private
    def capability_lists(connection)
      %i[tools prompts resources].index_with { |kind| discover_capability(kind, connection) }
    end

    def discover_capability(kind, connection)
      return Result.new(:not_loaded, []) unless ready_for_tools?

      if local?
        if Engines::Registry[metadata&.[]("engine")]
          Result.new(:loaded, kind == :tools ? local_tools : [])
        else
          Result.new(:unavailable, [])
        end
      elsif connection
        items = connection.public_send(kind)
        items.nil? ? Result.new(:unavailable, []) : Result.new(:loaded, Array(items))
      else
        Result.new(:unavailable, [])
      end
    rescue StandardError
      Result.new(:unavailable, [])
    end
end
