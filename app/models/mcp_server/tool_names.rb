require "digest/sha2"
require "set"

# Allocates provider-facing names without changing the MCP wire names.
class McpServer::ToolNames
  MAX_LENGTH = 64
  SAFE = /\A[A-Za-z0-9_-]{1,#{MAX_LENGTH}}\z/
  DIGEST_LENGTH = 16

  # @param prefix [String] Stable connector prefix, before the separating underscore
  # @param server_names [Array<String>] Names advertised by this connector
  def initialize(prefix, server_names)
    @prefix = "#{prefix}_"
    @names = {}
    used = Set.new
    safe, unsafe = server_names.uniq.sort.partition { |name| SAFE.match?("#{@prefix}#{name}") }

    # Reserve safe names first so a coinciding synthesized name cannot take one.
    safe.each { |name| used.add(@names[name] = "#{@prefix}#{name}") }
    unsafe.each do |name|
      @names[name] = 0.step.lazy.map { |attempt| candidate(name, attempt) }.find { |candidate| used.add?(candidate) }
    end
  end

  # @param server_name [String] The original name used on the wire
  # @return [String] The name to register with the model provider
  def fetch(server_name) = @names.fetch(server_name)

  private
    def candidate(name, attempt)
      digest = Digest::SHA256.hexdigest("#{name}\0#{attempt}").first(DIGEST_LENGTH)
      stem_length = MAX_LENGTH - @prefix.length - DIGEST_LENGTH - 1
      stem = name.gsub(/[^A-Za-z0-9_-]/, "_").first(stem_length)
      "#{@prefix}#{stem}_#{digest}"
    end
end
