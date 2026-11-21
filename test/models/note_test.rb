require "test_helper"

class NoteTest < ActiveSupport::TestCase
  self.fixture_paths = [ Rails.root.join("test/support/fixtures/chat_accounts") ]
  fixtures :users, :accounts, :note_folders, :notes

  setup do
    @account = accounts(:picker_first)
    @folder = note_folders(:research)
    @note = notes(:field_notes)
  end

  test "current body governs normalized hashtags and literal search" do
    note = save_draft(title: "Research 100%",
      body_html: "<p>#Réunion #réunion</p><pre>#code</pre><p><a href='https://example.invalid/#url'>link</a></p>")

    assert_equal [ "réunion" ], note.note_tags.pluck(:key)
    active = Note.active_in(@account.id)
    assert_equal [ note.id ], active.search_literal("  RESEARCH 100% ").ids
    assert_empty active.search_literal("100_")
    assert_equal [ note.id ], active.search_literal("RÉUNION").ids

    travel 1.minute do
      note.edit_content!(expected_revision: 1, title: "Research", body_html: "<p>No tags</p>")
      assert_equal 2, note.content_revision
      assert_in_delta Time.current, note.content_updated_at, 0.01
    end
    assert_empty note.note_tags.reload
    assert_empty active.search_literal("réunion")
    assert_equal [ note.id ], active.search_literal("No tags").ids
    assert_raises(Note::EditConflict) do
      note.edit_content!(expected_revision: 1, title: "Old tab", body_html: "<p>Old #tag</p>")
    end
    assert_equal "Research", note.reload.title
    assert_equal "No tags", note.body_text
    assert_empty note.note_tags
  end

  test "literal search matches escaped characters without searching markup or destinations" do
    note = save_draft(title: "code_42\\notes", body_html: '<p><a href="/hidden-path">Visible text</a></p>')

    assert_equal [ note.id ], Note.active_in(@account.id).search_literal("_42\\").ids
    assert_empty Note.active_in(@account.id).search_literal("hidden-path")
  end

  test "canonical first-save replay never mutates content and the key is account scoped" do
    draft_key = @note.draft_key
    replay = nil
    assert_no_difference -> { @account.notes.count } do
      replay = save_draft(folder: @note.note_folder, draft_key:, title: " Field notes ",
        body_html: '<p class="editor">Interview outline</p>')
    end

    assert_equal @note, replay
    assert_equal @note.content_updated_at, replay.content_updated_at
    assert_equal 1, replay.content_revision
    assert_not_equal replay, notes(:second_team_note)
    assert_equal draft_key, notes(:second_team_note).draft_key
  end

  test "reposting a newly saved draft returns the original note and tag links" do
    draft_key = SecureRandom.uuid
    original = save_draft(draft_key:, body_html: "<p>#original</p>")

    assert_no_difference [ "Note.count", "NoteTagging.count" ] do
      replay = save_draft(draft_key:, body_html: "<p>#original</p>")
      assert_equal original.id, replay.id
      assert_equal original.content_updated_at, replay.content_updated_at
      assert_equal 1, replay.content_revision
    end
  end

  test "first-save replay conflicts with different content or a later revision" do
    params = { folder: @note.note_folder, draft_key: @note.draft_key, title: @note.title, body_html: @note.body_html }

    assert_raises(Note::EditConflict) { save_draft(**params.merge(title: "Different")) }
    assert_raises(Note::EditConflict) { save_draft(**params.merge(body_html: "<p>Different</p>")) }
    other_editor = @account.notes.find(@note.id)
    other_editor.edit_content!(expected_revision: 1, title: "Member's change", body_html: "<p>#approved</p>")

    assert_raises(Note::EditConflict) { save_draft(**params) }
    assert_raises(Note::EditConflict) { save_draft(**params.merge(title: other_editor.title, body_html: other_editor.body_html)) }
    assert_equal "Member's change", @note.reload.title
    assert_equal [ "approved" ], @note.note_tags.pluck(:key)
  end

  test "a new draft only saves into an active folder owned by the account" do
    note_folders(:sessions).create_trashing!

    assert_no_difference -> { @account.notes.count } do
      assert_raises(ActiveRecord::RecordInvalid) { save_draft(folder: note_folders(:private)) }
      assert_raises(ActiveRecord::RecordInvalid) { save_draft(folder: note_folders(:interviews)) }
      assert_raises(ActiveRecord::RecordInvalid) { save_draft(folder: @account.note_folders.build(name: "Unsaved")) }
    end
  end

  test "replaying an active draft still rejects a foreign destination" do
    assert_raises(ActiveRecord::RecordInvalid) do
      save_draft(folder: note_folders(:private), draft_key: @note.draft_key, title: @note.title, body_html: @note.body_html)
    end
  end

  test "a note covered by branch trash cannot be edited or replayed" do
    note_folders(:sessions).create_trashing!

    assert_raises(Note::Unavailable) do
      @note.edit_content!(expected_revision: 1, title: "Hidden", body_html: "")
    end
    assert_raises(Note::Unavailable) do
      save_draft(folder: @note.note_folder, draft_key: @note.draft_key, title: @note.title, body_html: @note.body_html)
    end
    assert_equal "Field notes", @note.reload.title
    refute_includes Note.active_in(@account.id), @note
  end

  test "a directly trashed note cannot be edited or replayed" do
    @note.create_trashing!

    assert_raises(Note::Unavailable) do
      @note.edit_content!(expected_revision: 1, title: "Hidden", body_html: "")
    end
    assert_raises(Note::Unavailable) do
      save_draft(folder: @note.note_folder, draft_key: @note.draft_key, title: @note.title, body_html: @note.body_html)
    end
    refute_includes Note.active_in(@account.id), @note
  end

  test "a new draft needs a UUID and meaningful sanitized body or title" do
    assert_raises(ActiveRecord::RecordInvalid) { save_draft(draft_key: "not-a-uuid") }
    assert_raises(ActiveRecord::RecordInvalid) { save_draft(draft_key: [ SecureRandom.uuid ]) }
    assert_raises(ActiveRecord::RecordInvalid) do
      save_draft(title: " \t", body_html: '<p>&nbsp;<br></p><img src="/picture"><script>not visible</script>')
    end

    assert_equal "Title only", save_draft(title: " Title only ", body_html: "").title
    assert_equal "Body only", save_draft(title: "", body_html: "<p>Body only</p>").body_text
  end

  test "malformed content is rejected instead of being coerced during persistence" do
    assert_raises(ActiveRecord::RecordInvalid) { save_draft(title: [ "title" ], body_html: "") }
    assert_raises(ActiveRecord::RecordInvalid) { save_draft(title: "Title", body_html: { html: "<p>Not a string</p>" }) }
    assert_raises(ActiveRecord::RecordInvalid) do
      @note.edit_content!(expected_revision: 1, title: "Title\0", body_html: "")
    end
    assert_equal "Field notes", @note.reload.title
  end

  test "overly nested editor HTML fails as a validation error" do
    body_html = ("<span>" * 600) + "Text" + ("</span>" * 600)

    error = assert_raises(ActiveRecord::RecordInvalid) { save_draft(body_html:) }
    assert error.record.errors.added?(:body_html, :invalid)
  end

  test "saved rich formatting reopens intact and its plain text preserves block boundaries" do
    html = "<h2>Topic</h2><p><strong>Bold</strong> <em>italic</em> <u>underlined</u> <s>crossed</s><br>next</p>" \
      '<blockquote><p>Quote</p></blockquote><ol start="3"><li><span>First</span></li><li>Second</li></ol>' \
      '<pre><code>  a &lt; b</code></pre><table><tbody><tr><th>Label</th><td colspan="2">Value</td></tr></tbody></table>' \
      '<p><a href="https://example.invalid/">Link</a></p>'
    note = save_draft(title: "", body_html: html).reload

    assert_equal html, note.body_html
    assert_equal "Topic\nBold italic underlined crossed\nnext\nQuote\nFirst\nSecond\n  a < b\nLabel\nValue\nLink", note.body_text
    assert_empty Note.active_in(@account.id).search_literal("FirstSecond")
  end

  test "preformatted text keeps leading code line breaks through save and reopen" do
    note = save_draft(body_html: "<pre>\n\n  line</pre>").reload

    assert_equal "\n  line", note.body_text
    assert_equal note.body_text, Nokogiri::HTML5.fragment(note.body_html).text
    note.edit_content!(expected_revision: 1, title: note.title, body_html: note.body_html)
    assert_equal 1, note.content_revision
  end

  test "visible text outside code blocks contributes to Unicode hashtag keys" do
    note = save_draft(body_html: <<~HTML)
      <p>#Réunion #RÉUNION #Straße #STRASSE #resume #résumé</p>
      <p>https://example.invalid/#url www.example.invalid/#www ftp://example.invalid/#ftp
      <a href="https://example.invalid/#destination">https://example.invalid/#label-url</a>
      <a href="/notes/#destination">Prose <strong>#Link</strong></a> <code>#inline</code></p>
      <pre data-language="ruby" spellcheck="false"><code><span>#block</span></code></pre>
      <p>word#no ##no #<strong>Split</strong></p>
    HTML

    assert_equal %w[inline link resume réunion résumé split strasse].sort, note.note_tags.pluck(:key).sort
    assert_includes note.body_text, "#inline"
    assert_includes note.body_text, "#block"
  end

  test "a hashtag can span inline code formatting but not a code block" do
    note = save_draft(body_html: "<p>For #<code>planning</code></p><pre><code>#ignored</code></pre>")

    assert_equal [ "planning" ], note.note_tags.pluck(:key)
  end

  test "non-rendered table attributes are removed without losing the table contents" do
    note = save_draft(body_html: <<~HTML)
      <table style="width: 75px"><colgroup><col style="width: 75px"></colgroup>
      <tbody><tr><td style="border: 1px solid black" data-temporary-table-cell-lexical-key="3">
      <p><u><em style="white-space: pre-wrap">Lexxy text</em></u></p></td></tr></tbody></table>
    HTML

    assert_includes note.body_html, "<p><u><em>Lexxy text</em></u></p>"
    assert_equal "Lexxy text", note.body_text
    assert_no_match(/(?:style|data-temporary|colgroup)/, note.body_html)
  end

  test "a table caption remains a separate paragraph through an exact HTML round trip" do
    note = save_draft(body_html: '<p>Intro</p><table><caption onclick="example()"><em>#legend</em></caption>' \
      "<tbody><tr><th>Label</th><td>Value</td></tr></tbody></table>").reload
    stored_html = note.body_html
    revision = note.content_revision

    note.edit_content!(expected_revision: revision, title: note.title, body_html: stored_html).reload

    assert_equal revision, note.content_revision
    assert_equal stored_html, note.body_html
    assert_equal "<p>Intro</p><p><em>#legend</em></p><table><tbody><tr><th>Label</th><td>Value</td></tr></tbody></table>", stored_html
    assert_equal stored_html, Nokogiri::HTML5.fragment(stored_html).to_html
    assert_equal "Intro\n#legend\nLabel\nValue", note.body_text
    assert_equal [ "legend" ], note.note_tags.pluck(:key)
  end

  test "unsupported elements, media, and unsafe attributes cannot persist as rich text" do
    note = save_draft(body_html: <<~HTML).reload
      <div><p onclick="example()">Kept<a href="javascript:void(0)"> label</a><img src="/picture">
      <script>hidden script</script><style>hidden style</style><iframe>hidden iframe</iframe></p>
      <action-text-attachment sgid="example"><p>hidden attachment</p></action-text-attachment>
      <figure class="attachment"><figcaption>hidden caption</figcaption></figure>
      <video src="/video">hidden video</video><audio src="/audio">hidden audio</audio></div>
    HTML

    assert_equal "Kept label", note.body_text
    assert_equal %w[p a], Nokogiri::HTML5.fragment(note.body_html).css("*").map(&:name)
    assert_no_match(/(?:href|onclick|sgid|hidden)/, note.body_html)
  end

  test "attachment descendants do not become visible if their invalid nesting would close a paragraph" do
    note = save_draft(body_html: "<p>Kept<action-text-attachment><p>#hidden</p></action-text-attachment> prose</p>")

    assert_equal "<p>Kept prose</p>", note.body_html
    assert_equal "Kept prose", note.body_text
    assert_empty note.note_tags
  end

  test "a canonical no-op does not bump revision or timestamps and edits may clear existing text" do
    original_content_time = @note.content_updated_at
    original_update_time = @note.updated_at

    travel 1.minute do
      @note.edit_content!(expected_revision: 1, title: " Field notes ", body_html: '<p class="editor">Interview outline</p>')

      assert_equal 1, @note.content_revision
      assert_equal original_content_time, @note.content_updated_at
      assert_equal original_update_time, @note.reload.updated_at
      assert_no_changes -> { @note.reload.content_updated_at } do
        @note.touch
      end

      @note.edit_content!(expected_revision: 1, title: "", body_html: "")
      assert_equal "", @note.reload.body_text
      assert_equal 2, @note.content_revision
    end
  end

  test "Lexxy's empty paragraph is equivalent to empty HTML" do
    note = save_draft(body_html: '<p class="lexxy-content"><br></p>').reload

    assert_equal "", note.body_html
    note.edit_content!(expected_revision: 1, title: note.title, body_html: "<p></p>")
    assert_equal 1, note.content_revision
  end

  test "revision comparison reloads and requires the exact integer" do
    assert_raises(Note::EditConflict) do
      @note.edit_content!(expected_revision: 1.0, title: "Not saved", body_html: "")
    end
    assert_raises(Note::EditConflict) do
      @note.edit_content!(expected_revision: "1", title: "Not saved", body_html: "")
    end
    @account.notes.find(@note.id).edit_content!(expected_revision: 1, title: "Newer edit", body_html: "")

    assert_raises(Note::EditConflict) do
      @note.edit_content!(expected_revision: 1, title: "Not saved", body_html: "")
    end
    assert_equal "Newer edit", @note.reload.title
  end

  test "note writes reject foreign folders or an account reassignment" do
    assert_raises(ActiveRecord::RecordInvalid) { @note.update!(note_folder_id: note_folders(:private).id) }
    assert_raises(ActiveRecord::RecordInvalid) do
      @note.update!(account: accounts(:picker_second), note_folder: note_folders(:second_team))
    end
    assert_equal @account, @note.reload.account
  end

  test "an ordinary folder assignment cannot hide a note in a trashed branch" do
    note = save_draft
    note_folders(:sessions).create_trashing!

    assert_raises(ActiveRecord::RecordInvalid) { note.update!(note_folder: note_folders(:interviews)) }
    assert_equal @folder, note.reload.note_folder
    assert Note.active_in(@account.id).exists?(note.id)
  end

  test "an ordinary folder assignment cannot restore a note from a trashed branch" do
    note_folders(:sessions).create_trashing!

    assert_raises(ActiveRecord::RecordInvalid) { @note.update!(note_folder: @folder) }
    assert_equal note_folders(:interviews), @note.reload.note_folder
    refute Note.active_in(@account.id).exists?(@note.id)
  end

  test "an ordinary folder assignment requires the note itself to be active" do
    @note.create_trashing!

    assert_raises(ActiveRecord::RecordInvalid) { @note.update!(note_folder: @folder) }
    assert_equal note_folders(:interviews), @note.reload.note_folder
  end

  test "validated creation cannot attach a note to a trashed folder" do
    destination = note_folders(:sessions)
    destination.create_trashing!
    draft = @account.notes.build(note_folder: destination, draft_key: SecureRandom.uuid,
      title: "Draft", content_revision: 1, content_updated_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) { draft.save!(context: :revisioned_content) }
    assert error.record.errors.added?(:note_folder, :invalid)
  end

  test "an ordinary model update cannot bypass the revisioned content write" do
    assert_raises(ActiveRecord::RecordInvalid) { @note.update!(body_html: "<p>Unsynchronized content</p>") }
    assert_equal "<p>Interview outline</p>", @note.reload.body_html
  end

  test "tagging scope comes from stored note and tag identities" do
    foreign = accounts(:picker_second).note_tags.create!(key: "new")
    foreign.account = @account
    local = @account.note_tags.create!(key: "new")

    assert_raises(ActiveRecord::RecordInvalid) { @note.note_taggings.create!(note_tag: foreign) }
    assert_raises(ActiveRecord::RecordInvalid) do
      @note.note_taggings.create!(note_tag: local, account: accounts(:picker_second))
    end
    assert_equal local, @note.note_taggings.create!(note_tag: local).note_tag
    assert_raises(ActiveRecord::RecordInvalid) { local.update!(account: accounts(:picker_second)) }
  end

  test "an invalid hashtag key rolls back the entire content transaction" do
    note = save_draft(body_html: "<p>#original</p>")
    original_time = note.content_updated_at
    oversized_key = SecureRandom.alphanumeric(5_000)

    Note.transaction do
      assert_raises(ActiveRecord::RecordInvalid) do
        note.edit_content!(expected_revision: 1, title: "Not saved", body_html: "<p>#not_saved ##{oversized_key}</p>")
      end
    end
    assert_equal "Draft", note.reload.title
    assert_equal 1, note.content_revision
    assert_equal original_time, note.content_updated_at
    assert_equal [ "original" ], note.note_tags.pluck(:key)
    refute @account.note_tags.exists?(key: "not_saved")
  end

  test "note trashing scope comes from stored note identity and cannot be reassigned" do
    foreign = notes(:second_team_note)
    foreign.account = @account
    assert_raises(ActiveRecord::RecordInvalid) { NoteTrashing.create!(note: foreign, account: @account) }

    marker = @note.create_trashing!
    assert_raises(ActiveRecord::RecordInvalid) { marker.update!(note: save_draft) }
    assert_raises(ActiveRecord::RecordInvalid) do
      marker.update!(note_id: foreign.id, account_id: foreign.account_id_in_database)
    end
    assert_equal @note, marker.reload.note
  end

  test "parameter filtering hides both note fields without hiding unrelated titles" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    assert_equal({
      "note" => { "title" => "[FILTERED]", "body_html" => "[FILTERED]" },
      "other" => { "title" => "visible", "body_html" => "unrelated" }
    }, filter.filter({
      "note" => { "title" => "private", "body_html" => "<p>private</p>" },
      "other" => { "title" => "visible", "body_html" => "unrelated" }
    }))
  end

  private
    def save_draft(folder: @folder, draft_key: SecureRandom.uuid, title: "Draft", body_html: "")
      Note.save_draft!(account: @account, folder:, draft_key:, title:, body_html:)
    end
end

class NoteLockingTest < ActiveSupport::TestCase
  self.use_transactional_tests = false
  self.fixture_paths = [ Rails.root.join("test/support/fixtures/chat_accounts") ]
  fixtures :users, :accounts, :note_folders, :notes

  setup do
    @account = accounts(:picker_first)
    @note = notes(:field_notes)
  end

  teardown do
    if @account
      Account.where(id: accounts.map(&:id)).destroy_all
      User.where(id: users.map(&:id)).destroy_all
    end
  end

  test "direct marker creation and dirty destruction lock the persisted account without touching a replacement" do
    marker = nil
    NoteTrashing.transaction do
      marker = NoteTrashing.create!(note: @note)
      assert_account_lock_held
    end

    replacement = notes(:second_team_note)
    timestamp = replacement.updated_at
    assert_raises(ActiveRecord::RecordInvalid) { marker.update!(account: replacement.account, note: replacement) }

    NoteTrashing.transaction do
      marker.destroy!
      assert_account_lock_held
    end
    refute NoteTrashing.exists?(marker.id)
    assert_equal timestamp, replacement.reload.updated_at
  end

  test "direct marker writes still lock and preserve identity if model validations are skipped" do
    marker = NoteTrashing.new(note: @note, account: @account)
    NoteTrashing.transaction do
      marker.save!(validate: false)
      assert_account_lock_held
    end

    replacement = notes(:second_team_note)
    marker.assign_attributes(note: replacement, account: replacement.account)
    assert_raises(ActiveRecord::RecordInvalid) { marker.save!(validate: false) }
    assert_equal @note, marker.reload.note
  end

  test "edits check current visibility even when a different connection changed it" do
    active = Note.active_in(@account.id)
    Note.cache do
      assert active.exists?(@note.id)
      in_another_session { NoteTrashing.create!(account_id: @account.id, note_id: @note.id) }
      assert active.exists?(@note.id), "the editing session still has the old visibility cached"

      assert_raises(Note::Unavailable) do
        @note.edit_content!(expected_revision: 1, title: "Must not save", body_html: "")
      end
    end
    assert_equal "Field notes", @note.reload.title
  end

  test "an ordinary folder assignment holds the account lock without changing the content revision" do
    destination = note_folders(:reading)
    content_time = @note.content_updated_at

    Note.transaction do
      @note.update!(note_folder: destination)
      assert_account_lock_held
    end

    assert_equal destination, @note.reload.note_folder
    assert_equal 1, @note.content_revision
    assert_equal content_time, @note.content_updated_at
  end

  test "an ordinary save rechecks destination visibility after validation cached the active tree" do
    destination = note_folders(:reading)
    @note.note_folder = destination
    active = NoteFolder.active_in(@account.id)

    Note.cache do
      assert @note.valid?
      assert active.exists?(destination.id)
      in_another_session { NoteFolderTrashing.create!(note_folder_id: destination.id, account_id: @account.id) }
      assert active.exists?(destination.id), "the saving connection still has the old tree cached"

      assert_raises(ActiveRecord::RecordInvalid) { @note.save! }
    end
    assert_equal note_folders(:interviews), @note.reload.note_folder
  end

  test "an ordinary save rechecks the source after another connection trashes its branch" do
    @note.note_folder = note_folders(:reading)
    branch = note_folders(:sessions)
    active = Note.active_in(@account.id)

    Note.cache do
      assert @note.valid?
      assert active.exists?(@note.id)
      in_another_session { NoteFolderTrashing.create!(note_folder_id: branch.id, account_id: @account.id) }
      assert active.exists?(@note.id), "the saving connection still has the old note visibility cached"

      assert_raises(ActiveRecord::RecordInvalid) { @note.save! }
    end
    assert_equal note_folders(:interviews), @note.reload.note_folder
  end

  test "a draft replay reads the current revision even after an earlier version was cached" do
    params = { account: @account, folder: @note.note_folder, draft_key: @note.draft_key,
      title: @note.title, body_html: @note.body_html }

    Note.cache do
      Note.find_by!(account_id: @account.id, draft_key: @note.draft_key)
      in_another_session do
        Note.find(@note.id).edit_content!(expected_revision: 1, title: "Committed edit", body_html: "")
      end
      assert_equal 1, Note.find_by!(account_id: @account.id, draft_key: @note.draft_key).content_revision

      assert_raises(Note::EditConflict) { Note.save_draft!(**params) }
    end
    assert_equal "Committed edit", @note.reload.title
  end

  test "account destruction refreshes cached Notes collections and deletes their dependents" do
    saved = nil
    Note.cache do
      @account.notes.load
      @account.note_tags.load
      @account.note_folders.load
      saved = in_another_session do
        account = Account.find(@account.id)
        note = Note.save_draft!(account:, folder: account.general_note_folder, draft_key: SecureRandom.uuid,
          title: "New", body_html: "<p>#new</p>")
        { note: note.id, folder: note.note_folder_id, tag: note.note_tags.sole.id,
          tagging: note.note_taggings.sole.id, marker: note.create_trashing!.id }
      end

      @account.destroy!
    end

    refute Note.exists?(saved.fetch(:note))
    refute NoteFolder.exists?(saved.fetch(:folder))
    refute NoteTag.exists?(saved.fetch(:tag))
    refute NoteTagging.exists?(saved.fetch(:tagging))
    refute NoteTrashing.exists?(saved.fetch(:marker))
  end

  private
    def assert_account_lock_held
      pool = ApplicationRecord.connection_pool
      connection = pool.checkout
      assert_raises ActiveRecord::LockWaitTimeout do
        connection.select_value("SELECT id FROM accounts WHERE id = #{connection.quote(@account.id)} FOR UPDATE NOWAIT")
      end
    ensure
      pool.checkin(connection) if connection
    end

    def in_another_session(&block)
      worker = Thread.new { ApplicationRecord.with_connection { block.call } }
      assert worker.join(5), "the second database session did not finish"
      worker.value
    ensure
      if worker&.alive?
        worker.kill
        worker.join(5)
      end
    end
end
