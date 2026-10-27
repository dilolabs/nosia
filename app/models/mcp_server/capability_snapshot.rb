# Discovers capability lists with independent, request-local loading outcomes.
module McpServer::CapabilitySnapshot
  extend ActiveSupport::Concern

  # Holds a loading state (:not_loaded, :loaded, :unavailable) and listed items.
  Result = Data.define(:state, :items)

  # @return [Hash<Symbol, Result>] Request-local discovery; never executes content
  def capability_snapshot
    signature = [ status, transport_type, metadata["engine"] ]
    if @capability_snapshot_signature != signature
      @capability_snapshot_signature = signature
      @capability_snapshot = %i[tools prompts resources].to_h { |kind| [ kind, discover_capability(kind) ] }
    end
    @capability_snapshot
  end

  private
    def discover_capability(kind)
      return Result.new(:not_loaded, []) unless status_ready?

      if local?
        if Engines::Registry[metadata["engine"]]
          Result.new(:loaded, kind == :tools ? local_tools : [])
        else
          Result.new(:unavailable, [])
        end
      elsif (mcp_client = client)
        items = mcp_client.public_send(kind)
        items.nil? ? Result.new(:unavailable, []) : Result.new(:loaded, Array(items))
      else
        Result.new(:unavailable, [])
      end
    rescue StandardError
      Result.new(:unavailable, [])
    end
end
