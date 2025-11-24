# frozen_string_literal: true

# Environment Variable Validator
# This initializer validates required environment variables at application startup
# to prevent runtime failures and provide clear error messages.

module EnvironmentValidator
  class ValidationError < StandardError; end

  class << self
    def validate!
      # Skip validation in test environment
      return if defined?(Rails) && Rails.env.test?

      missing_vars = []
      invalid_vars = []

      # Required variables for all environments
      required_vars = {
        "SECRET_KEY_BASE" => { validator: :non_empty_string },
        "AI_BASE_URL" => { validator: :url },
        "LLM_MODEL" => { validator: :non_empty_string },
        "EMBEDDING_MODEL" => { validator: :non_empty_string },
        "EMBEDDING_DIMENSIONS" => { validator: :positive_integer }
      }

      # Production-specific required variables
      if defined?(Rails) && Rails.env.production?
        required_vars.merge!({
          "DATABASE_URL" => { validator: :database_url }
        })
      end

      # Validate each required variable
      required_vars.each do |var_name, config|
        value = ENV[var_name]

        if value.nil? || value.strip.empty?
          missing_vars << var_name
        elsif !valid_value?(value, config[:validator])
          invalid_vars << "#{var_name} (expected #{config[:validator]}, got: #{value.inspect})"
        end
      end

      # Optional variables with validation
      optional_vars = {
        "NOSIA_URL" => { validator: :url, default: "https://nosia.localhost" },
        "REGISTRATION_ALLOWED" => { validator: :boolean, default: "true" },
        "AI_API_KEY" => { validator: :non_empty_string, default: "" },
        "LLM_TEMPERATURE" => { validator: :float_between_0_and_1, default: "0.1" },
        "LLM_MAX_TOKENS" => { validator: :positive_integer, default: "1024" },
        "LLM_TOP_K" => { validator: :positive_integer, default: "40" },
        "LLM_TOP_P" => { validator: :float_between_0_and_1, default: "0.9" },
        "RETRIEVAL_FETCH_K" => { validator: :positive_integer, default: "3" },
        "CHUNK_MAX_TOKENS" => { validator: :positive_integer, default: "512" },
        "CHUNK_MIN_TOKENS" => { validator: :positive_integer, default: "128" },
        "CHUNK_MERGE_PEERS" => { validator: :boolean, default: "true" },
        "CHUNK_SIZE" => { validator: :positive_integer, default: "1500" },
        "CHUNK_OVERLAP" => { validator: :positive_integer, default: "250" }
      }

      optional_vars.each do |var_name, config|
        value = ENV[var_name]

        if value.present? && !valid_value?(value, config[:validator])
          invalid_vars << "#{var_name} (expected #{config[:validator]}, got: #{value.inspect})"
        elsif value.nil? || value.strip.empty?
          # Set default if not provided
          ENV[var_name] = config[:default] if config[:default]
        end
      end

      # Report errors
      errors = []
      errors << "Missing required environment variables: #{missing_vars.join(", ")}" if missing_vars.any?
      errors << "Invalid environment variable values: #{invalid_vars.join(", ")}" if invalid_vars.any?

      if errors.any?
        error_message = <<~ERROR

        ============================================================
        ENVIRONMENT VARIABLE VALIDATION FAILED
        ============================================================

        #{errors.join("\n\n")}

        Please check your .env file or environment configuration.

        For production deployments, ensure all required variables
        are properly configured in your deployment environment.

        See .env.example for reference configuration.
        ============================================================

        ERROR

        raise ValidationError, error_message
      end

      log_configuration if defined?(Rails) && Rails.env.development?
    end

    private

    def valid_value?(value, validator)
      case validator
      when :boolean
        %w[true false].include?(value.downcase)
      when :non_empty_string
        value.is_a?(String) && !value.strip.empty?
      when :url
        value =~ URI::DEFAULT_PARSER.make_regexp(%w[http https])
      when :database_url
        value =~ /\A(postgres|postgresql):\/\/.+/
      when :positive_integer
        value.to_s =~ /\A\d[\d_]*\z/ && value.gsub("_", "").to_i > 0
      when :float_between_0_and_1
        value.to_s =~ /\A\d+(\.\d+)?\z/ && (0..1).cover?(value.to_f)
      else
        true
      end
    end

    def log_configuration
      return unless defined?(Rails.logger)

      Rails.logger.info "=" * 60
      Rails.logger.info "Environment Configuration Validated Successfully"
      Rails.logger.info "=" * 60
      Rails.logger.info "LLM Model: #{ENV["LLM_MODEL"]}"
      Rails.logger.info "Embedding Model: #{ENV["EMBEDDING_MODEL"]}"
      Rails.logger.info "Embedding Dimensions: #{ENV["EMBEDDING_DIMENSIONS"]}"
      Rails.logger.info "AI Base URL: #{ENV["AI_BASE_URL"]}"
      Rails.logger.info "=" * 60
    end
  end
end

# Run validation at startup
EnvironmentValidator.validate! unless ENV["SECRET_KEY_BASE_DUMMY"] == "1"
