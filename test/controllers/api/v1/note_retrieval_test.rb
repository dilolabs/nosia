require "test_helper"
require_relative "../../../support/note_retrieval_fixtures"

class Api::V1::NoteRetrievalTest < ActionDispatch::IntegrationTest
  include NoteRetrievalFixtures

  setup do
    @token = @first.api_tokens.create!(user: @user, name: "Synthetic Notes API")
    @second.update!(uid: "synthetic-notes-legacy")
  end

  [ false, true ].each do |stream|
    test "matching token retrieves and cites current Notes (stream: #{stream})" do
      ENV["GUARD_MODEL"] = "synthetic-notes-guard"
      with_note_provider do |requests|
        post_completion(stream:)

        assert_completion_response(stream)
        assert_equal 2, requests.count { |request| request["model"] == ENV["GUARD_MODEL"] && provider_text([ request ]).include?("Context:") }
        assert_includes provider_text(requests.select { |request| request["model"] == ENV["GUARD_MODEL"] }), "FIRST_NOTE_MARKER"
        assert_includes provider_text(requests.select { |request| request["stream"] }), "FIRST_NOTE_MARKER"
        assert_includes provider_text(requests), "FIRST_TEXT_MARKER"
        assert_not_includes provider_text(requests), "SECOND_NOTE_MARKER"
        assert_not_includes provider_text(requests), "FOREIGN_NOTE_MARKER"
        assert_includes last_answer.similar_chunks.ids, @first_chunk.id
      end
    end

    test "legacy account switch keeps existing Sources but excludes Notes (stream: #{stream})" do
      ENV["GUARD_MODEL"] = "synthetic-notes-guard"
      with_note_provider do |requests|
        post_completion(stream:, user: @second.uid)

        assert_completion_response(stream)
        assert_includes provider_text(requests), "SECOND_TEXT_MARKER"
        assert_no_note_context(requests)
        assert_equal [ @second_text.id ], last_answer.similar_chunks.ids
      end
    end

    test "retained token without membership keeps existing Sources but excludes Notes (stream: #{stream})" do
      @first.account_users.find_by!(user: @user).destroy!
      ENV["GUARD_MODEL"] = "synthetic-notes-guard"
      with_note_provider do |requests|
        post_completion(stream:)

        assert_completion_response(stream)
        assert_includes provider_text(requests), "FIRST_TEXT_MARKER"
        assert_no_note_context(requests)
        assert_equal [ @first_text.id ], last_answer.similar_chunks.ids
      end
    end

    test "membership revoked at ranking leaves the top result available to Text (stream: #{stream})" do
      ENV["RETRIEVAL_FETCH_K"] = "1"
      membership = @first.account_users.find_by!(user: @user)
      revoked = false
      revoke_before_rank = ->(sql) do
        next if revoked || !sql.include?("AS neighbor_distance")

        revoked = true
        AccountUser.find(membership.id).destroy!
      end

      with_note_provider do |requests|
        with_note_sql_barrier(before: revoke_before_rank) { post_completion(stream:) }

        assert revoked, "expected membership revocation immediately before ranking SQL"
        assert ApiToken.exists?(@token.id), "test covers legacy access through a retained token"
        assert_completion_response(stream)
        assert_includes provider_text(requests), "FIRST_TEXT_MARKER"
        assert_no_note_context(requests)
        assert_equal [ @first_text.id ], last_answer.similar_chunks.ids
      end
    end

    test "a Faraday retry drops a Note after membership is revoked (stream: #{stream})" do
      membership_id = @first.account_users.find_by!(user: @user).id
      failed = false
      fail_before_delivery = ->(_request) do
        next if failed

        failed = true
        AccountUser.find(membership_id).destroy!
        raise Faraday::ConnectionFailed, "Synthetic pre-delivery failure"
      end

      with_note_provider(after_request: fail_before_delivery) do |requests|
        post_completion(stream:)

        assert_completion_response(stream)
        assert_equal 2, requests.size
        assert_includes provider_text(requests.first(1)), "FIRST_NOTE_MARKER"
        assert_includes provider_text(requests.last(1)), "FIRST_TEXT_MARKER"
        assert_no_note_context(requests.last(1))
        assert_equal [ @first_text.id ], last_answer.similar_chunk_ids.map(&:to_i)
      end
    end

    test "a source-only Faraday retry keeps the same request (stream: #{stream})" do
      failed = false
      fail_once = ->(_request) do
        next if failed

        failed = true
        raise Faraday::ConnectionFailed, "Synthetic pre-delivery failure"
      end

      with_note_provider(after_request: fail_once) do |requests|
        post_completion(stream:, user: @second.uid)

        assert_completion_response(stream)
        assert_equal 2, requests.size
        assert_equal requests.first, requests.last
        assert_includes provider_text(requests), "SECOND_TEXT_MARKER"
        assert_no_note_context(requests)
      end
    end
  end

  test "token revoked by a separate write during the guard does not send Notes in the completion" do
    ENV["GUARD_MODEL"] = "synthetic-notes-guard"
    revoke_token = ->(request) do
      ApiToken.find(@token.id).destroy! if provider_text([ request ]).include?("Context: FIRST_NOTE_MARKER")
    end

    with_note_provider(after_request: revoke_token) do |requests|
      post_completion(stream: false)

      assert_response :success
      assert_includes provider_text(requests.reject { |request| request["stream"] }), "FIRST_NOTE_MARKER"
      assert_includes provider_text(requests.select { |request| request["stream"] }), "FIRST_TEXT_MARKER"
      assert_no_note_context(requests.select { |request| request["stream"] })
      assert_equal [ @first_text.id ], last_answer.similar_chunks.ids
    end
  end

  test "the relevance guard does not replay a trashed Note on a Faraday retry" do
    ENV["GUARD_MODEL"] = "synthetic-notes-guard"
    failed = false
    fail_first_note_guard_attempt = ->(request) do
      next if failed || !provider_text([ request ]).include?("Context: FIRST_NOTE_MARKER")

      failed = true
      Note.find(@first_note.id).trash
      raise Faraday::ConnectionFailed, "Synthetic pre-delivery failure"
    end

    with_note_provider(after_request: fail_first_note_guard_attempt) do |requests|
      post_completion(stream: false)

      assert_completion_response(false)
      assert_includes provider_text(requests.first(1)), "Context: FIRST_NOTE_MARKER"
      assert_no_note_context(requests.drop(1))
      assert_includes provider_text(requests.select { |request| request["stream"] }), "FIRST_TEXT_MARKER"
      assert_equal [ @first_text.id ], last_answer.similar_chunk_ids.map(&:to_i)
    end
  end

  test "Note completions suppress provider body diagnostics without muting source-only requests" do
    with_provider_debug_log do |log|
      with_note_provider(stream_content: "PRIVATE_PROVIDER_ECHO") do |requests|
        post_completion(stream: true)

        assert_response :success
        assert_includes provider_text(requests), "FIRST_NOTE_MARKER"
        assert_includes response.body, "PRIVATE_PROVIDER_ECHO"
        assert_not_includes log.string, "PRIVATE_PROVIDER_ECHO"
      end

      with_note_provider(stream_content: "ORDINARY_PROVIDER_ECHO") do
        post_completion(stream: false, user: @second.uid)

        assert_response :success
        assert_includes log.string, "SECOND_TEXT_MARKER"
        assert_includes log.string, "ORDINARY_PROVIDER_ECHO"
      end
    end
  end

  test "Note relevance guards do not log provider errors that quote their input" do
    ENV["GUARD_MODEL"] = "synthetic-notes-guard"
    fail_note_guard = ->(request) do
      if provider_text([ request ]).include?("Context: FIRST_NOTE_MARKER")
        raise RubyLLM::BadRequestError, "SYNTHETIC_NOTE_GUARD_ERROR_ECHO"
      end
    end

    with_provider_debug_log do |log|
      with_note_provider(after_request: fail_note_guard) do |requests|
        post_completion(stream: false)

        assert_response :success
        assert_includes provider_text(requests.first(1)), "FIRST_NOTE_MARKER"
        assert_not_includes log.string, "SYNTHETIC_NOTE_GUARD_ERROR_ECHO"
        assert_includes provider_text(requests.select { |request| request["stream"] }), "FIRST_TEXT_MARKER"
      end
    end
  end

  private
    def post_completion(stream:, **legacy)
      post "/v1/chat/completions", params: { model: "synthetic-notes-api", prompt: "Question", stream:, **legacy },
        headers: { "Authorization" => "Bearer #{@token.plain_token}" }, as: :json
    end

    def assert_completion_response(stream)
      assert_response :success
      assert_includes response.body, "Synthetic answer"
      assert_includes response.body, "data: [DONE]" if stream
      assert_not_includes response.body, "NOTE_MARKER"
    end

    def last_answer
      Chat.root.order(:id).last.messages.assistant.last
    end

    def assert_no_note_context(requests)
      %w[FIRST_NOTE_MARKER SECOND_NOTE_MARKER FOREIGN_NOTE_MARKER].each do |marker|
        assert_not_includes provider_text(requests), marker
      end
    end
end
