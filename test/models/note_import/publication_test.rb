require "test_helper"
require_relative "../../support/note_import_test_support"

class NoteImportPublicationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include NoteImportTestSupport

  self.use_transactional_tests = false
  self.fixture_paths = [ Rails.root.join("test/support/fixtures/chat_accounts") ]
  fixtures :users, :accounts, :account_users

  setup do
    @initiator = users(:picker_owner)
    @account = Account.create!(owner: @initiator, name: "Disposable Notes import")
    @account.account_users.grant_to(@initiator)
  end

  teardown do
    @account&.destroy!
    ActiveRecord::FixtureSet.reset_cache
  end

  test "two confirmations publish independent trees with canonical Notes and stable links" do
    paths = Rails.application.routes.url_helpers
    files = {
      "Accueil.md" => "A searchable paragraph **with formatting** and #voyage.\n\n[[Carnet/Archive/Réunion|Meeting]] [[Accueil]] [[Missing]]",
      "Carnet/Archive/Réunion.md" => "[Back](../../Accueil.md) [[Accueil]]"
    }
    results = 2.times.map do |index|
      import = sealed_import(files)
      assert enqueued_jobs.empty? if index.zero?

      assert_enqueued_jobs 2, only: Note::IndexJob do
        NoteImport::PublishJob.perform_now(import.id)
      end

      root = @account.note_folders.find(import.reload.root_note_folder_id)
      archive = root.children.sole.children.sole
      assert_equal [ "Carnet", "Archive" ], [ archive.parent.name, archive.name ]
      home = @account.notes.find_by!(note_folder: root)
      meeting = @account.notes.find_by!(note_folder: archive)
      assert_equal [ "Accueil", "Réunion" ], [ home.title, meeting.title ]
      assert_equal [ 1, 1 ], [ home.content_revision, meeting.content_revision ]
      assert_includes home.body_html, "<strong>with formatting</strong>"
      assert_equal [ "voyage" ], home.note_tags.pluck(:key)
      assert_equal [ home.id ], Note.active_in(@account.id).where(note_folder: root).search_literal("searchable paragraph").ids
      home_href = paths.account_note_path(@account, home)
      meeting_href = paths.account_note_path(@account, meeting)
      assert_equal [ meeting_href, home_href ], Nokogiri::HTML5.fragment(home.body_html).css("a").map { |link| link["href"] }
      assert_equal [ home_href, home_href ], Nokogiri::HTML5.fragment(meeting.body_html).css("a").map { |link| link["href"] }
      assert_predicate import, :succeeded?
      assert_nil import.claim_token
      assert_nil import.claim_expires_at
      assert_equal({
        "root_name" => index.zero? ? "Coffre" : "Coffre (2)", "note_count" => 2, "folder_count" => 3,
        "ignored_counts" => { "obsidian" => 0, "other" => 0 }, "unresolved_count" => 1,
        "unresolved_examples" => [ { "path" => "Accueil.md", "target" => "Missing" } ]
      }, import.report)
      assert_empty import.staged_files
      [ root, home, meeting ]
    end
    assert_empty(results.first & results.last)
  end

  test "root allocation respects active NFC names, trashed roots and a lazy General" do
    active = @account.note_folders.create!(name: "Cafe\u0301")
    trashed = @account.note_folders.create!(name: "Café (2)")
    trashing = NoteFolderTrashing.create!(note_folder: trashed)
    assert_empty @account.note_folders.where(system_key: NoteFolder::GENERAL_SYSTEM_KEY)

    [ [ "Café", "Café (3)" ], [ "General", "General (2)" ] ].each do |requested, assigned|
      import = sealed_import(root_name: requested)
      NoteImport::PublishJob.perform_now(import.id)
      assert_equal assigned, @account.note_folders.find(import.reload.root_note_folder_id).name
    end
    assert_equal "Cafe\u0301", active.reload.name
    assert_predicate trashing.reload, :persisted?
    assert_equal "General", @account.general_note_folder.name
  end

  test "suffix truncation preserves UTF-8 character boundaries and finds the first free name" do
    stem = "é" * 127 + "x"
    @account.note_folders.create!(name: stem)
    @account.note_folders.create!(name: "#{'é' * 125} (3)")
    import = sealed_import(root_name: stem)

    NoteImport::PublishJob.perform_now(import.id)

    name = @account.note_folders.find(import.reload.root_note_folder_id).name
    assert_equal "#{'é' * 125} (2)", name
    assert_operator name.bytesize, :<=, 255
    assert_predicate name, :valid_encoding?
  end

  test "a rejected note rolls back an earlier note, its tags, the whole branch and index handoff" do
    import = sealed_import({ "A.md" => "# Heading\n\n#rollbacktag", "Nested/.md" => "" })
    inserts = []
    observe_insert = ->(event) do
      inserts << event.payload.fetch(:sql) if event.payload.fetch(:sql).start_with?('INSERT INTO "notes"')
    end

    assert_no_enqueued_jobs(only: Note::IndexJob) do
      assert_no_difference [ "@account.notes.count", "@account.note_folders.count", "NoteTag.count", "NoteTagging.count" ] do
        ActiveSupport::Notifications.subscribed(observe_insert, "sql.active_record") do
          NoteImport::PublishJob.perform_now(import.id)
        end
      end
    end
    assert_equal 1, inserts.size, "the valid note must be saved before the rejected one"
    assert_predicate import.reload, :failed?
    assert_equal({ "error" => "publication_failed" }, import.report)
    assert_nil import.root_note_folder_id
    assert_empty import.staged_files
  end

  test "index handoff sees the committed receipt and a refusal does not change import success" do
    import = sealed_import
    adapter = Note::IndexJob.queue_adapter
    observed = []
    other_session = method(:in_another_session)
    adapter.define_singleton_method(:enqueue_at) do |job, _timestamp|
      observed << other_session.call do
        note = Note.find(job.arguments.first)
        [ note.note_folder_id, NoteImport.find(import.id).root_note_folder_id ]
      end
      raise ActiveJob::EnqueueError, "private adapter details"
    end

    NoteImport::PublishJob.perform_now(import.id)

    assert_predicate import.reload, :succeeded?
    assert_equal [ [ import.root_note_folder_id, import.root_note_folder_id ] ], observed
    assert_predicate @account.notes.sole, :embedding_failed?
  ensure
    adapter&.singleton_class&.remove_method(:enqueue_at)
  end

  test "prepared templates have an import-wide budget before the account is locked" do
    import = sealed_import({ "A.md" => "x" * 30, "B.md" => "y" * 30 })
    publication_writes = []
    observer = ->(event) do
      publication_writes << event.payload[:sql] if event.payload[:sql].start_with?('INSERT INTO "note_folders"')
    end

    with_render_budget(64) do
      ActiveSupport::Notifications.subscribed(observer, "sql.active_record") do
        NoteImport::PublishJob.perform_now(import.id)
      end
    end

    assert_empty publication_writes
    assert_equal({ "error" => "rendered_total_size_exceeded" }, import.reload.report)
  end

  test "expanded links have a separate import-wide budget and discard prior writes" do
    import = sealed_import({ "A.md" => "[[B]]", "B.md" => "[[A]]" })
    id = 2_000_000_000 # Conservatively budget for at most ten decimal digits here.
    href = Rails.application.routes.url_helpers.account_note_path(@account, id)
    final_note_size = %(<p><a href="#{href}">B</a></p>\n).bytesize

    with_render_budget(final_note_size + 10) do
      assert_no_enqueued_jobs(only: Note::IndexJob) do
        assert_no_difference [ "@account.notes.count", "@account.note_folders.count" ] do
          NoteImport::PublishJob.perform_now(import.id)
        end
      end
    end

    assert_equal({ "error" => "rendered_total_size_exceeded" }, import.reload.report)
  end

  test "unresolved examples are capped across documents without capping the count" do
    import = sealed_import({ "A.md" => "[[Missing]] " * 80, "B.md" => "[[Missing]] " * 40 })

    NoteImport::PublishJob.perform_now(import.id)

    report = import.reload.report
    assert_equal 120, report.fetch("unresolved_count")
    assert_equal({ "A.md" => 80, "B.md" => 20 }, report.fetch("unresolved_examples").map { |example| example.fetch("path") }.tally)
  end

  private
    def with_render_budget(bytes)
      converter = NoteImport::Markdown
      original = converter::MAX_TOTAL_RENDERED_BYTES
      converter.send(:remove_const, :MAX_TOTAL_RENDERED_BYTES)
      converter.const_set(:MAX_TOTAL_RENDERED_BYTES, bytes)
      yield
    ensure
      converter.send(:remove_const, :MAX_TOTAL_RENDERED_BYTES)
      converter.const_set(:MAX_TOTAL_RENDERED_BYTES, original)
    end
end
