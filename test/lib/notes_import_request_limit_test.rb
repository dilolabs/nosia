require "test_helper"

class NotesImportRequestLimitTest < ActiveSupport::TestCase
  IMPORTS_PATH = "/accounts/42/note-imports"
  BATCHES_PATH = "#{IMPORTS_PATH}/7/batches"
  SEAL_PATH = "#{IMPORTS_PATH}/7/seal"
  JSON_TYPE = "application/json"
  MULTIPART_TYPE = "multipart/form-data; boundary=RackTestBoundary"

  test "rejects missing and malformed content lengths without reading input" do
    [ nil, "" ].each do |length|
      assert_rejected(411, "length_required", length:)
    end
    [ "-1", "0", "+1", "1e6", "2, 2", " 2", "2 ", "abc" ].each do |length|
      assert_rejected(400, "invalid_length", length:)
    end
    assert_rejected 400, "invalid_length", length: "2", extra: { "HTTP_TRANSFER_ENCODING" => "chunked" }
  end

  test "each request uses its own inclusive wire budget" do
    { IMPORTS_PATH => [ 1.megabyte, JSON_TYPE ], BATCHES_PATH => [ 4.megabytes, MULTIPART_TYPE ],
      SEAL_PATH => [ 16.kilobytes, JSON_TYPE ] }.each do |path, (limit, content_type)|
      assert_rejected(413, "payload_too_large", path:, length: (limit + 1).to_s, content_type:)
      assert_forwarded(path:, length: limit.to_s, content_type:)
    end
    assert_rejected 413, "payload_too_large", length: "9" * 100
  end

  test "requires the appropriate MIME type and a usable multipart boundary" do
    assert_rejected 415, "unsupported_media_type", content_type: "text/plain"
    assert_rejected 415, "unsupported_media_type", path: SEAL_PATH, content_type: nil
    [
      JSON_TYPE, "multipart/form-data", "multipart/form-data; boundary=", "multipart/form-data; boundary=\"abc",
      "multipart/form-data; boundary=\"a\nb\"", "multipart/form-data; boundary=#{'x' * 71}",
      "multipart/form-data; boundary=first; boundary=second"
    ].each do |content_type|
      assert_rejected(415, "unsupported_media_type", path: BATCHES_PATH, content_type:)
    end
    assert_forwarded path: BATCHES_PATH, length: "22", content_type: 'multipart/form-data; boundary="RackTestBoundary"'
    assert_forwarded content_type: "application/json; charset=UTF-8"
  end

  test "matches Rails path normalization and leaves unrelated requests untouched" do
    assert_rejected 411, "length_required", path: "/accounts//%34%32/note-imports.json/", length: nil
    assert_rejected 411, "length_required", path: "#{BATCHES_PATH}.json//", length: nil
    assert_rejected 411, "length_required", path: "#{SEAL_PATH}.xml", length: nil

    [ "/accounts/42/notes", "/note-imports", "#{IMPORTS_PATH}/new",
      "#{BATCHES_PATH}/other", "#{IMPORTS_PATH}-elsewhere" ].each do |path|
      assert_forwarded path:, length: nil, content_type: nil
    end
    assert_forwarded method: "GET", length: nil, content_type: nil
  end

  private
    def assert_rejected(status, code, **options)
      middleware = NotesImportRequestLimit.new(->(*) { flunk "Rejected request reached downstream middleware" }, [ /\A/ ])
      actual_status, headers, body = middleware.call(request_env(**options))
      assert_equal status, actual_status
      assert_equal "no-store", headers.fetch("cache-control")
      assert_equal code, JSON.parse(body.join).fetch("error")
    end

    def assert_forwarded(**options)
      forwarded = [ 204, {}, [] ]
      env = request_env(**options)
      if env["CONTENT_TYPE"]&.start_with?(JSON_TYPE)
        env["rack.input"] = StringIO.new("{}")
      elsif env["CONTENT_TYPE"]&.start_with?("multipart/form-data")
        env["rack.input"] = StringIO.new("--RackTestBoundary--\r\n")
      end
      middleware = NotesImportRequestLimit.new(->(received) { assert_same env, received; forwarded }, [ /\A/ ])
      assert_equal 204, middleware.call(env).first
    end

    def request_env(path: IMPORTS_PATH, method: "POST", length: "2", content_type: JSON_TYPE, extra: {})
      input = Object.new
      input.define_singleton_method(:read) { |*| raise "request body must not be consumed" }
      { "REQUEST_METHOD" => method, "PATH_INFO" => path, "CONTENT_LENGTH" => length,
        "CONTENT_TYPE" => content_type, "rack.input" => input }.merge(extra)
    end
end
