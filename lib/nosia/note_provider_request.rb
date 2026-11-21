module Nosia
  # Keeps Note excerpts out of the request body saved for RubyLLM's transport retries.
  module NoteProviderRequest
    REFRESH = :@nosia_note_refresh
    PRIVATE_LOGS = :nosia_note_private_logs
    private_constant :REFRESH, :PRIVATE_LOGS

    # @param payload [Hash] The Note-free request to keep between attempts.
    # @yieldparam attempt [Hash] A fresh copy, reauthorized just before encoding.
    def self.refresh_each_attempt(payload, &refresh)
      payload.instance_variable_set(REFRESH, refresh)
    end

    def self.with_private_logs(payload)
      previous = Fiber[PRIVATE_LOGS]
      Fiber[PRIVATE_LOGS] = payload.instance_variable_defined?(REFRESH)
      yield
    ensure
      Fiber[PRIVATE_LOGS] = previous
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
      def complete_request(payload, ...)
        # The outer logger also receives responses and errors on unwind, so
        # suppress diagnostics for this whole model request, not just the send.
        NoteProviderRequest.with_private_logs(payload) { super }
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
