# Shared Chat Composer UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (recommended) or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply approved direction A to new and saved conversations: one composer surface, compact contextual actions, retained rich-text/PDF capabilities, and a reachable Stop action.

**Architecture:** Keep the two request-owning form partials and share their presentation through explicit ERB locals. Preserve Lexxy's generated native toolbar and uploader; expose formatting on demand and delegate the compact PDF button to the native upload command. Existing account/source controllers remain authoritative for request safety; a small presentation-only controller owns disclosures, not upload or submission state.

**Tech Stack:** Actual repository: Ruby 4, Rails 8.0, PostgreSQL/pgvector, Minitest fixtures, Turbo/Stimulus/importmap, Lexxy 0.9.23, Ruby-native Tailwind 4. No dependency, route, schema, provider, or build-system changes.

---

## Approved scope and execution boundary

Read `docs/superpowers/specs/2026-10-19-chat-composer-ui-design.md`. The user chose A, requested the same UI for existing conversations, approved the detailed design, and approved the written specification with "Ok". This plan is not implemented code.

- Preserve membership/account isolation, source registration, upload retry/reset, rich text, `/skill`, MCP persistence, generation, and Turbo history protections.
- Do not redesign the dashboard dropzone, message bubbles, MCP administration, global navigation, or other editors.
- Reuse the existing `stop_chat_path` POST. Do not add actions/routes or change cancellation logic.
- No application tests were run while writing this plan. Record a fresh execution baseline rather than treating historical numbers as current results.
- The previously verified full suite had one existing `Chat::RequestOptionsTest` error: its chunk double lacks `augmented_context`. Do not repair unrelated tests, skip failures, or claim a green full suite with this error.

## File map and interfaces

| Path | Responsibility |
| --- | --- |
| `app/views/chats/_form.html.erb` | New-chat request, optional model, MCP hidden fields, and optional sibling Stop form. |
| `app/views/messages/_form.html.erb` | Saved-message request and existing replaceable Turbo Frame, plus sibling Stop form. |
| `app/views/chats/_composer.html.erb` (new) | Shared editor/source/error/skill/action presentation. Locals: `form`, `chat`, `field`, `skills`, `generating`, `stop_form_id`. |
| `app/views/chats/_tools.html.erb` (new) | Initial-selection disclosure or existing saved-tool management trigger. Locals: `chat`. |
| `app/views/chats/_account.html.erb` | Compact native picker/read-only label. Account help moves to the shared meta row; its ID stays `chat-account-help`. |
| `app/javascript/controllers/composer_chrome_controller.js` (new) | Delegate native PDF command; show/hide native formatting; close presentation disclosures. |
| `app/javascript/controllers/chat_account_controller.js` | Extend the existing editor lock to the new PDF/formatting controls. No replacement state machine. |
| `app/assets/stylesheets/nosia/composer.css` (new) | Scoped component tokens, surface, controls, native-toolbar visibility, responsive/theme/focus rules. |
| `app/assets/tailwind/application.css` | Import the new component stylesheet. |
| `app/views/dashboards/show.html.erb`, `app/views/chats/new.html.erb`, `app/views/chats/show.html.erb` | Remove only redundant outer composer chrome. |
| `test/integration/chat_composer_ui_test.rb` (new) | Form ownership, namespaces, account/empty/error/Stop/background rendering. |
| `test/system/chat_composer_ui_test.rb` (new) | Real native PDF, formatting, shortcuts, Stop, tools, viewport, theme, and locks. |
| Existing composer/account tests | Update only intentional presentation assertions, preserving every safety assertion. |
| `docs/chat-composer.md` (new), `docs/README.md` | Explain the UI, native-toolbar delegation, and verification. |

### Native Lexxy integration decision

Lexxy 0.9.23 generates a complete toolbar, including required overflow plumbing, nested format/highlight/link controls, undo/redo, and its real file chooser. Keep that toolbar inside the editor. Do not copy its template, move an initialized custom element, replace the uploader, or call private Lexical state.

The compact PDF action calls the existing `editor.toolbarElement` upload button's `click()` from the user gesture. A discreet Formatting disclosure reveals the generated toolbar above the input only when requested. This preserves the complete rich-text command set without another permanently visible formatting row. Ctrl/Command+K must reveal the toolbar before delegating to its native Link button; otherwise the native link dialog would open inside a hidden toolbar.

## Commands and test isolation

Run test processes sequentially; they share a database. Use the existing opt-in `ChatAccountFixtures`; never move its YAML into globally discovered `test/fixtures` or change `test/test_helper.rb`.

```sh
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test test/integration/chat_composer_ui_test.rb

# Local ARM64: bypass the incompatible bundled Selenium Manager, process-only.
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec ruby -rselenium-webdriver -e 'Selenium::WebDriver::Chrome::Service.driver_path = "/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path = "/usr/bin/chromium"; load "bin/rails"' -- test test/system/chat_composer_ui_test.rb

RAILS_ENV=test bin/rails tailwindcss:build
```

Do not use `test:system TEST=...` here: the selector was previously ignored. No real AI/MCP/crawl/index workers, live credentials, Node installation, global driver changes, or `.env` output. RuboCop needs the process-only `RUBOCOP_TARGET_RUBY_VERSION=4.0` override for this interpreter.

## Task 0: Establish the execution baseline

- [ ] Check `git status --short --branch`, `bundle check`, and the approved spec. Work on an isolated feature branch containing the account-selection commits, not on `main`; preserve any unrelated work.
- [ ] Build test Tailwind and run the baseline below before modifying templates:

```sh
RAILS_ENV=test bin/rails tailwindcss:build
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test test/integration/composer_partials_render_test.rb test/controllers/chat_account_selection_test.rb test/controllers/chat_account_sources_test.rb test/controllers/chat_account_access_test.rb test/controllers/chat_account_tools_test.rb test/models/chat_account_test.rb
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec ruby -rselenium-webdriver -e 'Selenium::WebDriver::Chrome::Service.driver_path = "/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path = "/usr/bin/chromium"; load "bin/rails"' -- test test/system/chat_account_selection_test.rb
```

- [ ] Record counts, unexpected failures, and relevant screenshots under `/tmp/opencode`. Investigate failures before attributing them to the redesign. The expected feature baseline is zero failures/errors/skips; the known full-suite error is separate.

## Task 1: Share the presentation and introduce a real Stop form

**Files:** Create the shared composer/tools partials and integration test; replace both form wrappers and compact the account partial. Do not change controllers/models/routes.

- [ ] Write `test/integration/chat_composer_ui_test.rb` first:

```ruby
require "test_helper"
require_relative "../support/chat_account_fixtures"

class ChatComposerUiTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures
  include ActionView::RecordIdentifier

  setup { sign_in_picker_user }

  test "both entry points use one shared surface and preserve new-chat fields" do
    [ user_root_url, new_chat_url ].each do |url|
      get url, params: { account_id: @second.id, model: "picker-test-model" }

      assert_response :success
      assert_select "#chat-form .n-chat-composer .n-composer-surface", count: 1
      assert_select "lexxy-editor[name='chat[prompt]'][data-composer-target=editor][data-composer-sources-target=editor]"
      assert_select "input[name='chat[attached_website_ids][]'][data-composer-sources-target=websiteIds]"
      assert_select "input[name='chat[attached_document_ids][]'][data-composer-sources-target=documentIds]"
      assert_select "input[name='chat[model]'][value='picker-test-model']"
      assert_select "#mcp-server-hidden-fields[data-mcp-fields-sync-target=hiddenFields]"
      assert_select ".n-composer-actions select[name='chat[account_id]'] option[selected][value='#{@second.id}']"
      assert_select "[data-composer-tools] input[name='mcp_server_ids[]'][value='#{mcp_servers(:picker_second_tool).id}']"
      assert_select "[data-composer-tools]", text: /ms/, count: 0
      assert_select "#chat-account-help", text: "Searches and attachments use this account."
      assert_select "button[aria-label=Send][data-chat-account-target=send]"
      assert_select ".n-composer-validation", count: 0
      assert_select "form form", count: 0
    end
  end

  test "saved generation exposes Stop on a separate form and no editable account" do
    chat = chats(:picker_second_chat)
    chat.start_generation!
    get chat_url(chat)

    assert_response :success
    assert_select "turbo-frame##{dom_id(chat)}_message_form .n-chat-composer", count: 1
    assert_select "lexxy-editor[name='message[content]'][disabled]"
    assert_select "input[name='message[attached_website_ids][]']"
    assert_select "input[name='message[attached_document_ids][]']"
    assert_select "[data-chat-account-readonly]", text: /Research team/
    assert_select "select[name='chat[account_id]']", count: 0
    assert_select "button[aria-label=Send]", count: 0
    assert_select "button[aria-label='Stop generating'][form='#{dom_id(chat, :composer_stop)}']"
    assert_select "form##{dom_id(chat, :composer_stop)}[method=post][action='#{stop_chat_path(chat)}'][data-turbo-frame='_top']"
    assert_select "form[data-chat-account-target=form] button[aria-label='Stop generating']"
    assert_select "form form", count: 0

    counts = [ Chat.count, Message.count ]
    assert_no_enqueued_jobs only: ChatResponseJob do
      post stop_chat_url(chat)
    end
    assert_redirected_to chat_url(chat)
    assert_not chat.reload.generating?
    assert chat.generation_stopped?
    assert_equal counts, [ Chat.count, Message.count ]
  end

  test "saved partial renders the same surface without request Current" do
    Current.reset
    chat = chats(:picker_second_chat)
    html = ApplicationController.render(partial: "messages/form", locals: { chat: chat })
    fragment = Nokogiri::HTML.fragment(html)

    assert_select fragment, ".n-chat-composer .n-composer-surface", count: 1
    assert_select fragment, "[data-chat-account-readonly]", text: /Research team/
    assert_select fragment, "button[aria-label=Send]"
    assert_select fragment, "select[name='chat[account_id]']", count: 0
  end

  test "validation errors render only when present and remain escaped" do
    chat = @user.chats.new(account: @second)
    chat.errors.add(:base, "Invalid <script>message</script>")
    html = Current.set(session: Session.new(user: @user)) do
      ApplicationController.render(partial: "chats/form", locals: { chat: chat })
    end
    fragment = Nokogiri::HTML.fragment(html)

    assert_select fragment, ".n-composer-validation[role=alert]", text: /Invalid/
    assert_select fragment, ".n-composer-validation script", count: 0
  end

  test "empty options retain composing and the no-account state remains empty" do
    @first.mcp_servers.destroy_all
    @first.agent_skills.destroy_all
    get new_chat_url
    assert_select ".n-chat-composer"
    assert_select "[data-composer-tools]", count: 0
    assert_select ".n-composer-hints", text: /skills/, count: 0

    delete logout_url
    sign_in_picker_user(users(:picker_no_account))
    get new_chat_url
    assert_select "[data-chat-no-account]"
    assert_select ".n-chat-composer, lexxy-editor", count: 0
  end
end
```

- [ ] Run the new test. Expected RED: shared surface/Stop markup absent, not syntax or fixture errors.
- [ ] Replace `app/views/chats/_form.html.erb` with:

```erb
<% if chat.account.present? %>
  <% generating = chat.persisted? && chat.generating? %>
  <% skills = JSON.parse(agent_skill_autocomplete_data(chat.account)) %>
  <% stop_form_id = dom_id(chat, :composer_stop) if generating %>
  <%= form_with model: chat, url: chats_path, id: "chat-form", class: "w-full",
        data: { controller: "mcp-fields-sync", chat_account_target: "form", generation_busy: generating,
          action: "submit->chat-account#guard submit->mcp-fields-sync#copy" } do |form| %>
    <%= form.hidden_field :model, value: @selected_model if @selected_model.present? %>
    <div id="mcp-server-hidden-fields" data-mcp-fields-sync-target="hiddenFields"></div>
    <%= render "chats/composer", form: form, chat: chat, field: :prompt,
      skills: skills, generating: generating, stop_form_id: stop_form_id %>
  <% end %>
  <% if generating %>
    <%= form_with url: stop_chat_path(chat), method: :post, id: stop_form_id,
      html: { hidden: true }, data: { turbo_frame: "_top" } do %>
    <% end %>
  <% end %>
<% else %>
  <%= render "chats/no_account" %>
<% end %>
```

- [ ] Replace `app/views/messages/_form.html.erb` with:

```erb
<%= turbo_frame_tag "#{dom_id(chat)}_message_form" do %>
  <% generating = chat.generating? %>
  <% skills = JSON.parse(agent_skill_autocomplete_data(chat.account)) %>
  <% stop_form_id = dom_id(chat, :composer_stop) if generating %>
  <%= form_with model: Message.new, url: [chat, chat.messages.new], class: "w-full",
        data: { chat_account_target: "form", generation_busy: generating,
          action: "submit->chat-account#guard" } do |form| %>
    <%= render "chats/composer", form: form, chat: chat, field: :content,
      skills: skills, generating: generating, stop_form_id: stop_form_id %>
  <% end %>
  <% if generating %>
    <%= form_with url: stop_chat_path(chat), method: :post, id: stop_form_id,
      html: { hidden: true }, data: { turbo_frame: "_top" } do %>
    <% end %>
  <% end %>
<% end %>
```

- [ ] Create `app/views/chats/_composer.html.erb`:

```erb
<%# locals: (form:, chat:, field:, skills:, generating:, stop_form_id:) %>
<% editor_id = form.field_id(field) %>
<% validation_id = "#{editor_id}_validation" %>
<% source_errors_id = "#{editor_id}_sources" %>
<div class="n-chat-composer" data-controller="composer composer-sources"
     data-composer-skills-value="<%= skills.to_json %>"
     data-composer-sources-account-id-value="<%= chat.account_id %>"
     data-composer-sources-chat-id-value="<%= chat.id if chat.persisted? %>"
     data-action="chat-account:reset@window->composer-sources#reset">
  <div class="n-composer-surface">
    <%= form.label field, "Message", class: "sr-only" %>
    <%= form.lexxy_rich_text_area field, id: editor_id,
      permitted_attachment_types: "application/pdf", toolbar: '{"upload":"file"}',
      autofocus: !generating, placeholder: generating ? "Generating…" : "Ask anything…",
      disabled: generating, aria: { describedby: [source_errors_id, (validation_id if form.object.errors.any?)].compact.join(" ") },
      data: { composer_target: "editor", composer_sources_target: "editor" },
      class: "n-composer-editor" %>
    <%= form.hidden_field :attached_website_ids, multiple: true, value: nil, data: { composer_sources_target: "websiteIds" } %>
    <%= form.hidden_field :attached_document_ids, multiple: true, value: nil, data: { composer_sources_target: "documentIds" } %>
    <div class="n-skill-menu hidden" role="listbox" aria-label="Available skills" data-composer-target="menu"></div>
    <ul id="<%= source_errors_id %>" hidden role="alert" class="n-composer-errors" data-composer-sources-target="errors"></ul>
    <% if form.object.errors.any? %>
      <ul id="<%= validation_id %>" class="n-composer-errors n-composer-validation" role="alert" aria-label="Message errors">
        <% form.object.errors.each do |error| %>
          <li><%= error.full_message %></li>
        <% end %>
      </ul>
    <% end %>

    <div class="n-composer-actions">
      <%= render "chats/account", chat: chat, form: form %>
      <%= render "chats/tools", chat: chat %>
      <% if generating %>
        <%= form.button type: :submit, form: stop_form_id, class: "n-composer-send n-composer-stop",
              aria: { label: "Stop generating" }, title: "Stop generating" do %>
          <svg class="n-composer-icon" aria-hidden="true" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="6" width="12" height="12" rx="1"/></svg>
        <% end %>
      <% else %>
        <%= form.button type: :submit, class: "n-composer-send", aria: { label: "Send" }, title: "Send",
              data: { chat_account_target: "send" } do %>
          <svg class="n-composer-icon" aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M12 19V5m-6 6 6-6 6 6"/></svg>
        <% end %>
      <% end %>
    </div>
  </div>
  <div class="n-composer-meta">
    <span id="chat-account-help">Searches and attachments use this account.</span>
    <span class="n-composer-hints">Enter to send · Shift+Enter for a line break<%= " · / for skills" if skills.any? %></span>
  </div>
  <p class="n-composer-notice">NOSIA can make mistakes. Check important information.</p>
</div>
```

This first extraction deliberately retains the visible native editor toolbar. Compact PDF/Formatting controls arrive with their tested controller in Task 2; CSS hides the native row by default only in Task 3. Each intermediate task therefore retains a working uploader rather than rendering controls with undefined handlers.

- [ ] Create `app/views/chats/_tools.html.erb`:

```erb
<%# locals: (chat:) %>
<% if chat.persisted? %>
  <button type="button" class="n-composer-control n-composer-tools-trigger"
          data-controller="modal-open" data-modal-open-target-value="mcp-selector-modal"
          data-action="click->modal-open#open" aria-controls="mcp-selector-modal">
    Tools <span class="n-composer-count"><%= chat.chat_mcp_sessions.count %></span>
  </button>
<% else %>
  <% servers = ready_chat_mcp_servers(chat.account) %>
  <% if servers.any? %>
    <details class="n-composer-tools" data-composer-tools>
      <summary class="n-composer-control">Tools <span id="mcp-selected-count" class="n-composer-count">0</span></summary>
      <div class="n-composer-tools-panel" data-controller="mcp-selection">
        <p class="n-composer-tools-heading">Connected tools</p>
        <% servers.each do |server| %>
          <label class="n-composer-tool-option">
            <input type="checkbox" name="mcp_server_ids[]" value="<%= server.id %>" data-action="change->mcp-selection#updateCount">
            <span title="<%= server.name %>"><%= server.name %></span>
          </label>
        <% end %>
      </div>
    </details>
  <% end %>
<% end %>
```

- [ ] Replace `app/views/chats/_account.html.erb`; retain IDs/actions/default selection:

```erb
<div class="n-composer-account">
  <% if chat.persisted? %>
    <span data-chat-account-readonly title="<%= chat.account.name %>">Account: <%= chat.account.name %></span>
  <% else %>
    <%= form.label :account_id, "Account" %>
    <%= form.collection_select :account_id, Current.user.accounts.order(:name), :id, :name,
      { selected: chat.account_id, prompt: "Select an account" },
      { required: true, aria: { describedby: "chat-account-help" },
        data: { chat_account_target: "picker", action: "change->chat-account#change" } } %>
  <% end %>
</div>
```

- [ ] Update only these two old assertions in `test/controllers/chat_account_selection_test.rb`:

```ruby
# Saved tools trigger: replace the old MCP (1) text assertion.
assert_select "button.n-composer-tools-trigger", text: /Tools\s+1/

# Generating saved form: replace the disabled Send assertion.
assert_select "button[aria-label=Send]", count: 0
assert_select "button[aria-label='Stop generating'][form='#{dom_id(chat, :composer_stop)}']"
```

- [ ] In the four existing `test/system/chat_account_selection_test.rb` occurrences that find a summary by `/MCP Tools/`, replace only that lookup with:

```ruby
find("[data-composer-tools] summary").click
```

Keep the subsequent checks, request counts, saved-source assertions, and history actions intact. This is a label adaptation, not permission to weaken behavior coverage.

- [ ] Run the integration file plus existing composer/selection/access/model tests and the original 44 browser cases GREEN. Keep field names, source contexts, toolbar configuration, frame IDs, and background rendering assertions. Commit only the named ERB/test files: `refactor: Share chat composer presentation and Stop controls`.

## Task 2: Delegate native PDF/formatting and extend the existing edit lock

**Files:** Create `composer_chrome_controller.js` and the initial UI system test; modify the account coordinator only for editing-control synchronization.

- [ ] Create `test/system/chat_composer_ui_test.rb` with these failing interactions:

```ruby
require "application_system_test_case"
require "tempfile"
require_relative "../support/chat_account_fixtures"

class ChatComposerUiSystemTest < ApplicationSystemTestCase
  include ChatAccountFixtures
  include ActionView::RecordIdentifier

  setup do
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_on "Sign in"
    visit new_chat_url(model: "picker-test-model")
    assert_selector "lexxy-editor[connected]"
  end

  test "compact PDF action uses the native uploader in both new-chat entry points" do
    [ user_root_url(account_id: @second.id), new_chat_url(account_id: @second.id) ].each do |url|
      visit url
      assert_selector "lexxy-editor[connected]"
      with_pdf do |path|
        assert_enqueued_jobs 1, only: AddDocumentJob do
          attach_file(path) { click_button "Attach PDF" }
          assert_selector "input[name='chat[attached_document_ids][]']", count: 2, visible: :all
        end
        document = @second.documents.joins(file_attachment: :blob).find_by!(active_storage_blobs: { filename: File.basename(path) })
        assert_equal File.binread(path), document.file.download
        assert_not @first.documents.joins(file_attachment: :blob).exists?(active_storage_blobs: { filename: File.basename(path) })
      end
    end
  end

  test "formatting opens by keyboard and still runs native bold and link commands" do
    content = find("lexxy-editor .lexxy-editor__content")
    content.send_keys("Format this")
    content.send_keys([ :control, "a" ])
    find("summary[aria-label=Formatting]").send_keys(:enter)
    assert_selector ".n-chat-composer[data-formatting-open] lexxy-toolbar"
    find("lexxy-toolbar button[name=bold]").click
    assert_selector "lexxy-editor strong", text: "Format this"
    find("lexxy-editor .lexxy-editor__content").send_keys([ :control, "k" ])
    assert_selector "lexxy-link-dropdown [data-dropdown-panel]:not([hidden]) input[type=url]"
    find("lexxy-link-dropdown input[type=url]").send_keys(:escape)
    find("lexxy-editor .lexxy-editor__content").send_keys(:escape)
    assert_no_selector ".n-chat-composer[data-formatting-open]"
    assert_selector "summary[aria-label=Formatting]:focus"
  end

  test "submission locks the compact actions and restores real formatting afterwards" do
    form = find("#chat-form")
    page.execute_script("arguments[0].dispatchEvent(new CustomEvent('turbo:submit-start', { bubbles: true }))", form)
    assert_selector "[data-chat-account-target=editingTools][inert][aria-disabled=true]"
    assert_button "Attach PDF", disabled: true
    assert_selector "lexxy-editor[inert][disabled]"
    page.execute_script("document.querySelector('[data-action=\"composer-chrome#upload\"]').click()")
    assert_no_selector "lexxy-editor input[type=file]", visible: :all
    page.execute_script("arguments[0].dispatchEvent(new CustomEvent('turbo:submit-end', { bubbles: true }))", form)
    assert_button "Attach PDF", disabled: false
    assert_no_selector "[data-chat-account-target=editingTools][inert]"
    find("summary[aria-label=Formatting]").send_keys(:enter)
    assert_selector ".n-chat-composer[data-formatting-open] lexxy-toolbar"
  end

  test "saved generation has a reachable Stop and returns to the same enabled composer" do
    chat = chats(:picker_second_chat)
    chat.start_generation!
    visit chat_url(chat)
    assert_selector "lexxy-editor[inert][disabled]"
    assert_selector "[data-chat-account-readonly]", text: /Research team/
    assert_button "Attach PDF", disabled: true
    counts = [ Chat.count, Message.count ]
    click_button "Stop generating"
    assert_selector "button[aria-label=Send]:not([disabled])"
    assert_no_selector "button[aria-label='Stop generating']"
    assert_selector ".n-chat-composer lexxy-editor:not([inert]):not([disabled])"
    assert_equal counts, [ Chat.count, Message.count ]
    assert chat.reload.generation_stopped?
    assert_not chat.generating?
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  private
    def with_pdf
      stream = "BT /F1 12 Tf 40 100 Td (Composer PDF) Tj ET\n"
      objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        "<< /Length #{stream.bytesize} >>\nstream\n#{stream}endstream"
      ]
      pdf = +"%PDF-1.4\n"
      offsets = objects.each_with_index.map do |object, index|
        offset = pdf.bytesize
        pdf << "#{index + 1} 0 obj\n#{object}\nendobj\n"
        offset
      end
      start = pdf.bytesize
      pdf << "xref\n0 6\n0000000000 65535 f \n"
      offsets.each { |offset| pdf << format("%010d 00000 n \n", offset) }
      pdf << "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n#{start}\n%%EOF\n"
      Tempfile.create([ "composer-ui", ".pdf" ]) do |file|
        file.binmode
        file.write(pdf)
        file.flush
        yield file.path
      end
    end
end
```

- [ ] Run this browser file RED before implementing chrome/lock behavior. Expected failures: missing controller delegation and missing editingTools synchronization. Real browser boot errors are not a behavioral RED.
- [ ] In `chats/_composer.html.erb`, add `composer-chrome` to the root controller token list, add `composer_chrome_target: "editor"` to the editor's data hash, and replace the root's `data-action` with:

```erb
data-action="chat-account:reset@window->composer-sources#reset chat-account:reset@window->composer-chrome#reset keydown.esc->composer-chrome#escape keydown->composer-chrome#linkShortcut:capture click@document->composer-chrome#outside"
```

Insert this editing group at the start of `.n-composer-actions`, before the account partial:

```erb
<%= tag.div class: "n-composer-editing-tools", role: "group", aria: { label: "Editor actions", disabled: generating },
      inert: generating, data: { chat_account_target: "editingTools" } do %>
  <button type="button" class="n-composer-control" aria-label="Attach PDF" data-action="composer-chrome#upload" <%= "disabled" if generating %>>
    <svg class="n-composer-icon" aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path stroke-linecap="round" stroke-linejoin="round" d="m8 12 6-6a3.5 3.5 0 0 1 5 5l-8 8a5 5 0 0 1-7-7l8-8M7 14l7-7"/></svg>
    <span>PDF</span>
  </button>
  <details class="n-composer-formatting" data-composer-chrome-target="formatting" data-action="toggle->composer-chrome#syncFormatting">
    <summary class="n-composer-control" aria-label="Formatting" title="Formatting" data-action="keydown.enter->composer-chrome#formattingKey keydown.space->composer-chrome#formattingKey">
      <svg class="n-composer-icon" aria-hidden="true" viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="19" cy="12" r="1.5"/></svg>
    </summary>
    <span class="sr-only">Text formatting controls appear above the message.</span>
  </details>
<% end %>
```

In `chats/_tools.html.erb`, change the new-chat details opening tag to:

```erb
<details class="n-composer-tools" data-composer-tools data-action="toggle->composer-chrome#toolsToggled">
```

The Formatting utility preserves the existing rich-text commands, not a new Skills feature. Keep the native toolbar DOM intact.
- [ ] Create `app/javascript/controllers/composer_chrome_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["editor", "formatting"]

  get locked() {
    return this.editorTarget.inert || this.editorTarget.hasAttribute("disabled") || Boolean(this.element.closest("[inert]"))
  }

  get toolbar() {
    return this.editorTarget.toolbarElement
  }

  upload() {
    if (this.locked) return
    this.toolbar?.querySelector("button[data-command='uploadFile']")?.click()
  }

  syncFormatting() {
    if (this.locked) this.formattingTarget.open = false
    this.element.toggleAttribute("data-formatting-open", this.formattingTarget.open)
    if (this.formattingTarget.open) {
      this.toolbar?.requestOverflowRefresh()
    } else {
      this.toolbar?.closeDropdowns({})
    }
  }

  formattingKey(event) {
    event.preventDefault()
    if (this.locked) return
    this.formattingTarget.open = !this.formattingTarget.open
    this.syncFormatting()
    if (this.formattingTarget.open) {
      requestAnimationFrame(() => {
        if (!this.element.isConnected || !this.formattingTarget.open || this.locked) return
        const button = [...(this.toolbar?.querySelectorAll("button") || [])].find(item => !item.disabled && item.getClientRects().length)
        button?.focus()
      })
    }
  }

  linkShortcut(event) {
    if (event.key.toLowerCase() !== "k" || !(event.ctrlKey || event.metaKey) || this.locked) return
    if (!this.editorTarget.contains(event.target)) return
    event.preventDefault()
    event.stopPropagation()
    this.formattingTarget.open = true
    this.syncFormatting()
    this.toolbar?.querySelector("button[name='link']")?.click()
  }

  toolsToggled(event) {
    if (event.currentTarget.open) {
      this.formattingTarget.open = false
      this.syncFormatting()
    }
  }

  escape(event) {
    const tools = this.element.querySelector("[data-composer-tools][open]")
    if (tools) {
      event.preventDefault()
      tools.open = false
      tools.querySelector("summary")?.focus()
    } else if (this.formattingTarget.open) {
      event.preventDefault()
      this.formattingTarget.open = false
      this.syncFormatting()
      this.formattingTarget.querySelector("summary")?.focus()
    }
  }

  outside(event) {
    if (!this.element.contains(event.target)) this.closeDisclosures()
  }

  reset(event) {
    if (event.detail?.root && !event.detail.root.contains(this.element)) return
    this.closeDisclosures()
  }

  closeDisclosures() {
    this.formattingTarget.open = false
    const tools = this.element.querySelector("[data-composer-tools]")
    if (tools) tools.open = false
    this.syncFormatting()
  }
}
```

Do not add an asynchronous uploader, upload state, native toolbar template copying, or private Lexical APIs here. Keep the existing toolbar lifecycle/disposal under Lexxy.

- [ ] In `chat_account_controller.js`, change the target declaration and add the connection callback:

```javascript
static targets = ["picker", "form", "send", "editingTools"]

editingToolsTargetConnected() {
  this.syncControls()
}
```

Inside the existing `if (this.hasFormTarget)` in `syncControls()`, immediately after synchronizing the editor and before the Send target, insert:

```javascript
for (const group of this.editingToolsTargets) {
  group.inert = editorLocked
  group.setAttribute("aria-disabled", String(editorLocked))
  for (const button of group.querySelectorAll("button")) button.disabled = editorLocked
}
```

This group excludes account selection, saved tool management, and Stop. Pending source registration does not lock text/PDF editing: existing pending rules still lock Send/account. Preserve that distinction and all existing navigation/generation flags.

- [ ] Build Tailwind, run the new UI file and the old account browser file GREEN, and run the integration tests too. The native toolbar remains visible until Task 3; this task verifies the new command delegation and safety behavior. Commit only the new controller, coordinator, the two view additions, and UI system test: `feat: Delegate compact composer controls to native Lexxy`.

## Task 3: Apply scoped styling and remove duplicate outer chrome

**Files:** Create `composer.css`; import it; modify only the surrounding composer wrappers on dashboard/new/show. Extend the new UI browser test.

- [ ] Add these tests before styling, then run them RED:

```ruby
test "the shared surface fits narrow screens with long account names in both themes" do
  @second.update!(name: "Research team with a deliberately long account name")
  [ false, true ].each do |dark|
    [ new_chat_url(account_id: @second.id), chat_url(chats(:picker_second_chat)) ].each do |url|
      visit url
      page.current_window.resize_to(375, 844)
      page.execute_script("document.documentElement.classList.toggle('dark', arguments[0])", dark)
      assert_selector ".n-chat-composer"
      bounds = page.evaluate_script(<<~JS)
        (() => {
          const selectors = ['.n-composer-surface', '.n-composer-account', '.n-composer-send'];
          return selectors.map(selector => {
            const rect = document.querySelector(selector).getBoundingClientRect();
            return { left: rect.left, right: rect.right, width: rect.width, height: rect.height };
          });
        })()
      JS
      bounds.each do |rect|
        assert_operator rect.fetch("left"), :>=, 0
        assert_operator rect.fetch("right"), :<=, page.evaluate_script("window.innerWidth")
      end
      assert_operator bounds.last.fetch("width"), :>=, 40
      assert_operator bounds.last.fetch("height"), :>=, 40
      assert_no_selector "lexxy-editor lexxy-toolbar"
      assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('.n-composer-editor')).boxShadow")
      assert_equal 0, page.evaluate_script("parseFloat(getComputedStyle(document.querySelector('.n-composer-editor')).borderTopWidth)")
    end
  end
ensure
  page.current_window.resize_to(1400, 1400)
end

test "normal help and primary controls meet text contrast in both themes" do
  [ false, true ].each do |dark|
    page.execute_script("document.documentElement.classList.toggle('dark', arguments[0])", dark)
    ratios = page.evaluate_script(<<~JS)
      (() => {
        const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1;
        const context = canvas.getContext('2d', { willReadFrequently: true });
        const rgb = color => { context.clearRect(0, 0, 1, 1); context.fillStyle = color; context.fillRect(0, 0, 1, 1); return [...context.getImageData(0, 0, 1, 1).data].slice(0, 3); };
        const luminance = values => values.map(value => { const v = value / 255; return v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4; }).reduce((sum, value, i) => sum + value * [.2126, .7152, .0722][i], 0);
        const ratio = (a, b) => { const x = luminance(rgb(a)); const y = luminance(rgb(b)); return (Math.max(x, y) + .05) / (Math.min(x, y) + .05); };
        const surface = getComputedStyle(document.querySelector('.n-composer-surface')).backgroundColor;
        const help = getComputedStyle(document.querySelector('.n-composer-meta'));
        const pageBackground = getComputedStyle(document.body).backgroundColor;
        const send = getComputedStyle(document.querySelector('.n-composer-send'));
        return { help: ratio(help.color, pageBackground), send: ratio(send.color, send.backgroundColor), control: ratio(getComputedStyle(document.querySelector('.n-composer-control')).color, surface) };
      })()
    JS
    ratios.each_value { |value| assert_operator value, :>=, 4.5 }
  end
end

test "reduced motion and hovering Send do not rotate the primary action" do
  page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
  find("button[aria-label=Send]").hover
  assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('.n-composer-send')).transform")
  assert_equal "0s", page.evaluate_script("getComputedStyle(document.querySelector('.n-composer-send')).transitionDuration")
ensure
  page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
end
```

These assert real browser geometry/computed styles, not just class names. Add a 375px Tools-open assertion in Task 4. Compare helper text with its actual surface; the wrappers below become transparent, so the body background is appropriate here.

- [ ] Create `app/assets/stylesheets/nosia/composer.css` with scoped component rules:

```css
.n-chat-composer {
  --composer-paper: var(--color-white);
  --composer-text: var(--color-neutral-900);
  --composer-muted: var(--color-neutral-600);
  --composer-border: var(--color-neutral-300);
  --composer-hover: var(--color-neutral-100);
  --composer-accent: var(--color-green-700);
  --composer-on-accent: var(--color-white);
  --composer-danger: var(--color-red-700);
  position: relative;
  color: var(--composer-text);
  font-size: 0.875rem;
  min-width: 0;
}

.dark .n-chat-composer {
  --composer-paper: var(--color-neutral-800);
  --composer-text: var(--color-neutral-100);
  --composer-muted: var(--color-neutral-300);
  --composer-border: var(--color-neutral-600);
  --composer-hover: var(--color-neutral-700);
  --composer-accent: var(--color-green-300);
  --composer-on-accent: var(--color-neutral-900);
  --composer-danger: var(--color-red-300);
}

.n-chat-composer .n-composer-surface {
  border: 1px solid var(--composer-border);
  border-radius: 1rem;
  background: var(--composer-paper);
  box-shadow: 0 2px 8px rgb(0 0 0 / 0.03);
  overflow: visible;
}

.n-chat-composer .n-composer-editor {
  border: 0;
  border-radius: 1rem;
  box-shadow: none;
  padding: 0;
  background: transparent;
  color: var(--composer-text);
  --lexxy-editor-rows: 3lh;
}

.n-chat-composer .n-composer-editor .lexxy-editor__content {
  padding: 1rem;
  min-block-size: 7rem;
}

.n-chat-composer:not([data-formatting-open]) lexxy-toolbar { display: none; }
.n-chat-composer lexxy-toolbar { border-radius: 1rem 1rem 0 0; }

.n-chat-composer .n-composer-actions,
.n-chat-composer .n-composer-editing-tools,
.n-chat-composer .n-composer-account {
  display: flex;
  align-items: center;
  min-width: 0;
  gap: 0.375rem;
}

.n-chat-composer .n-composer-actions { flex-wrap: wrap; padding: 0.5rem 0.75rem 0.75rem; }
.n-chat-composer .n-composer-editing-tools { flex-shrink: 0; }
.n-chat-composer .n-composer-editing-tools[inert] { opacity: 0.5; }
.n-chat-composer .n-composer-account { flex: 0 1 auto; max-width: 100%; }
.n-chat-composer .n-composer-account label { font-size: 0.75rem; color: var(--composer-muted); flex-shrink: 0; }
.n-chat-composer .n-composer-account [data-chat-account-readonly] { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 0.75rem; }
.n-chat-composer .n-composer-account select {
  min-height: 36px;
  min-width: 0;
  max-width: min(16rem, 100%);
  padding: 0.375rem;
  border: 0;
  border-radius: 0.5rem;
  background: var(--composer-paper);
  color: var(--composer-text);
  font-size: 0.75rem;
  font-weight: 600;
}

.n-chat-composer .n-composer-control,
.n-chat-composer .n-composer-send {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.375rem;
  flex-shrink: 0;
  min-height: 36px;
  padding: 0.375rem 0.5rem;
  border: 0;
  border-radius: 0.5rem;
  background: transparent;
  color: var(--composer-muted);
  font: inherit;
  font-size: 0.75rem;
  cursor: pointer;
  list-style: none;
  transition: background-color 150ms, color 150ms;
}

.n-chat-composer summary::-webkit-details-marker { display: none; }
.n-chat-composer .n-composer-control:hover:not(:disabled) { background: var(--composer-hover); color: var(--composer-text); }
.n-chat-composer .n-composer-icon { width: 1.125rem; height: 1.125rem; flex-shrink: 0; }
.n-chat-composer .n-composer-send {
  margin-left: auto;
  width: 40px;
  height: 40px;
  min-height: 40px;
  padding: 0;
  border-radius: 0.625rem;
  background: var(--composer-accent);
  color: var(--composer-on-accent);
  transform: none;
}
.n-chat-composer .n-composer-send:hover:not(:disabled) { filter: brightness(0.95); }
.n-chat-composer .n-composer-stop { background: var(--composer-danger); }
.n-chat-composer button:disabled, .n-chat-composer select:disabled { cursor: not-allowed; opacity: 0.5; }
.n-chat-composer :is(button, summary, select):focus-visible { outline: 2px solid var(--composer-accent); outline-offset: 3px; }
.n-chat-composer .n-composer-count { border-radius: 0.25rem; padding: 0 0.3rem; background: var(--composer-hover); color: var(--composer-text); }

.n-chat-composer .n-composer-tools { position: relative; min-width: 0; }
.n-chat-composer .n-composer-tools-panel {
  position: absolute;
  bottom: calc(100% + 0.5rem);
  left: 0;
  z-index: 30;
  width: 16rem;
  max-width: calc(100vw - 4rem);
  max-height: min(16rem, 45dvh);
  overflow: auto;
  padding: 0.5rem;
  border: 1px solid var(--composer-border);
  border-radius: 0.75rem;
  background: var(--composer-paper);
  box-shadow: 0 8px 24px rgb(0 0 0 / 0.12);
}
.n-chat-composer .n-composer-tools-heading { padding: 0.25rem; color: var(--composer-muted); font-size: 0.75rem; }
.n-chat-composer .n-composer-tool-option { display: flex; align-items: center; gap: 0.5rem; padding: 0.5rem 0.25rem; cursor: pointer; }
.n-chat-composer .n-composer-tool-option input { flex-shrink: 0; accent-color: var(--composer-accent); }
.n-chat-composer .n-composer-tool-option span { min-width: 0; overflow-wrap: anywhere; }
.n-chat-composer .n-composer-meta { display: flex; justify-content: space-between; flex-wrap: wrap; gap: 0.375rem 1rem; padding: 0.5rem 0.25rem 0; color: var(--composer-muted); font-size: 0.75rem; }
.n-chat-composer .n-composer-notice { margin: 0.75rem 0 0; color: var(--composer-muted); font-size: 0.75rem; text-align: center; }
.n-chat-composer .n-composer-errors { list-style: none; margin: 0.5rem 1rem; padding: 0; color: var(--composer-danger); font-size: 0.875rem; }
.n-chat-composer .n-composer-errors button { margin-left: 0.5rem; text-decoration: underline; }

@media (max-width: 639px) {
  .n-chat-composer .n-composer-account { order: -1; flex-basis: 100%; }
  .n-chat-composer .n-composer-account select { max-width: calc(100% - 4rem); }
  .n-chat-composer .n-composer-tools { position: static; }
  .n-chat-composer .n-composer-actions { position: relative; }
  .n-chat-composer .n-composer-tools-panel { left: 0.75rem; right: 0.75rem; width: auto; max-width: none; }
}

@media (prefers-reduced-motion: reduce) {
  .n-chat-composer *, .n-chat-composer *::before, .n-chat-composer *::after { transition-duration: 0s !important; animation-duration: 0s !important; }
}
```

- [ ] Add the stylesheet import after `form.css` in `app/assets/tailwind/application.css`:

```css
@import "../stylesheets/nosia/composer.css" layer(utilities);
```

- [ ] Replace only the redundant outer wrapper classes around the form render with `class="mx-auto pointer-events-auto"` in all three entry-point templates. Preserve each root's controller/actions and the dashboard uploader exactly. The resulting inner sections are:

```erb
<%# dashboards/show.html.erb: replace the current composer section only %>
<section class="w-full max-w-4xl mx-auto">
  <div class="mx-auto pointer-events-auto">
    <%= render "chats/form", chat: @chat %>
  </div>
</section>
```

```erb
<%# chats/new.html.erb: keep its root unchanged %>
<section class="w-full max-w-4xl mx-auto">
  <div class="mx-auto pointer-events-auto">
    <%= render "form", chat: @chat %>
  </div>
</section>
```

```erb
<%# chats/show.html.erb: keep messages, subscriptions, root, and modal unchanged %>
<section class="w-full max-w-4xl mx-auto">
  <div class="mx-auto pointer-events-auto">
    <%= render partial: "messages/form", locals: { chat: @chat } %>
  </div>
</section>
```

- [ ] Adapt the original account browser test "submission prevents real toolbar formatting" to reveal Formatting before its physical click attempts. Replace that test's body with this exact sequence; retain its existing test name:

```ruby
write_draft("Keep this formatting")
find("lexxy-editor .lexxy-editor__content").send_keys([ :control, "a" ])
find("summary[aria-label=Formatting]").send_keys(:enter)
page.execute_script("document.querySelector('#chat-form').dispatchEvent(new CustomEvent('turbo:submit-start', { bubbles: true }))")
before = draft_html
page.driver.browser.action.move_to(find("lexxy-editor button[data-command='bold']").native).click.perform
assert_equal before, draft_html
assert_selector "lexxy-editor[disabled][inert]"
page.execute_script("document.querySelector('#chat-form').dispatchEvent(new CustomEvent('turbo:submit-end', { bubbles: true }))")
assert_selector "lexxy-editor:not([disabled]):not([inert])"
find("lexxy-editor .lexxy-editor__content").send_keys([ :control, "a" ])
find("lexxy-editor button[data-command='bold']").click
assert_selector "lexxy-editor .lexxy-editor__content strong", text: "Keep this formatting"
```

- [ ] Build test Tailwind. Run both UI browser files GREEN; inspect desktop/375px light/dark screenshots. If engine CSS wins, adjust only `.n-chat-composer` selectors, not global Lexxy variables or the engine. Commit the CSS/import, three wrappers, and style/selector tests: `style: Unify chat composer surfaces and responsive controls`.

## Task 4: Verify tools, native editing, source safety, and replacement

**Files:** Extend UI browser tests; update intentional presentation selectors in the legacy account browser test; keep legacy test semantics.

- [ ] Add these integration browser checks. They should pass if Tasks 1–3 are correct; do not manufacture RED in working code. Preserve failures before any focused correction:

```ruby
test "tools remain account-specific and their panel fits a narrow viewport" do
  page.current_window.resize_to(375, 844)
  find("[data-composer-tools] summary").send_keys(:enter)
  assert_selector "[data-composer-tools][open]"
  assert_text "First tool"
  assert_no_text "Second tool"
  find("input[name='mcp_server_ids[]']").check
  assert_selector "#mcp-selected-count", text: "1"
  rect = page.evaluate_script("const r = document.querySelector('.n-composer-tools-panel').getBoundingClientRect(); return [r.left, r.right, innerWidth]")
  assert_operator rect[0], :>=, 0
  assert_operator rect[1], :<=, rect[2]
  find("[data-composer-tools] summary").send_keys(:escape)
  assert_no_selector "[data-composer-tools][open]"
  assert_selector "[data-composer-tools] summary:focus"
  find("lexxy-editor .lexxy-editor__content").send_keys("Tools question")
  click_button "Send"
  assert_selector "[data-chat-account-readonly]"
  chat = @user.chats.order(:id).last
  assert_equal [ mcp_servers(:picker_first_tool).id ], chat.chat_mcp_sessions.pluck(:mcp_server_id)
  click_button "Stop generating"
  find(".n-composer-tools-trigger").click
  assert_selector "#mcp-selector-modal:not(.hidden)", text: "First tool"
ensure
  page.current_window.resize_to(1400, 1400)
end

test "skill selection retains priority over sending and pasted URLs keep chat context" do
  find("lexxy-editor .lexxy-editor__content").send_keys("/first")
  assert_selector ".n-skill-item-active", text: "/first-skill"
  count = @user.chats.count
  find("lexxy-editor .lexxy-editor__content").send_keys(:enter)
  assert_no_selector ".n-skill-menu:not(.hidden)"
  assert_includes page.evaluate_script("document.querySelector('lexxy-editor').value"), "/first-skill"
  assert_equal count, @user.chats.count
  visit chat_url(chats(:picker_second_chat))
  page.execute_script("document.querySelector('lexxy-editor').dispatchEvent(new CustomEvent('lexxy:insert-link', { detail: { url: 'https://composer-saved.example/reference' }, bubbles: true }))")
  assert_selector "input[name='message[attached_website_ids][]']", count: 2, visible: :all
  assert @second.websites.exists?(url: "https://composer-saved.example/reference")
  assert_not @first.websites.exists?(url: "https://composer-saved.example/reference")
end

test "saved PDF action registers a real native upload in the stored account" do
  visit chat_url(chats(:picker_second_chat))
  assert_selector "lexxy-editor[connected]"
  with_pdf do |path|
    attach_file(path) { click_button "Attach PDF" }
    assert_selector "input[name='message[attached_document_ids][]']", count: 2, visible: :all
    document = @second.documents.joins(file_attachment: :blob).find_by!(active_storage_blobs: { filename: File.basename(path) })
    assert_equal File.binread(path), document.file.download
    assert_not @first.documents.joins(file_attachment: :blob).exists?(active_storage_blobs: { filename: File.basename(path) })
  end
end

test "an unlock replacement keeps the same shared surface without a request session" do
  chat = chats(:picker_second_chat)
  chat.start_generation!
  visit chat_url(chat)
  assert_selector "button[aria-label='Stop generating']"
  Current.reset
  chat.finish_generation!
  # A visit also verifies recovery when the live cable delivery is missed.
  visit chat_url(chat)
  assert_selector "turbo-frame##{dom_id(chat)}_message_form .n-chat-composer", count: 1
  assert_selector "button[aria-label=Send]:not([disabled])"
  assert_selector "[data-chat-account-readonly]", text: /Research team/
  assert_no_selector "form form"
end
```

- [ ] Add actual broadcast rendering proof to the integration file rather than pretending a page visit tests WebSocket delivery:

```ruby
# At file top:
require "turbo/broadcastable/test_helper"
# Inside ChatComposerUiTest:
include Turbo::Broadcastable::TestHelper

test "background unlock broadcast uses the shared saved presentation" do
  chat = chats(:picker_second_chat)
  chat.start_generation!
  Current.reset
  streams = capture_turbo_stream_broadcasts([ chat, "messages" ]) { chat.finish_generation! }
  replacement = streams.find { |stream| stream["target"] == "#{dom_id(chat)}_message_form" }
  assert replacement
  fragment = Nokogiri::HTML.fragment(replacement.inner_html)
  assert_select fragment, ".n-chat-composer", count: 1
  assert_select fragment, "button[aria-label=Send]"
  assert_select fragment, "[data-chat-account-readonly]", text: /Research team/
end
```

- [ ] Recheck the narrowly adapted legacy selectors from Tasks 1 and 3. Do not change hidden-field assertions, blocked-source or pending POST tests, request counts, real upload/cancellation helpers, current-account values, fixture isolation, or expected persistence to accommodate the redesign. Keep the original native toolbar configuration assertion in `composer_partials_render_test.rb`: this plan deliberately preserves that configuration.

- [ ] Run both browser files in the same process using the ARM launcher, then integration/controller/model feature tests in one process. Expected GREEN. If a physical click on an inert element is intercepted by the driver, use its existing low-level pointer action, not a script that bypasses the user-interaction lock. Commit only the new tests and intentional selector adaptations: `test: Verify redesigned composer workflows and replacement`.

## Task 5: Document, inspect, and verify the completed component

**Files:** Create `docs/chat-composer.md`; add its Development quick link in `docs/README.md`. No unrelated cleanup.

- [ ] Create `docs/chat-composer.md` with:

```markdown
# Chat composer

New chats and saved conversations share one visual composer. The lower action
row contains PDF attachment, account context, Tools, and Send. Saved accounts
remain read-only. During generation, Stop submits the existing cancellation
endpoint through a separate form; it does not submit another message.

Formatting reveals Lexxy's native toolbar on demand. The compact PDF button
delegates to its real upload command; there is no second uploader or copied
toolbar template. Enter sends, Shift+Enter inserts a line break, and an open
skill palette retains priority. Ctrl/Command+K opens native link editing.

Source registration, upload retry/reset, account switching, pending submission,
and Turbo-history protections remain owned by the existing controllers. The
presentation-only composer-chrome controller does not maintain a second upload
or submission state. Editor actions remain inert during generation/submission;
Stop and saved tool management remain reachable.

Styles are scoped under .n-chat-composer. At narrow widths the account context
wraps above the remaining actions. Preserve keyboard focus, theme contrast,
long-label bounds, and reduced-motion rules when changing this component.

See the approved design and its implementation plan in docs/superpowers.
Run the rendering and browser tests below with the local environment's browser
configuration; do not start provider or indexing workers during UI tests.

    AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test test/integration/chat_composer_ui_test.rb test/integration/composer_partials_render_test.rb

    AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec ruby -rselenium-webdriver -e 'Selenium::WebDriver::Chrome::Service.driver_path = "/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path = "/usr/bin/chromium"; load "bin/rails"' -- test test/system/chat_composer_ui_test.rb test/system/chat_account_selection_test.rb
```

- [ ] Add this docs README Development link:

```markdown
- [Chat composer](chat-composer.md) — shared presentation, native Lexxy controls, and UI verification.
```

- [ ] Build Tailwind and run the focused backend suite, both UI browser files, and the full suite sequentially:

```sh
RAILS_ENV=test bin/rails tailwindcss:build
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test test/integration/chat_composer_ui_test.rb test/integration/composer_partials_render_test.rb test/controllers/chat_account_selection_test.rb test/controllers/chat_account_sources_test.rb test/controllers/chat_account_access_test.rb test/controllers/chat_account_tools_test.rb test/controllers/chat_account_citations_test.rb test/models/chat_account_test.rb
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec ruby -rselenium-webdriver -e 'Selenium::WebDriver::Chrome::Service.driver_path = "/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path = "/usr/bin/chromium"; load "bin/rails"' -- test test/system/chat_composer_ui_test.rb test/system/chat_account_selection_test.rb
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test
RUBOCOP_TARGET_RUBY_VERSION=4.0 bundle exec rubocop test/integration/chat_composer_ui_test.rb test/system/chat_composer_ui_test.rb test/controllers/chat_account_selection_test.rb test/system/chat_account_selection_test.rb
bundle exec brakeman --no-pager
git diff --check
git status --short
```

- [ ] Inspect screenshots on both entry points and a saved chat: desktop plus 375px, light/dark, tools open, source failure, generation Stop, and unlocked state. Also inspect 200% zoom and native formatting/link/overflow panels; retain browser evidence under `/tmp/opencode` without committing artifacts.
- [ ] Review native bold/italic/headings/lists/link/highlight/code/table/undo/redo availability in the revealed toolbar. A hidden native toolbar must not break Ctrl/Command+K, PDF chooser activation, selection preservation, or keyboard navigation.
- [ ] Compare any failures against the fresh baseline. Report the existing full-suite `augmented_context` test-double error and unchanged scanner warnings/offenses separately. Do not suppress them or report full success from focused results alone.
- [ ] Use `rails-code-review` and `rails-security-review` for template escaping, form ownership, account-specific data, source/reset lifecycle, and background rendering. Obtain spec-compliance and code-quality reviews under the chosen execution workflow.
- [ ] Commit only the two documentation paths: `docs: Explain the shared chat composer controls`. Use `verification-before-completion` before final claims. Do not merge, push, or open a PR without instruction.

## Plan-to-spec coverage

| Requirement | Tasks |
| --- | --- |
| Shared single surface on dashboard/new/saved | 1, 3 |
| Visible membership picker/read-only saved account | 1, 3, 4 |
| Compact native PDF and retained rich-text capabilities | 1, 2, 4, 5 |
| On-demand tools/count and existing saved management | 1, 4 |
| Stop, separate form, retained route and generation state | 1, 2, 4 |
| Secondary help, skills, conditional validation and source errors | 1, 4 |
| Live/cached POST/source/history safety | 2, 4 |
| Background replacement without Current | 1, 4 |
| Narrow/long-label/contrast/focus/reduced-motion checks | 2, 3, 4, 5 |
| Existing request namespaces/no backend/dependency changes | 0, 1, 4, 5 |

## Planning self-review and handoff

Planning self-review completed: every approved spec requirement maps to the tasks above; the placeholder scan is clean; all eight Ruby blocks, eleven Rails ERB blocks, and three JavaScript blocks parse; Markdown renders. Shared locals, `editingTools`, controller actions, field namespaces, and Stop form IDs were checked for consistency. Task ordering keeps native controls working until their replacements and locks are tested together.

These are documentation/syntax checks, not application verification. No application files changed and no application tests ran while writing this plan. Offer subagent-driven or inline execution next; implementation starts only under the selected workflow and its failing-test gates.
