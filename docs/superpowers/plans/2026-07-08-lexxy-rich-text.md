# Lexxy Rich Text Editor Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace plain `text_area` inputs on the chat/message composer and the Sources editors (texts, q&a, websites) with the Lexxy rich text editor, and make pasting a URL / uploading a PDF in the chat composer create a `Website` / `Document` that is indexed **before** `ChatResponseJob` runs the LLM call.

**Architecture:** Lexxy submits sanitized HTML; we convert HTML→markdown on save so the existing Commonmarker render, markdown chunker, and LLM prompt text stay unchanged (no Action Text). A new `index_status` enum on each source model (`pending`/`indexed`/`failed`) lets `ChatResponseJob` poll attached sources with a bounded wait before completion. A new account-scoped `ChatSourcesController` creates sources from the composer at paste/upload time (sources carry no `chat_id`, so they can be created before the chat exists). A `composer_controller.js` Stimulus controller ports Enter-to-send and the `/skill` palette to Lexxy and accumulates attached source ids into hidden form fields.

**Tech Stack:** Ruby on Rails 8.0.x · Ruby 4.0.5 · Solid Queue · Stimulus 3.2 · Importmap · `lexxy` gem (~> 0.9.23) · `html-to-markdown` gem (v3.6.1) · Active Storage · pgvector · Minitest (setup-based, no fixtures)

**Spec:** `docs/superpowers/specs/2026-07-08-lexxy-rich-text-design.md`

**Conventions:** Rich models, thin controllers, concerns for horizontal behavior, shallow jobs, no service objects, Minitest+fixtures, expanded conditionals. `Current.account` comes from `Current.user.first_account` (there is **no** `/:account_id` URL path namespace — ignore any rule file that says otherwise).

---

## File Structure

### Files to Create

| Path | Purpose |
|------|---------|
| `db/migrate/YYYYMMDDHHMMSS_add_index_status_and_attached_sources.rb` | Adds `index_status` + `indexed_at` to sources; `attached_website_ids` + `attached_document_ids` to messages; backfills. |
| `app/models/concerns/indexable.rb` | `enum :index_status` + `mark_indexed!` / `mark_indexing_failed!` shared by all four source models. |
| `app/models/concerns/html_to_markdown_formattable.rb` | `before_save` HTML→markdown for source editors (texts/qna/websites). |
| `app/controllers/chat_sources_controller.rb` | Account-scoped `create` (URL→Website, blob→Document), JSON response. |
| `app/javascript/controllers/composer_controller.js` | Replaces `chat_input_controller` + `skill_autocomplete_controller` for the Lexxy editor: Enter-to-send, `/skill` palette, link→Website, PDF→Document, hidden-id accumulation. |
| `test/models/indexable_test.rb` | Index-status transitions. |
| `test/models/website_find_or_create_by_url_test.rb` | `Website.find_or_create_by_url!`. |
| `test/models/document_create_from_blob_test.rb` | `Document.create_from_blob!`. |
| `test/models/message_html_to_markdown_test.rb` | Message `before_save` conversion. |
| `test/models/chat/wait_for_attached_sources_test.rb` | The polling gate. |
| `test/controllers/chat_sources_controller_test.rb` | Interception endpoint. |
| `test/jobs/chat_response_job_test.rb` | Gate wiring + warn note. |
| `test/system/chat_composer_test.rb` | End-to-end paste→index→completion. |

### Files to Modify

| Path | Change |
|------|--------|
| `app/models/website.rb` | `include Indexable`; early-returns in `Crawlable` set `failed`. |
| `app/models/document.rb` | `include Indexable`. |
| `app/models/text.rb` | `include Indexable`. |
| `app/models/qna.rb` | `include Indexable`. |
| `app/models/website/chunkable.rb` | `chunkify!` ends with `mark_indexed!`. |
| `app/models/document/chunkable.rb` | `chunkify!` ends with `mark_indexed!`. |
| `app/models/text/chunkable.rb` | `chunkify!` ends with `mark_indexed!`. |
| `app/models/qna/chunkable.rb` | `chunkify!` ends with `mark_indexed!`. |
| `app/models/website/crawlable.rb` | Robots-disallowed / nil-html paths call `mark_indexing_failed!`. |
| `app/jobs/crawl_website_url_job.rb` | `retry_on` block marks `failed` on exhaustion. |
| `app/jobs/add_document_job.rb` | `retry_on` block marks `failed` on exhaustion. |
| `app/jobs/add_text_job.rb` | `retry_on` block marks `failed` on exhaustion. |
| `app/jobs/add_qna_job.rb` | `retry_on` block marks `failed` on exhaustion. |
| `app/models/message.rb` | `before_save` HTML→markdown (user role only) + `attached_websites`/`attached_documents` helpers. |
| `app/models/chat.rb` | `wait_for_attached_sources!` (or a `Chat::IndexingGate` concern). |
| `app/models/chat/completionable.rb` | Accept `excluded_sources:` and append the warn note to instructions. |
| `app/jobs/chat_response_job.rb` | Call `wait_for_attached_sources!` before completion; pass excluded list. |
| `app/controllers/chats_controller.rb` | Stamp `attached_*_ids` on the user message; pass `@user_message.content` (markdown) to the job. |
| `app/controllers/messages_controller.rb` | Same as above. |
| `config/routes.rb` | Add `resources :chat_sources, only: :create` inside the authenticated constraint. |
| `config/importmap.rb` | `pin "lexxy", to: "lexxy.js"` + `pin "@rails/activestorage", to: "activestorage.esm.js"`. |
| `app/javascript/application.js` | `import "lexxy"`. |
| `Gemfile` | `gem "lexxy", "~> 0.9.23"`. |
| `app/views/chats/_form.html.erb` | Lexxy `:prompt` + hidden `attached_*_ids` fields; keep MCP hidden-fields block + Stop/Send branch. |
| `app/views/messages/_form.html.erb` | Lexxy `:content` + hidden `attached_*_ids` fields. |
| `app/views/sources/texts/_form.html.erb` | Lexxy `:data` (attachments disabled). |
| `app/views/sources/qnas/_form.html.erb` | Lexxy `:answer` (attachments disabled). |
| `app/views/sources/websites/_form.html.erb` | Lexxy `:data` (attachments disabled). |
| `app/models/text.rb` / `qna.rb` / `website.rb` | `include HtmlToMarkdownFormattable` (per-attribute). |

---

## Pre-flight (run once before Task 1)

- [ ] Confirm clean tree: `git status` (branch `feat/lexxy`).
- [ ] `bin/rails test` passes on `main` baseline (snapshot of current green).
- [ ] Read the spec: `docs/superpowers/specs/2026-07-08-lexxy-rich-text-design.md`.

Relevant skills: @test-driven-development, @concern-patterns, @job-patterns, @migration-patterns, @crud-patterns, @stimulus-patterns, @turbo-patterns, @testing-patterns.

---

## Implementation Tasks

### Task 1: Migration — index_status, indexed_at, attached source ids

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_add_index_status_and_attached_sources.rb`
- Test: `test/migrations/add_index_status_and_attached_sources_test.rb` (skip if migration tests aren't set up — verify via model tests in Task 2 instead)

**Purpose:** Add the columns the whole feature depends on. Use `rails g migration`.

- [ ] **Step 1: Generate the migration**

```bash
bin/rails g migration AddIndexStatusAndAttachedSources
```

- [ ] **Step 2: Edit the migration to match exactly**

```ruby
class AddIndexStatusAndAttachedSources < ActiveRecord::Migration[8.0]
  def up
    [:websites, :documents, :texts, :qnas].each do |table|
      add_column table, :index_status, :integer, default: 0, null: false
      add_column table, :indexed_at,   :datetime
    end
    add_column :messages, :attached_website_ids,  :string, array: true, default: []
    add_column :messages, :attached_document_ids, :string, array: true, default: []

    # Backfill: sources that already have chunks are indexed.
    [:websites, :documents, :texts, :qnas].each do |table|
      execute <<~SQL.squish
        UPDATE #{table} SET index_status = 10, indexed_at = updated_at
        WHERE id IN (SELECT chunkable_id FROM chunks WHERE chunkable_type = '#{table.to_s.classify}')
      SQL
    end
  end

  def down
    [:websites, :documents, :texts, :qnas].each do |table|
      remove_column table, :index_status
      remove_column table, :indexed_at
    end
    remove_column :messages, :attached_website_ids
    remove_column :messages, :attached_document_ids
  end
end
```

> Open item from spec resolved here: sources-without-chunks stay `pending` (default 0). Existing indexed sources get `10` (`indexed`) + `indexed_at = updated_at`.

- [ ] **Step 3: Run the migration**

```bash
bin/rails db:migrate
```
Expected: migration applies; `db/schema.rb` updated with the new columns.

- [ ] **Step 4: Commit**

```bash
git add db/migrate/*_add_index_status_and_attached_sources.rb db/schema.rb
git commit -m "feat: add index_status to sources and attached source ids to messages"
```

---

### Task 2: Indexable concern + wire chunkify! to mark indexed

**Files:**
- Create: `app/models/concerns/indexable.rb`
- Modify: `app/models/website.rb`, `app/models/document.rb`, `app/models/text.rb`, `app/models/qna.rb`
- Modify: `app/models/website/chunkable.rb`, `app/models/document/chunkable.rb`, `app/models/text/chunkable.rb`, `app/models/qna/chunkable.rb`
- Test: `test/models/indexable_test.rb`

**Purpose:** Shared `enum :index_status` + `mark_indexed!` / `mark_indexing_failed!`. Each `chunkify!` flips the source to `indexed` after chunks are written. (See @concern-patterns.)

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/indexable_test.rb
require "test_helper"

class IndexableTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "ix@example.com", password: "testpassword123")
    @account = Account.create!(name: "IX Account", owner: @user)
    ActsAsTenant.current_tenant = @account
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "new source defaults to pending index_status" do
    website = @account.websites.new(url: "https://example.com/x")
    assert website.index_status.pending?
  end

  test "mark_indexed! sets indexed and indexed_at" do
    text = @account.texts.create!(data: "# Hi")
    text.mark_indexed!
    assert text.index_status.indexed?
    assert_not_nil text.indexed_at
  end

  test "mark_indexing_failed! sets failed" do
    text = @account.texts.create!(data: "# Hi")
    text.mark_indexing_failed!
    assert text.index_status.failed?
  end

  test "chunkify! marks the source indexed" do
    text = @account.texts.new(data: "# Title\n\nSome body text here.")
    text.save!
    text.chunkify!
    assert text.index_status.indexed?
  end
end
```

> **Test harness note (read first):** This codebase does **not** use fixtures — `test/fixtures/` is empty and `fixtures :all` in `test_helper.rb` is a no-op. Tests create records in `setup` with `@user`/`@account` + `ActsAsTenant.current_tenant = @account`, and use `@account.<association>` (never `Current.account`, which is nil in model tests). Integration/controller tests additionally call `@account.account_users.grant_to(@user)` then `post login_url, params: { email: @user.email, password: "testpassword123" }` to set the session cookie so `Current.account` resolves in the controller. Every test in this plan follows that pattern. Verify `Account` has the `has_many` you use (`websites`, `documents`, `texts`, `qnas`, `chats`) — the Sources controllers already rely on `Current.account.websites`/`.documents`/`.texts`/`.qnas`, so they do.

- [ ] **Step 2: Run the test to verify it fails**

```bash
bin/rails test test/models/indexable_test.rb
```
Expected: FAIL — `undefined method index_status` / `mark_indexed!`.

- [ ] **Step 3: Create the Indexable concern**

```ruby
# app/models/concerns/indexable.rb
module Indexable
  extend ActiveSupport::Concern

  included do
    enum :index_status, { pending: 0, indexed: 10, failed: 20 }
  end

  def mark_indexed!
    update!(index_status: :indexed, indexed_at: Time.current)
  end

  def mark_indexing_failed!
    update!(index_status: :failed)
  end
end
```

- [ ] **Step 4: Include `Indexable` in each source model**

Add `include Indexable` to `app/models/website.rb`, `app/models/document.rb`, `app/models/text.rb`, `app/models/qna.rb` (alongside their existing `include Chunkable`, etc.).

- [ ] **Step 5: End each `chunkify!` with `mark_indexed!`**

In `Website::Chunkable#chunkify!`, `Text::Chunkable#chunkify!`, `Qna::Chunkable#chunkify!` — after the chunk-creation loop, add:

```ruby
    mark_indexed!
```

In `Document::Chunkable#chunkify!` (which has an early `return if new_chunks.empty?`), set failed on empty and indexed otherwise:

```ruby
  def chunkify!
    new_chunks = build_chunks
    if new_chunks.empty?
      mark_indexing_failed!
      return
    end

    self.chunks.destroy_all
    self.chunks.create(new_chunks)
    mark_indexed!
  end
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
bin/rails test test/models/indexable_test.rb
```
Expected: PASS.

- [ ] **Step 7: Run the full source test suite to check for regressions**

```bash
bin/rails test test/models/website_test.rb test/models/document_test.rb test/models/text_test.rb test/models/qna_test.rb test/models/chunk_test.rb
```
Expected: PASS (existing chunkify! callers now also flip status; no behavior change beyond the new column).

- [ ] **Step 8: Commit**

```bash
git add app/models/concerns/indexable.rb app/models/website.rb app/models/document.rb app/models/text.rb app/models/qna.rb \
        app/models/website/chunkable.rb app/models/document/chunkable.rb app/models/text/chunkable.rb app/models/qna/chunkable.rb \
        test/models/indexable_test.rb test/fixtures
git commit -m "feat: Indexable concern tracks source indexing state"
```

---

### Task 3: Mark failed on crawl skip + job exhaustion

**Files:**
- Modify: `app/models/website/crawlable.rb`
- Modify: `app/jobs/crawl_website_url_job.rb`, `app/jobs/add_document_job.rb`, `app/jobs/add_text_job.rb`, `app/jobs/add_qna_job.rb`
- Test: `test/jobs/indexing_failure_test.rb`

**Purpose:** Sources that can't index must reach a terminal `failed` state so the completion gate doesn't wait forever. Two paths: (a) `crawl_url!` skips on robots-disallowed / nil HTML; (b) a job exhausts retries. Use ActiveJob's `retry_on(...) { |job, error| ... }` block form, which runs on exhaustion. (See @job-patterns.)

- [ ] **Step 1: Write the failing test**

```ruby
# test/jobs/indexing_failure_test.rb
require "test_helper"

class IndexingFailureTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "if@example.com", password: "testpassword123")
    @account = Account.create!(name: "IF Account", owner: @user)
    ActsAsTenant.current_tenant = @account
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "crawl_url! marks failed when robots disallows" do
    website = @account.websites.create!(url: "https://disallowed.example")
    Website::RobotsCheckable.any_instance.stubs(:robots_allowed?).returns(false)
    website.crawl_url!
    assert website.index_status.failed?
  end

  test "the exhausted-retry contract sets failed (model-level)" do
    # The retry_on block's only job is to call mark_indexing_failed! — which is
    # independently verified here and in IndexableTest. The real exhausted-retry
    # path is exercised end-to-end in the Task 16 system test.
    website = @account.websites.create!(url: "https://example.com")
    website.mark_indexing_failed!
    assert website.reload.index_status.failed?
  end
end
```

> **Why not a `perform_now`-with-retries test:** the ActiveJob `retry_on` block form only fires after `attempts` executions; under the Rails `:test` adapter, `perform_enqueued_jobs` runs a job once and the inline retry semantics vary, making such tests flaky. Instead we verify the contract the block depends on (`mark_indexing_failed!`) at the model level here, and exercise the real exhausted-retry path in the Task 16 system test. If you want a job-level assertion, set `Rails.application.config.active_job.queue_adapter = :inline` for that one test and stub the model method to raise — but prefer the approach above.

- [ ] **Step 2: Update `crawl_url!` early-returns to mark failed**

In `app/models/website/crawlable.rb`:

```ruby
  def crawl_url!
    if url.blank?
      mark_indexing_failed!
      return
    end
    unless robots_allowed?
      mark_indexing_failed!
      return
    end

    html = fetch_html
    unless html
      mark_indexing_failed!
      return
    end

    self.data = convert_to_markdown(html)
    save!
    chunkify!   # chunkify! sets indexed
    self
  end
```

- [ ] **Step 3: Add exhausted-retry blocks to all four indexing jobs**

`app/jobs/crawl_website_url_job.rb` (add a block to the existing `retry_on`):

```ruby
class CrawlWebsiteUrlJob < ApplicationJob
  queue_as :background

  retry_on Faraday::TimeoutError,
           Faraday::ConnectionFailed,
           Faraday::ServerError,
           Website::Crawlable::ConversionError,
           wait: 30.seconds,
           attempts: 5 do |job, error|
    Website.find_by(id: job.arguments.first)&.mark_indexing_failed!
  end

  discard_on ActiveRecord::RecordNotFound

  def perform(website_id)
    website = Website.find(website_id)
    website.crawl_url!
  end
end
```

`app/jobs/add_document_job.rb`:

```ruby
class AddDocumentJob < ApplicationJob
  queue_as :background

  retry_on StandardError, wait: 30.seconds, attempts: 3 do |job, error|
    Document.find_by(id: job.arguments.first)&.mark_indexing_failed!
  end

  def perform(document_id)
    document = Document.find(document_id)
    document.titlize!
    document.parse!
    document.chunkify! if document.content.present?
  end
end
```

Apply the same `retry_on StandardError, wait: 30.seconds, attempts: 3 do |job, error| ...find_by(id: job.arguments.first)&.mark_indexing_failed! end` to `AddTextJob` (`Text`) and `AddQnaJob` (`Qna`).

- [ ] **Step 4: Tests are the ones shown in Step 1 (already updated to the `@account`/`ActsAsTenant` pattern)**

No separate "real" test — the Step 1 block is the real test. The robots-disallowed path is driven through `crawl_url!` directly; the exhausted-retry contract is verified at the model level (`mark_indexing_failed!`) and end-to-end in Task 16.

- [ ] **Step 5: Run the tests**

```bash
bin/rails test test/jobs/indexing_failure_test.rb
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/models/website/crawlable.rb app/jobs/*.rb test/jobs/indexing_failure_test.rb
git commit -m "feat: mark sources failed on crawl skip and job exhaustion"
```

---

### Task 4: Website.find_or_create_by_url! + Document.create_from_blob!

**Files:**
- Modify: `app/models/website.rb`, `app/models/document.rb`
- Test: `test/models/website_find_or_create_by_url_test.rb`, `test/models/document_create_from_blob_test.rb`

**Purpose:** The model methods the `ChatSourcesController` delegates to. (See @model-patterns.)

- [ ] **Step 1: Write the failing tests**

```ruby
# test/models/website_find_or_create_by_url_test.rb
require "test_helper"

class WebsiteFindByCreateByUrlTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "wu@example.com", password: "testpassword123")
    @account = Account.create!(name: "WU Account", owner: @user)
    @other_user = User.create!(email: "wu2@example.com", password: "testpassword123")
    @other_account = Account.create!(name: "WU Other", owner: @other_user)
    ActsAsTenant.current_tenant = @account
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "creates a new website and enqueues the crawl job" do
    assert_enqueued_with(job: CrawlWebsiteUrlJob) do
      @website = Website.find_or_create_by_url!(@account, "https://new.example/page")
    end
    assert @website.persisted?
    assert @website.index_status.pending?
    assert_equal "https://new.example/page", @website.url
  end

  test "reuses an existing website for the same account+url without enqueuing" do
    existing = @account.websites.create!(url: "https://dup.example", index_status: :indexed)
    assert_no_enqueued_jobs(only: CrawlWebsiteUrlJob) do
      found = Website.find_or_create_by_url!(@account, "https://dup.example")
      assert_equal existing.id, found.id
    end
  end

  test "re-crawls when the existing website is failed" do
    existing = @account.websites.create!(url: "https://stale.example", index_status: :failed)
    assert_enqueued_with(job: CrawlWebsiteUrlJob) do
      Website.find_or_create_by_url!(@account, "https://stale.example")
    end
    assert existing.reload.index_status.pending?
  end

  test "does not cross accounts" do
    ActsAsTenant.current_tenant = @other_account
    @other_account.websites.create!(url: "https://share.example", index_status: :indexed)
    ActsAsTenant.current_tenant = @account
    assert_enqueued_with(job: CrawlWebsiteUrlJob) do
      Website.find_or_create_by_url!(@account, "https://share.example")
    end
  end
end
```

```ruby
# test/models/document_create_from_blob_test.rb
require "test_helper"

class DocumentCreateFromBlobTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "db@example.com", password: "testpassword123")
    @account = Account.create!(name: "DB Account", owner: @user)
    ActsAsTenant.current_tenant = @account
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "creates a document, owns the blob, and enqueues AddDocumentJob" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 fake"),
      filename: "report.pdf",
      content_type: "application/pdf"
    )
    assert_enqueued_with(job: AddDocumentJob) do
      @document = Document.create_from_blob!(@account, blob.signed_id)
    end
    assert @document.persisted?
    assert @document.file.attached?
    assert_equal blob, @document.file.blob
    assert @document.index_status.pending?
  end
end
```

> Verify `Account` has `has_many :websites` and `has_many :documents` (the Sources controllers already use `Current.account.websites` / `.documents`, so it does).

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bin/rails test test/models/website_find_or_create_by_url_test.rb test/models/document_create_from_blob_test.rb
```
Expected: FAIL — `undefined method find_or_create_by_url!` / `create_from_blob!`.

- [ ] **Step 3: Implement the model methods**

`app/models/website.rb` (add class method, ordered before `private`):

```ruby
  def self.find_or_create_by_url!(account, url)
    website = account.websites.find_or_initialize_by(url: url)

    if website.new_record?
      website.save!
      CrawlWebsiteUrlJob.perform_later(website.id)
    elsif website.index_status.failed? || website.chunks.empty?
      website.update!(index_status: :pending, indexed_at: nil)
      CrawlWebsiteUrlJob.perform_later(website.id)
    end

    website
  end
```

`app/models/document.rb`:

```ruby
  def self.create_from_blob!(account, signed_id)
    document = account.documents.new
    document.file.attach(signed_id)
    document.save!
    AddDocumentJob.perform_later(document.id)
    document
  end
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
bin/rails test test/models/website_find_or_create_by_url_test.rb test/models/document_create_from_blob_test.rb
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/website.rb app/models/document.rb test/models/website_find_or_create_by_url_test.rb test/models/document_create_from_blob_test.rb
git commit -m "feat: Website.find_or_create_by_url! and Document.create_from_blob!"
```

---

### Task 5: Message attached-source helpers + attached ids persistence

**Files:**
- Modify: `app/models/message.rb`
- Test: `test/models/message_test.rb` (append)

**Purpose:** Read the two array columns back into source records.

- [ ] **Step 1: Write the failing test (append to existing `message_test.rb`)**

```ruby
  # Append these tests to the existing MessageTest class. If it has no setup,
  # add one mirroring ChatTest:
  def setup
    @user = User.create!(email: "mt@example.com", password: "testpassword123")
    @account = Account.create!(name: "MT Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "attached_websites and attached_documents resolve ids to records" do
    w = @account.websites.create!(url: "https://a.example")
    d = @account.documents.new
    d.file.attach(io: StringIO.new("x"), filename: "d.pdf", content_type: "application/pdf")
    d.save!

    message = @chat.messages.create!(role: "user", content: "hi",
      attached_website_ids: [w.id], attached_document_ids: [d.id])

    assert_equal [w], message.attached_websites
    assert_equal [d], message.attached_documents
  end

  test "attached ids default to empty arrays" do
    message = @chat.messages.create!(role: "user", content: "hi")
    assert_equal [], message.attached_website_ids
    assert_equal [], message.attached_document_ids
  end
```

- [ ] **Step 2: Run to verify it fails**

```bash
bin/rails test test/models/message_test.rb
```
Expected: FAIL — `undefined method attached_websites`.

- [ ] **Step 3: Add the helpers to `app/models/message.rb`** (near `similar_chunks`):

```ruby
  def attached_websites
    Website.where(id: attached_website_ids)
  end

  def attached_documents
    Document.where(id: attached_document_ids)
  end
```

- [ ] **Step 4: Run to verify it passes**

```bash
bin/rails test test/models/message_test.rb
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/message.rb test/models/message_test.rb
git commit -m "feat: Message attached_websites/attached_documents helpers"
```

---

### Task 6: Message HTML→markdown on save (user role only)

**Files:**
- Modify: `app/models/message.rb`
- Test: `test/models/message_html_to_markdown_test.rb`

**Purpose:** Composer submits Lexxy HTML under `content`; convert to markdown before persist so rendering, chunking, and the LLM prompt keep working. Guard to `user?` so assistant/streamed content (markdown) and the assistant warning-text update are untouched. PDF attachment nodes become `📎 filename` markers; URL anchors pass through. (See @concern-patterns for the shared source-editor concern in Task 14; Message uses its own private method because of the attachment-strip step.)

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/message_html_to_markdown_test.rb
require "test_helper"

class MessageHtmlToMarkdownTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "mh@example.com", password: "testpassword123")
    @account = Account.create!(name: "MH Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "user message HTML content is converted to markdown on save" do
    message = @chat.messages.create!(role: "user", content: "<p>Hello <strong>world</strong></p>")
    assert_equal "Hello **world**", message.content.strip
  end

  test "anchors pass through as markdown links" do
    message = @chat.messages.create!(role: "user",
      content: '<p>See <a href="https://x.example">https://x.example</a></p>')
    assert_includes message.content, "https://x.example"
    assert_includes message.content, "[https://x.example](https://x.example)"
  end

  test "action-text-attachment PDF nodes become a paperclip marker" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4"), filename: "report.pdf", content_type: "application/pdf"
    )
    sgid = blob.attachable_sgid
    html = %(<p>Here is the doc</p><action-text-attachment sgid="#{sgid}" content-type="application/pdf"></action-text-attachment>)
    message = @chat.messages.create!(role: "user", content: html)
    assert_includes message.content, "📎 report.pdf"
    refute_includes message.content, "action-text-attachment"
  end

  test "assistant markdown content is not converted" do
    message = @chat.messages.create!(role: "assistant", content: "Already **markdown** here")
    assert_equal "Already **markdown** here", message.content
  end

  test "plain text user content without HTML tags is unchanged" do
    message = @chat.messages.create!(role: "user", content: "Just plain text, no tags.")
    assert_equal "Just plain text, no tags.", message.content
  end
end
```

> The last test is the open-item safety check. If `HtmlToMarkdown` mangles plain text (e.g. wraps/escapes), tighten the guard in Step 3 to `if: -> { user? && content.to_s.match?(/<[a-z!]/i) }` so only HTML-bearing content converts, and re-run.

- [ ] **Step 2: Run to verify it fails**

```bash
bin/rails test test/models/message_html_to_markdown_test.rb
```
Expected: FAIL — content stored as raw HTML.

- [ ] **Step 3: Implement the conversion on `Message`**

In `app/models/message.rb`, register the callback (near the other `before_create`):

```ruby
  before_save :normalize_content_to_markdown, if: -> { user? }
```

Add the private method (no newline under `private`; order by invocation flow):

```ruby
  def normalize_content_to_markdown
    return if content.blank?
    self.content = self.class.html_to_markdown(content)
  end

  def self.html_to_markdown(html)
    doc = Nokogiri::HTML::DocumentFragment.parse(html)
    doc.css("action-text-attachment[content-type='application/pdf']").each do |node|
      filename = filename_for_attachment(node)
      node.replace(Nokogiri::HTML::DocumentFragment.parse("📎 #{filename}"))
    end
    HtmlToMarkdown.convert(doc.to_html, skip_images: true).content
  end

  def self.filename_for_attachment(node)
    sgid = node["sgid"]
    return "attachment" unless sgid

    attachable = ActionText::Attachable.from_attachable_sgid(sgid)
    case attachable
    when ActiveStorage::Blob then attachable.filename.to_s
    when Document then attachable.file.filename.to_s
    else "attachment"
    end
  rescue
    "attachment"
  end
```

> `ActionText::Attachable.from_attachable_sgid` resolves a direct-uploaded file's sgid to the `ActiveStorage::Blob`. The `case` also handles a `Document` (defensive). Wrap in `rescue` so a bad sgid never breaks the save.

- [ ] **Step 4: Run the tests**

```bash
bin/rails test test/models/message_html_to_markdown_test.rb
```
Expected: PASS. If the plain-text identity test fails, apply the guard tightening noted in Step 1 and re-run.

- [ ] **Step 5: Run the broader message/chat suite for regressions**

```bash
bin/rails test test/models/message_test.rb test/models/chat_test.rb test/jobs/chat_response_job_test.rb
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/models/message.rb test/models/message_html_to_markdown_test.rb
git commit -m "feat: convert composer HTML to markdown on user message save"
```

---

### Task 7: Chat#wait_for_attached_sources! (the indexing gate)

**Files:**
- Modify: `app/models/chat.rb` (or create `app/models/chat/indexing_gate.rb` concern)
- Test: `test/models/chat/wait_for_attached_sources_test.rb`

**Purpose:** Bounded poll over a message's attached sources; returns `{ready:, failed:, timed_out:}`. No-op when there are none.

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/chat/wait_for_attached_sources_test.rb
require "test_helper"

class ChatWaitForAttachedSourcesTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "wg@example.com", password: "testpassword123")
    @account = Account.create!(name: "WG Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  def message_with(websites: [], documents: [])
    @chat.messages.create!(role: "user", content: "hi",
      attached_website_ids: websites, attached_document_ids: documents)
  end

  test "no-op when there are no attached sources" do
    message = message_with
    result = @chat.wait_for_attached_sources!(message, timeout: 1.second, step: 0.05)
    assert_equal [], result[:ready]
    assert_equal [], result[:failed]
    assert_equal [], result[:timed_out]
  end

  test "waits for a pending source to become indexed, then returns it ready" do
    w = @account.websites.create!(url: "https://w.example", index_status: :pending)
    message = message_with(websites: [w.id])
    Thread.new { sleep 0.1; w.reload.update!(index_status: :indexed, indexed_at: Time.current) }
    result = @chat.wait_for_attached_sources!(message, timeout: 5.seconds, step: 0.05)
    assert_includes result[:ready].map(&:id), w.id
    assert_equal [], result[:timed_out]
  end

  test "a failed source is excluded and reported as failed without waiting" do
    w = @account.websites.create!(url: "https://f.example", index_status: :failed)
    message = message_with(websites: [w.id])
    result = @chat.wait_for_attached_sources!(message, timeout: 1.second, step: 0.05)
    assert_includes result[:failed].map(&:id), w.id
    assert_equal [], result[:ready]
  end

  test "a source still pending at the timeout is reported as timed_out" do
    w = @account.websites.create!(url: "https://t.example", index_status: :pending)
    message = message_with(websites: [w.id])
    result = @chat.wait_for_attached_sources!(message, timeout: 0.2.seconds, step: 0.05)
    assert_includes result[:timed_out].map(&:id), w.id
  end
end
```

> Keep `step` and `timeout` tiny in tests so they run fast. Production uses the defaults (120s / 1s).

- [ ] **Step 2: Run to verify it fails**

```bash
bin/rails test test/models/chat/wait_for_attached_sources_test.rb
```
Expected: FAIL — `undefined method wait_for_attached_sources!`.

- [ ] **Step 3: Implement the gate**

Add to `app/models/chat.rb` (instance method, public, ordered with other public methods):

```ruby
  def wait_for_attached_sources!(user_message, timeout: ENV.fetch("CHAT_INDEXING_TIMEOUT", 120).to_i.seconds, step: 1.second)
    sources = user_message.attached_websites + user_message.attached_documents
    return { ready: [], failed: [], timed_out: [] } if sources.empty?

    deadline = Time.current + timeout

    loop do
      pending = sources.reject { |source| source.index_status.indexed? || source.index_status.failed? }
      break if pending.empty? || Time.current >= deadline
      sleep step
      sources = sources.map(&:reload)
    end

    {
      ready:     sources.select { |source| source.index_status.indexed? },
      failed:    sources.select { |source| source.index_status.failed? },
      timed_out: sources.reject { |source| source.index_status.indexed? || source.index_status.failed? }
    }
  end
```

> Spec's advisory optimization: reload only `pending` sources each tick. For ≤ a handful of attachments per message the simpler `map(&:reload)` is fine; if profiling later shows cost, narrow to pending.

- [ ] **Step 4: Run to verify it passes**

```bash
bin/rails test test/models/chat/wait_for_attached_sources_test.rb
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/chat.rb test/models/chat/wait_for_attached_sources_test.rb
git commit -m "feat: Chat#wait_for_attached_sources! polling gate"
```

---

### Task 8: ChatSourcesController + route

**Files:**
- Create: `app/controllers/chat_sources_controller.rb`
- Modify: `config/routes.rb`
- Test: `test/controllers/chat_sources_controller_test.rb`

**Purpose:** Account-scoped `create` that the composer POSTs to. Two branches: `url` → `Website.find_or_create_by_url!`, `blob_signed_id` → `Document.create_from_blob!`. JSON only. (See @crud-patterns, @controllers rules.)

- [ ] **Step 1: Write the failing test**

```ruby
# test/controllers/chat_sources_controller_test.rb
require "test_helper"

class ChatSourcesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(email: "cs@example.com", password: "testpassword123")
    @account = Account.create!(name: "CS Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    post login_url, params: { email: @user.email, password: "testpassword123" }
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "url branch creates a website and returns its id/title/status as JSON" do
    assert_enqueued_with(job: CrawlWebsiteUrlJob) do
      post chat_sources_url, params: { url: "https://x.example/page" }, as: :json
    end
    assert_response :success
    json = JSON.parse(response.body)
    assert json["id"].present?
    assert_equal "https://x.example/page", json["url"]
    assert_equal "pending", json["index_status"]
    assert @account.websites.exists?(id: json["id"])
  end

  test "blob branch creates a document and returns its id/filename/status as JSON" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4"), filename: "report.pdf", content_type: "application/pdf"
    )
    assert_enqueued_with(job: AddDocumentJob) do
      post chat_sources_url, params: { blob_signed_id: blob.signed_id }, as: :json
    end
    assert_response :success
    json = JSON.parse(response.body)
    assert json["id"].present?
    assert_equal "report.pdf", json["filename"]
    assert_equal "pending", json["index_status"]
  end

  test "duplicate url reuses the existing website without creating a new one" do
    existing = @account.websites.create!(url: "https://dup.example", index_status: :indexed)
    post chat_sources_url, params: { url: "https://dup.example" }, as: :json
    assert_response :success
    assert_equal existing.id, JSON.parse(response.body)["id"]
  end

  test "rejects when neither url nor blob_signed_id is provided" do
    post chat_sources_url, params: {}, as: :json
    assert_response :bad_request
  end
end
```

> `Current.account` resolves in the controller via the session cookie set by `post login_url` (the auth middleware sets `Current.session.user.first_account`). Cross-account isolation is covered at the model level in Task 4; add a second-logged-in-user integration test only if you want belt-and-suspenders.

- [ ] **Step 2: Run to verify it fails**

```bash
bin/rails test test/controllers/chat_sources_controller_test.rb
```
Expected: FAIL — `undefined route chat_sources_url` / no controller.

- [ ] **Step 3: Add the route**

In `config/routes.rb`, inside `constraints Authentication::Authenticated` (next to `resources :chats`):

```ruby
    resources :chat_sources, only: [ :create ]
```

- [ ] **Step 4: Create the controller**

```ruby
# app/controllers/chat_sources_controller.rb
class ChatSourcesController < ApplicationController
  def create
    if url_param.present?
      website = Website.find_or_create_by_url!(Current.account, url_param)
      render json: {
        id: website.id,
        title: website.title,
        url: website.url,
        index_status: website.index_status
      }
    elsif blob_signed_id.present?
      document = Document.create_from_blob!(Current.account, blob_signed_id)
      render json: {
        id: document.id,
        filename: document.file.filename.to_s,
        index_status: document.index_status
      }
    else
      render json: { error: "url or blob_signed_id is required" }, status: :bad_request
    end
  end

  private

  def url_param
    params[:url]
  end

  def blob_signed_id
    params[:blob_signed_id]
  end
end
```

> `website.index_status` serializes to the string `"pending"` (Rails enum serialization in JSON). Confirm in the test output; if it serializes as the integer, use `website.index_status.to_s`.

- [ ] **Step 5: Run the test to verify it passes**

```bash
bin/rails test test/controllers/chat_sources_controller_test.rb
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/chat_sources_controller.rb config/routes.rb test/controllers/chat_sources_controller_test.rb
git commit -m "feat: ChatSourcesController creates sources from the composer"
```

---

### Task 9: Wire controllers to stamp attached ids + pass markdown to the job

**Files:**
- Modify: `app/controllers/chats_controller.rb`, `app/controllers/messages_controller.rb`
- Test: `test/controllers/chats_controller_test.rb`, `test/controllers/messages_controller_test.rb` (append)

**Purpose:** Both controllers read the hidden `attached_*_ids` params and stamp them on the user message, and pass the persisted markdown `@user_message.content` to `ChatResponseJob` (so the LLM never sees HTML). (See @controllers rules.)

- [ ] **Step 1: Write the failing tests (append)**

```ruby
# append to ChatsControllerTest (ActionDispatch::IntegrationTest). If the class
# already has a setup that logs in (mirror the McpServersControllerTest pattern),
# reuse it; otherwise add:
  def setup
    @user = User.create!(email: "cc@example.com", password: "testpassword123")
    @account = Account.create!(name: "CC Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    post login_url, params: { email: @user.email, password: "testpassword123" }
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "create stamps attached source ids on the user message" do
    w = @account.websites.create!(url: "https://c.example", index_status: :indexed)
    assert_enqueued_with(job: ChatResponseJob) do
      post chats_url, params: { chat: { prompt: "<p>hello</p>", attached_website_ids: [w.id] } }
    end
    message = Chat.last.messages.where(role: :user).last
    assert_equal [w.id], message.attached_website_ids
    assert_equal "hello", message.content.strip # HTML converted to markdown
  end
```

```ruby
# append to MessagesControllerTest (ActionDispatch::IntegrationTest), same setup pattern:
  test "create stamps attached document ids and passes markdown to the job" do
    chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
    d = @account.documents.new
    d.file.attach(io: StringIO.new("x"), filename: "d.pdf", content_type: "application/pdf")
    d.save!
    assert_enqueued_with(job: ChatResponseJob) do
      post chat_messages_url(chat), params: { message: { content: "<p>hi <em>there</em></p>", attached_document_ids: [d.id] } }
    end
    message = chat.messages.where(role: :user).last
    assert_equal [d.id], message.attached_document_ids
    assert_equal "hi *there*", message.content.strip
  end
```

> If `ChatsControllerTest`/`MessagesControllerTest` don't yet exist, create them as `ActionDispatch::IntegrationTest` classes with the `setup` shown. If `ChatResponseJob` is stubbed in existing chat tests (so no real LLM call fires), mirror that stub here.

- [ ] **Step 2: Run to verify they fail**

```bash
bin/rails test test/controllers/chats_controller_test.rb test/controllers/messages_controller_test.rb
```
Expected: FAIL — ids not stamped / content still HTML.

- [ ] **Step 3: Update `ChatsController#create`**

```ruby
  def create
    return unless prompt.present?

    @chat = Current.user.chats.create!(account: Current.account, model: model, provider: :openai, assume_model_exists: true)

    if params[:mcp_server_ids].present?
      mcp_server_ids = params[:mcp_server_ids].reject(&:blank?)
      mcp_server_ids.each do |server_id|
        mcp_server = Current.account.mcp_servers.find_by(id: server_id)
        @chat.add_mcp_server(mcp_server) if mcp_server
      end
    end

    @user_message = @chat.messages.create!(
      role: "user",
      content: prompt,
      attached_website_ids: Array(params[:chat][:attached_website_ids]).compact_blank,
      attached_document_ids: Array(params[:chat][:attached_document_ids]).compact_blank
    )

    ChatResponseJob.perform_later(@chat.id, @user_message.content, @user_message.id)

    redirect_to @chat
  end
```

> `@user_message.content` is markdown (the `before_save` from Task 6 ran inside `create!`). Previously the job received the raw `prompt`; now it receives markdown.

- [ ] **Step 4: Update `MessagesController#create`**

```ruby
  def create
    return unless content.present?

    @user_message = @chat.messages.create!(
      role: "user",
      content: content,
      attached_website_ids: Array(params[:message][:attached_website_ids]).compact_blank,
      attached_document_ids: Array(params[:message][:attached_document_ids]).compact_blank
    )

    ChatResponseJob.perform_later(@chat.id, @user_message.content, @user_message.id)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @chat }
    end
  end
```

- [ ] **Step 5: Run to verify they pass**

```bash
bin/rails test test/controllers/chats_controller_test.rb test/controllers/messages_controller_test.rb
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/chats_controller.rb app/controllers/messages_controller.rb test/controllers/chats_controller_test.rb test/controllers/messages_controller_test.rb
git commit -m "feat: stamp attached source ids and pass markdown to ChatResponseJob"
```

---

### Task 10: ChatResponseJob gate + warn note

**Files:**
- Modify: `app/jobs/chat_response_job.rb`, `app/models/chat/completionable.rb`
- Test: `test/jobs/chat_response_job_test.rb`

**Purpose:** The job waits on attached sources before completion and passes excluded (failed/timed-out) sources into the prompt as a note. (See @job-patterns.)

- [ ] **Step 1: Write the failing test**

```ruby
# test/jobs/chat_response_job_test.rb
require "test_helper"

class ChatResponseJobTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "cr@example.com", password: "testpassword123")
    @account = Account.create!(name: "CR Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "waits for an attached website to index, then completes" do
    w = @account.websites.create!(url: "https://j.example", index_status: :pending)
    user_message = @chat.messages.create!(role: "user", content: "ask",
      attached_website_ids: [w.id])

    Thread.new { sleep 0.1; w.reload.update!(index_status: :indexed, indexed_at: Time.current) }

    Chat.any_instance.stubs(:complete_with_nosia).returns(@chat.messages.create!(role: :assistant, content: "ok"))
    ChatResponseJob.perform_now(@chat.id, user_message.content, user_message.id)

    assert w.reload.index_status.indexed?
  end

  test "a failed attached source is excluded and the prompt includes a warn note" do
    w = @account.websites.create!(url: "https://f.example", index_status: :failed, data: "# Failed Title")
    user_message = @chat.messages.create!(role: "user", content: "ask",
      attached_website_ids: [w.id])

    captured = nil
    Chat.any_instance.stubs(:complete_with_nosia) do |question, **opts|
      captured = opts[:excluded_sources]
      @chat.messages.create!(role: :assistant, content: "ok")
    end

    ChatResponseJob.perform_now(@chat.id, user_message.content, user_message.id)

    assert captured
    assert_includes captured.map { |s| s.respond_to?(:title) ? s.title : s.to_s }, w.title
  end

  test "no attached sources -> behaves as today (no wait)" do
    user_message = @chat.messages.create!(role: "user", content: "ask")
    Chat.any_instance.stubs(:complete_with_nosia).returns(@chat.messages.create!(role: :assistant, content: "ok"))
    assert_nothing_raised { ChatResponseJob.perform_now(@chat.id, user_message.content, user_message.id) }
  end
end
```

> Stub `complete_with_nosia`/`complete_with_agent_skills` so no real LLM call fires (match how existing chat tests stub the completion). The failed website has `data: "# Failed Title"` so `w.title` is non-nil.

- [ ] **Step 2: Run to verify it fails**

```bash
bin/rails test test/jobs/chat_response_job_test.rb
```
Expected: FAIL — no gate / no `excluded_sources` kwarg.

- [ ] **Step 3: Update `ChatResponseJob#perform`**

```ruby
  def perform(chat_id, content, user_message_id = nil)
    Rails.logger.info "=== ChatResponseJob started for chat ##{chat_id} ==="
    chat = Chat.find(chat_id)
    user_message = user_message_id ? Message.find(user_message_id) : nil
    Rails.logger.info "User message: #{user_message&.id} - Content: #{content[0..100]}..."

    excluded = if user_message
      result = chat.wait_for_attached_sources!(user_message)
      result[:failed] + result[:timed_out]
    else
      []
    end

    if Rails.application.config.agent_skills.enabled
      result = chat.complete_with_agent_skills(content, user_message: user_message, excluded_sources: excluded)
    else
      result = chat.complete_with_nosia(content, user_message: user_message, excluded_sources: excluded)
    end

    Rails.logger.info "=== ChatResponseJob completed. Result: #{result&.id} ==="
  rescue Faraday::TimeoutError => e
    Rails.logger.error "=== ChatResponseJob ERROR: Timeout ==="
    Rails.logger.error e.message
  rescue Faraday::Error => e
    Rails.logger.error "=== ChatResponseJob ERROR: Network error ==="
    Rails.logger.error e.message
  rescue => e
    Rails.logger.error "=== ChatResponseJob ERROR: #{e.class} ==="
    Rails.logger.error e.message
    Rails.logger.error e.backtrace.join("\n")
  end
```

- [ ] **Step 4: Accept `excluded_sources:` in `complete_with_nosia` and append the warn note**

In `app/models/chat/completionable.rb`, update the signature and the instructions step:

```ruby
  def complete_with_nosia(question, model: nil, temperature: nil, top_k: nil, top_p: nil, max_tokens: nil, user_message: nil, excluded_sources: [], &block)
```

After the `if chunks.any? ... else ... end` instructions block (around line 48), add:

```ruby
    if excluded_sources.present?
      titles = excluded_sources.filter_map { |source| source.respond_to?(:title) ? source.title : nil }.compact
      names = titles.any? ? titles : excluded_sources.map { |source| source.class.name.downcase }
      note = "Note: the following attachments could not be retrieved and were excluded: #{names.join(", ")}."
      self.with_instructions(note, append: true) # appends after the system prompt; does NOT replace
    end
```

> The `ruby_llm` gem signature is `with_instructions(instructions, append: false, replace: nil)` — the default does **not** append. You must pass `append: true` (confirmed in `ruby_llm-1.14.0`'s `chat_methods.rb`, which uses `with_instructions(instruction, append: true)` itself). Without `append: true` this would clobber the system prompt. If your installed `ruby_llm` version differs and `append:` isn't supported, instead prepend the note to the `augmented_system_prompt` / `system_prompt` string before the existing `with_instructions(..., replace: true)` call.

Do the same for `complete_with_agent_skills` (`app/models/chat/agent_skillable.rb`): add `excluded_sources: []` to its signature and forward it to `complete_with_nosia` on the fall-through path (and apply the note similarly if it builds its own instructions).

- [ ] **Step 5: Run the tests**

```bash
bin/rails test test/jobs/chat_response_job_test.rb
```
Expected: PASS.

- [ ] **Step 6: Run the full chat suite for regressions**

```bash
bin/rails test test/models/chat_test.rb test/models/chat/ test/jobs/
```
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/jobs/chat_response_job.rb app/models/chat/completionable.rb app/models/chat/agent_skillable.rb test/jobs/chat_response_job_test.rb
git commit -m "feat: ChatResponseJob waits for attached sources and warns on exclusions"
```

---

### Task 11: Install Lexxy (gem + importmap + spike)

**Files:**
- Modify: `Gemfile`, `config/importmap.rb`, `app/javascript/application.js`

**Purpose:** Bring in Lexxy via the gem (Importmap, no Node). Spike to confirm `lexxy_rich_text_area` renders `<lexxy-editor>` with the right `name` and does **not** create an Action Text table, and that Active Storage direct upload works for PDFs.

- [ ] **Step 1: Add the gem**

```ruby
# Gemfile
gem "lexxy", "~> 0.9.23"
```

```bash
bundle install
```

- [ ] **Step 2: Pin via importmap**

```ruby
# config/importmap.rb (append)
pin "lexxy", to: "lexxy.js"
pin "@rails/activestorage", to: "activestorage.esm.js" # for PDF direct uploads
```

- [ ] **Step 3: Import in the bundle**

```js
// app/javascript/application.js (append)
import "lexxy"
```

- [ ] **Step 4: Spike — render the editor in a throwaway view and verify**

Temporarily add to a view you can load (e.g. a new `chats#new` local override is coming in Task 14; for the spike, render in a scratch erb and remove it):

```erb
<%= form_with url: root_path, method: :get do |f| %>
  <%= f.lexxy_rich_text_area :prompt, permitted_attachment_types: "application/pdf" %>
<% end %>
```

Verify in the browser:
- [ ] The element renders as `<lexxy-editor name="prompt">` (inspect the form).
- [ ] Typing and submit sends the HTML string under `prompt` (check server logs / `params`).
- [ ] Pasting a URL creates an `<a href>` and fires a `lexxy:insert-link` event (add a temporary `addEventListener` in the console to confirm).
- [ ] Dragging a PDF onto the editor triggers an Active Storage direct upload to `/rails/active_storage/direct_uploads` and embeds an `<action-text-attachment>` (check Network tab + the editor DOM).
- [ ] **No `action_text_rich_texts` row is created** (Lexxy explicit helper must not persist Action Text): `bin/rails runner "puts ActionText::RichText.count"` — confirm it stays 0 after a submit.

> If `lexxy_rich_text_area` is unavailable or persists Action Text, set `config.lexxy.override_action_text_defaults = false` in `config/application.rb` and re-test. Record which helper name works; use it consistently from Task 14 on. (See @stimulus-patterns.)

- [ ] **Step 5: Run the test suite to confirm the gem load doesn't break anything**

```bash
bin/rails test
```
Expected: PASS (no regressions from the gem).

- [ ] **Step 6: Remove the scratch spike view; commit the install**

```bash
git add Gemfile Gemfile.lock config/importmap.rb app/javascript/application.js
git commit -m "feat: install Lexxy rich text editor (importmap, no Action Text)"
```

---

### Task 12: composer_controller.js — Enter-to-send, link & PDF interception, hidden ids

**Files:**
- Create: `app/javascript/controllers/composer_controller.js`
- Test: `test/system/chat_composer_test.rb` (interception part)

**Purpose:** The composer's JS brain (minus the `/skill` palette, which is Task 13). Listens to Lexxy events, POSTs to `/chat_sources`, accumulates source ids into hidden inputs, and sends on plain Enter. (See @stimulus-patterns.)

- [ ] **Step 1: Write the controller**

```js
// app/javascript/controllers/composer_controller.js
import { Controller } from "@hotwired/stimulus"
import { post } from "@rails/request.js"

export default class extends Controller {
  static targets = ["editor", "websiteIds", "documentIds"]

  connect() {
    this.editorTarget.addEventListener("lexxy:insert-link", this.onInsertLink.bind(this))
    this.editorTarget.addEventListener("lexxy:upload-end", this.onUploadEnd.bind(this))
  }

  disconnect() {
    this.editorTarget.removeEventListener("lexxy:insert-link", this.onInsertLink.bind(this))
    this.editorTarget.removeEventListener("lexxy:upload-end", this.onUploadEnd.bind(this))
  }

  // Enter to send, Shift+Enter newline.
  handleKeys(event) {
    if (event.key === "Enter" && !event.shiftKey && !event.metaKey && !event.ctrlKey) {
      event.preventDefault()
      this.element.requestSubmit()
    }
  }

  async onInsertLink(event) {
    const url = event.detail.url
    if (!url) return

    // Let Lexxy keep its default <a href> anchor; just record the Website.
    const response = await post("/chat_sources", {
      body: JSON.stringify({ url }),
      headers: { "Content-Type": "application/json", "Accept": "application/json" }
    })
    if (response.ok) {
      const data = await response.json
      this.addId(this.websiteIdsTarget, data.id)
    }
  }

  async onUploadEnd(event) {
    if (event.detail.error) return

    const file = event.detail.file
    // The blob was created by Active Storage direct upload; fetch its signed_id.
    // Lexxy exposes the attachable on the event/detail when available; otherwise
    // read it from the embedded attachment node after it lands.
    const signedId = file?.signed_id || this.signedIdFromLatestAttachment()
    if (!signedId) return

    const response = await post("/chat_sources", {
      body: JSON.stringify({ blob_signed_id: signedId }),
      headers: { "Content-Type": "application/json", "Accept": "application/json" }
    })
    if (response.ok) {
      const data = await response.json
      this.addId(this.documentIdsTarget, data.id)
    }
  }

  signedIdFromLatestAttachment() {
    const node = this.editorTarget.querySelector("action-text-attachment")
    return node?.getAttribute("sgid")
  }

  // Clone the target hidden input's name so it submits in the right params namespace
  // (chat[attached_website_ids][] vs message[attached_website_ids][]).
  addId(target, id) {
    if (!id) return
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = target.name
    input.value = id
    target.parentNode.appendChild(input)
  }
}
```

> `@rails/request.js` must be importmap-pinned if not already. Check `config/importmap.rb` for `pin "@rails/request.js"`; if missing, add `pin "@rails/request.js", to: "requestjs.esm.js"` (or the path your app uses) and `bundle exec rails importmap:install`-style pin. The `signedId` extraction is the part most likely to differ from Lexxy's actual `upload-end` detail shape — confirm against the Lexxy docs during the Task 11 spike and adjust `onUploadEnd`/`signedIdFromLatestAttachment` to match. The fallback reads the `sgid` from the embedded `action-text-attachment` node, which is reliable.

- [ ] **Step 2: Write the system test (interception)**

```ruby
# test/system/chat_composer_test.rb
require "test_helper"

class ChatComposerTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]

  def setup
    @user = User.create!(email: "sc@example.com", password: "testpassword123")
    @account = Account.create!(name: "SC Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    visit login_url
    fill_in "email", with: @user.email
    fill_in "password", with: "testpassword123"
    click_button "Login" # adjust selector to match the real login form
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "pasting a URL creates a Website indexed before the assistant replies" do
    visit root_url # landing composer

    find("lexxy-editor").click
    page.execute_script(<<~JS)
      const editor = document.querySelector("lexxy-editor");
      editor.value = '<p>https://example.com</p>';
      editor.dispatchEvent(new CustomEvent("lexxy:insert-link", { detail: { url: "https://example.com" } }));
    JS

    assert_difference -> { @account.websites.where(url: "https://example.com").count }, 1 do
      sleep 1 # wait for the POST to /chat_sources
    end

    find("lexxy-editor").send_keys :return
    # assert the assistant reply stream appears (mirror existing chat system test waits).
  end
end
```

> System tests for a custom-element editor are fiddly. Mirror the existing `test/system` setup (Capybara + Selenium config, login form selectors, LLM stubbing). `ActsAsTenant.current_tenant = @account` is set in the test process so `@account.websites` queries are scoped correctly; the browser runs in its own session. If driving the editor via `execute_script` is brittle, the next best coverage is `ChatSourcesControllerTest` (Task 8). Keep this test focused on the paste→Website link; the `/skill` palette gets its own test in Task 13.

- [ ] **Step 3: Run the system test**

```bash
bin/rails test test/system/chat_composer_test.rb
```
Expected: PASS (adjust the editor-driving script until it reliably creates the Website).

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/composer_controller.js test/system/chat_composer_test.rb
git commit -m "feat: composer_controller handles link/PDF interception and Enter-to-send"
```

---

### Task 13: composer_controller.js — `/skill` palette port

**Files:**
- Modify: `app/javascript/controllers/composer_controller.js`
- Test: `test/system/chat_skill_palette_test.rb`

**Purpose:** Port `skill_autocomplete_controller` to Lexxy's selection API. **Highest-risk task** — spike first. (See @stimulus-patterns.)

- [ ] **Step 1: Spike the Lexxy selection/insert API**

In the browser console on a page with `<lexxy-editor>`:

```js
const editor = document.querySelector("lexxy-editor")
// Inspect the Lexical editor instance and selection API:
editor.editor  // the Lexical editor
editor.editor.read(() => {
  const sel = editor.editor.getEditorState().read(() => window.Lexical.$getSelection?.())
  console.log(sel)
})
```

Confirm how to (a) read the text around the caret, (b) insert a text node at the caret via `editor.update(() => { ... $insertNodes(...) })`. Document the exact calls that work; these drive Step 2. If the API can't be reached cleanly, fall back to the documented fallback: keep a hidden sync `<textarea>` mirror of the editor's plain text that the palette reads, and insert `/skill-name ` by setting the editor value to `currentHtml + insertion` (less ideal — note this in the commit).

- [ ] **Step 2: Port the palette logic**

Read the existing `app/javascript/controllers/skill_autocomplete_controller.js` and reproduce its menu rendering + skills-fetch against the same `data-skills` value, but:
- detect `/` at the start of the current line via the Lexxy selection API (from the spike),
- on selection, insert `/skill-name ` as a text node at the caret via `editor.update(...)`.

Add to `composer_controller.js`:
- `static values = { skills: Array }` (read from `data-composer-skills-value`, mirroring the old `data-skill-autocomplete-skills-value`).
- a `menuTarget` for the dropdown.
- `onSelectionChange` / key handling to show/hide/insert.

- [ ] **Step 3: Write the system test**

```ruby
# test/system/chat_skill_palette_test.rb
require "test_helper"

class ChatSkillPaletteTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]

  def setup
    @user = User.create!(email: "sk@example.com", password: "testpassword123")
    @account = Account.create!(name: "SK Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    visit login_url
    fill_in "email", with: @user.email
    fill_in "password", with: "testpassword123"
    click_button "Login" # adjust to match the real login form
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "typing / shows the skill menu and selecting inserts the skill command" do
    visit root_url
    find("lexxy-editor").click
    page.execute_script(<<~JS)
      const editor = document.querySelector("lexxy-editor");
      editor.value = "<p>/</p>";
    JS
    # Wait for the menu to appear (mirror the menu selector from skill_autocomplete).
    assert_selector(".n-skill-menu", visible: true)
    # Click the first item.
    first(".n-skill-menu [role='option']").click
    # The editor value now contains the /skill-name token.
    assert_includes page.evaluate_script("document.querySelector('lexxy-editor').value"), "/"
  end
end
```

> Adjust selectors to match the ported menu markup. If the skill menu driving is too brittle under Selenium, assert at the controller/DOM level that the menu element becomes visible when the editor dispatches the right event.

- [ ] **Step 4: Run the test**

```bash
bin/rails test test/system/chat_skill_palette_test.rb
```
Expected: PASS (or, if the API spike blocked a clean port, mark the test `pending` with a note and use the hidden-textarea fallback — record the decision in the commit message).

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/composer_controller.js test/system/chat_skill_palette_test.rb
git commit -m "feat: port /skill command palette to the Lexxy composer"
```

---

### Task 14: Composer views — Lexxy + hidden fields (carry over existing bits)

**Files:**
- Modify: `app/views/messages/_form.html.erb`, `app/views/chats/_form.html.erb`

**Purpose:** Swap the `text_area` for `lexxy_rich_text_area`, add hidden `attached_*_ids` fields, wire `composer_controller`. **Keep** the existing MCP hidden-fields block, Stop/Send button branch, and footer text — do not silently drop them (spec open item).

- [ ] **Step 1: Update `app/views/messages/_form.html.erb`**

Replace the `text_area` (line 6) and wrap with the composer controller. Keep the MCP button/footer and the skill-menu div (now the composer's menu target). Example diff:

```erb
  <div class="relative w-full" data-controller="composer" data-composer-skills-value="<%= agent_skill_autocomplete_data %>">
    <%= form.hidden_field :attached_website_ids, multiple: true, data: { composer_target: "websiteIds" } %>
    <%= form.hidden_field :attached_document_ids, multiple: true, data: { composer_target: "documentIds" } %>

    <%= form.lexxy_rich_text_area :content,
          class: "n-form-chat",
          permitted_attachment_types: "application/pdf",
          data: { composer_target: "editor",
                  action: "lexxy:insert-link->composer#onInsertLink
                           lexxy:upload-end->composer#onUploadEnd
                           keydown->composer#handleKeys
                           keydown.meta+enter->form#submit
                           keydown.ctrl+enter->form#submit" } %>

    <div class="n-skill-menu hidden" role="listbox" aria-label="Available skills" data-composer-target="menu"></div>

    <%= form.button type: :submit, data: { action: "form#submit" }, class: "n-btn-chat n-btn-chat-send" do %>
      <%# keep existing send-icon SVG %>
    <% end %>
  </div>
```

> Also update the outer `form_with` `data:` from `controller: "form chat-input"` to `controller: "form composer"` and `chat_input_target: "wrapper"` → `composer_target: "wrapper"` (add `wrapper` to `static targets` in the controller, or drop the wrapper target if unused). Keep the `form` controller for submit. Preserve the footer `Enter to send · Shift+Enter…` line and the MCP button.

- [ ] **Step 2: Update `app/views/chats/_form.html.erb`**

Same swap for the `:prompt` field (line 10). Because the form object is a `Chat` (no `attached_*_ids` columns), use `hidden_field_tag`:

```erb
  <div class="relative w-full" data-composer-target="wrapper" data-controller="composer" data-composer-skills-value="<%= agent_skill_autocomplete_data %>">
    <%= hidden_field_tag "chat[attached_website_ids][]", nil, data: { composer_target: "websiteIds" } %>
    <%= hidden_field_tag "chat[attached_document_ids][]", nil, data: { composer_target: "documentIds" } %>

    <%= form.lexxy_rich_text_area :prompt,
          rows: 2, autofocus: !is_generating,
          placeholder: (is_generating ? "AI is generating..." : "Ask anything…"),
          disabled: is_generating,
          class: "n-form-chat",
          permitted_attachment_types: "application/pdf",
          data: { composer_target: "editor",
                  action: "lexxy:insert-link->composer#onInsertLink
                           lexxy:upload-end->composer#onUploadEnd
                           keydown->composer#handleKeys" } %>

    <div class="n-skill-menu hidden" role="listbox" aria-label="Available skills" data-composer-target="menu"></div>

    <% if is_generating %>
      <%= button_to stop_chat_path(chat), method: :post, class: "n-btn-chat n-btn-stop-chat" do %>
        <%# keep stop SVG %>
      <% end %>
    <% else %>
      <%= form.button type: :submit, data: { action: "form#submit" }, class: "n-btn-chat n-btn-chat-send" do %>
        <%# keep send SVG %>
      <% end %>
    <% end %>
  </div>
```

> Keep the `#mcp-server-hidden-fields` div (line 7), the MCP selection `<details>` block (lines 41-74), and the footer (lines 76-86). Update the outer `form_with` `data: { controller: "chat-input" }` → `data: { controller: "composer" }`.

- [ ] **Step 3: Smoke-test both forms in the browser**

- [ ] `bin/dev`, open the landing composer and an existing chat.
- [ ] Both render a `<lexxy-editor>`; typing works; Enter sends; Shift+Enter adds a newline.
- [ ] The MCP selection + Stop/Send buttons still work.
- [ ] No console errors about missing Stimulus targets.

- [ ] **Step 4: Run the controller + system tests**

```bash
bin/rails test test/controllers/chats_controller_test.rb test/controllers/messages_controller_test.rb test/system/chat_composer_test.rb
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/views/messages/_form.html.erb app/views/chats/_form.html.erb
git commit -m "feat: chat composer forms use Lexxy with attached-source hidden fields"
```

---

### Task 15: Source editors — Lexxy + HTML→markdown on save + markdown→HTML round-trip

**Files:**
- Create: `app/models/concerns/html_to_markdown_formattable.rb`
- Modify: `app/models/text.rb`, `app/models/qna.rb`, `app/models/website.rb`
- Modify: `app/views/sources/texts/_form.html.erb`, `app/views/sources/qnas/_form.html.erb`, `app/views/sources/websites/_form.html.erb`
- Test: `test/models/html_to_markdown_formattable_test.rb`

**Purpose:** Sources store markdown; Lexxy edits HTML. A shared concern converts HTML→markdown before save. On edit, render stored markdown→HTML (Commonmarker) as the editor's initial value. Attachments disabled (text-only). (See @concern-patterns.)

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/html_to_markdown_formattable_test.rb
require "test_helper"

class HtmlToMarkdownFormattableTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "hf@example.com", password: "testpassword123")
    @account = Account.create!(name: "HF Account", owner: @user)
    ActsAsTenant.current_tenant = @account
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "Text converts data HTML to markdown on save" do
    text = @account.texts.new(data: "<p>Hello <strong>world</strong></p>")
    text.save!
    assert_equal "Hello **world**", text.data.strip
  end

  test "Qna converts answer HTML to markdown on save (question untouched)" do
    qna = @account.qnas.new(question: "What?", answer: "<p>Because <em>reasons</em></p>")
    qna.save!
    assert_equal "What?", qna.question
    assert_equal "Because *reasons*", qna.answer.strip
  end

  test "Website converts data HTML to markdown on save" do
    website = @account.websites.new(url: "https://e.example", data: "<p>Body <a href=\"https://e.example\">link</a></p>")
    website.save!
    refute_includes website.data, "<p>"
    assert_includes website.data, "link"
  end
end
```

> Confirm `Account` has `has_many :texts` / `:qnas` (the Sources controllers use `Current.account.texts` etc.).

- [ ] **Step 2: Run to verify it fails**

```bash
bin/rails test test/models/html_to_markdown_formattable_test.rb
```
Expected: FAIL — data stored as HTML.

- [ ] **Step 3: Create the concern**

```ruby
# app/models/concerns/html_to_markdown_formattable.rb
module HtmlToMarkdownFormattable
  extend ActiveSupport::Concern

  class_methods do
    def html_to_markdown_attribute(attribute)
      define_method :"normalize_#{attribute}_to_markdown" do
        value = public_send(attribute)
        return if value.blank?
        return unless value.to_s.match?(/<[a-z!]/i) # only convert HTML, leave plain markdown alone

        public_send("#{attribute}=", HtmlToMarkdown.convert(value, skip_images: true).content)
      end

      before_save :"normalize_#{attribute}_to_markdown"
    end
  end
end
```

> The guard `match?(/<[a-z!]/i)` skips content that's already markdown (so editing a source that already stores markdown doesn't mangle it when no HTML is present). This is the safe variant of the spec's `before_save`.

- [ ] **Step 4: Include + declare attributes per model**

`app/models/text.rb`:
```ruby
  include HtmlToMarkdownFormattable
  html_to_markdown_attribute :data
```
`app/models/qna.rb`:
```ruby
  include HtmlToMarkdownFormattable
  html_to_markdown_attribute :answer
```
`app/models/website.rb`:
```ruby
  include HtmlToMarkdownFormattable
  html_to_markdown_attribute :data
```

- [ ] **Step 5: Run to verify it passes**

```bash
bin/rails test test/models/html_to_markdown_formattable_test.rb
```
Expected: PASS.

- [ ] **Step 6: Update the three source form views**

`app/views/sources/texts/_form.html.erb` — replace the `text_area :data` (line ~9) with:

```erb
    <%= form.lexxy_rich_text_area :data,
          value: Commonmarker.to_html(text.data.to_s),
          class: "n-textarea",
          permitted_attachment_types: "" %>
```

`app/views/sources/qnas/_form.html.erb` — replace `text_area :answer` with:

```erb
    <%= form.lexxy_rich_text_area :answer,
          value: Commonmarker.to_html(qna.answer.to_s),
          class: "n-textarea",
          permitted_attachment_types: "" %>
```

`app/views/sources/websites/_form.html.erb` — replace `text_area :data` (line 9) with:

```erb
    <%= form.lexxy_rich_text_area :data,
          value: Commonmarker.to_html(website.page_body_for_edit),
          class: "n-textarea",
          permitted_attachment_types: "" %>
```

> `Website` strips frontmatter before rendering (`page_body` private method). Add a public `page_body_for_edit` (or reuse `to_html`'s source) that returns the body without frontmatter, then Commonmarker→HTML. For `Text`/`Qna`, `Commonmarker.to_html(data)` renders stored markdown to HTML for the editor's initial value. **Caveat (spec):** the MD→HTML→MD round-trip is clean for prose; tables/complex formatting may drift — acceptable per the approved decision.

> Confirm `lexxy_rich_text_area` accepts a `value:` option that seeds the editor. If it instead reads from the form object's attribute, render the HTML into a transient attribute or use the `lexxy_rich_textarea_tag` form with an explicit value. Verify in the Task 11 spike.

- [ ] **Step 7: Smoke-test source editors in the browser**

- [ ] Create/edit a Text, a Qna, a Website; type formatted content; save; reload edit form; content round-trips for prose.

- [ ] **Step 8: Run the source test suites**

```bash
bin/rails test test/models/text_test.rb test/models/qna_test.rb test/models/website_test.rb test/models/html_to_markdown_formattable_test.rb
```
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add app/models/concerns/html_to_markdown_formattable.rb app/models/text.rb app/models/qna.rb app/models/website.rb \
        app/views/sources/texts/_form.html.erb app/views/sources/qnas/_form.html.erb app/views/sources/websites/_form.html.erb \
        test/models/html_to_markdown_formattable_test.rb
git commit -m "feat: source editors use Lexxy with HTML<->markdown round-trip"
```

---

### Task 16: End-to-end + CI

**Files:**
- Modify: `test/system/chat_composer_test.rb` (extend)

**Purpose:** One full pass: paste URL → Website indexed → submit → assistant references indexed content. Plus lint/security/CI. (See @verification-before-completion.)

- [ ] **Step 1: Extend the end-to-end system test**

In `test/system/chat_composer_test.rb`, add (or extend) a test that:
- [ ] pastes a URL into the landing composer (driving `lexxy:insert-link`),
- [ ] asserts a `Website` exists for the account with `index_status` reaching `indexed` (stub the crawl to set `data` + flip `indexed` synchronously, mirroring how existing tests stub the LLM/embedding),
- [ ] submits, and
- [ ] asserts the assistant reply renders (stubbed completion) and `similar_chunk_ids` on the resulting message includes a chunk from the Website (or that completion ran after the gate).

- [ ] **Step 2: Run the whole suite**

```bash
bin/rails test
```
Expected: PASS.

- [ ] **Step 3: Run the system tests**

```bash
bin/rails test:system
```
Expected: PASS (or pending for the palette test if the spike blocked it).

- [ ] **Step 4: Rubocop + Brakeman + full CI**

```bash
bundle exec rubocop -a
bundle exec brakeman --no-pager
bin/ci
```
Expected: green. Address any new offenses introduced by the added files.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "test: end-to-end chat composer paste-to-index and CI green"
```

---

## Rollout risks (from spec, tracked here for the implementer)

- **Lexxy on Rails 8.0.5** — use the explicit `lexxy_rich_text_area` helper; confirm in the Task 11 spike it does not create Action Text rows.
- **`/skill` palette port** — highest-risk JS; Task 13 spikes first; fallback is a hidden sync textarea.
- **MD→HTML→MD source round-trip** — prose is clean; tables/complex formatting may drift (accepted).
- **real_time worker occupancy** — `ChatResponseJob` sleeps during the gate (bounded 120s); Approach B is the documented escape hatch if starvation appears.
- **Active Storage direct upload auth** — confirm `/rails/active_storage/direct_uploads` is reachable by authenticated users in the Task 11 spike; set `config.lexxy.global.authenticatedUploads = true` if `withCredentials` is needed.

## Out of scope (YAGNI — do not build)

Image attachments in source editors · clickable citation links in rendered messages · scheduled re-indexing of stale sources · interception in non-chat editors · a separate `ChatCompletionGateJob` (Approach B).