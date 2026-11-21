require "test_helper"
require_relative "../../support/note_retrieval_fixtures"

class Chat::NoteRetrievalTest < ActiveSupport::TestCase
  include NoteRetrievalFixtures
  uses_transaction :test_a_branch_trashed_after_ranking_never_reaches_the_relevance_provider

  setup do
    @chat = chats(:picker_second_chat)
    @chat.messages.create!(role: :user, content: "Question")
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
    ENV["GUARD_MODEL"] = "synthetic-notes-guard"
    provider_models = RubyLLM::ActiveRecord::Model.where(model_id: [ ENV["LLM_MODEL"], ENV["GUARD_MODEL"] ], provider: "openai")
    original_model_ids = provider_models.ids
    folder = @second.note_folders.create!(name: "Previously active")
    @second_note.move_to(folder)
    indexed_note(@second, "UNAFFECTED_NOTE_MARKER")
    broadcast = @chat.method(:broadcast_thinking_phase)
    @chat.define_singleton_method(:broadcast_thinking_phase) do |phase|
      broadcast.call(phase)
      if phase == "retrieving"
        Thread.new { NoteFolder.with_connection { NoteFolder.find(folder.id).trash } }.value
      end
    end

    with_note_provider do |requests|
      complete_web_turn

      assert_includes provider_text(requests), "SECOND_TEXT_MARKER"
      assert_includes provider_text(requests), "UNAFFECTED_NOTE_MARKER"
      assert_not_includes provider_text(requests), "SECOND_NOTE_MARKER"
    end
  ensure
    Account.where(id: [ @first.id, @second.id, @foreign.id ]).destroy_all
    User.where(id: [ @user.id, users(:picker_outsider).id ]).destroy_all
    provider_models.where.not(id: original_model_ids).delete_all
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
    def complete_web_turn
      find_chat = Chat.method(:find)
      chat = @chat
      with_singleton_replacement(Chat, :find, ->(id) { id == chat.id ? chat : find_chat.call(id) }) do
        ChatResponseJob.perform_now(chat.id, "Question")
      end
    end
end
