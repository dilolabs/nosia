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
    assert_select "[data-notes-screen='folders'] [data-notes-sidebar]"
    assert_select "[data-notes-list]"
    assert_select "[data-notes-accounts] a[href='#{workspace(@other)}']", text: @other.name
    assert_select "[data-notes-accounts] a[href='#{workspace(@foreign)}']", count: 0
    assert_select ".n-orbite-rail a[href='/notes'], .n-orbite-panel-links a[href='/notes']", count: 2

    get "/"
    assert_select "[data-dashboard-destination='notes'][href='#{workspace}']"
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
