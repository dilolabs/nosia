# Enforces wire limits for Notes import writes before middleware can parse their bodies.
class NotesImportRequestLimit
  # Match Journey's default parameter and optional format segments, including encoded IDs.
  WRITE_PATH = %r{\A/accounts/[^./?]+/note-imports(?:/[^./?]+/(?<part>batches|seal))?(?:\.[^./?]+)?\z}
  READ_PATH = %r{\A/accounts/[^./?]+/note-imports/[^./?]+(?:\.[^./?]+)?\z}
  LIMITS = { nil => 1.megabyte, "batches" => 4.megabytes, "seal" => 16.kilobytes }.freeze
  BODY_FIELDS = { nil => %w[confirmation_key root_name files ignored_counts], "batches" => %w[entries], "seal" => [] }.freeze
  JSON_TYPE = %r{\Aapplication/json(?:[ \t]*;[ \t]*charset=(?:UTF-8|"UTF-8"))?[ \t]*\z}i
  MULTIPART_TYPE = %r{\Amultipart/form-data[ \t]*;[ \t]*boundary=(?:[a-z0-9'+_.-]{1,70}|"[a-z0-9'()+_,./:=? \-]{0,69}[a-z0-9'()+_,./:=?\-]")\z}i

  class TooManyFiles < StandardError; end
  private_constant :TooManyFiles

  # @param app [#call] Downstream Rack application.
  # @param filters [Array<Regexp>] Redaction applied only to private import requests.
  def initialize(app, filters)
    @app, @filters = app, filters
    @parse_logger = ActiveSupport::Logger.new(nil)
  end

  # @param env [Hash] Rack request environment.
  # @return [Array] Rack response.
  def call(env)
    path = ActionDispatch::Journey::Router::Utils.normalize_path(env["PATH_INFO"])

    if env["REQUEST_METHOD"] == "POST" && (match = WRITE_PATH.match(path))
      write(env, match[:part])
    elsif %w[GET HEAD].include?(env["REQUEST_METHOD"]) && READ_PATH.match?(path)
      private_request(env) { |request| request.request_parameters = {}.with_indifferent_access }
    else
      @app.call(env)
    end
  end

  private
    def write(env, part)
      if (error = request_error(env, part))
        reject(env, *error)
      else
        private_request(env) do |request|
          body = part == "batches" ? parse_batch(request) : parse_json(request)
          # Redaction hides values, not keys. Discard arbitrary top-level keys
          # before controller instrumentation, retaining Rails' CSRF field.
          request.request_parameters = body.slice(*BODY_FIELDS.fetch(part), "authenticity_token")
        end
      end
    end

    def request_error(env, part)
      length = env["CONTENT_LENGTH"]
      return [ 411, :length_required ] if length.nil? || length == ""
      return [ 400, :invalid_length ] if env.key?("HTTP_TRANSFER_ENCODING") || !length.is_a?(String) || !/\A0*[1-9][0-9]*\z/.match?(length)
      return [ 413, :payload_too_large ] if length.to_i > LIMITS.fetch(part)

      expected_type = part == "batches" ? MULTIPART_TYPE : JSON_TYPE
      [ 415, :unsupported_media_type ] unless expected_type.match?(env["CONTENT_TYPE"])
    end

    def private_request(env)
      env["action_dispatch.parameter_filter"] = @filters
      # These requests have no query inputs. Do not log even malformed query strings.
      env["QUERY_STRING"] = ""
      yield ActionDispatch::Request.new(env)
      status, headers, body = @app.call(env)
      [ status, headers.merge("cache-control" => "no-store"), body ]
    rescue ActionDispatch::Http::Parameters::ParseError, ActionController::BadRequest, Rack::BadRequest
      reject(env, 400, :invalid_request)
    rescue TooManyFiles
      reject(env, 422, :invalid_batch)
    end

    def parse_json(request)
      # Action Dispatch debug-logs the unfiltered body on a JSON parse failure.
      logger = request.logger
      request.set_header("action_dispatch.logger", @parse_logger)
      request.request_parameters
    ensure
      request.set_header("action_dispatch.logger", logger)
    end

    def parse_batch(request)
      # Bound all file parts, even ones Rails might discard when building params.
      # Rack::TempfileReaper takes over once parsing succeeds.
      files = []
      factory_key = Rack::RACK_MULTIPART_TEMPFILE_FACTORY
      factory = request.get_header(factory_key)
      request.set_header(factory_key, ->(*) do
        raise TooManyFiles if files.size >= NoteImport::MAX_BATCH_FILES

        file = factory ? factory.call("upload", "application/octet-stream") : Tempfile.new("notes-import")
        files << file
        file
      end)
      body = request.request_parameters
      parsed = true
      body
    ensure
      request.set_header(factory_key, factory)
      files.each(&:close!) unless parsed
    end

    def reject(env, status, code)
      locale = LanguagePreference.resolve(override: nil, header: env["HTTP_ACCEPT_LANGUAGE"])
      body = { error: code, message: I18n.t("nosia.notes.imports.errors.#{code}", locale:) }.to_json
      [ status, { "content-type" => "application/json", "cache-control" => "no-store", "content-language" => locale.to_s }, [ body ] ]
    end
end
