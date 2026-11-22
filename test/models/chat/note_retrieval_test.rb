require "test_helper"
require_relative "../../support/note_retrieval_fixtures"

class Chat::NoteRetrievalTest < ActiveSupport::TestCase
  include NoteRetrievalFixtures
  uses_transaction :test_a_branch_trashed_after_ranking_never_reaches_the_relevance_provider,
    :test_trashing_a_shared_branch_during_final_assembly_excludes_both_previously_ranked_Notes,
    :test_a_committed_branch_trash_is_seen_by_the_next_provider_transport_attempt

  setup do
    @chat ||= chats(:picker_second_chat)
    @chat.messages.create!(role: :user, content: "Question")
  end

  teardown do
    if @race_models
      [ @first, @second, @foreign, @user, @outsider ].compact.each(&:destroy!)
      RubyLLM::ActiveRecord::Model.where(provider: "openai", model_id: @race_models.values).delete_all
    end
  end

  test "ordinary web job guards and cites Notes in its saved account" do
    ENV["GUARD_MODEL"] = "synthetic-notes-guard"
    with_note_provider do |requests|
      ChatResponseJob.perform_now(@chat.id, "Question")

      assert_includes provider_text(requests.reject { |request| request["stream"] }), "SECOND_NOTE_MARKER"
      assert_includes provider_text(requests.select { |request| request["stream"] }), "SECOND_NOTE_MARKER"
      assert_includes provider_text(requests), "SECOND_TEXT_MARKER"
      assert_not_includes provider_text(requests), "FIRST_NOTE_MARKER"
      assert_not_includes provider_text(requests), "FOREIGN_NOTE_MARKER"
      answer = @chat.messages.assistant.last
      assert_includes answer.similar_chunks.ids, @second_chunk.id
      assert_equal %w[completion embedding], @chat.token_usages.order(:kind).pluck(:kind)
      assert_not_includes @chat.messages.system.pluck(:content).join, "SECOND_NOTE_MARKER"
    end
  end

  test "without trusted turn context, ordinary completion still sends only non-note Sources" do
    with_note_provider do |requests|
      @chat.complete_with_nosia("Question") { |_| }

      assert_equal 1, requests.size
      assert_includes provider_text(requests), "SECOND_TEXT_MARKER"
      assert_not_includes provider_text(requests), "NOTE_MARKER"
    end
  end

  test "the web job raises and logs a safe provider rejection without retaining the response" do
    log = Rails.root.join("log/test.log")
    log_offset = log.size
    with_note_provider(error_response: provider_rejection("SECOND_NOTE_MARKER")) do |requests|
      error = assert_raises(RubyLLM::BadRequestError) { ChatResponseJob.perform_now(@chat.id, "Question") }

      assert_includes provider_text(requests), "SECOND_NOTE_MARKER"
      diagnostics = File.read(log, nil, log_offset)
      assert_includes diagnostics, "Error performing ChatResponseJob"
      assert_not_includes diagnostics, "SECOND_NOTE_MARKER"
      assert_equal "Note-context provider request failed", error.message
      assert_nil error.response
      assert_nil error.cause
      assert_nil error.provider_message
    end
  end

  test "an ordinary source-only provider rejection keeps its original message and response" do
    with_note_provider(error_response: provider_rejection("SECOND_TEXT_MARKER")) do
      error = assert_raises(RubyLLM::BadRequestError) { @chat.complete_with_nosia("Question") { |_| } }

      assert_includes error.message, "SECOND_TEXT_MARKER"
      assert_equal 400, error.response.status
    end
  end

  test "a Faraday parsing error from a Note completion loses its wrapped exception and response" do
    provider_error = ->(_request) do
      raise Faraday::ParsingError.new(JSON::ParserError.new("SECOND_NOTE_MARKER"), { body: "SECOND_NOTE_MARKER" })
    end

    with_note_provider(after_request: provider_error) do |requests|
      error = assert_raises(Faraday::ParsingError) { complete_web_turn }

      assert_includes provider_text(requests), "SECOND_NOTE_MARKER"
      assert_equal "Note-context provider request failed", error.message
      assert_nil error.wrapped_exception
      assert_nil error.response
      assert_nil error.cause
    end
  end

  test "ineligible Notes do not crowd an eligible passage out of top-k" do
    ENV["RETRIEVAL_FETCH_K"] = "1"
    @second_chunk.update!(embedding: other_vector)
    @second_text.update!(embedding: [ 0.0, 1.0 ] + query_vector.drop(2))
    stale = indexed_note(@second, "STALE_GENERATION")
    stale.chunks.sole.update!(metadata: { "position" => 1, "note_generation" => stale.embedding_generation - 1 })
    trashed = indexed_note(@second, "DIRECTLY_TRASHED")
    trashed.trash
    parent = @second.note_folders.create!(name: "Trashed branch")
    child = @second.note_folders.create!(name: "Child", parent:)
    indexed_note(@second, "TRASHED_BRANCH", folder: child)
    parent.trash
    pending = indexed_note(@second, "PENDING_INDEX")
    pending.update!(embedding_status: :pending, embedding_generation: pending.embedding_generation + 1)
    insert_note_chunk(@foreign_note, "FOREIGN_IN_ACCOUNT", account: @second)
    malformed = indexed_note(@second, "MALFORMED_GENERATION")
    malformed.chunks.sole.update!(metadata: { "position" => 1, "note_generation" => "non-numeric" })

    with_note_provider do |requests|
      ChatResponseJob.perform_now(@chat.id, "Question")

      assert_includes provider_text(requests), "SECOND_NOTE_MARKER"
      assert_equal [ @second_chunk.id ], @chat.messages.assistant.last.similar_chunks.ids
    end
  end

  test "adjacent excerpts retain only valid vectors and positions in the same current Note" do
    ENV.update("AUGMENTED_CONTEXT" => "true", "RETRIEVAL_FETCH_K" => "1", "GUARD_MODEL" => "synthetic-notes-guard")
    @second_chunk.update!(metadata: { "position" => 3, "note_generation" => @second_note.embedding_generation })
    insert_note_chunk(@second_note, "CURRENT_NEIGHBOR", position: 2, vector: other_vector)
    insert_note_chunk(@second_note, "DISTANT_NEIGHBOR", position: 6, vector: other_vector)
    insert_note_chunk(@second_note, "STALE_NEIGHBOR", position: 4, generation: 0, vector: other_vector)
    insert_note_chunk(@second_note, "FOREIGN_NEIGHBOR", position: 4, account: @foreign)
    insert_note_chunk(@second_note, "MISSING_VECTOR_NEIGHBOR", position: 4, vector: nil)
    insert_note_chunk(@second_note, "ZERO_VECTOR_NEIGHBOR", position: 4, vector: Array.new(query_vector.size, 0.0))

    with_note_provider do |requests|
      ChatResponseJob.perform_now(@chat.id, "Question")

      assert_equal 3, requests.size
      assert_includes provider_text(requests.reject { |request| request["stream"] }), "CURRENT_NEIGHBOR\nSECOND_NOTE_MARKER"
      assert_includes provider_text(requests.select { |request| request["stream"] }), 'CURRENT_NEIGHBOR\nSECOND_NOTE_MARKER'
      %w[DISTANT STALE FOREIGN MISSING_VECTOR ZERO_VECTOR].each do |excluded|
        assert_not_includes provider_text(requests), "#{excluded}_NEIGHBOR"
      end
    end
  end

  test "a branch trashed after ranking never reaches the relevance provider" do
    ENV["GUARD_MODEL"] = @race_models.fetch(:guard)
    folder = @second.note_folders.create!(name: "Previously active")
    @second_note.move_to(folder)
    indexed_note(@second, "UNAFFECTED_NOTE_MARKER")
    broadcast = @chat.method(:broadcast_thinking_phase)
    trash_folder = method(:trash_on_another_connection)
    @chat.define_singleton_method(:broadcast_thinking_phase) do |phase|
      broadcast.call(phase)
      trash_folder.call(folder) if phase == "retrieving"
    end

    with_note_provider do |requests|
      complete_web_turn

      assert_includes provider_text(requests), "SECOND_TEXT_MARKER"
      assert_includes provider_text(requests), "UNAFFECTED_NOTE_MARKER"
      assert_not_includes provider_text(requests), "SECOND_NOTE_MARKER"
    end
  end

  test "an edit during tool discovery does not send a previously guarded excerpt to completion" do
    ENV["GUARD_MODEL"] = "synthetic-notes-guard"
    note_id = @second_note.id
    @chat.define_singleton_method(:with_mcp_tools) do |&turn|
      note = Note.find(note_id)
      note.edit_content!(expected_revision: note.content_revision, title: note.title, body_html: "<p>New text pending</p>")
      turn.call
    end

    with_note_provider do |requests|
      complete_web_turn

      assert_includes provider_text(requests.reject { |request| request["stream"] }), "SECOND_NOTE_MARKER"
      assert_includes provider_text(requests.select { |request| request["stream"] }), "SECOND_TEXT_MARKER"
      assert_not_includes provider_text(requests.select { |request| request["stream"] }), "SECOND_NOTE_MARKER"
      assert_equal [ @second_text.id ], @chat.messages.assistant.last.similar_chunks.ids
    end
  end

  test "trashing a shared branch during final assembly excludes both previously ranked Notes" do
    ENV["GUARD_MODEL"] = @race_models.fetch(:guard)
    folder = @second.note_folders.create!(name: "Shared branch")
    @second_note.move_to(folder)
    indexed_note(@second, "SHARED_BRANCH_MARKER", folder:, vector: other_vector)
    final_assembly = trashed = false
    broadcast = @chat.method(:broadcast_thinking_phase)
    @chat.define_singleton_method(:broadcast_thinking_phase) do |phase|
      broadcast.call(phase)
      final_assembly = true if phase == "generating"
    end
    trash_after_first_eligible_read = ->(sql) do
      next unless final_assembly && !trashed && sql.include?("vector_norm(chunks.embedding)")

      trashed = true
      trash_on_another_connection(folder)
    end

    with_note_provider do |requests|
      with_note_sql_barrier(after: trash_after_first_eligible_read) { complete_web_turn }

      assert trashed, "expected a branch change between excerpt loading and completion"
      guard, completion = requests.partition { |request| !request["stream"] }
      %w[SECOND_NOTE_MARKER SHARED_BRANCH_MARKER].each do |marker|
        assert_includes provider_text(guard), marker
        assert_not_includes provider_text(completion), marker
      end
      assert_includes provider_text(completion), "SECOND_TEXT_MARKER"
      assert_equal [ @second_text.id ], @chat.messages.assistant.last.similar_chunk_ids.map(&:to_i)
    end
  end

  test "a committed branch trash is seen by the next provider transport attempt" do
    folder = @second.note_folders.create!(name: "Race branch")
    @second_note.move_to(folder)
    failed = false
    fail_once = ->(_request) do
      next if failed

      failed = true
      trash_on_another_connection(folder)
      raise Faraday::ConnectionFailed, "Synthetic pre-delivery failure"
    end

    with_note_provider(after_request: fail_once) do |requests|
      complete_web_turn

      assert_equal 2, requests.size
      assert_includes provider_text(requests.first(1)), "SECOND_NOTE_MARKER"
      assert_not_includes provider_text(requests.last(1)), "SECOND_NOTE_MARKER"
      assert_includes provider_text(requests.last(1)), "SECOND_TEXT_MARKER"
      assert_equal [ @second_text.id ], @chat.messages.assistant.last.similar_chunk_ids.map(&:to_i)
    end
  end

  test "an SDK tool follow-up does not replay an excerpt after the Note is trashed" do
    note_id = @second_note.id
    tool = Class.new(RubyLLM::Tool) do
      def name = "test_note_change"
      define_method(:execute) { Note.find(note_id).trash; "Synthetic tool result" }
    end
    @chat.define_singleton_method(:with_mcp_tools) do |&turn|
      with_tools(tool.new)
      turn.call
    end

    with_note_provider(tools_on_first_completion: true) do |requests|
      complete_web_turn

      assert_equal 2, requests.size
      assert_includes provider_text([ requests.first ]), "SECOND_NOTE_MARKER"
      assert_includes provider_text([ requests.last ]), "Synthetic tool result"
      assert_includes provider_text([ requests.last ]), "SECOND_TEXT_MARKER"
      assert_not_includes provider_text([ requests.last ]), "SECOND_NOTE_MARKER"
    end
  end

  test "executable skills receive no Note capability, but the ordinary fallback gets it" do
    skill_context = nil
    execute = ->(_skill, context:) do
      skill_context = context
      nil
    end

    with_note_provider do |requests|
      with_singleton_replacement(AgentSkill::Executor, :execute, execute) do
        @chat.complete_with_agent_skills("/second-skill", note_access: Chat::NoteRetrieval.web)
      end
      assert_includes provider_text(requests), "SECOND_NOTE_MARKER"
      assert_equal({}, skill_context.fetch(:options))
    end
  end

  test "the ordinary fallback when skills are enabled retains the web Note capability" do
    settings = Rails.application.config.agent_skills
    original = settings.enabled
    settings.enabled = true

    with_note_provider do |requests|
      complete_web_turn

      assert_includes provider_text(requests), "SECOND_NOTE_MARKER"
    end
  ensure
    settings.enabled = original
  end

  private
    def set_up_picker_accounts
      return super unless self.class.uses_transaction?(name)

      # These examples commit with a second connection. Never load a shared
      # fixture set outside its usual rollback or remove its model/users.
      key = SecureRandom.hex(6)
      @race_models = { completion: "synthetic-completion-#{key}", guard: "synthetic-guard-#{key}" }
      @race_models.each_value do |model_id|
        RubyLLM::ActiveRecord::Model.create!(model_id:, provider: "openai", name: model_id)
      end
      @user = User.create!(email: "notes-owner-#{key}@example.com", password: ChatAccountFixtures::PASSWORD)
      @outsider = User.create!(email: "notes-outsider-#{key}@example.com", password: ChatAccountFixtures::PASSWORD)
      @first = isolated_account(@user, "First account")
      @second = isolated_account(@user, "Research account")
      @foreign = isolated_account(@outsider, "Foreign account")
      @isolated_texts = { first: @first.texts.create!(data: "First Text"), second: @second.texts.create!(data: "Second Text") }
      @chat = @second.chats.create!(user: @user, model: @race_models.fetch(:completion), provider: :openai, assume_model_exists: true)
      model = @race_models.fetch(:completion)
      @chat.define_singleton_method(:default_options) { super().merge(model:) }
    end

    def isolated_account(user, name)
      Account.create!(owner: user, name:).tap do |account|
        account.account_users.grant_to(user)
        account.prompts.create!(name: "system_prompt", content: "Synthetic prompt %{documents}")
      end
    end

    def trash_on_another_connection(folder)
      Thread.new { NoteFolder.with_connection { NoteFolder.find(folder.id).trash } }.value
    end

    def complete_web_turn
      find_chat = Chat.method(:find)
      chat = @chat
      with_singleton_replacement(Chat, :find, ->(id) { id == chat.id ? chat : find_chat.call(id) }) do
        ChatResponseJob.perform_now(chat.id, "Question")
      end
    end
end
