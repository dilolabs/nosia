require "test_helper"

class NotesWorkspaceTest < ActionDispatch::IntegrationTest
  self.fixture_paths = [ Rails.root.join("test/support/fixtures/chat_accounts") ]
  fixtures :users, :accounts, :account_users, :note_folders, :notes

  setup do
    @user = users(:picker_owner)
    @account = accounts(:picker_first)
    @other = accounts(:picker_second)
    @foreign = accounts(:picker_foreign)
    @folder = note_folders(:interviews)
    @note = notes(:field_notes)
    sign_in(@user)
  end

  test "entry opens the first authorized account and Notes is in desktop and mobile navigation" do
    get "/notes"
    assert_redirected_to workspace
    follow_redirect!
    assert_response :success
    assert_select "h1", count: 1
    assert_select "meta[name=turbo-cache-control][content=no-cache]", count: 1
    assert_select "[data-notes-screen='folders'] [data-notes-sidebar]"
    assert_select "[data-notes-list]"
    assert_select "[data-notes-accounts] a[href='#{workspace(@other)}']", text: @other.name
    assert_select "[data-notes-accounts] a[href='#{workspace(@foreign)}']", count: 0
    assert_select ".n-orbite-rail a[href='/notes'], .n-orbite-panel-links a[href='/notes']", count: 2

    get "/"
    assert_select "[data-dashboard-destination='notes'][href='#{workspace}']"
    assert_select "meta[name=turbo-cache-control][content=no-cache]", count: 0
  end

  test "entry and account switch honor revoked and absent membership" do
    @user.account_users.find_by!(account: @account).destroy!
    get workspace
    assert_response :not_found
    get "/notes"
    assert_redirected_to workspace(@other)
    follow_redirect!
    assert_select "[data-notes-accounts]", text: /#{@other.name}/
    assert_select "[data-notes-accounts] a[href='#{workspace}']", count: 0

    delete "/logout"
    sign_in(users(:picker_no_account))
    get "/notes", headers: { "Accept-Language" => "fr" }
    assert_response :success
    assert_select "[data-notes-no-account] a[href='/accounts']"
    assert_select "[data-notes-sidebar], lexxy-editor", count: 0
    refute_match(/translation missing/i, response.body)
  end

  test "explicit scopes do not fall back or expose another account's records" do
    get workspace(@other), params: { account_id: @account.id }
    assert_response :success
    assert_select "[data-notes-list]", text: /Research 100%/
    assert_select "[data-notes-list]", text: /Field notes/, count: 0

    [ workspace(@foreign), note_url(@note, @other), "#{workspace}?folder_id[]=#{@folder.id}",
      "#{workspace}?folder_id=#{note_folders(:private).id}", "#{workspace}?tag[]=private",
      "#{workspace}?tag=unknown", "#{workspace}?tag=%00", "/accounts/#{@account.id}wrong/notes" ].each do |path|
      get path
      assert_response :not_found
    end
  end

  test "real folders list only direct notes and promote pins while All Notes stays chronological" do
    parent = note_folders(:sessions)
    pinned = save_note(parent, title: "Older pinned")
    pinned.pin_in_folder
    travel 1.second do
      recent = save_note(parent, title: "Newer unpinned")

      get workspace, params: { folder_id: parent.id }
      assert_response :success
      assert_select "[data-notes-screen='list']"
      assert_equal [ pinned.id, recent.id ], listed_ids

      get workspace, params: { view: "list" }
      assert_equal [ recent.id, pinned.id, @note.id ], listed_ids
    end
  end

  test "tag views match normalized active hashtags, preserve Back, and seed an unsaved note" do
    @note.pin_in_folder
    @note.edit_content!(expected_revision: 1, title: "", body_html: "<p>Résumé #École</p>")
    later = travel(1.second) { save_note(note_folders(:reading), body: "<p>#école</p>") }
    get workspace, params: { tag: "E\u0301COLE" }
    assert_response :success
    assert_equal [ later.id, @note.id ], listed_ids
    assert_select "[data-notes-list]", text: /Untitled.*Résumé/m
    assert_equal @folder.id, @note.reload.note_folder_id

    get note_url(@note), params: { tag: "école", page: 2, return_to: "https://example.test" }
    assert_response :success
    assert_select "[data-notes-back]" do |links|
      assert_equal({ "tag" => "école", "page" => "2" }, Rack::Utils.parse_query(URI.parse(links.first["href"]).query))
    end

    assert_no_difference [ "Note.count", "NoteFolder.count" ] do
      get "#{workspace}/new", params: { tag: "école" }
    end
    assert_response :success
    assert_select "[data-notes-screen='editor'] lexxy-editor[attachments='false']"
    assert_select "lexxy-editor[name='note[body_html]'][value*='#école']"
    seed = { title: "", body_html: "<p>#école</p>", draft_key: SecureRandom.uuid }
    assert_no_difference [ "Note.count", "NoteFolder.count" ] do
      post workspace, params: { tag: "école", note: seed }
      assert_response 422
    end
    post workspace, params: { tag: "école", folder_id: @folder.id, note: seed.merge(title: "School plan") }
    assert_response :see_other
    assert Note.find_by!(draft_key: seed[:draft_key]).note_folder.general?
  end

  test "editing the last note under a tag succeeds without redirecting to a dead filter" do
    @note.edit_content!(expected_revision: 1, title: "", body_html: "<p>#retiring</p>")
    patch note_url(@note), params: { tag: "retiring", note: { title: "Retagged", body_html: "<p>Rewritten</p>", expected_revision: 2 } }
    assert_response :see_other
    follow_redirect!
    assert_response :success
    assert_select "[data-notes-back][href='#{workspace}?folder_id=#{@folder.id}']"
  end

  test "an edit submitted under a tag that went to Trash reports unavailability" do
    @note.edit_content!(expected_revision: 1, title: "", body_html: "<p>#disappeared</p>")
    @note.trash
    patch note_url(@note), params: { tag: "disappeared", note: { title: "Unavailable", body_html: "", expected_revision: 2 } }
    assert_response :conflict
    assert_equal 2, @note.reload.content_revision
  end

  test "only a known unavailable Notes destination identifies its 404 as draft-recoverable" do
    @note.edit_content!(expected_revision: 1, title: @note.title, body_html: "<p>#retired</p>")
    @note.trash
    get note_url(@note)
    assert_response :not_found
    assert_equal "unavailable", response.headers["X-Notes-Draft-Recovery"]

    @folder.trash
    [ { folder_id: @folder.id }, { tag: "retired" } ].each do |filter|
      get workspace, params: filter
      assert_response :not_found
      assert_equal "unavailable", response.headers["X-Notes-Draft-Recovery"]
    end

    get note_url(@note, @other)
    assert_response :not_found
    assert_nil response.headers["X-Notes-Draft-Recovery"]

    @user.account_users.find_by!(account: @account).destroy!
    get note_url(@note)
    assert_response :not_found
    assert_nil response.headers["X-Notes-Draft-Recovery"]
  end

  test "a draft from a tag that disappears still creates in General" do
    @note.edit_content!(expected_revision: 1, title: @note.title, body_html: "<p>#retiring</p>")
    get new_account_note_path(@account, tag: "retiring", page: 2)
    assert_response :success
    assert_select "lexxy-editor[value='<p>#retiring</p>']"
    key = css_select("input[name='note[draft_key]']").sole["value"]
    action = css_select("form.n-notes-form").sole["action"]
    @note.edit_content!(expected_revision: 2, title: @note.title, body_html: "")

    assert_difference "Note.count", 1 do
      post action, params: { note: { draft_key: key, title: "Keep this draft", body_html: "<p>New ideas</p>" } }
    end
    assert_response :see_other
    saved = @account.notes.find_by!(draft_key: key)
    assert_predicate saved.note_folder, :general?
    assert_redirected_to account_note_path(@account, saved)
    follow_redirect!
    assert_select "[data-notes-back][href='#{account_notes_workspace_path(@account, folder_id: saved.note_folder_id)}']"
  end

  test "invalid drafts from a retired tag keep the editor and fall back to a valid list" do
    @note.edit_content!(expected_revision: 1, title: @note.title, body_html: "<p>#retiring</p>")
    @note.edit_content!(expected_revision: 2, title: @note.title, body_html: "")
    key = SecureRandom.uuid
    draft = { draft_key: key, title: "Keep the title" }

    assert_no_difference [ "Note.count", "NoteFolder.count" ] do
      post account_notes_path(@account, tag: "retiring", page: 2), params: { note: draft }
    end
    assert_response 422
    assert_select "[data-notes-back][href='#{account_notes_workspace_path(@account, view: "list")}']"
    assert_select "input[name='note[title]'][value='Keep the title']"
    assert_select "input[name='note[draft_key]'][value='#{key}']"
    retry_path = css_select("form.n-notes-form").sole["action"]
    post retry_path, params: { note: draft.merge(body_html: "<p>Corrected draft</p>") }
    assert_response :see_other
    assert_predicate @account.notes.find_by!(draft_key: key).note_folder, :general?
  end

  test "retrying a seed-only draft from a retired tag still requires a user edit" do
    @note.edit_content!(expected_revision: 1, title: @note.title, body_html: "<p>#retiring</p>")
    @note.edit_content!(expected_revision: 2, title: @note.title, body_html: "")
    draft = { draft_key: SecureRandom.uuid, title: "", body_html: "<p>#retiring</p>" }

    assert_no_difference [ "Note.count", "NoteFolder.count" ] do
      post account_notes_path(@account, tag: "retiring"), params: { note: draft }
      assert_response 422
      assert_select "[data-notes-back][href='#{account_notes_workspace_path(@account, view: "list")}']"

      form = css_select("form.n-notes-form").sole
      preserved_fields = form.css("input[type=hidden][name^='note[']").to_h do |field|
        [ field["name"].delete_prefix("note[").delete_suffix("]").to_sym, field["value"] ]
      end
      post form["action"], params: { note: draft.merge(preserved_fields) }
      assert_response 422
    end
  end

  test "an active note with a retired tag context still validates and saves edits" do
    origin = save_note(note_folders(:reading), body: "<p>#retiring</p>")
    get account_note_path(@account, @note, tag: "retiring", page: 2)
    action = css_select("form.n-notes-form").sole["action"]
    origin.edit_content!(expected_revision: 1, title: origin.title, body_html: "")

    patch action, params: { note: { title: "Edited notes", expected_revision: 1 } }
    assert_response 422
    assert_select "[data-notes-back][href='#{account_notes_workspace_path(@account, folder_id: @folder.id)}']"
    assert_select "input[name='note[title]'][value='Edited notes']"
    assert_select "input[name='note[expected_revision]'][value='1']"
    patch action, params: { note: { title: "Ignored", body_html: "", expected_revision: 0 } }
    assert_response :conflict
    assert_select "[role=alert]", text: /This note changed/

    patch action, params: { note: { title: "Edited notes", body_html: "<p>Edited outline</p>", expected_revision: 1 } }
    assert_response :see_other
    follow_redirect!
    assert_select "[data-notes-back][href='#{account_notes_workspace_path(@account, folder_id: @folder.id)}']"
    assert_equal [ "Edited notes", 2 ], @note.reload.values_at(:title, :content_revision)
  end

  test "a moved note can be edited after its original list folder is trashed" do
    destination = note_folders(:reading)
    get account_note_path(@account, @note, folder_id: @folder.id, page: 2)
    action = css_select("form.n-notes-form").sole["action"]
    @note.move_to(destination)
    @folder.trash

    patch action, params: { note: { title: "Moved and edited", body_html: "", expected_revision: 1 } }
    assert_response :see_other
    follow_redirect!
    assert_select "[data-notes-back][href='#{account_notes_workspace_path(@account, folder_id: destination.id)}']"
    assert_equal [ "Moved and edited", destination.id ], @note.reload.values_at(:title, :note_folder_id)
  end

  test "literal search is account wide, shows real paths and previews, and excludes trashed content and tags" do
    active = save_note(@folder, title: "Budget", body: "<p>Forecast 100% &lt;literal&gt; #visible</p>")
    save_note(@folder, title: "Wildcard impostor", body: "<p>Forecast 100x</p>")
    hidden = save_note(@folder, title: "Hidden 100%", body: "<p>Secret preview #forgotten</p>")
    hidden.trash
    save_note(note_folders(:reading), title: "Hidden branch 100%", body: "<p>#inheritedtag</p>")
    note_folders(:reading).trash
    get workspace, params: { folder_id: note_folders(:sessions).id, q: "100%" }
    assert_response :success
    assert_equal [ active.id ], listed_ids
    assert_select "[data-notes-list]", text: /Research \/ Sessions \/ Interviews/
    assert_select "[data-notes-list]", text: /<literal>/
    assert_includes response.body, "&lt;literal&gt;"
    assert_no_match(/Secret preview|Hidden branch|forgotten|inheritedtag|Research 100%/, response.body)
    get workspace, params: { tag: "forgotten" }
    assert_response :not_found
  end

  test "search from an open folder page submits no folder or tag filter" do
    origin = note_folders(:reading)
    get workspace, params: { folder_id: origin.id }
    assert_response :success
    assert_select "form.n-notes-search" do |forms|
      assert_equal workspace, forms.first["action"]
      assert_select "input[name=folder_id], input[name=tag]", count: 0
    end
  end

  test "account-wide search ignores a trashed originating folder and tag" do
    origin = note_folders(:reading)
    save_note(origin, title: "Outline in a hidden folder", body: "<p>#retired</p>")
    origin.trash

    get workspace, params: { q: "outline", folder_id: origin.id, tag: "retired" }
    assert_response :success
    assert_equal [ @note.id ], listed_ids
    assert_select "[data-note-id] a[href='#{account_note_path(@account, @note, q: "outline")}']"

    get workspace, params: { q: "  ", folder_id: origin.id }
    assert_response :not_found
    get workspace, params: { tag: "retired" }
    assert_response :not_found

    get workspace(@foreign), params: { q: "outline", folder_id: origin.id, account_id: @account.id }
    assert_response :not_found
  end

  test "an active note opened from a stale search keeps only query and page in Back" do
    origin = note_folders(:reading).trash
    context = { q: "outline", page: 2, folder_id: origin.id, tag: "no-longer-active" }
    get note_url(@note), params: context
    assert_response :success
    assert_select "lexxy-editor[value='<p>Interview outline</p>']"
    assert_select "[data-notes-back][href='#{account_notes_workspace_path(@account, q: "outline", page: 2)}']"
    assert_select "form.n-notes-form[action='#{account_note_path(@account, @note, q: "outline", page: 2)}']"

    get note_url(notes(:second_team_note)), params: context
    assert_response :not_found
    get note_url(@note, @other), params: context.merge(account_id: @account.id)
    assert_response :not_found
  end

  test "pagination retains context, caps input, and offers a next link only for an extra row" do
    31.times { |i| save_note(@folder, title: "Page note #{i}") }
    get workspace, params: { folder_id: @folder.id, q: "Page note" }
    assert_response :success
    assert_equal 30, listed_ids.size
    assert_select "[data-notes-next]" do |links|
      get links.first["href"]
    end
    assert_equal 1, listed_ids.size
    assert_select "[data-notes-next]", count: 0

    get workspace, params: { page: "1000000000000", q: "a" * 210 }
    assert_response :success
    assert_select "input[name=q][value='#{'a' * 200}']"
    assert_select "[data-notes-previous][href*='page=999']"
  end

  test "manual note forms canonicalize and retain separate navigation, revisions and account scope" do
    draft = { title: "Manual edit", body_html: "<p>Hello<script>untrusted</script><img src=x>#safe</p>",
              draft_key: SecureRandom.uuid, account_id: @foreign.id, note_folder_id: note_folders(:private).id }
    post workspace, params: { folder_id: @folder.id, note: draft }
    assert_response :see_other
    saved = @account.notes.find_by!(draft_key: draft[:draft_key])
    assert_equal @folder.id, saved.note_folder_id
    assert_equal "<p>Hello#safe</p>", saved.body_html
    get note_url(saved)
    assert_select "[data-notes-back][href='#{workspace}?folder_id=#{@folder.id}']"
    assert_select "input[name='note[expected_revision]'][value='1']"
    assert_select "form form", count: 0

    patch note_url(saved), params: { note: { title: "Second edit", body_html: "", expected_revision: 1 } }
    assert_response :see_other
    assert_equal 2, saved.reload.content_revision
    patch note_url(saved), params: { note: { title: "Stale edit", body_html: "", expected_revision: 1 } }
    assert_response :conflict
    assert_equal "Second edit", saved.reload.title
    patch note_url(saved), params: { note: { title: "Invalid edit", expected_revision: 2 } }
    assert_response 422
    assert_select "lexxy-editor"
  end

  test "an invalid edit does not silently advance a stale form to the latest revision" do
    @note.edit_content!(expected_revision: 1, title: "Another editor", body_html: "")
    patch note_url(@note), params: { note: { title: "My edit", expected_revision: 1 } }
    assert_response 422
    assert_select "input[name='note[expected_revision]'][value='1']"
    assert_equal "Another editor", @note.reload.title
  end

  test "an HTML conflict preserves only the submitted draft in readonly controls" do
    @note.edit_content!(expected_revision: 1, title: "Other editor's saved title", body_html: "<p>Saved body marker</p>")
    title = "<img src=x onerror=alert(1)> My draft"
    body = "<p>My draft &lt;/textarea&gt; &lt;img&gt;<script>script marker</script><img src=x onerror=alert(1)></p>"

    patch note_url(@note), params: { note: { title:, body_html: body, expected_revision: 1 } }

    assert_response :conflict
    assert_select "label[for=notes-draft-title]", text: "Submitted title"
    assert_select "input#notes-draft-title[readonly]" do |fields|
      assert_equal title, fields.sole["value"]
    end
    assert_select "label[for=notes-draft-body]", text: "Submitted note text"
    assert_select "textarea#notes-draft-body[readonly]", text: "My draft </textarea> <img>"
    assert_select "[onerror], lexxy-editor", count: 0
    assert_select "a[href='#{note_url(@note)}']", text: "Load saved version"
    refute_includes response.body, "script marker"
    refute_includes response.body, "Saved body marker"
    assert_equal [ "Other editor's saved title", "Saved body marker", 2 ], @note.reload.values_at(:title, :body_text, :content_revision)
  end

  test "an unavailable HTML save lets an authorized member copy their draft but not load the hidden note" do
    @note.edit_content!(expected_revision: 1, title: "Hidden title marker", body_html: "<p>Hidden body marker</p>")
    @folder.trash

    patch note_url(@note), params: { note: { title: "Mon brouillon", body_html: "<p>Mon texte</p>", expected_revision: 2 } },
      headers: { "Accept-Language" => "fr" }

    assert_response :conflict
    assert_select "label[for=notes-draft-title]", text: "Titre envoyé"
    assert_select "input#notes-draft-title[readonly][value='Mon brouillon']"
    assert_select "label[for=notes-draft-body]", text: "Texte de la note envoyé"
    assert_select "textarea#notes-draft-body[readonly]", text: "Mon texte"
    assert_select "a", text: "Charger la version enregistrée", count: 0
    refute_includes response.body, "Hidden title marker"
    refute_includes response.body, "Hidden body marker"
  end

  test "an HTML save submitted through Turbo still returns the copyable draft" do
    patch note_url(@note), params: { note: { title: "Turbo draft", body_html: "<p>Submitted text</p>", expected_revision: 0 } },
      headers: { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }

    assert_response :conflict
    assert_equal "text/html", response.media_type
    assert_select "textarea#notes-draft-body[readonly]", text: "Submitted text"
    assert_select "a[href='#{note_url(@note)}']", text: "Load saved version"
  end

  test "HTML saves denied by account scope or membership return 404 without rendering a draft" do
    foreign_note = Note.save_draft!(account: @foreign, folder: note_folders(:private), draft_key: SecureRandom.uuid,
      title: "Foreign note", body_html: "")
    draft = { title: "Submitted denial marker", body_html: "<p>Submitted body marker</p>", expected_revision: 0 }
    [ note_url(foreign_note, @foreign), note_url(foreign_note), note_url(@note, @other) ].each do |url|
      patch url, params: { note: draft }
      assert_response :not_found
      refute_includes response.body, "Submitted denial marker"
      refute_includes response.body, "Submitted body marker"
    end

    @foreign.account_users.create!(user: @user)
    patch note_url(foreign_note), params: { note: draft }
    assert_response :not_found
    refute_includes response.body, "Submitted denial marker"

    @user.account_users.find_by!(account: @account).destroy!
    patch note_url(@note), params: { note: draft }
    assert_response :not_found
    refute_includes response.body, "Submitted denial marker"
    refute_includes response.body, "Submitted body marker"
  end

  test "an HTML create replay conflict preserves the draft and links only to an active saved note" do
    saved = save_note(@folder, title: "Saved title", body: "<p>Private saved body</p>")
    draft = { draft_key: saved.draft_key, title: "Replay title", body_html: "<p>Replay body</p>" }
    assert_no_difference "Note.count" do
      post workspace, params: { folder_id: @folder.id, note: draft }
      assert_response :conflict
      assert_select "input#notes-draft-title[readonly][value='Replay title']"
      assert_select "textarea#notes-draft-body[readonly]", text: "Replay body"
      assert_select "a[href='#{note_url(saved)}']", text: "Load saved version"

      saved.trash
      post workspace, params: { folder_id: @folder.id, note: draft }
      assert_response :conflict
      assert_select "textarea#notes-draft-body[readonly]", text: "Replay body"
      assert_select "a", text: "Load saved version", count: 0
      refute_includes response.body, "Private saved body"
    end
    assert_equal [ "Saved title", 1 ], saved.reload.values_at(:title, :content_revision)
  end

  test "a rejected long hashtag preserves the edit form and a correction updates the same note" do
    long_tag = "é" * (NoteTag::MAX_KEY_BYTES / 2 + 1)
    title = "Edited outline"
    body = "<p>Keep this ##{long_tag}<script>discard_me</script></p>"
    action = account_note_path(@account, @note, q: "outline", page: 2)
    draft = { title:, body_html: body, expected_revision: 1 }
    assert_no_difference [ "Note.count", "NoteTag.count" ] do
      patch action, params: { note: draft }, headers: { "Accept-Language" => "fr" }
    end
    assert_response 422
    assert_select ".n-notes-errors", text: /Un mot-dièse est trop long/
    assert_select "form.n-notes-form[action='#{action}']" do
      assert_select "input[name=_method][value=patch]"
      assert_select "input[name='note[expected_revision]'][value='1']"
      assert_select "input[name='note[title]'][value='#{title}']"
      assert_select "lexxy-editor[name='note[body_html]'][value='<p>Keep this ##{long_tag}</p>']"
    end
    refute_includes response.body, "discard_me"
    assert_equal [ "Field notes", 1 ], @note.reload.values_at(:title, :content_revision)

    assert_no_difference "Note.count" do
      patch action, params: { note: draft.merge(body_html: "<p>Keep this #short</p>") }
    end
    assert_response :see_other
    assert_equal [ title, 2 ], @note.reload.values_at(:title, :content_revision)
    assert_equal [ "short" ], @note.note_tags.pluck(:key)

    patch action, params: { note: draft }
    assert_response :conflict
    assert_equal [ title, 2 ], @note.reload.values_at(:title, :content_revision)
  end

  test "a rejected long hashtag preserves the new draft key and destination for resubmission" do
    long_tag = "x" * (NoteTag::MAX_KEY_BYTES + 1)
    title = "New outline"
    key = SecureRandom.uuid
    action = account_notes_path(@account, folder_id: @folder.id)
    draft = { draft_key: key, title:, body_html: "<p>New ##{long_tag}<img src=x></p>" }
    assert_no_difference [ "Note.count", "NoteTag.count" ] do
      post action, params: { note: draft }
    end
    assert_response 422
    assert_select ".n-notes-errors", text: /A hashtag is too long/
    assert_select "form.n-notes-form[action='#{action}']" do
      assert_select "input[name=_method]", count: 0
      assert_select "input[name='note[draft_key]'][value='#{key}']"
      assert_select "input[name='note[title]'][value='#{title}']"
      assert_select "lexxy-editor[name='note[body_html]'][value='<p>New ##{long_tag}</p>']"
    end

    corrected = { note: draft.merge(body_html: "<p>New #short</p>") }
    assert_difference "Note.count", 1 do
      post action, params: corrected
      assert_response :see_other
      post action, params: corrected
      assert_response :see_other
    end
    saved = @account.notes.find_by!(draft_key: key)
    assert_equal [ title, @folder.id, 1 ], saved.values_at(:title, :note_folder_id, :content_revision)
    assert_equal [ "short" ], saved.note_tags.pluck(:key)
  end

  test "autosave creates once and updates using the acknowledged revision and authorized list context" do
    context = { folder_id: @folder.id, view: "list" }
    action = account_notes_path(@account, **context)
    draft = { draft_key: SecureRandom.uuid, title: "New outline", body_html: "<p>Ideas #research</p>", expected_revision: 0 }

    assert_difference "Note.count", 1 do
      post action, params: { note: draft }, headers: json_headers
      assert_response :created
      saved = @account.notes.find_by!(draft_key: draft[:draft_key])
      assert_equal @folder, saved.note_folder
      assert_equal [ "research" ], saved.note_tags.pluck(:key)
      canonical = account_note_path(@account, saved, **context)
      assert_equal({ "id" => saved.id, "revision" => 1, "update_url" => canonical, "location" => canonical },
        response.parsed_body.slice("id", "revision", "update_url", "location"))

      post action, params: { note: draft }, headers: json_headers
      assert_response :ok
      assert_equal 1, response.parsed_body.fetch("revision")

      patch canonical, params: { note: { title: "Revised outline", body_html: "", expected_revision: 1 } }, headers: json_headers
      assert_response :ok
      assert_equal({ "id" => saved.id, "revision" => 2, "update_url" => canonical, "location" => canonical },
        response.parsed_body.slice("id", "revision", "update_url", "location"))
      assert_equal [ "Revised outline", 2 ], saved.reload.values_at(:title, :content_revision)

      post action, params: { note: draft }, headers: json_headers
      assert_response :conflict
      assert_equal "edit_conflict", response.parsed_body.fetch("code")
      assert_equal canonical, response.parsed_body.fetch("location")
    end
  end

  test "bad autosave revisions return a localized conflict and do not change content or tags" do
    canonical = account_note_path(@account, @note, q: "outline")
    [ "0", "1wrong", nil ].each do |revision|
      assert_no_difference "NoteTag.count" do
        patch canonical, params: { note: { title: "Unsaved", body_html: "<p>#unsaved</p>", expected_revision: revision } },
          headers: json_headers.merge("Accept-Language" => "fr")
      end
      assert_response :conflict
      assert_equal({ "code" => "edit_conflict", "message" => I18n.t("nosia.notes.edit_conflict", locale: :fr),
        "location" => canonical }, response.parsed_body)
      refute_includes response.body, @note.title
      assert_equal [ "Field notes", "Interview outline", 1 ], @note.reload.values_at(:title, :body_text, :content_revision)
    end
  end

  test "autosave distinguishes known unavailability from a missing or foreign scope" do
    @note.trash
    draft = { title: "Keep my draft", body_html: "", expected_revision: 1 }
    patch note_url(@note), params: { note: draft }, headers: json_headers
    assert_response :conflict
    assert_equal({ "code" => "unavailable", "message" => I18n.t("nosia.notes.unavailable") }, response.parsed_body)

    patch note_url(@note, @other), params: { note: draft }, headers: json_headers
    assert_response :not_found
    post account_notes_path(@account, folder_id: note_folders(:private).id),
      params: { note: draft.merge(draft_key: SecureRandom.uuid) }, headers: json_headers
    assert_response :not_found
    post workspace(@foreign), params: { note: draft.merge(draft_key: SecureRandom.uuid) }, headers: json_headers
    assert_response :not_found
    refute_includes response.body, @note.title
    assert_equal [ "Field notes", 1 ], @note.reload.values_at(:title, :content_revision)
  end

  test "autosave drops a retired tag without returning an unsafe list or update path" do
    @note.edit_content!(expected_revision: 1, title: @note.title, body_html: "<p>#retired</p>")
    action = account_note_path(@account, @note, tag: "retired", page: 2, return_to: "https://example.test")
    patch action, params: { note: { title: "Retagged", body_html: "<p>Outline</p>", expected_revision: 2 } }, headers: json_headers
    assert_response :ok
    canonical = account_note_path(@account, @note, folder_id: @folder.id)
    assert_equal [ canonical, canonical ], response.parsed_body.values_at("update_url", "location")
    refute_match(/retired|example\.test/, response.body)
  end

  test "autosave returns localized validation text without echoing the rejected draft and accepts a corrected POST" do
    key = SecureRandom.uuid
    draft = { draft_key: key, title: "Private local draft", body_html: "<p>##{'é' * (NoteTag::MAX_KEY_BYTES / 2 + 1)}</p>" }
    assert_no_difference [ "Note.count", "NoteTag.count" ] do
      post workspace, params: { note: draft }, headers: json_headers.merge("Accept-Language" => "fr")
    end
    assert_response 422
    assert_equal({ "code" => "invalid", "message" => I18n.t("nosia.notes.hashtag_too_long", locale: :fr) }, response.parsed_body)
    refute_includes response.body, draft[:title]

    post workspace, params: { note: draft.merge(body_html: "<p>#short</p>") }, headers: json_headers
    assert_response :created
    assert_predicate @account.notes.find_by!(draft_key: key).note_folder, :general?
  end

  test "loading new editors generates distinct keys and neither blank nor seed-only JSON saves create a note" do
    @note.edit_content!(expected_revision: 1, title: @note.title, body_html: "<p>#research</p>")
    keys = []
    assert_no_difference "Note.count" do
      [ { folder_id: @folder.id }, { tag: "research" } ].each do |context|
        get new_account_note_path(@account, **context)
        assert_response :success
        assert_select ".n-notes-editor-heading .n-notes-meta", text: (context[:tag] ? "General" : "Research / Sessions / Interviews")
        keys << css_select("input[name='note[draft_key]']").sole["value"]
        post account_notes_path(@account, **context), params: {
          note: { draft_key: keys.last, title: "", body_html: context[:tag] ? "<p>#research</p>" : "" }
        }, headers: json_headers
        assert_response 422
        assert_equal "application/json", response.media_type
        assert_equal "invalid", response.parsed_body.fetch("code")
      end
    end
    assert_equal 2, keys.uniq.size
  end

  test "mutations use authorized targets and destinations, not submitted account or note IDs" do
    outside = notes(:second_team_note)
    post "#{note_url(@note)}/movement", params: { note_folder_id: note_folders(:private).id }
    assert_response :not_found
    patch note_url(outside), params: { note: { title: "Wrong note", body_html: "", expected_revision: 1 } }
    assert_response :not_found
    post "#{note_url(@note, @other)}/pin", params: { account_id: @account.id, note_id: outside.id }
    assert_response :not_found
    post "#{note_url(@note, @foreign)}/pin", params: { account_id: @account.id }
    assert_response :not_found

    assert_nil @note.reload.pin
    assert_equal @folder, @note.note_folder
    assert_equal "Research 100%", outside.reload.title
    post "#{note_url(@note)}/pin"
    assert_response :see_other
    assert @note.reload.pin
    post "#{note_url(@note)}/movement", params: { note_folder_id: note_folders(:reading).id }
    assert_response :see_other
    assert_equal note_folders(:reading), @note.reload.note_folder
    assert_nil @note.pin
  end

  test "saving from a stale folder or moving into it reports unavailability without writing" do
    stale = note_folders(:reading).trash
    draft = { title: "Stale draft", body_html: "", draft_key: SecureRandom.uuid }
    assert_no_difference "Note.count" do
      post workspace, params: { folder_id: stale.id, note: draft }
      assert_response :conflict
    end
    post "#{note_url(@note)}/movement", params: { note_folder_id: stale.id },
         headers: { "Accept-Language" => "fr" }
    assert_response :conflict
    assert_select "[role=alert]", text: /Cette modification est impossible/
    assert_select "#notes-draft-title, #notes-draft-body", count: 0
    assert_equal @folder, @note.reload.note_folder
  end

  test "folders validate their ancestry and cannot mutate General" do
    general = @account.general_note_folder
    post folder_url, params: { note_folder: { name: "Projects", parent_id: @folder.id, account_id: @foreign.id } }
    assert_response :see_other
    child = @account.note_folders.find_by!(name: "Projects")
    assert_equal @folder, child.parent
    patch folder_url(child), params: { note_folder: { name: "Renamed", parent_id: "" } }
    assert_response :see_other
    assert_nil child.reload.parent
    patch folder_url(@folder), params: { note_folder: { name: "", parent_id: "" } }
    assert_response 422
    patch folder_url(note_folders(:research)), params: { note_folder: { name: "Research", parent_id: @folder.id } }
    assert_response 422
    post folder_url, params: { note_folder: { name: "Foreign", parent_id: note_folders(:private).id } }
    assert_response :not_found
    patch folder_url(general), params: { note_folder: { name: "Renamed", parent_id: @folder.id } }
    assert_response :conflict
    post "#{folder_url(general)}/trashing"
    assert_response :conflict
    get workspace, headers: { "Accept-Language" => "fr" }
    assert_select "[data-notes-sidebar]", text: /Général/
  end

  test "Trash nests branches once, permits direct purge to owner and otherwise requires restoring the parent first" do
    branch = note_folders(:sessions)
    inherited = save_note(@folder, title: "Inherited draft")
    post "#{note_url(@note)}/trashing"
    assert_response :see_other
    post "#{folder_url(@folder)}/trashing"
    assert_response :see_other
    post "#{folder_url(branch)}/trashing"
    assert_response :see_other
    get workspace, params: { view: "trash" }
    assert_response :success
    assert_select "[data-notes-trash] [data-notes-trash-folder='#{branch.id}'] [data-notes-trash-folder='#{@folder.id}']", count: 1
    assert_select "[data-notes-trash-folder='#{@folder.id}']", count: 1
    assert_select "[data-notes-trash-note='#{inherited.id}']", text: /Inherited from folder/
    assert_select "form[action='#{note_url(@note)}/trashing'], form[action='#{folder_url(@folder)}/trashing']", count: 0
    assert_select "form[action='#{note_url(@note)}/purge'][data-turbo-confirm]"
    assert_select "form[action='#{folder_url(@folder)}/purge'][data-turbo-confirm]"

    [ note_url(@note), folder_url(@folder) ].each do |url|
      delete "#{url}/trashing"
      assert_response :conflict
    end
    patch note_url(inherited), params: { folder_id: @folder.id, note: { title: "Unavailable", body_html: "", expected_revision: 1 } }
    assert_response :conflict
    patch note_url(inherited), params: { folder_id: note_folders(:private).id, note: { title: "Wrong scope", body_html: "", expected_revision: 1 } }
    assert_response :not_found
    post "#{note_url(inherited)}/pin"
    assert_response :conflict
    delete "#{note_url(inherited)}/purge"
    assert_response :conflict

    member = users(:picker_outsider)
    @account.account_users.grant_to(member)
    delete "/logout"
    sign_in(member)
    [ note_url(@note), folder_url(@folder) ].each do |url|
      delete "#{url}/purge"
      assert_response :forbidden
    end
    get workspace, params: { view: "trash" }
    assert_select "form[action$='/purge']", count: 0
    delete "#{folder_url(branch)}/trashing"
    assert_response :see_other
    delete "#{folder_url(@folder)}/trashing"
    assert_response :see_other
    assert Note.active_in(@account.id).exists?(inherited.id)
    refute Note.active_in(@account.id).exists?(@note.id)
    delete "#{note_url(@note)}/trashing"
    assert_response :see_other
    assert Note.active_in(@account.id).exists?(@note.id)

    delete "/logout"
    sign_in(@user)
    @note.trash
    @folder.trash
    branch.trash
    delete "#{note_url(@note)}/purge"
    assert_response :see_other
    refute Note.exists?(@note.id)
    delete "#{folder_url(@folder)}/purge"
    assert_response :see_other
    refute NoteFolder.exists?(@folder.id)
    assert NoteFolder.exists?(branch.id)
  end

  private
    def json_headers
      { "Accept" => "application/json" }
    end

    def sign_in(user)
      post "/login", params: { email: user.email, password: "picker-password-123" }
      assert_response :redirect
    end

    def workspace(account = @account)
      "/accounts/#{account.id}/notes"
    end

    def note_url(note, account = @account)
      "#{workspace(account)}/#{note.id}"
    end

    def folder_url(folder = nil)
      [ "/accounts/#{@account.id}/note-folders", folder&.id ].compact.join("/")
    end

    def save_note(folder, title: "Draft", body: "")
      Note.save_draft!(account: @account, folder:, draft_key: SecureRandom.uuid, title:, body_html: body)
    end

    def listed_ids
      css_select("[data-notes-list] [data-note-id]").map { |row| row["data-note-id"].to_i }
    end
end
