require "json"
require "uri"

module Nosia
  # Defines the opt-in local runtime and its packaged compatibility metadata.
  module NativeStack
    PROTOCOL_VERSION = 1
    class ConfigurationError < StandardError; end

    # @param environment [#[]] runtime environment
    # @return [Boolean] whether native local mode was explicitly requested
    def self.enabled?(environment = ENV)
      environment["NOSIA_NATIVE_LOCAL"] == "1"
    end

    # @param environment [#[]] runtime environment
    # @return [nil]
    # @raise [ConfigurationError] when native mode is not enabled
    def self.require_enabled!(environment = ENV)
      raise ConfigurationError, "Native local mode must be explicitly enabled" unless enabled?(environment)
    end

    # @param environment [#fetch] runtime environment containing NOSIA_URL
    # @return [URI::HTTP] the validated unprivileged loopback origin
    # @raise [ConfigurationError] when the origin is missing or unsafe
    def self.origin(environment = ENV)
      value = environment.fetch("NOSIA_URL", "")
      raise ConfigurationError, "Native local origin is required" if value.empty?
      uri = URI.parse(value)
      unless uri.scheme == "http" && uri.host == "127.0.0.1" && uri.port.between?(1024, 65535) &&
          uri.userinfo.nil? && [ nil, "", "/" ].include?(uri.path) && uri.query.nil? && uri.fragment.nil?
        raise ConfigurationError, "Native local origin must be http://127.0.0.1:<port>"
      end
      uri
    rescue URI::InvalidURIError, URI::InvalidComponentError
      raise ConfigurationError, "Native local origin is invalid"
    end

    # @param environment [#fetch] native runtime configuration
    # @return [String] the nonblank identity of the embedding space
    # @raise [ConfigurationError] when the fingerprint is missing or blank
    def self.embedding_fingerprint(environment = ENV)
      fingerprint = environment.fetch("NOSIA_NATIVE_EMBEDDING_FINGERPRINT", "")
      raise ConfigurationError, "Native embedding fingerprint is required" if fingerprint.strip.empty?
      fingerprint
    end

    # @param root [String, Pathname] packaged application root
    # @return [Integer] the latest packaged migration version
    # @raise [ConfigurationError] when no migration version can be determined
    def self.database_schema_version(root:)
      versions = Dir.glob(File.join(root, "db/migrate/[0-9]*_*.rb")).map do |path|
        prefix = File.basename(path).split("_", 2).first
        prefix.to_i if prefix.match?(/\A[0-9]{14}\z/)
      end.compact
      raise ConfigurationError, "No database migrations found" if versions.empty?
      versions.max
    end

    # @param root [String, Pathname] packaged application root
    # @param revision [String] full lowercase source Git SHA
    # @return [Hash] protocol, source commit and packaged schema version
    # @raise [ConfigurationError] when source or schema metadata is invalid
    def self.capabilities(root:, revision:)
      unless revision.match?(/\A[0-9a-f]{40}\z/)
        raise ConfigurationError, "GIT_REVISION must identify the exact source commit"
      end
      { protocolVersion: PROTOCOL_VERSION, serverCommit: revision, databaseSchemaVersion: database_schema_version(root: root) }
    end
  end
end
