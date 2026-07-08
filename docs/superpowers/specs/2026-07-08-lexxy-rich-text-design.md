# Lexxy Rich Text Editor Integration — Design

**Date:** 2026-07-08
**Status:** Approved (brainstorming complete, pending implementation plan)
**Branch:** `feat/lexxy`

## Goal

Replace the plain `text_area` inputs on the chat/message composer and on the Sources editors (texts, q&a, websites) with the [Lexxy](https://github.com/basecamp/lexxy) rich text editor. In the chat composer specifically, pasting a URL must create a `Website` and uploading a PDF must create a `Document`, each indexed **before** chat completion runs.

## Decisions (from brainstorming)

| Decision | Choice |
|---|---|
| Index timing model | Index on paste/upload (background job); user may submit freely; `ChatResponseJob` joins in-flight indexing before the LLM call. |
| Storage format | Store markdown. Lexxy submits HTML; convert HTML→markdown on save. Existing Commonmarker render, markdown chunker, and LLM prompt text stay unchanged. |
| Interception scope | Link→Website and PDF→Document (with index-before-completion) happens **only** in the chat composer. Source editors get Lexxy as a pure formatting editor, no auto-source-creation. |
| Chat composer UX | Port both existing behaviors to Lexxy: Enter-to-send (Shift+Enter newline) and the `/skill-name` command palette. |
| Index failure | Skip the failed/timed-out source, proceed with completion, and warn the assistant which attachments were excluded. |
| Wait mechanism | Polling gate inside `ChatResponseJob` (Approach A). A separate gate job (Approach B) is the documented escape hatch. |
| URL representation | Keep Lexxy's default `<a href>` anchor for pasted URLs (converts naturally to markdown). Website creation is a side effect tracked by a hidden field — no Action Text attachment machinery for links. |
| PDF representation | Lexxy's Active Storage direct upload embeds an `action-text-attachment` node; on save convert it to a `📎 filename` markdown marker and attach the same blob to the `Document`. |
| Source edit round-trip | Render stored markdown→HTML (Commonmarker) for the editor's initial value; edit as HTML; save HTML→markdown. Round-trip fidelity caveat applies to tables/complex formatting. |

## Context (current state)

- **Chat composer:** `app/views/chats/_form.html.erb` and `app/views/messages/_form.html.erb` use plain `text_area :prompt` / `:content`, driven by `chat_input_controller` (auto-grow + Enter-to-send) and `skill_autocomplete_controller` (`/skill` palette). Message `content` is a plain string rendered as markdown via Commonmarker + `sanitize`. No Action Text/Trix anywhere.
- **Sources:** four independent models — `Text`, `Qna`, `Website`, `Document` — each with a `Chunkable` concern producing polymorphic `Chunk` records that auto-embed via `Chunk::Vectorizable` (`before_save :generate_embedding`). Indexing is fully async: `CrawlWebsiteUrlJob` / `AddDocumentJob` / `AddTextJob` / `AddQnaJob` run on Solid Queue's `:background` queue. Chat completion runs on `:real_time` via `ChatResponseJob`.
- **Retrieval:** account-scoped similarity search over `chunks` (`Chat#similarity_search` → `Chunk::Searchable.search_by_similarity`). Sources are not linked to chats; matched chunks are recorded post-hoc on the message as `similar_chunk_ids`. The new paste-to-index sources ride this same pipeline — the only change is *when* their chunks land (before completion, enforced by the gate).
- **Lexxy:** Rails engine gem (`gem "lexxy"`), MIT, v0.9.23, Importmap-compatible (no Node). Form-associated custom element `<lexxy-editor>` submits sanitized HTML via `ElementInternals.setFormValue`. On Rails 8.0/8.1 it monkeypatches `form.rich_text_area`; the explicit `form.lexxy_rich_text_area` helper avoids Action Text. Attachments use Active Storage direct upload (`lexxy:file-accept`, `lexxy:upload-end` events). Links: `lexxy:insert-link` event with callbacks.

## Design

### Section 1 — Data model & indexing state

`ChatResponseJob` needs to ask "is this source indexed yet?" Today there is no explicit state. Add one.

**Migration** (`db/migrate/..._add_index_status_and_attached_sources.rb`):

```ruby
[:websites, :documents, :texts, :qnas].each do |t|
  add_column t, :index_status, :integer, default: 0, null: false
  add_column t, :indexed_at,   :datetime
end
add_column :messages, :attached_website_ids,  :string, array: true, default: []
add_column :messages, :attached_document_ids, :string, array: true, default: []
```

Backfill: existing sources with chunks → `index_status = :indexed` (`indexed_at = updated_at`); sources without chunks and no clear prior state → `pending`. Existing messages get empty arrays (default).

**State transitions (in the model, not the job):**

```ruby
# each source model
enum :index_status, { pending: 0, indexed: 10, failed: 20 }
```

- `pending` — DB default at creation.
- `indexed` — set at the end of each model's `chunkify!` (in the `Chunkable` concern, after chunks are bulk-created): `update!(index_status: :indexed, indexed_at: Time.current)`.
- `failed` — set when an indexing job exhausts retries. Each indexing job's `perform` wraps the model work in a method that sets `failed` on terminal exception before the job dies. Solid Queue retry config stays unchanged; `failed` is only final-marked on the terminal attempt (via `discard_on` / `rescue_from` on the exhausted-retry path).

**Message source tracking:** two explicit array columns (only `Website` and `Document` are chat-attachable, so no polymorphism needed):

```ruby
class Message < ApplicationRecord
  # loose associations, no FK per house style; account-scoped lookups
  def attached_websites; Website.where(id: attached_website_ids); end
  def attached_documents; Document.where(id: attached_document_ids); end
end
```

### Section 2 — Chat composer: Lexxy + interception Stimulus controller

**Install (Importmap, no Node):**

```ruby
# Gemfile
gem "lexxy", "~> 0.9.23"
```
```ruby
# config/importmap.rb
pin "lexxy", to: "lexxy.js"
pin "@rails/activestorage", to: "activestorage.esm.js"   # for PDF direct uploads
```
```js
// app/javascript/application.js
import "lexxy"
```

**Both composer forms** get Lexxy + hidden fields for accumulated source ids. They differ only in form object and field name:

- `messages/_form.html.erb` (existing-chat composer) — form object is the new `Message`; Lexxy field is `:content`; submits under `params[:message]`.
- `chats/_form.html.erb` (new-chat landing composer) — form object is a `Chat`; Lexxy field is `:prompt` (the existing field `ChatsController#create` reads); submits under `params[:chat]`. The `Chat` model has no `attached_*_ids` columns, so the hidden fields are plain `hidden_field_tag` carrying transient form params (not `form.hidden_field` against the model).

```erb
<%# messages/_form.html.erb (form object = message) %>
<%= form.hidden_field :attached_website_ids, multiple: true, data: { composer_target: "websiteIds" } %>
<%= form.hidden_field :attached_document_ids, multiple: true, data: { composer_target: "documentIds" } %>
<%= form.lexxy_rich_text_area :content,
      class: "n-form-chat",
      permitted_attachment_types: "application/pdf",
      data: { composer_target: "editor",
              action: "lexxy:insert-link->composer#onInsertLink
                       lexxy:upload-end->composer#onUploadEnd
                       keydown->composer#handleKeys" } %>

<%# chats/_form.html.erb (form object = chat; :prompt not :content) %>
<%= hidden_field_tag "chat[attached_website_ids][]", nil, data: { composer_target: "websiteIds" } %>
<%= hidden_field_tag "chat[attached_document_ids][]", nil, data: { composer_target: "documentIds" } %>
<%= form.lexxy_rich_text_area :prompt,
      class: "n-form-chat",
      permitted_attachment_types: "application/pdf",
      data: { composer_target: "editor",
              action: "lexxy:insert-link->composer#onInsertLink
                       lexxy:upload-end->composer#onUploadEnd
                       keydown->composer#handleKeys" } %>
```

**The interception endpoint is account-scoped, not chat-scoped.** This is the key to supporting the new-chat composer, where no `Chat` exists yet at paste time. Sources are account-scoped in the existing design (retrieval is account-wide similarity search; sources carry no `chat_id`), so creating a source before its chat exists is sound. The composer just needs the source id back to accumulate client-side.

nosia does **not** use a `/:account_id/` URL path namespace — `Current.account` is derived from `Current.user.first_account` (`app/models/current.rb`), not the URL. So `chat_sources` is a top-level authenticated resource like `chats`, and the controller scopes via `Current.account` (the same way `ChatsController#create` already uses `Current.account`).

```ruby
# config/routes.rb — top-level, under the existing authenticated constraint (same as chats)
resources :chat_sources, only: :create   # controller: ChatSourcesController
```

```
POST /chat_sources  { url: "..." }             # → Website
POST /chat_sources  { blob_signed_id: "..." }  # → Document
```

Returns JSON `{ id, title, url, index_status }` (Website) or `{ id, filename, index_status }` (Document). Thin controller — authorizes against `Current.account`, delegates to `Website.find_or_create_by_url!(Current.account, url)` / `Document.create_from_blob!(Current.account, signed_id)` model methods.

**Both controllers stamp the accumulated ids onto the user message they create**, so the gate (Section 3) works identically for both flows:

```ruby
# ChatsController#create (new-chat) — reads transient params[:chat][:attached_*]
@user_message = @chat.messages.create!(
  role: "user", content: prompt,
  attached_website_ids:  Array(params[:chat][:attached_website_ids]).compact_blank,
  attached_document_ids: Array(params[:chat][:attached_document_ids]).compact_blank
)

# MessagesController#create (existing-chat) — reads params[:message][:attached_*]
@user_message = @chat.messages.create!(
  role: "user", content: content,
  attached_website_ids:  Array(params[:message][:attached_website_ids]).compact_blank,
  attached_document_ids: Array(params[:message][:attached_document_ids]).compact_blank
)
```

**New `composer_controller.js`** (replaces `chat_input_controller` + `skill_autocomplete_controller` for the Lexxy editor):

1. **Enter-to-send, Shift+Enter newline** (`handleKeys`): on plain Enter, prevent default and submit the form. Same feel as today.
2. **`/skill` palette** (port of `skill_autocomplete_controller`): read the editor text around the caret via Lexxy's selection API (`editor.read(() => $getSelection())`) rather than `textarea.value`; on `/` at line start show the palette; on selection insert `/skill-name ` as a text node at the caret via `editor.update(...)`. Reuses the existing skills endpoint.
3. **Link interception → Website** (`onInsertLink`): on `lexxy:insert-link`, POST the URL to `POST /chat_sources { url }` (top-level, same authenticated path as the rest of the app; the controller scopes via `Current.account`). Endpoint find-or-creates the Website by `(account_id, url)` (reuse if exists; re-enqueue crawl if `index_status` stale/failed), enqueues `CrawlWebsiteUrlJob`, returns `{ id, title, url, index_status }`. Controller pushes `id` into the hidden `attached_website_ids` and **lets Lexxy's default anchor stand** (does not call `replaceLinkWith` with an attachment sgid).
4. **PDF interception → Document** (`onUploadEnd`): on `lexxy:upload-end` (success, no error), the blob already exists via Active Storage direct upload. POST the blob `signed_id` to `POST /chat_sources { blob_signed_id }`. Endpoint builds a `Document` for `Current.account`, attaches the blob (`document.file.attach(signed_id)` — blob owned by the Document, not orphaned), calls `titlize!`, enqueues `AddDocumentJob`, returns `{ id, filename, index_status }`. Controller pushes `id` into `attached_document_ids`. The in-editor `action-text-attachment` preview node remains; it is handled at save (Section 5).

### Section 3 — Completion flow: indexing gate in `ChatResponseJob`

The load-bearing "index before completion" piece.

**Bounded wait helper on `Chat` (model method):**

```ruby
# app/models/chat.rb (or a small Chat::IndexingGate concern)
def wait_for_attached_sources!(user_message, timeout: ENV.fetch("CHAT_INDEXING_TIMEOUT", 120).to_i.seconds, step: 1.second)
  deadline = Time.current + timeout
  sources = user_message.attached_websites + user_message.attached_documents
  return { ready: [], failed: [], timed_out: [] } if sources.empty?

  loop do
    pending = sources.reject { |s| s.index_status.indexed? || s.index_status.failed? }
    break if pending.empty? || Time.current >= deadline
    sleep step
    sources = sources.map(&:reload)
  end

  {
    ready:     sources.select { |s| s.index_status.indexed? },
    failed:    sources.select { |s| s.index_status.failed? },
    timed_out: sources.reject { |s| s.index_status.indexed? || s.index_status.failed? }
  }
end
```

**Wiring (`app/jobs/chat_response_job.rb` + `Chat::Completionable#complete_with_nosia`):**

1. `ChatResponseJob#perform` calls `chat.wait_for_attached_sources!(user_message)` **before** `complete_with_nosia` / `complete_with_agent_skills`.
2. The gate result's `failed` + `timed_out` lists are passed into the prompt so the assistant warns the user which attachments were excluded. A short system note: *"Note: the following attachments could not be retrieved and were excluded: <titles>."* If none failed/timed out, nothing is added.
3. `complete_with_nosia` runs `similarity_search` as today. Ready sources' chunks are now in the account's vector store (indexed before this point), so retrieval picks them up normally. `similar_chunk_ids` is stamped on the message afterward as today.

**Failure semantics:**
- Source still `pending` at the timeout → treated like `failed` (excluded + warned). Default 120s cap via `CHAT_INDEXING_TIMEOUT`.
- Source whose job exhausted retries and set `failed` → excluded + warned immediately (no wait).
- Zero attached sources → gate is a no-op; completion behaves exactly as today (no regression on plain text-only messages).

**Resource note:** `ChatResponseJob` is `queue_as :real_time` and will `sleep` during the poll — the accepted trade-off of Approach A. The poll step (1s) and bounded timeout (120s) cap the worst case. If real_time worker starvation appears, Approach B (a separate `:background` gate job that enqueues `ChatResponseJob` only once sources are ready) is the documented escape hatch and requires no data-model change.

### Section 4 — Source editors: Lexxy as a formatting upgrade (no interception)

`sources/texts/_form`, `sources/qnas/_form`, `sources/websites/_form` get Lexxy as a richer editor. No link→Website or PDF→Document behavior. The `data`/`answer` columns stay markdown.

```erb
<%# sources/texts/_form.html.erb %>
<%= form.lexxy_rich_text_area :data, class: "n-textarea" %>

<%# sources/qnas/_form.html.erb — :question stays a text_field %>
<%= form.lexxy_rich_text_area :answer, class: "n-textarea" %>

<%# sources/websites/_form.html.erb — :url stays url_field %>
<%= form.lexxy_rich_text_area :data, class: "n-textarea" %>
```

`Documents` untouched (file field). System prompts / MCP server textareas untouched (out of scope).

**HTML → markdown on save** (thin model concern, reused by all source editors):

```ruby
# app/models/concerns/html_to_markdown_formattable.rb
included do
  before_save :normalize_rich_content_to_markdown
end
```

Applied per-attribute (`data` for Text/Website, `answer` for Qna). Uses the existing `html-to-markdown` gem (v3.6.1 in `Gemfile.lock`, native Rust/Magnus extension), already a crawler dependency invoked as `HtmlToMarkdown.convert(html, skip_images: true).content`; `reverse_markdown` is the fallback if the gem's input signature doesn't fit the editor's sanitized HTML — the plan confirms which.

**Source editors disable attachments** (`permitted_attachment_types: ""`) — text-formatting only, no blob lifecycle to manage, no orphaned Active Storage blobs. Image attachments in source content are out of scope (YAGNI).

**Editing round-trip (option a):** on edit, the form renders stored markdown→HTML (Commonmarker) as the editor's initial value; the user edits as HTML; save converts HTML→markdown. **Caveat:** the MD→HTML→MD loop is clean for prose but tables/complex formatting may drift. Flagged in the plan.

### Section 5 — Message storage: HTML→markdown on submit, attachment nodes handled

The composer submits sanitized HTML for `content`. Store markdown, matching today.

**Conversion pipeline (`before_save` on `Message`):**

1. **Extract & strip attachment nodes first.** For each `<action-text-attachment content-type="application/pdf" sgid="...">` node, resolve the sgid via `ActionText::Attachable` — which for a direct-uploaded file returns the `ActiveStorage::Blob`, **not** the `Document` (the blob is the attachable Lexxy embeds). Pull the filename from `blob.filename` (or, equivalently, from the tracked Document in `attached_document_ids`). Replace the node with a compact markdown marker: `📎 report.pdf`. The Document id is already in `attached_document_ids` (tracked at upload time), so the marker is purely visual.
2. **Leave anchors as-is.** URL pastes are plain `<a href="url">url</a>`; they pass straight through to markdown.
3. **Convert remaining HTML → markdown.** `self.content = HtmlToMarkdown.convert(html_without_attachments, skip_images: true).content`. `/skill-name` text from the palette is plain text in the editor and survives unchanged.
4. **Store markdown in `content`.** Downstream unchanged: `Message#response_content` (Commonmarker + sanitize), the LLM prompt (text), streaming.

**`before_save` is safe:** `Message` has no content validation (only scopes), so no validation sees the pre-conversion HTML. `before_save` runs after validations; `content` is overwritten with markdown before insert/update. `lexxy_rich_text_area :content` submits the HTML string under `message[content]` (Lexxy uses `ElementInternals.setFormValue`, not a separate rich-text attribute), so the `before_save` reads the submitted HTML from `content` and overwrites it with markdown — no extra column, no Action Text table. For the new-chat form, the field is `:prompt` under `chat[prompt]`; `ChatsController#create` sets it as the message `content` and the same `before_save` converts it.

**The LLM must receive markdown, not HTML.** `ChatResponseJob.perform_later(chat_id, prompt, user_message_id)` is called with the content as a separate arg and `complete_with_nosia` feeds it to the LLM. Today `prompt`/`content` is already markdown, so it works. After this change the controller receives **HTML** for that arg. Since `before_save` runs synchronously inside `messages.create!`, the persisted `@user_message.content` is already markdown by the time the job is enqueued. Both controllers therefore pass `@user_message.content` (markdown) to `ChatResponseJob` instead of the raw HTML param. (Equivalently, the job could read `user_message.content` and ignore the separate arg — the plan picks one.)

**No edit round-trip:** chat messages have no edit action, so the markdown `content` is only rendered read-only via Commonmarker — simpler than sources.

**Sanitization:** Lexxy already runs output through DOMPurify; `Message`'s existing `sanitize` in rendering stays as defense-in-depth. No new trust boundary.

### Section 6 — Testing, migration & rollout

**Testing (Minitest + fixtures — behavior, not implementation):**

- **Model:** `index_status` transitions (pending→indexed after `chunkify!`, →failed on terminal failure); `Website.find_or_create_by_url!` reuses existing and re-enqueues when stale/failed; `Document.create_from_blob!` attaches and owns the blob (no orphan); `Message` `before_save` HTML→markdown with attachment nodes → `📎 filename` and anchors passing through; `attached_*_ids` persistence; `Chat#wait_for_attached_sources!` no-op with no sources, waits-then-returns-ready, excludes failed/timed-out, respects the 120s cap.
- **Controller:** `ChatSourcesControllerTest` URL and blob branches (create source + enqueue job + return id/title/status), unauthorized account rejected, duplicate URL reused; `MessagesControllerTest` / `ChatsControllerTest` persist `attached_*_ids` and still return the right turbo_stream (LLM call stubbed as in existing tests).
- **Job:** `ChatResponseJobTest` waits on `pending` sources then proceeds; proceeds without `failed` source and the prompt includes the warn note; with no attached sources behaves as today.
- **System:** `ChatComposerSystemTest` paste URL → Website appears in account sources → submit → assistant streams and references indexed content. Dedicated system test for the `/skill` palette port.

**Rollout / risks:**
- **Lexxy on Rails 8.0.5:** gem targets `>= 8.0.2`. Use explicit `lexxy_rich_text_area` to avoid Action Text. Confirm gem pins cleanly in the setup spike.
- **`/skill` palette port** is the highest-risk JS piece (Lexxy selection API vs. textarea). Timeboxed spike early; fallback is a hidden sync textarea (not ideal). Flagged as risk.
- **MD→HTML→MD round-trip on source edits:** tables/complex formatting may drift. Known caveat; prose is fine.
- **real_time worker occupancy** during the gate: bounded by 120s; Approach B is the documented escape hatch.

**Out of scope (YAGNI):** image attachments in source editors; clickable citation links in rendered messages; scheduled re-indexing of stale sources; interception in non-chat editors.

## Open items for the implementation plan

- Confirm the `html-to-markdown` gem's input signature fits Lexxy's sanitized HTML; else fall back to `reverse_markdown`.
- Confirm the Solid Queue "terminal failure → `failed` status" wiring (`discard_on` / `rescue_from` on exhausted retries).
- Spike: Lexxy selection API for the `/skill` palette port (highest-risk JS piece; fallback = hidden sync textarea).
- Spike: explicit `lexxy_rich_text_area` helper renders `<lexxy-editor>` with the expected `name` on Rails 8.0.5 and does not create an Action Text table.
- Spike: confirm Active Storage direct-upload endpoint is enabled/authenticated for Lexxy PDF uploads (`global.authenticatedUploads`).
- Decide backfill behavior for sources-without-chunks (`pending` vs. `failed`).
- Decide whether `ChatResponseJob` reads markdown from `user_message.content` (drop the separate prompt arg) or the controller passes `@user_message.content`.
- Carry over the existing `chats/_form.html.erb` bits the spec's abbreviated snippet omits: the MCP-server hidden-fields block (`#mcp-server-hidden-fields`) and the Stop-button branch for `chat.generating`. Don't silently drop them when adopting Lexxy.