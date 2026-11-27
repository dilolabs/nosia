module Nosia
  # Keeps Note excerpts out of the request body saved for RubyLLM's transport retries.
  module NoteProviderRequest
    REFRESH = :@nosia_note_refresh
    PRIVATE_LOGS = :nosia_note_private_logs
    ERROR_MESSAGE = "Note-context provider request failed"
    private_constant :REFRESH, :PRIVATE_LOGS, :ERROR_MESSAGE

    # @param payload [Hash] The Note-free request to keep between attempts.
    # @yieldparam attempt [Hash] A fresh copy, reauthorized just before encoding.
    def self.refresh_each_attempt(payload, &refresh)
      payload.instance_variable_set(REFRESH, refresh)
    end

    def self.with_private_logs(payload)
      previous = Fiber[PRIVATE_LOGS]
      Fiber[PRIVATE_LOGS] = private_payload?(payload)
      yield
    ensure
      Fiber[PRIVATE_LOGS] = previous
    end

    # @api private
    # @param payload [Hash] The request before Note excerpts are refreshed.
    # @return [Boolean] Whether an attempt could contain Note excerpts.
    def self.private_payload?(payload)
      payload.instance_variable_defined?(REFRESH)
    end

    def self.private_logs?
      Fiber[PRIVATE_LOGS]
    end

    # RubyLLM 2.2.3 builds this part of its Faraday stack inside :retry.
    module ConnectionStack
      private
        def setup_middleware(faraday, settings)
          faraday.use Refresh
          super
        end
    end

    class Refresh < Faraday::Middleware
      def on_request(env)
        if (refresh = env.body.instance_variable_get(REFRESH))
          # Faraday restores the original Note-free Hash before each attempt.
          # Never put retrieved text or retry state into that shared Hash.
          RubyLLM::Support::Cancellation.check
          env.body = env.body.deep_dup
          refresh.call(env.body)
        end
      end
    end

    module CompletionLogging
      def complete_request(payload, *args, **options, &stream)
        # The outer logger also receives responses and errors on unwind, so
        # suppress diagnostics for this whole model request, not just the send.
        stream_error = nil
        if stream && NoteProviderRequest.private_payload?(payload)
          forward_chunk = ->(chunk) do
            stream.call(chunk)
          rescue RubyLLM::Error, Faraday::Error => error
            stream_error = error
            raise
          end
        end

        NoteProviderRequest.with_private_logs(payload) { super(payload, *args, **options, &(forward_chunk || stream)) }
      rescue RubyLLM::Error, Faraday::Error => error
        raise unless NoteProviderRequest.private_payload?(payload) && !error.equal?(stream_error)

        # Let RubyLLM classify and retry the original failure first. A fresh
        # exception keeps its type without retaining the response or raw cause.
        raise error.class.new(ERROR_MESSAGE), cause: nil
      end
    end

    module WireLogging
      private
        def log_body?(...)
          !NoteProviderRequest.private_logs? && super
        end

        def log_errors?
          !NoteProviderRequest.private_logs? && super
        end
    end

    module StreamLogging
      def log_debug(...)
        super unless NoteProviderRequest.private_logs?
      end
    end
  end
end
