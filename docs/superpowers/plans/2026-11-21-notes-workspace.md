# Notes Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a first-class, shared Notes workspace with nested folders and Lexxy editing, then make current active notes available to authorized chats and account API completions.

**Architecture:** Build account-qualified CRUD and Hotwire views on one PostgreSQL folder tree and shared active-visibility relation. Save sanitized rich text and its derived search text and hashtags transactionally, using a content revision and a draft key for autosave. Add separately versioned indexing in Solid Queue and restrict note chunks at each existing retrieval boundary before enabling reads.

**Tech Stack:** Ruby 4, Rails 8.1, PostgreSQL/pgvector, Solid Queue, Lexxy via Importmap, Hotwire/Stimulus, Tailwind, Minitest with fixtures, and Capybara/Selenium.

---

**Approved spec:** [Notes workspace](../specs/2026-11-21-notes-workspace-design.md), `30db317`. Work in two ordered slices: **1–5 workspace**, **6–8 retrieval and release verification**. The workspace is testable separately but both slices are required for V1. Do not add attachments, public sharing, offline sync, live co-editing, a second source record, or an API for managing notes.

## File map

| Boundary | Files and responsibilities |
|---|---|
| Folder/Note storage | `app/models/account.rb` owns collections and provisions General; `app/models/note_folder.rb` and `app/models/note_folder/tree.rb` own topology and active ancestry; `app/models/note.rb`, `app/models/note/body.rb`, `app/models/note/editable.rb`, and `app/models/note/taggable.rb` own content, revisions, search, and tag synchronization. |
| State records | `app/models/note_pin.rb`, `app/models/note_trashing.rb`, `app/models/note_folder_trashing.rb`, `app/models/note/trashable.rb`, `app/models/note_folder/trashable.rb`, `app/models/note_tag.rb`, and `app/models/note_tagging.rb` model Notes-specific state. |
| HTTP | `config/routes.rb`, `app/controllers/notes/entries_controller.rb`, `workspaces_controller.rb`, `notes_controller.rb`, `folders_controller.rb`, `pins_controller.rb`, `movements_controller.rb`, separate `note_trashings_controller.rb` / `folder_trashings_controller.rb`, and `note_purges_controller.rb` / `folder_purges_controller.rb` under `app/controllers/notes/`; `app/controllers/concerns/notes_account_scoped.rb` owns request membership and scoped lookups. |
| Web layout | `app/views/notes/workspaces/` contains the workspace shell, sidebar/tree, results, editor, and Trash; `app/views/notes/notes/` and `app/views/notes/folders/` contain contextual forms. `app/helpers/notes_helper.rb` renders scope and return links; the Orbite rail and dashboard link to the workspace. |
| Interaction | `app/javascript/controllers/note_autosave_controller.js` owns one in-flight save per editor; `app/javascript/controllers/notes_navigation_controller.js` owns tablet drawer focus. `app/assets/stylesheets/nosia/notes_workspace.css` uses existing theme tokens. |
| Indexing | `app/models/note/indexable.rb` chooses and atomically publishes a generation, `app/jobs/note/index_job.rb` invokes it, `app/models/chunk/vectorizable.rb` prepares embeddings before locking, and `app/controllers/notes/index_retries_controller.rb` relaunches failed indexing. |
| RAG and citations | `app/models/chunk/note_visibility.rb` applies note eligibility; `app/models/chat/note_retrieval.rb` validates the turn's caller; `app/models/chat/similarity_search.rb` and `completionable.rb` recheck before provider requests. `app/jobs/chat_response_job.rb` and the API controllers pass trusted caller information; `app/models/message.rb`, `app/controllers/chunks_controller.rb`, and the existing citation views guard and render note links. |
| Tests and docs | Use established Rails test patterns in `test/models/`, `test/controllers/`, `test/jobs/`, and `test/system/`; EN/FR strings live in `config/locales/`; document the workspace and model-provider boundary in `docs/notes-workspace.md`, `docs/README.md`, and `README.md`. |

## Execution preflight

- [ ] **Verify the baseline in the implementation worktree.** Use Ruby from `.ruby-version`. Configure `NOTES_TEST_DATABASE_URL` for a disposable PostgreSQL database dedicated to this worktree; never reuse the main checkout's database or copy its `.env`. Start no development workers or real model providers. Run:

  ```bash
  bundle check
  export RAILS_ENV=test DATABASE_URL="${NOTES_TEST_DATABASE_URL:?set a disposable Notes test database URL}"
  bin/rails db:prepare
  bin/rails test test/controllers/chat_account_citations_test.rb test/controllers/api/v1/completions_controller_test.rb test/models/chunk/vectorizable_test.rb
  ```

  Expected: bundle satisfied, the dedicated DB prepares with pgvector, and the targeted baseline has no failures. Stop and record any baseline failure before implementation. Unset `DATABASE_URL` and `RAILS_ENV` before invoking unrelated commands. Regenerate only the primary schema from this dedicated DB after each migration; do not stage existing queue/cache/cable schema changes.

## Slice 1 — Notes workspace

### Task 1: Account-owned folders, General, and active tree

**Files:** Create `db/migrate/20261121000001_create_note_folders.rb`, `app/models/note_folder.rb`, `app/models/note_folder/tree.rb`, `app/models/note_folder_trashing.rb`, `test/fixtures/note_folders.yml`, `test/models/note_folder_test.rb`. Modify `app/models/account.rb` and regenerate `db/schema.rb`.

- [ ] **RED: Cover tree and isolation.** Use `ChatAccountFixtures` for two authorized accounts and a foreign one. Load the Notes fixture via its existing support-fixture pattern if it references those scoped accounts. This test uses ordinary model associations and tests the outcome:

  ```ruby
  test "a descendant cannot become its ancestor's new parent" do
    root = @first.note_folders.create!(name: "Research")
    child = @first.note_folders.create!(name: "Sessions", parent: root)
    leaf = @first.note_folders.create!(name: "Interviews", parent: child)

    assert_raises(ActiveRecord::RecordInvalid) { root.change_location!(parent: leaf) }
    assert_nil root.reload.parent_id
    assert_equal [root.id, child.id, leaf.id].sort, NoteFolder.active_in(@first.id).where(id: [root, child, leaf]).ids.sort
  end
  ```

  Also cover a foreign parent, a foreign entry excluded from `.active_in`, a hidden branch with an unaffected sibling, and two calls to `@first.general_note_folder` yielding the same system root. Run `bin/rails test test/models/note_folder_test.rb`; expect missing `NoteFolder`/association before the migration and model.

- [ ] **GREEN: Add storage and tree operations.** Use the actual bigint account schema; add `note_folders(account_id, parent_id, name, system_key, timestamps)` with `(account_id, parent_id)` and a partial unique `(account_id, system_key)` for non-null keys. Add `note_folder_trashings(account_id, note_folder_id, timestamps)` with a unique folder index. Put `parent` and `children` self-associations and `trashing` on `NoteFolder`. Use the single `accounts` row as the short transaction lock for any Notes structural or content mutation. General is lazily provisioned under that lock with a stable `system_key: "general"` and a localized label in the view; do not create it on every account creation.

  ```ruby
  # app/models/note_folder/tree.rb
  def self.active_in(account_id)
    roots = where(account_id:, parent_id: nil).where.missing(:trashing)
    descendants = where(account_id:).where.missing(:trashing).joins(
      "INNER JOIN active_note_folders parent ON parent.id = note_folders.parent_id"
    )
    unscoped.with_recursive(active_note_folders: [roots, descendants])
      .from("active_note_folders AS note_folders").where(account_id:)
  end
  ```

  Define `.active_in` as a class method in the concern's `class_methods` block. Build `.branch_in(account_id, root_id:)` with the same recursive pattern seeded by the root ID but **without** the trash exclusion, for descent checks and purge. `change_location!(parent:)` reloads under `account.with_lock`, excludes General, checks the folder and candidate parent still belong to the active tree, and adds `errors.add(:parent, :invalid)` before raising when the destination ID is inside `.branch_in`. New and renamed folders validate nonblank names. Reject a parent in a different account on all write paths; never expose a freely writable `account_id` or `system_key`. Test SQL against PostgreSQL, including appending `.select(:id)` so the relation is composable as a subquery.

- [ ] **Verify and commit.** Run `bin/rails db:migrate` and the folder test against the dedicated test DB. Expected: tree traversal, validation, and General tests pass; `db/schema.rb` changes only for Notes. Stage only this task's files; commit `feat(notes): add account-owned folder trees`.

### Task 2: Rich text, hashtags, search, and atomic edits

**Files:** Create `db/migrate/20261121000002_create_notes.rb`, `app/models/note.rb`, `app/models/note/body.rb`, `app/models/note/editable.rb`, `app/models/note/taggable.rb`, `app/models/note_tag.rb`, `app/models/note_tagging.rb`, `app/models/note_trashing.rb`, `test/fixtures/notes.yml`, `test/models/note_test.rb`. Modify `app/models/account.rb`, `config/initializers/filter_parameter_logging.rb`, `db/schema.rb`.

- [ ] **RED: Cover observable revisions and derived text.**

  ```ruby
  test "the current body governs both hashtags and literal search" do
    note = Note.save_draft!(account: @first, folder: @first.general_note_folder, draft_key: SecureRandom.uuid,
      title: "Research 100%", body_html: "<p>#Réunion #réunion</p><pre>#code</pre><p><a href='https://example.invalid/#url'>link</a></p>")

    assert_equal ["réunion"], note.note_tags.pluck(:key)
    assert_equal [note.id], Note.active_in(@first.id).search_literal("100%").ids
    assert_empty Note.active_in(@first.id).search_literal("100_")
    revision = note.content_revision
    note.edit_content!(expected_revision: revision, title: "Research", body_html: "<p>No tags</p>")
    assert_empty note.note_tags.reload
    assert_raises(Note::EditConflict) do
      note.edit_content!(expected_revision: revision, title: "Old tab", body_html: "<p>Old text</p>")
    end
    assert_equal "Research", note.reload.title
  end
  ```

  Add tests for the same `(account, draft_key)` posted twice (including replay after a different editor updates the new note), a foreign or trashed folder, blank first save, block boundaries in search text, harmless rich formatting through save/reopen, and unsupported HTML/media removed server-side. Run `bin/rails test test/models/note_test.rb`; expect missing Note persistence/API.

- [ ] **GREEN: Persist and derive under the same lock.** Add `notes(account_id, note_folder_id, draft_key, title, body_html, body_text, content_revision, content_updated_at, timestamps)`. Use the actual bigint IDs for existing associations and the note ID so `chunks.chunkable_id` can refer to it without a polymorphic primary-key migration. Use a unique `(account_id, draft_key)` and list indexes on `(account_id, content_updated_at, id)` and `(account_id, note_folder_id, content_updated_at, id)`. Add `note_tags(account_id, key, timestamps)`, unique `(account_id, key)`, `note_taggings(account_id, note_id, note_tag_id, timestamps)`, unique `(note_id, note_tag_id)` plus `(note_tag_id, note_id)`, and `note_trashings(account_id, note_id, timestamps)` unique on `note_id`. Explicitly validate same-account associations. Add Notes associations to Account with dependent cleanup in an order that removes notes before folders or tags. Filter `note.body_html` and `note.title` in parameter logs.

  ```ruby
  scope :search_literal, ->(input) {
    pattern = "%#{sanitize_sql_like(input.strip)}%"
    where("notes.title ILIKE :query OR notes.body_text ILIKE :query", query: pattern)
  }

  def self.active_in(account_id)
    where(account_id:, note_folder_id: NoteFolder.active_in(account_id).select(:id)).where.missing(:trashing)
  end

  def edit_content!(expected_revision:, title:, body_html:)
    account.with_lock do
      reload
      raise Note::Unavailable unless Note.active_in(account_id).exists?(id:)
      raise Note::EditConflict unless content_revision == expected_revision

      apply_content!(title:, body_html:)
    end
    self
  end
  ```

  `Note.save_draft!` validates a UUID `draft_key` and looks it up in the account **before** creating under the same lock. A replay returns the active record only when it finds the initial `content_revision` of `1` and the same normalized title/body; raise `Note::EditConflict` if the content differs or advanced, or `Note::Unavailable` if it is no longer active. Returning a result never updates an existing note. `apply_content!` trims the title, assigns `Note::Body`'s strings, increments `content_revision` and sets `content_updated_at` only for an actual edit, and calls `sync_note_tags` transactionally after saving. Require text or a title on *initial* save. Treat `expected_revision` as an integer at the HTTP boundary; do not default a missing revision to the latest.

  `Note::Body` uses `Rails::HTML5::SafeListSanitizer` with `p br h1 h2 h3 h4 ul ol li blockquote strong b em i u s del code pre a table tbody thead tfoot tr td th hr span`, and only `href`, `colspan`, `rowspan`, `start` attributes; reject unsafe URL schemes. Before sanitizing remove script, style, iframe, and attachment nodes with their descendants. Build plain text from the sanitized tree, preserving breaks between block elements. For tags use a second text projection without `pre`, remove literal URLs (`%r{https?://[^\s<>]+}i`), then scan and normalize:

  ```ruby
  tag_text.scan(/(?<![\p{L}\p{M}\p{N}_#])#([\p{L}\p{N}][\p{L}\p{M}\p{N}_-]*)/u)
    .flatten.map { |tag| tag.unicode_normalize(:nfc).downcase(:fold).unicode_normalize(:nfc) }.uniq
  ```

  Keep prose link labels in the projection; do not read `href`. Synchronize additions/removals by tag ID within the account. Empty tag records may remain; only show tags attached to an active note.

- [ ] **Verify and commit.** `bin/rails db:migrate`, then `bin/rails test test/models/note_test.rb test/models/note_folder_test.rb`. Expected: all pass with no provider calls. Commit `feat(notes): save revisioned rich text and inline hashtags`.

### Task 3: Pins, moves, and the branch Trash lifecycle

**Files:** Create `db/migrate/20261121000003_create_note_pins.rb`, `app/models/note_pin.rb`, `app/models/note/trashable.rb`, `app/models/note_folder/trashable.rb`, `test/models/notes_trash_test.rb`. Modify `app/models/note.rb`, `app/models/note_folder.rb`, and `db/schema.rb`.

- [ ] **RED: Exercise a complete state transition.**

  ```ruby
  test "restoring a branch does not restore a separately trashed note" do
    root = @first.note_folders.create!(name: "Projects")
    deep = @first.note_folders.create!(name: "Archive", parent: root)
    retained = draft_in(deep, "Visible again")
    withheld = draft_in(deep, "Still trashed")

    withheld.trash
    root.trash
    assert_empty Note.active_in(@first.id).where(id: [retained, withheld])
    assert_raises(Note::Unavailable) { withheld.restore }
    root.restore
    assert_equal [retained.id], Note.active_in(@first.id).where(id: [retained, withheld]).ids
  end
  ```

  Define `draft_in(folder, title)` as `Note.save_draft!(account: folder.account, folder:, draft_key: SecureRandom.uuid, title:, body_html: "")`. Assert pin follows neither a move to a new folder nor an invalid move; compare ID, tags, and edit time before and after. Cover General protection, read-only Trash, a non-owner rejected for purge, and an owner purging a branch with covered and directly trashed descendants. Run `bin/rails test test/models/notes_trash_test.rb`; expect missing state methods.

- [ ] **GREEN: Expose explicit state methods and guard every write.** Add a `note_pins` table with `account_id`, `note_id`, timestamps, and a unique index on `note_id`. Use `has_one :pin`; provide `pin_in_folder` and `unpin`, both idempotent for active notes. An unchanged destination is a no-op so it does not clear an existing pin. `move_to` must look up the destination again under the same short lock:

  ```ruby
  def move_to(folder)
    account.with_lock do
      reload
      raise Note::Unavailable unless Note.active_in(account_id).exists?(id:)

      destination = NoteFolder.active_in(account_id).find(folder.id)
      if destination.id != note_folder_id
        pin&.destroy!
        update!(note_folder: destination)
      end
    end
    self
  end
  ```

  Implement `trash`, `restore`, and `purge(by:)` on the two trashable concerns. `trash` creates only a direct marker, with no descendant writes. `restore` deletes only that marker and requires an active parent (or root for a folder). `purge(by:)` requires the account owner, an existing marker, and the same account lock; destroy the branch post-order, including notes, taggings, pins, and both kinds of markers. Use one `.branch_in` query to establish the target branch and delete via the associations so future chunk cleanup runs. Preserve a note's pin across trash/restore when the folder is unchanged. Protect General from note-folder rename, move, trash, and purge; allow adding notes and children.

- [ ] **Verify and commit.** Migrate the dedicated test DB. Run `bin/rails test test/models/note_folder_test.rb test/models/note_test.rb test/models/notes_trash_test.rb`. Expected: pass. Add a concurrency test using two checked-out connections and a barrier, without transactional fixtures for that test, to race opposite folder moves; exactly one may commit and traversal must still terminate. Run the file again; commit `feat(notes): manage pins, moves and branch trash`.

### Task 4: Account-scoped routes and the three-pane workspace

**Files:** Create `app/controllers/concerns/notes_account_scoped.rb`, the Notes controllers mapped above except `index_retries_controller.rb`, `app/helpers/notes_helper.rb`, `app/views/notes/workspaces/show.html.erb`, `_sidebar.html.erb`, `_folder_tree.html.erb`, `_list.html.erb`, `_editor.html.erb`, `_trash.html.erb` in that directory, `app/views/notes/folders/_form.html.erb`, `app/views/notes/notes/_move.html.erb`, `app/javascript/controllers/notes_navigation_controller.js`, `app/assets/stylesheets/nosia/notes_workspace.css`, `app/assets/images/svg/note.svg`, `config/locales/en.nosia_notes.yml`, `config/locales/fr.nosia_notes.yml`, and `test/controllers/notes_workspace_test.rb`. Modify `config/routes.rb`, `app/views/application/_orbite_links.html.erb`, `app/views/application/_orbite_shell.html.erb`, `app/helpers/dashboards_helper.rb`, `app/assets/tailwind/application.css`.

- [ ] **RED: Test the workspace and changes through HTTP.**

  ```ruby
  test "the Notes entry lands in an authorized account and does not expose foreign folders" do
    get notes_entry_path
    assert_redirected_to account_notes_workspace_path(@user.first_account)
    follow_redirect!
    assert_select "[data-notes-sidebar]"
    assert_select "[data-notes-list]"
    assert_response :success

    get account_notes_workspace_path(@foreign)
    assert_response :not_found
  end
  ```

  Include tests for folder lists excluding grandchildren, All Notes including them, tag views not changing folder, search finding a matching result outside the selected folder and showing its path, a foreign destination on `POST .../movement`, and `DELETE .../purge` returning forbidden to a current non-owner. Cover account switch removal, no-account state, desktop/core/mobile nav links, and that no deleted title, preview, or tag appears in active HTML. Run `bin/rails test test/controllers/notes_workspace_test.rb`; expect a missing route.

- [ ] **GREEN: Define routes and share authorized loaders.** Add the entry inside the existing authenticated block; add nested workspace and folders/notes to the existing `resources :accounts`. Use a resource for each change:

  ```ruby
  resource :notes_entry, path: "notes", only: :show, controller: "notes/entries"
  # Inside resources :accounts
  scope module: :notes do
    resource :notes_workspace, path: "notes", only: :show, controller: "workspaces"
    resources :note_folders, path: "note-folders", controller: "folders", only: %i[new create edit update] do
      resource :trashing, only: %i[create destroy], controller: "folder_trashings"
      resource :purge, only: :destroy, controller: "folder_purges"
    end
    resources :notes, only: %i[new create show update] do
      resource :movement, only: :create
      resource :pin, only: %i[create destroy]
      resource :trashing, only: %i[create destroy], controller: "note_trashings"
      resource :purge, only: :destroy, controller: "note_purges"
    end
  end
  ```

  `NotesAccountScoped` includes `AccountScoped`; `@account = member_account(request.path_parameters.fetch(:account_id))`. Active note/destination lookups use `Note.active_in(@account.id)` and `NoteFolder.active_in(@account.id)`. For `update`, load via `@account.notes.find` and let `edit_content!` check active eligibility under lock: a member's own-account note removed from the active tree yields `409` for draft recovery, while a foreign ID still yields `404`. Restore/purge use `@account.notes.where.associated(:trashing)` or `@account.note_folders.where.associated(:trashing)` and owner check for purge. Use the declared model operations rather than assigning state params. Guard model conflicts with a localized `409`, invalid editorial input with `422`, inaccessible IDs with `404`, and an authenticated but non-owner purge with `403`. Use `303` after successful ordinary form writes. Global entry uses `Current.user.first_account`; no membership renders an empty state with a link to Accounts. Keep the current account visible in every pane and switch by linking to another authorized account's workspace.

- [ ] **GREEN: Render canonical lists and context-preserving navigation.** Use stable URL options `folder_id`, `tag`, `q`, `page`, and `view=folders|list|trash`. Resolve a nonempty `q` account-wide before folder/tag filters. Resolve an explicit tag through current-account tag IDs with active memberships. Build the list with deterministic content-date/ID order and fetch 31 rows to display up to 30 plus a next link, following `app/controllers/accounts/chats_controller.rb`; cap the parsed page number and query length at 1,000 and 200 respectively. Use a left join on `:pin` and sort pinned-first only in a real folder's list. Build the sidebar tree and result paths from one scoped folder map; use nested disclosure/link controls with an accessible selected link. A deleted branch appears once at its topmost deleted folder; render descendants within it with no edit/move/pin actions. When rendering an active note, use `account_note_path(@account, note, **list_options)` for forward navigation and `account_notes_workspace_path(@account, **list_options)` for Back; a direct deep link defaults Back to the note's folder. Safely render only whitelisted list options, never a freeform `return_to`.

  ```erb
  <div class="n-notes-workspace" data-controller="notes-navigation" data-notes-screen="<%= screen %>">
    <%= render "notes/workspaces/sidebar", account: @account, folders: @folders %>
    <%= render "notes/workspaces/list", account: @account, notes: @notes %>
    <section class="n-notes-reader" aria-label="<%= t("nosia.notes.editor") %>">
      <%= render "notes/workspaces/editor", account: @account, note: @note if @note %>
    </section>
  </div>
  ```

  Use normal GET links with Turbo history and a real GET search form; do not rebuild the editor on every input or invent client-side list state. Route Change Folder and Trash actions via form buttons. Keep the `h1`, account switching and primary actions visible; avoid duplicating the global breadcrumb. On tablet, open the folder sidebar with a native dialog, close on Escape, and restore focus to the opener. Render only one accessible copy of the sidebar at a time, use unique IDs, and close the dialog when the breakpoint changes. Keep a server-rendered `view=folders` route reachable if JS is unavailable. On mobile, expose only the active server-selected pane: default to folders on the unfiltered workspace, list for a folder/tag/search, and editor on the note route. Build with one layout scoped to Notes:

  ```css
  .n-notes-workspace { display: grid; min-inline-size: 0; }
  .n-notes-reader { min-inline-size: 0; overflow-wrap: anywhere; }
  @media (min-width: 64rem) {
    .n-notes-workspace { grid-template-columns: 15rem minmax(16rem, 22rem) minmax(0, 1fr); }
  }
  @media (min-width: 48rem) and (max-width: 63.999rem) {
    .n-notes-workspace { grid-template-columns: minmax(14rem, 19rem) minmax(0, 1fr); }
  }
  ```

  Import `nosia/notes_workspace.css` unlayered after the Orbite CSS. Use `--orbite-paper`, `--orbite-text`, `--orbite-line`, `--orbite-bubble`, and `--orbite-accent` rather than adding a palette. Add the icon, EN/FR labels, empty states and action confirmations. Run `bin/rails routes -g notes` to validate actual helpers; keep existing Sources and chat controls untouched.

- [ ] **Verify and commit.** Run `bin/rails test test/controllers/notes_workspace_test.rb test/models/notes_trash_test.rb`. Expected: all pass. Commit `feat(notes): add the account Notes workspace`.

### Task 5: Lexxy autosave, conflict recovery, and responsive use

**Files:** Create `app/javascript/controllers/note_autosave_controller.js` and `test/system/notes_workspace_test.rb`. Modify `app/controllers/notes/notes_controller.rb`, `app/views/notes/workspaces/_editor.html.erb`, `_list.html.erb`, and `show.html.erb` in that directory, `app/assets/stylesheets/nosia/notes_workspace.css`, `config/locales/en.nosia_notes.yml`, `config/locales/fr.nosia_notes.yml`, and `test/controllers/notes_workspace_test.rb`.

- [ ] **RED: Cover creation/revision in requests and Lexxy in a browser.** Use a desktop system test opening New Note, filling the title and Lexxy, and waiting on the save announcement rather than sleeping:

  ```ruby
  visit account_notes_workspace_path(@first)
  click_link "New note"
  fill_in "Title", with: "Research notes"
  find("lexxy-editor [contenteditable=true]").send_keys("Ideas #research")
  assert_selector "[data-note-autosave-target='status']", text: "Saved"
  assert @first.notes.find_by!(title: "Research notes").note_tags.exists?(key: "research")
  ```

  Add follow-up cases: a preset tag alone does not create a note, a fresh reload restores formatting, saving in two sessions preserves the stale editor's input and prevents overwrite, and retry after a failed first response results in one note. Add viewport system cases for mobile Back preserving the original search/list, tablet opening/closing the drawer with keyboard and focus return, and French/dark-mode rendering. Use `bin/rails test test/controllers/notes_workspace_test.rb` and `bin/rails test:system TEST=test/system/notes_workspace_test.rb`; expect pending form or save behavior to fail.

- [ ] **GREEN: Connect form to the authoritative save contract.** `new` chooses the authorized active folder or General; it supplies a fresh `draft_key`, plus `#tag` as the initial body only in a valid tag context. `create`/`update` support ordinary forms and the autosave JSON contract. `POST` returns `201` with `{ id, revision, update_url, location }` (`200` on replay); `PATCH` returns `200` with the same fields. Return `409` with a localized code/message for conflict or unavailable state, and `422` with validation text. Include an account-scoped folder ID hidden field for create, and use the same route whitelist for list context. The markup uses the existing standalone helper with uploads disabled:

  ```erb
  <%= form_with scope: :note, url: form_url, method: form_method,
      data: { controller: "note-autosave", action: "input->note-autosave#changed lexxy:change->note-autosave#changed submit->note-autosave#saveNow" } do |form| %>
    <%= form.hidden_field :draft_key, value: draft_key %>
    <%= form.hidden_field :content_revision, value: note.content_revision, data: { note_autosave_target: "revision" } %>
    <%= form.label :title, t("nosia.notes.title") %>
    <%= form.text_field :title, value: note.title %>
    <%= form.label :body_html, t("nosia.notes.body") %>
    <%= form.lexxy_rich_text_area :body_html, value: note.body_html.to_s, attachments: "false" %>
    <p role="status" aria-live="polite" data-note-autosave-target="status"></p>
    <%= form.submit t("nosia.notes.save"), class: "n-notes-manual-save" %>
  <% end %>
  ```

  Wire labels and state text, retry, copy draft and load saved version actions through localized data values. Keep the manual submit usable without Stimulus. Use a separate formatting toggle with `aria-expanded` and native Lexxy toolbar; do not hide keyboard focus inside a collapsed toolbar.

- [ ] **GREEN: Implement single-flight idle saves and protect drafts.** Use a wait of 600 ms, `FormData(form)`, `Accept: application/json`, and the Rails CSRF token for `fetch`. On connect do not schedule a save; listen only to edits after hydration. Use a monotonically increasing client edit serial:

  ```javascript
  changed() {
    this.serial += 1
    this.dirty = true
    clearTimeout(this.timer)
    if (!this.inFlight && !this.conflicted) this.timer = setTimeout(() => this.save(), 600)
  }

  acceptSave(result, sentSerial) {
    this.revisionTarget.value = result.revision
    this.updateUrl = result.update_url
    this.dirty = this.serial !== sentSerial
    if (!this.dirty) this.statusTarget.textContent = this.savedValue
  }
  ```

  A save snapshots the editor form before sending and posts if no update URL, patches otherwise. If the first response is lost, keep the original snapshot and serial in memory and retry those exactly with the same key; only a successful acknowledgment allows newer local edits to follow via PATCH. A new snapshot must never treat a replay acknowledgment as saving newer local content. Update the browser URL on the first acknowledged save without replacing the open editor; keep the originating list filters and preserve the history entry. Never insert response HTML over the editor. Clear the in-flight flag after every request; schedule the next save only if a newer edit landed and the request succeeded. An error keeps the text and shows Retry; a conflict stops automatic writes and offers Copy Draft and Load Saved, or only Copy Draft when unavailable. Block ordinary Turbo navigation while a draft is still dirty unless the member explicitly discards it; register `beforeunload` only while dirty. Do not store note content in browser local storage or allow Turbo to cache an unsaved editor snapshot. Refresh list projections without replacing the active form, and announce status only on meaningful transitions.

- [ ] **Verify and commit.** Re-run request and system tests above. Verify at 375, 768, 1024 and 1440 CSS px, plus landscape and immediately below/above the two breakpoints. Confirm no hidden keyboard focus, no page-level horizontal overflow, note title/body readable on both themes, and no preference leak across accounts. Commit `feat(notes): autosave Lexxy drafts without overwriting newer edits`.

## Slice 2 — Current note context in chats and completions

### Task 6: Debounce and publish complete vector generations

**Files:** Create `db/migrate/20261121000004_add_note_embedding_state.rb`, `app/models/note/indexable.rb`, `app/jobs/note/index_job.rb`, `app/jobs/note_folder/resume_indexing_job.rb`, `test/jobs/note/index_job_test.rb`. Modify `app/models/note.rb`, `app/models/note/editable.rb`, `app/models/note/trashable.rb`, `app/models/note_folder/trashable.rb`, `app/models/chunk/vectorizable.rb`, and `db/schema.rb`.

- [ ] **RED: Verify the stale-generation boundary.** Reuse `ChatAccountFixtures` and the singleton replacement helper. Set the provider stub to return an object exposing `vectors` and `tokens`; choose the vector width from `Chunk.columns_hash.fetch("embedding").limit`. Changing the note inside the provider stub tests the interval when no DB lock should be held:

  ```ruby
  test "an edit while embeddings are prepared prevents an obsolete publication" do
    note = draft_in(@first.general_note_folder, "First version")
    old_generation = note.embedding_generation
    called = false
    edit_during_embed = lambda do |_text|
      unless called
        called = true
        current = Note.find(note.id)
        current.edit_content!(expected_revision: current.content_revision, title: "New version", body_html: "")
      end
      embedding_result
    end

    with_singleton_replacement(Chunk, :embed_text, edit_during_embed) do
      Note::IndexJob.perform_now(note.id, old_generation)
    end
    assert called
    assert_empty note.chunks.reload
    assert_nil note.reload.indexed_generation
    assert_equal "pending", note.embedding_status
  end
  ```

  Add a branch trash during the same interval, provider failure on a later chunk, restore of a still-current index without re-embedding, restore of a pending branch, title-only indexing, formatting-only save without re-embedding, no vectors published for empty text, and usage ledger assertions. Use a barrier and separate connections for the lock-specific check so nested transactions do not hide a held row lock. Run `bin/rails test test/jobs/note/index_job_test.rb`; expect missing Note embedding state.

- [ ] **GREEN: Split note content edits from embedding generations.** Add `embedding_generation` (bigint, non-null, default 0), `indexed_generation` (nullable bigint), and `embedding_status` (string `empty`, `pending`, `ready`, `failed`, default `empty`). Compose the canonical input from the trimmed title and extracted body, with meaningful paragraph boundaries. Compare before and after in `apply_content!`; increment the generation and set `pending` or `empty` in that transaction when canonical input changes. Clear the live indexed marker for `empty` and delete its chunks. After the outermost transaction commits, invoke `note.index_later(generation)` for nonempty changed input. `index_later` schedules `Note::IndexJob.set(wait: 30.seconds).perform_later(id, generation)`; queued old jobs exit before contacting providers.

- [ ] **GREEN: Prepare vectors without locks; publish versions with a short lock.** Extract `Chunk.embed_text(text)` into class methods in `Chunk::Vectorizable`; use the existing `RubyLLM.embed` provider, dimensions, and error semantics. Existing source saves keep calling it synchronously through `generate_embedding`. Add a `prepared_embedding_result=` writer for note chunks so the existing save callback can consume a precomputed result, then use the existing after-save usage accounting. Do not permit this value through request parameters. For notes, validate nonempty vectors with the configured width, and split canonical text with the existing Baran chunk settings outside the lock.

  ```ruby
  # app/models/note/indexable.rb
  def index_now(generation)
    return unless indexable_generation?(generation)

    prepared = embedding_parts.map { |part| [part, Chunk.embed_text(part)] }
    account.with_lock do
      reload
      if indexable_generation?(generation)
        chunks.destroy_all
        prepared.each_with_index do |(part, result), position|
          chunks.create!(account:, content: part, prepared_embedding_result: result,
            metadata: { "position" => position, "note_generation" => generation })
        end
        update!(indexed_generation: generation, embedding_status: "ready")
      end
    end
  end
  ```

  `indexable_generation?` checks `embedding_generation == generation`, the status is `pending`, and `Note.active_in(account_id).exists?(id:)`; confirm it also fails when the record no longer exists. `Note::IndexJob` finds the note by ID, returns on removal, delegates to `index_now`, retries provider failures with bounded retries, and delegates terminal failure to `mark_index_failed(generation)` under the same lock/eligibility check; do not log provider responses containing user text. `retry_index` transitions only a failed active note back to pending, then enqueues the same generation after commit. `Note#restore` calls `resume_indexing` after commit; that method only enqueues eligible pending text (including failed text reset to pending by restoration). For a restored folder, enqueue `NoteFolder::ResumeIndexingJob` with its ID and delegate to a folder method that intersects `.branch_in` with `Note.active_in` and iterates in batches. A ready, unchanged note retains its current vectors across trash/restore. Add `has_many :chunks, as: :chunkable, dependent: :destroy` to Note so permanent removal cleans up vectors.

- [ ] **Verify and commit.** Migrate, then run `bin/rails test test/jobs/note/index_job_test.rb test/models/chunk/vectorizable_test.rb test/models/notes_trash_test.rb`. Expected: outdated jobs cannot publish or fail a newer version, errors never leave a partial generation, adjacent chunk positions are numeric, and the preexisting embedding usage tests remain green. Commit `feat(notes): index stable note text in the background`.

### Task 7: Scope retrieval and citations to the authorized account and current text

**Files:** Create `app/models/chunk/note_visibility.rb`, `app/models/chat/note_retrieval.rb`, `test/models/chat/note_retrieval_test.rb`, `test/controllers/api/v1/note_retrieval_test.rb`, `test/controllers/note_citations_test.rb`. Modify `app/models/note.rb`, `app/models/chunk.rb`, `app/models/chat/similarity_search.rb`, `app/models/chat/completionable.rb`, `app/models/chat/agent_skillable.rb`, `app/models/message.rb`, `app/jobs/chat_response_job.rb`, `app/controllers/api/v1/application_controller.rb`, `app/controllers/api/v1/completions_controller.rb`, `app/controllers/chunks_controller.rb`, `app/views/messages/_search_content.html.erb`.

- [ ] **RED: Test the provider and citation boundaries, not just the token object.** Share one synthetic text marker per source and use the repo's in-process `Faraday::Adapter::Test` completion adapter without its `similarity_search` stub. Stub `RubyLLM.embed` for query vectors and supply real chunks via the fixture helper. In the API test the user's current second membership intentionally exists for the legacy-switch case:

  ```ruby
  test "a token cannot retrieve notes in the legacy completion account" do
    with_note_completion_capture do |requests|
      post "/v1/chat/completions", params: completion_params.merge(user: @second.uid),
        headers: auth_headers, as: :json

      assert_response :success
      text = requests.flat_map { |request| request.fetch("messages") }.pluck("content").join("\n")
      assert_includes text, "SECOND_TEXT_MARKER"
      assert_not_includes text, "SECOND_NOTE_MARKER"
      assert_not_includes text, "FIRST_NOTE_MARKER"
    end
  end
  ```

  Build `with_note_completion_capture` from `test/controllers/api/v1/completions_controller_test.rb`'s `with_local_completion` (capture requests, keep the real retrieval scope, stub only external model results). Fixtures provide first/second note and Text markers and a foreign private note. Test JSON and SSE positive paths for a valid matching token/current member, mismatched legacy account, and still-valid token after membership removal. For web and API, capture the optional relevance input as well as the final request and prove outdated/inactive markers never appear, even when they would have ranked first. Simulate a trashed folder or edit between initial ranking and each send. Test that an inactive or stale note is absent from the Sources list of a previously generated message and `GET /chunks/:id`, and that an eligible note links directly to its account-qualified URL. Run `bin/rails test test/models/chat/note_retrieval_test.rb test/controllers/api/v1/note_retrieval_test.rb test/controllers/note_citations_test.rb`; expect note passages not yet integrated and note chunk visibility not enforced.

- [ ] **GREEN: Give each completion an explicit, trusted access context.** Use `Chat::NoteRetrieval = Data.define(:kind, :token_id)` as a request/turn value, with `Chat::NoteRetrieval.web` and `Chat::NoteRetrieval.api(id)` constructors (`kind: :web, token_id: nil` or `kind: :api, token_id: id`). The membership and token checks must query current rows rather than trusting associations from request setup:

  ```ruby
  def allowed?(chat)
    return false unless AccountUser.exists?(account_id: chat.account_id, user_id: chat.user_id)

    case kind
    when :web then true
    when :api then ApiToken.exists?(id: token_id, account_id: chat.account_id, user_id: chat.user_id)
    else false
    end
  end
  ```

  `Api::V1::ApplicationController` stores the authenticated `api_token` as `@api_token`; never read this ID from user params. Pass `note_access: Chat::NoteRetrieval.api(@api_token.id)` at both API completion call sites, leaving its legacy account resolution and other source eligibility intact. Pass `.web` from `ChatResponseJob` into the default web completion, and through `complete_with_agent_skills` only to its ordinary-completion fallback; do not pass the capability into executable skill inputs or enable a new retrieval API for existing skills. A missing context excludes notes rather than treating the caller as web. No trusted flag is persisted on `Chat`.

- [ ] **GREEN: Filter, recheck and cite.** Add `Chunk.with_visible_notes(account_id:, include_notes:)`, a relation that preserves non-note rows and admits only chunks belonging to current indexed notes in the given account. Use the same `.active_in` relation as the workspace:

  ```ruby
  ready = Note.active_in(account_id).where(embedding_status: "ready")
    .where("notes.indexed_generation = notes.embedding_generation").select(:id)
  non_notes = Chunk.where.not(chunkable_type: "Note")
  visible = include_notes ? non_notes.or(Chunk.where(chunkable_type: "Note", chunkable_id: ready)) : non_notes
  where(account_id:).merge(visible)
  ```

  Keep the note's whole published chunk set atomic (Task 6); only the eligible generation is present when a note is ready. Scope before `search_by_similarity(..., limit:)` and requery candidate note IDs before passing excerpts to `context_relevance`. For note excerpts use adjacency on the same eligible relation and same note ID, not a previously memoized association. Recheck note candidates again after `with_mcp_tools` finishes setup and immediately before assembling instructions and calling `complete` in both branches. Perform the rechecks and load their note rows and related passages inside `ActiveRecord::Base.uncached`; the Rails query cache must not retain a stale positive membership or visibility check during the turn. Remove newly ineligible rows from the emitted citation IDs as well; do not replace excluded stale excerpts with old message history or alter existing history. Preserve options, source exclusions, guard behavior for existing source types, usage, SSE and stop/stream behavior. When `note_access` is absent, keep old one-argument `similarity_search` calls compatible with existing test doubles.

  Add `Note#display_title` using its saved title or localized untitled text, and use it when `Chunk#title` sees a note. In `Message#similar_chunks`, load the note-visibility relation against the message's saved chat account. In `ChunksController#show`, use the already authorized account to find the scope-filtered chunk and redirect a note chunk to `account_note_path(account, @chunk.chunkable)`; invalid access remains `404`. In `_search_content.html.erb` link a note citation directly to `account_note_path(message.chat.account, chunk.chunkable)` and label its type with `t("nosia.notes.title_singular")`; keep existing non-note links unchanged. Load `chunkable` in the scope used for rendering, but use database rechecks for eligibility rather than a preloaded record.

- [ ] **Verify and commit.** Run the three new tests, plus `bin/rails test test/controllers/api/v1/completions_controller_test.rb test/controllers/chat_account_citations_test.rb test/jobs/chat_response_job_test.rb test/models/chat_account_test.rb`. Expected: all pass; denied note text does not reach either provider stage, legacy Text context still works, and existing direct source links and SSE format are unchanged. Commit `feat(notes): use current authorized note context in chats and completions`.

### Task 8: Expose indexing status, document the boundary, and run release checks

**Files:** Create `app/controllers/notes/index_retries_controller.rb`, `app/controllers/notes/index_statuses_controller.rb`, `app/views/notes/workspaces/_index_status.html.erb`, `app/javascript/controllers/note_index_status_controller.js`, `docs/notes-workspace.md`. Modify `config/routes.rb`, `app/views/notes/workspaces/_editor.html.erb`, `show.html.erb`, `config/locales/en.nosia_notes.yml`, `config/locales/fr.nosia_notes.yml`, `test/controllers/notes_workspace_test.rb`, `test/system/notes_workspace_test.rb`, `docs/README.md`, `README.md`.

- [ ] **RED: Verify that successful writing and failed indexing look different.**

  ```ruby
  get account_note_index_status_path(@first, note)
  assert_response :success
  assert_select "[data-note-index-status='failed']"
  assert_select "form[action='#{account_note_index_retry_path(@first, note)}']"

  assert_enqueued_with(job: Note::IndexJob, args: [note.id, note.embedding_generation]) do
    post account_note_index_retry_path(@first, note)
  end
  assert_redirected_to account_note_path(@first, note)
  assert_equal "pending", note.reload.embedding_status
  ```

  Sign in as a current member and set the existing active note to failed without a live provider. Add a foreign/trashed note status and retry case (`404`, no job), a status announce test while the editor stays mounted, and a keyboard test using the retry control. Run `bin/rails test test/controllers/notes_workspace_test.rb`; expect missing status routes and UI.

- [ ] **GREEN: Add dedicated status and retry resources.** Inside the Task 4 note resource, add `resource :index_status, only: :show` and `resource :index_retry, only: :create`. Use `NotesAccountScoped` to load an active note for both; `IndexRetriesController#create` calls `retry_index` and redirects with `303`. Keep this separate from the edit form and its writer status:

  ```erb
  <div data-note-index-status="<%= note.embedding_status %>" role="status">
    <%= t("nosia.notes.index_status.#{note.embedding_status}") %>
  </div>
  <% if note.embedding_status == "failed" %>
    <%= button_to t("nosia.notes.retry_index"), account_note_index_retry_path(account, note) %>
  <% end %>
  ```

  Return the same Rails partial for `GET` under a dedicated Turbo Frame, no editor content. Poll only while in `pending` for a persisted active note; request the frame at a fixed five-second interval while visible, stop on terminal state or navigation, and resume when an acknowledged autosave produces pending state. The polling controller owns only its frame timer/visibility hooks; it must never replace Lexxy. Keep error controls adjacent to their label and preserve focus. Add a short localized note in the workspace that notes are shared and are sent when appropriate to the configured embedding/completion providers and made available through authorized account API completions.

- [ ] **Document the shipped surface.** Add a README feature line and docs index link. In `docs/notes-workspace.md` explain opening Notes, account switching, folder/tag/search behavior, trash/restore/owner purge, save errors/conflicts, index failures/retry, account-token access, and why deleting a note cannot delete its prior quotations. Add YARD signatures for new public Ruby methods (workspace tree/read scopes, edit, lifecycle, and index transitions); describe exceptions that callers handle. Do not publish notes as a Sources type.

- [ ] **Run the focused and regression checks.**

  ```bash
  bin/rails test test/models/note_folder_test.rb test/models/note_test.rb test/models/notes_trash_test.rb test/jobs/note/index_job_test.rb test/models/chat/note_retrieval_test.rb test/controllers/notes_workspace_test.rb test/controllers/note_citations_test.rb test/controllers/api/v1/note_retrieval_test.rb
  bin/rails test test/controllers/chat_account_citations_test.rb test/controllers/api/v1/completions_controller_test.rb test/models/chat_account_test.rb test/models/chunk/vectorizable_test.rb test/jobs/chat_response_job_test.rb
  bin/rails test:system TEST=test/system/notes_workspace_test.rb
  bundle exec rubocop
  bundle exec brakeman --no-pager
  git diff --check
  ```

  Expected: zero Notes test failures, no new failures in existing retrieval/citation tests, no new lint or scanner warnings caused by Notes, and no whitespace errors. Run `bin/rails test` once on the dedicated database after the focused commands. Check 375px/mobile landscape, tablet drawer/focus, 1024px breakpoint, and 1440px desktop; validate focus order, light and dark active selection contrast, EN and FR strings, announcements and 44px primary/icon target sizes. Do not claim a full pass if a baseline, browser, database, or existing warning prevents it. Commit `docs(notes): explain Notes workflows and AI access` with the status UI split into `feat(notes): show and retry note indexing` if useful. Do not merge, push, or deploy without authorization.

## Spec coverage

| Spec section | Tasks and invariant |
|---|---|
| Workspace and daily use | 4–5: Orbite/home entry, selected account, three/two/one-pane behavior, accessible navigation, all/folder/tag/search views, standalone Lexxy and General fallback. |
| Organization, trash, shared editing | 1–3 and 5: deep hierarchy, pin/reset, separate trash records, branch restore, owner purge, inline tags, optimistic revisions and draft recovery. |
| Persistence and boundaries | 1–5 and 7: shared active relation, same-account writes and results, literal search, disposable test DB, membership checks, and API token/account matching. |
| Chat retrieval and vector lifecycle | 6–8: no save blocking, no partial/stale results, account checks before providers, preserved previous answers, guarded citations, and retry UI. |
| Acceptance and delivery | Both slices required; 8 checks Docs and each test layer. No out-of-scope editor, sharing, or API features. |
