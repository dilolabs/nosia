# Sources UI/UX Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace nosia's four fragmented per-type source pages with one unified, searchable, filterable Sources page that shows live per-source indexing status, supports drag-and-drop upload, and lets users retry failed sources.

**Architecture:** A new `Sourceable` model concern gives `Document`, `Text`, `Qna`, and `Website` a uniform row interface (label, title, subtitle, search, status broadcasts). A `SourceRow` plain Ruby object builds the merged/filtered/sorted/paginated collection for the unified `SourcesController#index` — a plain scoped query per single type, an in-memory merge for the "All" view (bounded to the hundreds-scale this product targets). One type-agnostic row partial replaces four duplicated card views. Live status uses Turbo Stream broadcasts fired from the model on `index_status` changes; new drag-dropped rows arrive via scoped create broadcasts. No database migration is required.

**Tech Stack:** Rails 8 (edge), Ruby 3.3, PostgreSQL, Hotwire (Turbo 8 + Stimulus 3.2), Propshaft + Importmap, Tailwind (`n-*` design-system classes), Solid Queue, Minitest (inline record creation — this project has **no fixtures**).

**Spec:** `docs/superpowers/specs/2026-07-11-sources-ux-design.md`

**Relevant project skills:** `concern-patterns`, `model-patterns`, `crud-patterns`, `turbo-patterns`, `testing-patterns`, `stimulus-patterns`.

---

## Conventions for every task

- **TDD:** write the failing test first, run it red, implement the minimum, run it green, commit.
- **Test setup pattern (copy this exactly — the project has no fixtures):**

```ruby
require "test_helper"

class SomethingTest < ActiveSupport::TestCase   # or ActionDispatch::IntegrationTest for controllers
  def setup
    @user = User.create!(email: "sx@example.com", password: "testpassword123")
    @account = Account.create!(name: "SX Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    # controllers only:
    post login_url, params: { email: @user.email, password: "testpassword123" }
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end
end
```

- **Chunk embedding stub:** any test that creates chunks must stub the embedding endpoint call, exactly as `test/models/indexable_test.rb` does:

```ruby
Chunk.define_method(:generate_embedding) { }
# ... test body ...
ensure
  Chunk.remove_method(:generate_embedding) if Chunk.instance_methods(false).include?(:generate_embedding)
```

- **Run a single test:** `bin/rails test test/path/to/file_test.rb` (append `:LINE` for one test).
- **Commit** after every green step. Commit messages follow Conventional Commits.
- **Do not** add fixtures, RSpec, FactoryBot, or a pagination gem.

---

## File structure

**Create:**
- `app/models/concerns/sourceable.rb` — uniform row interface + search declaration + status/create/destroy broadcasts.
- `app/models/source_row.rb` — PORO: builds the filtered/sorted/paginated collection and the sidebar counts.
- `app/views/sources/_source.html.erb` — single type-agnostic row partial (replaces 4 card partials).
- `app/views/sources/_sidebar.html.erb` — type/status navigation.
- `app/views/sources/_counts.html.erb` — just the count badges (id'd spans), broadcast-replaceable.
- `app/views/sources/_toolbar.html.erb` — search + sort + add-source chooser.
- `app/views/sources/_add_menu.html.erb` — the "+ Add source" chooser menu.
- `app/views/sources/_rows.html.erb` — the list body (rows + load-more), rendered by both HTML and turbo_stream.
- `app/views/sources/index.turbo_stream.erb` — "Load more" append response.
- `app/javascript/controllers/menu_controller.js` — tiny toggle for the add-source dropdown (only if `details/summary` is insufficient — see Task 9).
- Test files listed per task.

**Modify:**
- `app/models/concerns/indexable.rb` — add `mark_pending!`.
- `app/models/document.rb`, `text.rb`, `qna.rb`, `website.rb` — `include Sourceable`; define per-type `source_type_label`, `display_title`, `source_subtitle`, and a `search` scope.
- `app/controllers/sources_controller.rb` — unified `index`.
- `app/controllers/sources/documents_controller.rb`, `texts_controller.rb`, `qnas_controller.rb`, `websites_controller.rb` — add `retry`; redirect legacy `index` to unified; documents `create` prepends a live row.
- `config/routes.rb` — `member { post :retry }` on the four `sources` resources.
- `app/views/sources/index.html.erb` — rebuilt.

**Delete (replace body with a redirect or remove list markup):**
- The list markup in `app/views/sources/{documents,texts,qnas,websites}/index.html.erb` (their controllers will redirect instead).

---

## Phase 1 — Backend foundation

### Task 1: Add `Indexable#mark_pending!`

Retrying a failed source must reset it to `pending` so the UI shows "processing" again.

**Files:**
- Modify: `app/models/concerns/indexable.rb`
- Test: `test/models/indexable_test.rb`

- [ ] **Step 1: Write the failing test** — append inside `IndexableTest`:

```ruby
test "mark_pending! resets status to pending and clears indexed_at" do
  text = @account.texts.create!(data: "# Hi")
  text.mark_indexed!
  assert text.indexed?

  text.mark_pending!

  assert text.pending?
  assert_nil text.indexed_at
end
```

- [ ] **Step 2: Run it red** — `bin/rails test test/models/indexable_test.rb`
  Expected: FAIL — `NoMethodError: undefined method 'mark_pending!'`.

- [ ] **Step 3: Implement** — add to `app/models/concerns/indexable.rb` after `mark_indexed!`:

```ruby
  def mark_pending!
    update!(index_status: :pending, indexed_at: nil)
  end
```

- [ ] **Step 4: Run it green** — `bin/rails test test/models/indexable_test.rb` → PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/concerns/indexable.rb test/models/indexable_test.rb
git commit -m "feat: add Indexable#mark_pending! for source retry"
```

---

### Task 2: `Sourceable` concern — type identity, title, subtitle, search

One concern that every source model includes, giving the view a uniform interface. Per-type specifics (`source_type_label`, `display_title`, `source_subtitle`, `search`) are defined on each model; the concern documents/enforces the contract and provides safe fallbacks.

Reference: `concern-patterns`, `model-patterns`.

**Files:**
- Create: `app/models/concerns/sourceable.rb`
- Modify: `app/models/document.rb`, `app/models/text.rb`, `app/models/qna.rb`, `app/models/website.rb`
- Test: `test/models/sourceable_test.rb` (create)

- [ ] **Step 1: Write the failing test** — `test/models/sourceable_test.rb`:

```ruby
require "test_helper"

class SourceableTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "src@example.com", password: "testpassword123")
    @account = Account.create!(name: "SRC Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "each type reports its label and key" do
    doc  = @account.documents.new
    text = @account.texts.new(data: "hello")
    qna  = @account.qnas.new(question: "Q?", answer: "A")
    web  = @account.websites.new(url: "https://example.com")

    assert_equal "Document", doc.source_type_label
    assert_equal "document", doc.source_type_key
    assert_equal "Text",     text.source_type_label
    assert_equal "Q&A",      qna.source_type_label
    assert_equal "Website",  web.source_type_label
  end

  test "display_title falls back sensibly when title is blank" do
    text = @account.texts.new(data: "The quick brown fox jumps over the lazy dog and keeps going well past forty two characters")
    qna  = @account.qnas.new(question: "What is the refund policy?", answer: "30 days")
    web  = @account.websites.new(url: "https://example.com/blog")

    assert_equal "The quick brown fox jumps over the lazy do", text.display_title # first 42 chars
    assert_equal "What is the refund policy?", qna.display_title
    assert_equal "https://example.com/blog", web.display_title # no markdown H1 -> url
  end

  test "search scope matches on the type's natural columns" do
    matching = @account.qnas.create!(question: "How do refunds work?", answer: "Within 30 days")
    other    = @account.qnas.create!(question: "What are your hours?",  answer: "9 to 5")

    results = @account.qnas.search("refund")

    assert_includes results, matching
    assert_not_includes results, other
  end

  test "search with blank query returns all" do
    @account.texts.create!(data: "alpha")
    @account.texts.create!(data: "beta")
    assert_equal 2, @account.texts.search(nil).count
    assert_equal 2, @account.texts.search("").count
  end
end
```

- [ ] **Step 2: Run it red** — `bin/rails test test/models/sourceable_test.rb`
  Expected: FAIL — `undefined method 'source_type_label'`.

- [ ] **Step 3: Create the concern** — `app/models/concerns/sourceable.rb`:

```ruby
# Uniform interface every knowledge-base source (Document, Text, Qna, Website)
# exposes so the unified Sources list can render any of them with one partial.
# Including models MUST define #source_subtitle and a `search` scope; they MAY
# override #display_title. Requires Indexable (index_status) to be included too.
module Sourceable
  extend ActiveSupport::Concern

  # Human label + url-safe key, derived from the class name by default and
  # overridable per model (Qna -> "Q&A").
  def source_type_label
    model_name.human
  end

  def source_type_key
    model_name.element # "document", "text", "qna", "website"
  end

  # Best available one-line title. Override per model; this fallback covers the
  # common "title column is present" case and degrades to a blank string.
  def display_title
    title.presence || ""
  end

  # One-line contextual detail shown under the title. MUST be implemented by
  # each including model (file size, crawl progress, answer preview, word count).
  def source_subtitle
    raise NotImplementedError, "#{self.class} must implement #source_subtitle"
  end

  # A short human reason a source failed, or nil. Overridable per model.
  def failure_reason
    nil
  end
end
```

- [ ] **Step 4: Wire up `Document`** — edit `app/models/document.rb`: add `include Sourceable` under the existing includes, and add:

```ruby
  scope :search, ->(query) {
    query.present? ? where("title ILIKE ?", "%#{query}%") : all
  }

  def display_title
    title.presence || file.filename.to_s.presence || "Untitled document"
  end

  def source_subtitle
    return "" unless file.attached?
    "#{ActiveSupport::NumberHelper.number_to_human_size(file.byte_size)} · #{file.filename.extension.to_s.upcase.presence || 'FILE'}"
  end
```

- [ ] **Step 5: Wire up `Text`** — edit `app/models/text.rb`: add `include Sourceable`, and:

```ruby
  scope :search, ->(query) {
    query.present? ? where("data ILIKE :q OR title ILIKE :q", q: "%#{query}%") : all
  }

  def display_title
    title.presence || data.to_s.strip.first(42)
  end

  def source_subtitle
    "Pasted text · #{data.to_s.split.size} words"
  end
```

- [ ] **Step 6: Wire up `Qna`** — edit `app/models/qna.rb`: add `include Sourceable`, and:

```ruby
  scope :search, ->(query) {
    query.present? ? where("question ILIKE :q OR answer ILIKE :q", q: "%#{query}%") : all
  }

  def source_type_label
    "Q&A"
  end

  def display_title
    title.presence || question.to_s.strip.first(80)
  end

  def source_subtitle
    "A: #{answer.to_s.strip.first(60)}"
  end
```

Note: `model_name.element` for `Qna` yields `"qna"`, which is what the routes/params use — leave `source_type_key` as the default.

- [ ] **Step 7: Wire up `Website`** — edit `app/models/website.rb`: add `include Sourceable`. It already defines `#title` (computed from the markdown H1). Add:

```ruby
  scope :search, ->(query) {
    query.present? ? where("url ILIKE :q OR title ILIKE :q OR data ILIKE :q", q: "%#{query}%") : all
  }

  def display_title
    title.presence || url
  end

  def source_subtitle
    return failure_reason if failed? && failure_reason.present?
    url
  end
```

> **Search note (from the spec):** `Website#title` is *computed* from `data`, so the `title` **column** may be blank/stale — but the `data` term in the scope covers the same content, so search results stay correct. Do not "fix" this by assuming the column mirrors the displayed title.

- [ ] **Step 8: Run it green** — `bin/rails test test/models/sourceable_test.rb` → PASS. Then run the full model suite to catch regressions: `bin/rails test test/models/`.

- [ ] **Step 9: Commit**

```bash
git add app/models/concerns/sourceable.rb app/models/document.rb app/models/text.rb app/models/qna.rb app/models/website.rb test/models/sourceable_test.rb
git commit -m "feat: add Sourceable concern with uniform row interface and search"
```

---

### Task 3: `SourceRow` — the unified collection builder

A PORO that wraps a source record with its chunk count and builds the filtered/sorted/paginated page. Single-type views run one scoped query; the "All" view merges the four in memory (bounded to hundreds by design — see spec §6.3).

Reference: `model-patterns` (PORO/value object is justified here — it is query orchestration, not persisted domain logic).

**Files:**
- Create: `app/models/source_row.rb`
- Test: `test/models/source_row_test.rb` (create)

- [ ] **Step 1: Write the failing test** — `test/models/source_row_test.rb`:

```ruby
require "test_helper"

class SourceRowTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "row@example.com", password: "testpassword123")
    @account = Account.create!(name: "ROW Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account

    @text = @account.texts.create!(data: "alpha content")
    @qna  = @account.qnas.create!(question: "beta question", answer: "answer")
    @web  = @account.websites.create!(url: "https://example.com")
    @web.mark_indexing_failed!
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "all view merges every type" do
    rows = SourceRow.for_account(@account, type: "all")
    assert_equal 3, rows.size
    assert_equal %w[qna text website].sort, rows.map(&:source_type_key).sort
  end

  test "type filter returns only that type" do
    rows = SourceRow.for_account(@account, type: "text")
    assert_equal [ @text.id ], rows.map(&:id)
  end

  test "status filter returns only matching status" do
    rows = SourceRow.for_account(@account, type: "all", status: "failed")
    assert_equal [ @web.id ], rows.map(&:id)
  end

  test "query filters by search" do
    rows = SourceRow.for_account(@account, type: "all", query: "beta")
    assert_equal [ @qna.id ], rows.map(&:id)
  end

  test "rows carry a chunk count without N+1" do
    Chunk.define_method(:generate_embedding) { }
    @account.chunks.create!(chunkable: @text, content: "c1")
    @account.chunks.create!(chunkable: @text, content: "c2")

    row = SourceRow.for_account(@account, type: "text").first
    assert_equal 2, row.chunks_count
  ensure
    Chunk.remove_method(:generate_embedding) if Chunk.instance_methods(false).include?(:generate_embedding)
  end

  test "limit and offset paginate" do
    5.times { |i| @account.texts.create!(data: "extra #{i}") }
    page1 = SourceRow.for_account(@account, type: "text", limit: 3, offset: 0)
    page2 = SourceRow.for_account(@account, type: "text", limit: 3, offset: 3)
    assert_equal 3, page1.size
    assert_equal 3, page2.size
    assert_empty (page1.map(&:id) & page2.map(&:id))
  end

  test "total_for counts all matches ignoring pagination" do
    5.times { |i| @account.texts.create!(data: "extra #{i}") }
    assert_equal 6, SourceRow.total_for(@account, type: "text")
  end

  test "counts_for returns totals by type and status" do
    counts = SourceRow.counts_for(@account)
    assert_equal 3, counts[:total]
    assert_equal 1, counts[:by_type]["text"]
    assert_equal 1, counts[:by_type]["qna"]
    assert_equal 1, counts[:by_type]["website"]
    assert_equal 0, counts[:by_type]["document"]
    assert_equal 1, counts[:by_status]["failed"]
  end
end
```

- [ ] **Step 2: Run it red** — `bin/rails test test/models/source_row_test.rb`
  Expected: FAIL — `uninitialized constant SourceRow`.

- [ ] **Step 3: Implement** — `app/models/source_row.rb`:

```ruby
# Wraps a source record + its chunk count for the unified Sources list, and
# builds the filtered/sorted/paginated page across the four source types.
# Single-type views run one scoped query; the "all" view merges in memory,
# which is fine at this product's hundreds-scale (see spec §6.3).
class SourceRow
  TYPES  = %w[document text qna website].freeze
  SORTS  = %w[recent title status chunks].freeze
  STATUSES = %w[indexed pending failed].freeze

  attr_reader :record, :chunks_count

  def initialize(record, chunks_count:)
    @record = record
    @chunks_count = chunks_count
  end

  # delegate the interface the view needs
  def id            = record.id
  def to_model      = record
  def source_type_key   = record.source_type_key
  def source_type_label = record.source_type_label
  def display_title = record.display_title
  def source_subtitle = record.source_subtitle
  def index_status  = record.index_status
  def created_at    = record.created_at

  class << self
    def for_account(account, type: "all", status: "all", query: nil, sort: "recent", limit: 50, offset: 0)
      rows = build_rows(account, type:, status:, query:)
      rows = sort_rows(rows, sort)
      rows[offset, limit] || []
    end

    def total_for(account, type: "all", status: "all", query: nil)
      types(type).sum { |t| relation(account, t, status:, query:).count }
    end

    def counts_for(account)
      by_type = TYPES.index_with { |t| account.public_send(t.pluralize).count }
      by_status = STATUSES.index_with do |s|
        TYPES.sum { |t| account.public_send(t.pluralize).where(index_status: s).count }
      end
      { total: by_type.values.sum, by_type:, by_status: }
    end

    private

    def types(type)
      type == "all" ? TYPES : Array(type).select { |t| TYPES.include?(t) }
    end

    def relation(account, type, status:, query:)
      rel = account.public_send(type.pluralize)
      rel = rel.where(index_status: status) if STATUSES.include?(status)
      rel = rel.search(query) if query.present?
      rel
    end

    # Load matching records for every requested type, then attach chunk counts
    # in one grouped query per type (no N+1).
    def build_rows(account, type:, status:, query:)
      types(type).flat_map do |t|
        records = relation(account, t, status:, query:).to_a
        counts  = chunk_counts(account, records.first&.class&.name, records.map(&:id))
        records.map { |r| new(r, chunks_count: counts.fetch(r.id, 0)) }
      end
    end

    def chunk_counts(account, chunkable_type, ids)
      return {} if chunkable_type.nil? || ids.empty?
      account.chunks
        .where(chunkable_type:, chunkable_id: ids)
        .group(:chunkable_id)
        .count
    end

    def sort_rows(rows, sort)
      case sort
      when "title"  then rows.sort_by { |r| r.display_title.to_s.downcase }
      when "status" then rows.sort_by { |r| r.index_status.to_s }
      when "chunks" then rows.sort_by { |r| -r.chunks_count }
      else               rows.sort_by { |r| r.created_at }.reverse # recent
      end
    end
  end
end
```

- [ ] **Step 4: Run it green** — `bin/rails test test/models/source_row_test.rb` → PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/source_row.rb test/models/source_row_test.rb
git commit -m "feat: add SourceRow to build the unified sources collection"
```

---

## Phase 2 — Unified index UI (server-rendered)

### Task 4: `SourcesController#index` reads filter/search/sort/page params

**Files:**
- Modify: `app/controllers/sources_controller.rb`
- Test: `test/controllers/sources_controller_test.rb` (create)

- [ ] **Step 1: Write the failing test** — `test/controllers/sources_controller_test.rb`:

```ruby
require "test_helper"

class SourcesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(email: "sc@example.com", password: "testpassword123")
    @account = Account.create!(name: "SC Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    post login_url, params: { email: @user.email, password: "testpassword123" }

    @text = @account.texts.create!(data: "findable alpha text")
    @qna  = @account.qnas.create!(question: "hidden beta", answer: "a")
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "index renders all sources by default" do
    get sources_url
    assert_response :success
    assert_select "[data-source-id='#{@text.id}']"
    assert_select "[data-source-id='#{@qna.id}']"
  end

  test "index filters by type" do
    get sources_url(type: "text")
    assert_response :success
    assert_select "[data-source-id='#{@text.id}']"
    assert_select "[data-source-id='#{@qna.id}']", false
  end

  test "index filters by search query" do
    get sources_url(q: "alpha")
    assert_response :success
    assert_select "[data-source-id='#{@text.id}']"
    assert_select "[data-source-id='#{@qna.id}']", false
  end

  test "index ignores an unknown type and shows all" do
    get sources_url(type: "bogus")
    assert_response :success
  end
end
```

- [ ] **Step 2: Run it red** — `bin/rails test test/controllers/sources_controller_test.rb`
  Expected: FAIL (missing `data-source-id`, since the current view lists only documents). It will fail on the assert_select assertions.

- [ ] **Step 3: Implement the controller** — replace `app/controllers/sources_controller.rb`:

```ruby
# frozen_string_literal: true

class SourcesController < ApplicationController
  PAGE_SIZE = 50

  def index
    @type   = normalize(params[:type], SourceRow::TYPES, default: "all")
    @status = normalize(params[:status], SourceRow::STATUSES, default: "all")
    @sort   = normalize(params[:sort], SourceRow::SORTS, default: "recent")
    @query  = params[:q].presence
    @page   = [ params[:page].to_i, 1 ].max
    offset  = (@page - 1) * PAGE_SIZE

    @counts = SourceRow.counts_for(Current.account)
    @total  = SourceRow.total_for(Current.account, type: @type, status: @status, query: @query)
    @rows   = SourceRow.for_account(
      Current.account,
      type: @type, status: @status, query: @query, sort: @sort,
      limit: PAGE_SIZE, offset:
    )
    @has_more = offset + @rows.size < @total

    respond_to do |format|
      format.html
      format.turbo_stream # Load more (Task 12)
    end
  end

  private
    def normalize(value, allowed, default:)
      allowed.include?(value) ? value : default
    end
end
```

- [ ] **Step 4:** The view does not exist in its new form yet; the assertions need `data-source-id`. The row partial is built in Task 5. **Do not run green yet** — proceed to Task 5, which completes the view, then return here.

- [ ] **Step 5: Commit** (controller only)

```bash
git add app/controllers/sources_controller.rb test/controllers/sources_controller_test.rb
git commit -m "feat: unified SourcesController#index with type/status/search/sort/page params"
```

---

### Task 5: The unified index views (sidebar, toolbar, row, empty states)

Reference: `turbo-patterns`. Match existing `n-*` Tailwind classes seen in `app/views/sources/*`.

**Files:**
- Modify: `app/views/sources/index.html.erb`
- Create: `app/views/sources/_sidebar.html.erb`, `_counts.html.erb`, `_toolbar.html.erb`, `_add_menu.html.erb`, `_source.html.erb`, `_rows.html.erb`
- Test: reuse `test/controllers/sources_controller_test.rb` from Task 4.

> **Caveat:** the row partial references `source_retry_path`, whose route helper isn't created until Task 8. This is fine for Task 5's controller tests (their records are `pending`, so `failed?` is false and the helper is never called), but do **not** manually view a *failed* source until Task 8 is done, or the view will raise `NoMethodError`.

- [ ] **Step 1:** Create `app/views/sources/_source.html.erb` (the type-agnostic row):

```erb
<%# locals: row (SourceRow) %>
<div id="<%= dom_id(row.to_model, :source_row) %>"
     data-source-id="<%= row.id %>"
     class="grid grid-cols-[24px_1fr_auto] md:grid-cols-[24px_1fr_110px_120px_70px_110px_90px] gap-3 items-center px-2 py-3 border-b n-main-border">
  <span class="text-xl leading-none"><%= source_type_icon(row.source_type_key) %></span>

  <div class="min-w-0">
    <%= link_to source_show_path(row.to_model), class: "font-medium truncate block n-main-hover" do %>
      <%= row.display_title %>
    <% end %>
    <p class="text-xs text-neutral-500 dark:text-neutral-400 truncate"><%= row.source_subtitle %></p>
  </div>

  <span class="hidden md:inline text-xs px-2 py-0.5 rounded bg-neutral-100 dark:bg-neutral-800 text-center"><%= row.source_type_label %></span>

  <span class="hidden md:block"><%= render "sources/status", row: row %></span>

  <span class="hidden md:block text-sm text-neutral-600 dark:text-neutral-300"><%= row.chunks_count.zero? ? "—" : row.chunks_count %></span>

  <span class="hidden md:block text-xs text-neutral-400"><%= time_ago_in_words(row.created_at) %> ago</span>

  <div class="flex gap-3 justify-end text-neutral-500">
    <% if row.to_model.failed? %>
      <%= button_to source_retry_path(row.to_model), method: :post, class: "text-amber-600 font-medium text-sm", form: { data: { turbo_confirm: false } } do %>↻<% end %>
    <% end %>
    <%= link_to source_show_path(row.to_model), title: "Show", class: "n-btn-icon n-main-hover" do %>
      <%= inline_svg "svg/eye.svg", class: "w-5 h-5" %>
    <% end %>
    <%= link_to source_show_path(row.to_model), title: "Delete", data: { turbo_method: :delete, turbo_confirm: "Are you sure?" }, class: "n-btn-icon n-main-hover-danger text-red-600 dark:text-red-300" do %>
      <%= inline_svg "svg/trash-bin.svg", class: "w-5 h-5" %>
    <% end %>
  </div>
</div>
```

- [ ] **Step 2:** Create `app/views/sources/_status.html.erb` (status chip):

```erb
<%# locals: row %>
<% klass, label = source_status_display(row.to_model) %>
<span class="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full <%= klass %>">
  <span class="w-1.5 h-1.5 rounded-full bg-current"></span><%= label %>
</span>
```

- [ ] **Step 3:** Add view helpers — create `app/helpers/sources_helper.rb`:

```ruby
module SourcesHelper
  SOURCE_ICONS = { "document" => "📄", "text" => "📝", "qna" => "❓", "website" => "🌐" }.freeze

  def source_type_icon(key)
    SOURCE_ICONS.fetch(key, "📄")
  end

  # Returns [css_classes, label] for a source's status chip.
  def source_status_display(record)
    if record.indexed?
      [ "bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-300", "Indexed" ]
    elsif record.failed?
      [ "bg-red-100 text-red-800 dark:bg-red-900/40 dark:text-red-300", "Failed" ]
    else
      label = record.is_a?(Website) ? "Crawling…" : "Processing…"
      [ "bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300", label ]
    end
  end

  # Polymorphic path helpers so one partial serves all four types.
  def source_show_path(record)   = polymorphic_path([ :sources, record ])
  def source_retry_path(record)  = send("retry_sources_#{record.model_name.element}_path", record)
end
```

- [ ] **Step 4:** Create `app/views/sources/_counts.html.erb` (id'd badges, broadcast-replaceable):

```erb
<%# locals: counts %>
<span id="sources_counts" class="contents">
  <span data-count="all"><%= counts[:total] %></span>
  <% SourceRow::TYPES.each do |t| %>
    <span data-count="type-<%= t %>"><%= counts[:by_type][t] %></span>
  <% end %>
  <span data-count="status-failed"><%= counts[:by_status]["failed"] %></span>
  <span data-count="status-pending"><%= counts[:by_status]["pending"] %></span>
</span>
```

- [ ] **Step 5:** Create `app/views/sources/_sidebar.html.erb`:

```erb
<%# locals: type, status, counts %>
<nav class="w-full md:w-44 shrink-0 md:border-r n-main-border md:pr-3 text-sm" aria-label="Source filters">
  <% render "sources/counts", counts: counts %>
  <%= link_to sources_path, class: "flex justify-between items-center px-2 py-1.5 rounded #{'bg-neutral-100 dark:bg-neutral-800 font-semibold' if type == 'all' && status == 'all'}" do %>
    <span>All</span><span class="text-neutral-400"><%= counts[:total] %></span>
  <% end %>

  <p class="text-[11px] uppercase tracking-wide text-neutral-400 mt-3 mb-1 px-2">By type</p>
  <% SourceRow::TYPES.each do |t| %>
    <%= link_to sources_path(type: t), class: "flex justify-between items-center px-2 py-1.5 rounded #{'bg-neutral-100 dark:bg-neutral-800 font-semibold' if type == t && status == 'all'}" do %>
      <span><%= source_type_icon(t) %> <%= t == "qna" ? "Q&As" : t.pluralize.capitalize %></span>
      <span class="text-neutral-400"><%= counts[:by_type][t] %></span>
    <% end %>
  <% end %>

  <% if counts[:by_status]["failed"].positive? || counts[:by_status]["pending"].positive? %>
    <p class="text-[11px] uppercase tracking-wide text-neutral-400 mt-3 mb-1 px-2">Needs attention</p>
    <% if counts[:by_status]["failed"].positive? %>
      <%= link_to sources_path(status: "failed"), class: "flex justify-between items-center px-2 py-1.5 rounded #{'bg-neutral-100 dark:bg-neutral-800 font-semibold' if status == 'failed'}" do %>
        <span>⚠️ Failed</span><span class="text-neutral-400"><%= counts[:by_status]["failed"] %></span>
      <% end %>
    <% end %>
    <% if counts[:by_status]["pending"].positive? %>
      <%= link_to sources_path(status: "pending"), class: "flex justify-between items-center px-2 py-1.5 rounded #{'bg-neutral-100 dark:bg-neutral-800 font-semibold' if status == 'pending'}" do %>
        <span>⏳ Processing</span><span class="text-neutral-400"><%= counts[:by_status]["pending"] %></span>
      <% end %>
    <% end %>
  <% end %>
</nav>
```

- [ ] **Step 6:** Create `app/views/sources/_add_menu.html.erb` (native `<details>` chooser — no JS needed; do **not** add a `data-controller`, there is no `reveal`/menu Stimulus controller and `<details>` handles the toggle on its own):

```erb
<details class="relative">
  <summary class="n-btn-primary cursor-pointer list-none">+ Add source</summary>
  <div class="absolute right-0 z-20 mt-1 w-64 rounded-lg border n-main-border n-main-bg shadow-lg">
    <%= link_to new_sources_document_path, class: "flex gap-2 px-3 py-2 n-main-hover" do %>📄 Upload documents<% end %>
    <%= link_to new_sources_website_path,  class: "flex gap-2 px-3 py-2 n-main-hover" do %>🌐 Add website<% end %>
    <%= link_to new_sources_text_path,     class: "flex gap-2 px-3 py-2 n-main-hover" do %>📝 Paste text<% end %>
    <%= link_to new_sources_qna_path,      class: "flex gap-2 px-3 py-2 n-main-hover" do %>❓ Add Q&A<% end %>
  </div>
</details>
```

- [ ] **Step 7:** Create `app/views/sources/_toolbar.html.erb`:

```erb
<%# locals: type, status, sort, query %>
<div class="flex flex-wrap gap-3 items-center mb-4">
  <%= form_with url: sources_path, method: :get, class: "flex-1 min-w-[180px]" do |f| %>
    <%= f.hidden_field :type, value: type %>
    <%= f.hidden_field :status, value: status %>
    <%= f.search_field :q, value: query, placeholder: "Search sources…", class: "w-full n-input" %>
  <% end %>
  <%# No Stimulus controller here — the inline onchange submits the form. %>
  <%= form_with url: sources_path, method: :get do |f| %>
    <%= f.hidden_field :type, value: type %>
    <%= f.hidden_field :status, value: status %>
    <%= f.hidden_field :q, value: query %>
    <%= f.select :sort,
        options_for_select([["Recently added", "recent"], ["Title", "title"], ["Status", "status"], ["Chunk count", "chunks"]], sort),
        {}, class: "n-input", onchange: "this.form.requestSubmit()" %>
  <% end %>
  <%= render "sources/add_menu" %>
</div>
```

> If the project has no `n-input` class, use the class already used by inputs in `app/views/sources/*/_form.html.erb`. Grep first: `grep -rn "class=" app/views/sources/texts/_form.html.erb`.

- [ ] **Step 8:** Create `app/views/sources/_rows.html.erb` (list body, reused by HTML + turbo_stream):

```erb
<%# locals: rows, has_more, page, type, status, sort, query %>
<% if rows.empty? %>
  <%= render "sources/empty", type: type, status: status, query: query %>
<% else %>
  <% rows.each do |row| %>
    <%= render "sources/source", row: row %>
  <% end %>
  <% if has_more %>
    <div id="sources_load_more" class="py-4 text-center">
      <%= link_to "Load more",
            sources_path(type: type, status: status, sort: sort, q: query, page: page + 1, format: :turbo_stream),
            data: { turbo_stream: true }, class: "n-btn-secondary" %>
    </div>
  <% end %>
<% end %>
```

- [ ] **Step 9:** Create `app/views/sources/_empty.html.erb`:

```erb
<%# locals: type, status, query %>
<% if query.present? %>
  <div class="py-16 text-center text-neutral-500">No sources match “<%= query %>”.</div>
<% elsif status == "failed" %>
  <div class="py-16 text-center text-neutral-500">Nothing failed — all good ✅</div>
<% elsif status == "pending" %>
  <div class="py-16 text-center text-neutral-500">Nothing is processing right now.</div>
<% elsif type == "all" %>
  <div class="py-16 text-center space-y-3">
    <div class="text-3xl">🗂️</div>
    <h3 class="n-card-title">Add your first source</h3>
    <p class="text-neutral-500">Drop files anywhere here, or use “Add source”.</p>
  </div>
<% else %>
  <div class="py-16 text-center space-y-3">
    <div class="text-3xl"><%= source_type_icon(type) %></div>
    <h3 class="n-card-title">No <%= type == "qna" ? "Q&As" : type.pluralize %> yet</h3>
    <%= link_to "Add #{type == 'qna' ? 'Q&A' : type}", new_polymorphic_path([:sources, type.to_sym]), class: "n-btn-primary inline-block" %>
  </div>
<% end %>
```

- [ ] **Step 10:** Replace `app/views/sources/index.html.erb`:

```erb
<div class="n-title-container flex justify-between items-center">
  <h2 class="n-main-title">Sources</h2>
</div>

<div class="flex flex-col md:flex-row gap-4 mt-2">
  <%= render "sources/sidebar", type: @type, status: @status, counts: @counts %>

  <div class="flex-1 min-w-0">
    <%= render "sources/toolbar", type: @type, status: @status, sort: @sort, query: @query %>
    <div id="sources_list" class="rounded-lg border n-main-border">
      <%= render "sources/rows", rows: @rows, has_more: @has_more, page: @page,
            type: @type, status: @status, sort: @sort, query: @query %>
    </div>
  </div>
</div>
```

- [ ] **Step 11: Run green** — `bin/rails test test/controllers/sources_controller_test.rb`
  Expected: PASS. Fix helper/class-name mismatches if any assertion fails (most likely the `n-input` class — grep the real one).

- [ ] **Step 12: Verify manually** — `bin/dev`, log in, visit `/sources`. Confirm sidebar counts, filtering by clicking type links, search, and sort all work. Reference the run skill if needed.

- [ ] **Step 13: Commit**

```bash
git add app/views/sources/ app/helpers/sources_helper.rb
git commit -m "feat: unified Sources index with sidebar, toolbar, rows, empty states"
```

---

### Task 6: Redirect legacy per-type index pages to the unified view

The four `Sources::*Controller#index` actions and their `index.html.erb` list markup are now redundant. Redirect them so old bookmarks/links keep working; keep `new/create/show/edit/update/destroy`.

**Files:**
- Modify: `app/controllers/sources/documents_controller.rb`, `texts_controller.rb`, `qnas_controller.rb`, `websites_controller.rb`
- Delete: the list markup in `app/views/sources/{documents,texts,qnas,websites}/index.html.erb`
- Test: add to `test/controllers/sources_controller_test.rb`

- [ ] **Step 1: Write the failing test** — append:

```ruby
test "legacy per-type index redirects to unified view with type filter" do
  get sources_documents_url
  assert_redirected_to sources_url(type: "document")

  get sources_qnas_url
  assert_redirected_to sources_url(type: "qna")
end
```

- [ ] **Step 2: Run it red** — `bin/rails test test/controllers/sources_controller_test.rb` → the new test FAILS (renders 200 instead of redirect).

- [ ] **Step 3: Implement** — in each controller replace the `index` body. Example for documents:

```ruby
    def index
      redirect_to sources_path(type: "document")
    end
```

Use `type: "text"`, `type: "qna"`, `type: "website"` in the others. Then delete each `app/views/sources/<type>/index.html.erb` file (the redirect renders nothing).

- [ ] **Step 4: Run it green** — `bin/rails test test/controllers/sources_controller_test.rb` → PASS. Run `bin/rails test test/controllers/` to confirm no regressions.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/sources/ app/views/sources/
git commit -m "refactor: redirect legacy per-type source indexes to unified view"
```

---

## Phase 3 — Adding sources

### Task 7: Whole-list drag-and-drop upload

Wrap the list in a `dropzone` container so files dropped anywhere upload as documents. The existing `dropzone_controller.js` posts `document[title]` + `document[file]` to its `url-value` via XHR and renders its own progress list — reuse it unchanged.

Reference: `stimulus-patterns`.

**Files:**
- Modify: `app/views/sources/index.html.erb`
- Test: `test/system/sources_dropzone_test.rb` (create)

- [ ] **Step 1: Write the failing system test** — `test/system/sources_dropzone_test.rb`:

```ruby
require "application_system_test_case"

class SourcesDropzoneTest < ApplicationSystemTestCase
  def setup
    @user = User.create!(email: "dz@example.com", password: "testpassword123")
    @account = Account.create!(name: "DZ Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    sign_in_as(@user) # see note in Step 2
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "the sources list exposes a dropzone drop target" do
    visit sources_path
    assert_selector "[data-controller~='dropzone'] [data-dropzone-target='input']", visible: :all
  end
end
```

> **Note:** check how `test/system/chat_waiting_ux_test.rb` logs a user in and mirror it (there may be a `sign_in_as` helper in `test/application_system_test_case.rb`; if not, drive the login form with Capybara). Do not invent a helper that doesn't exist — read the file first.

- [ ] **Step 2: Run it red** — `bin/rails test:system TEST=test/system/sources_dropzone_test.rb`
  Expected: FAIL — no dropzone on the list.

- [ ] **Step 3: Make click-to-browse opt-out in the dropzone controller.** The existing `dropzone_controller.js` binds a `click` listener on `containerTarget` that opens the OS file picker (`this.inputTarget.click()`, line ~34). If the container wraps the whole list, **every** click in the list — a title link, the view/delete/retry buttons, empty space — pops the file chooser, making the list unusable. Add a `clickToBrowse` value (default `true`, preserving all existing uploaders) and guard the binding.

  In `app/javascript/controllers/dropzone_controller.js`, add to `static values`:

```js
    clickToBrowse: { type: Boolean, default: true },
```

  Then wrap the two click-related bindings in `_bindEvents()` (the `containerTarget` "click" listener and the `inputTarget` "change" listener stays; only the container click needs gating):

```js
    // Click to browse — opt-out so a full-list drop zone doesn't hijack row clicks
    if (this.clickToBrowseValue) {
      this.containerTarget.addEventListener("click", () => this.inputTarget.click());
    }
    this.inputTarget.addEventListener("change", (e) => this._handleFileSelect(e));
```

- [ ] **Step 4: Wrap the list region for drag-drop.** In `app/views/sources/index.html.erb`, replace the `<div class="flex-1 min-w-0">…</div>` block with the following. Note `data-dropzone-click-to-browse-value="false"` (whole-list drop, no click hijack) and the **explicit, Stimulus-prefixed** `data-dropzone-url-value="<%= sources_documents_path %>"`:

```erb
  <div class="flex-1 min-w-0"
       data-controller="dropzone"
       data-dropzone-url-value="<%= sources_documents_path %>"
       data-dropzone-max-file-size-value="50"
       data-dropzone-click-to-browse-value="false"
       data-dropzone-accepted-files-value="application/pdf,application/vnd.openxmlformats-officedocument.wordprocessingml.document,text/plain,image/png,image/jpeg">
    <%= render "sources/toolbar", type: @type, status: @status, sort: @sort, query: @query %>

    <div data-dropzone-target="container" class="relative rounded-lg border-2 border-dashed n-main-border transition data-[active=true]:border-blue-500">
      <input type="file" multiple class="hidden" data-dropzone-target="input"
             accept="application/pdf,application/vnd.openxmlformats-officedocument.wordprocessingml.document,text/plain,image/png,image/jpeg">
      <div id="sources_list">
        <%= render "sources/rows", rows: @rows, has_more: @has_more, page: @page,
              type: @type, status: @status, sort: @sort, query: @query %>
      </div>
    </div>
    <ul data-dropzone-target="list" class="mt-3 space-y-1 hidden"></ul>
  </div>
```

> **Why the explicit `data-dropzone-url-value`:** the controller's `urlValue` defaults to `""`, and it XHR-POSTs to that URL. The existing Documents uploader lives *on* `/sources/documents`, so an empty value happened to POST to the current page (the create route) and worked by accident. On the new `/sources` page the current URL is `/sources`, which has **no** POST route — so you MUST set `data-dropzone-url-value` to `sources_documents_path` explicitly. Do not copy the old page's bare `data-url-value` attribute; use the prefixed value attribute shown above.

- [ ] **Step 5: Run it green** — `bin/rails test:system TEST=test/system/sources_dropzone_test.rb` → PASS.

- [ ] **Step 6: Manual check** — `bin/dev`, drag a PDF onto the list; confirm it uploads (a new document is created; it appears on the next load, and live once Task 9 lands) and that clicking a row title/button does **not** open the file picker.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/controllers/dropzone_controller.js app/views/sources/index.html.erb test/system/sources_dropzone_test.rb
git commit -m "feat: drag-and-drop document upload across the whole sources list"
```

---

## Phase 4 — Retry failed sources

### Task 8: `retry` member action on each source type

Reference: `crud-patterns` (a state change re-enqueues the indexing job; kept minimal as a member action per the spec).

**Files:**
- Modify: `config/routes.rb`; `app/controllers/sources/{documents,texts,qnas,websites}_controller.rb`
- Test: `test/controllers/sources/retry_test.rb` (create)

- [ ] **Step 1: Add routes** — in `config/routes.rb`, change the `namespace :sources` block:

```ruby
    namespace :sources do
      resources :documents do
        member { post :retry }
      end
      resources :qnas do
        member { post :retry }
      end
      resources :texts do
        member { post :retry }
      end
      resources :websites do
        member { post :retry }
      end
    end
```

- [ ] **Step 2: Write the failing test** — `test/controllers/sources/retry_test.rb`. This project's default queue adapter is `:solid_queue`, so `assert_enqueued_with` requires the ActiveJob test helper **and** swapping the adapter to `:test` in setup/teardown — exactly as `test/controllers/chat_sources_controller_test.rb` does. Without this the test raises `NoMethodError: undefined method 'assert_enqueued_with'`:

```ruby
require "test_helper"
require "active_job/test_helper"

class Sources::RetryTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def setup
    @user = User.create!(email: "rt@example.com", password: "testpassword123")
    @account = Account.create!(name: "RT Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    post login_url, params: { email: @user.email, password: "testpassword123" }
    @original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  def teardown
    ActiveJob::Base.queue_adapter = @original_adapter
    ActsAsTenant.current_tenant = nil
  end

  test "retry resets a failed text to pending and re-enqueues indexing" do
    text = @account.texts.create!(data: "# Hi")
    text.mark_indexing_failed!

    assert_enqueued_with(job: AddTextJob) do
      post retry_sources_text_url(text)
    end

    assert text.reload.pending?
    assert_redirected_to sources_url(type: "text")
  end

  test "retry re-crawls a failed website" do
    web = @account.websites.create!(url: "https://example.com/x")
    web.mark_indexing_failed!

    assert_enqueued_with(job: CrawlWebsiteUrlJob) do
      post retry_sources_website_url(web)
    end
    assert web.reload.pending?
  end
end
```

- [ ] **Step 3: Run it red** — `bin/rails test test/controllers/sources/retry_test.rb`
  Expected: FAIL — no `retry` action.

- [ ] **Step 4: Implement** — add a `retry` action to each controller. It resets status and re-enqueues the type's job. Documents:

```ruby
    def retry
      document = Current.account.documents.find(params[:id])
      document.mark_pending!
      AddDocumentJob.perform_later(document.id)
      redirect_to sources_path(type: "document"), notice: "Re-indexing document."
    end
```

Texts (`AddTextJob`, `type: "text"`), Qnas (`AddQnaJob`, `type: "qna"`), Websites (`CrawlWebsiteUrlJob`, `type: "website"`) — same shape with the right model/job/type.

- [ ] **Step 5: Run it green** — `bin/rails test test/controllers/sources/retry_test.rb` → PASS.

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/sources/ test/controllers/sources/retry_test.rb
git commit -m "feat: retry action to re-index failed sources"
```

The Retry button in the row partial (Task 5, Step 1) already points at `source_retry_path`; verify it renders for a failed source.

---

## Phase 5 — Live updates & pagination

### Task 9: Broadcast live status changes and count updates

Fire Turbo Stream broadcasts from `Sourceable` when a source's `index_status` changes, so open Sources pages update the row and the sidebar counts without a refresh. Broadcasts render without `Current`, so pass the account explicitly.

Reference: `turbo-patterns`, and the existing model-broadcast pattern in `app/models/message.rb`.

**Files:**
- Modify: `app/models/concerns/sourceable.rb`, `app/views/sources/index.html.erb`, `app/views/sources/_counts.html.erb`
- Test: `test/models/sourceable_broadcast_test.rb` (create)

- [ ] **Step 1: Write the failing test** — `test/models/sourceable_broadcast_test.rb`. Use Turbo's broadcast test helper exactly as `test/models/message_test.rb` does (`assert_broadcasts` with a `[record, "name"]` array does **not** work — Turbo publishes to a signed stream name, so it would count 0). Cover **both** the `indexed` path (`update!`, fires the commit callback) and the `failed` path (`update_columns`, which bypasses callbacks — this is the one that silently regresses):

```ruby
require "test_helper"
require "turbo/broadcastable/test_helper"

class SourceableBroadcastTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  def setup
    @user = User.create!(email: "bc@example.com", password: "testpassword123")
    @account = Account.create!(name: "BC Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "mark_indexed! broadcasts a row replace and a counts replace" do
    text = @account.texts.create!(data: "# Hi")

    streams = capture_turbo_stream_broadcasts([ @account, "sources" ]) do
      text.mark_indexed!
    end

    assert_equal 2, streams.size
  end

  test "mark_indexing_failed! also broadcasts (update_columns bypasses callbacks)" do
    text = @account.texts.create!(data: "# Hi")

    streams = capture_turbo_stream_broadcasts([ @account, "sources" ]) do
      text.mark_indexing_failed!
    end

    assert_equal 2, streams.size
  end
end
```

- [ ] **Step 2: Run it red** — `bin/rails test test/models/sourceable_broadcast_test.rb`
  Expected: FAIL — 0 broadcasts captured.

- [ ] **Step 3: Implement** — add to `app/models/concerns/sourceable.rb`. Two paths change `index_status`: `update!`-based transitions (`mark_indexed!`, `mark_pending!`, and Website's re-crawl `update!`) fire the commit callback; `mark_indexing_failed!` uses `update_columns`, which fires **no** callback — so override it here to broadcast explicitly. (Ensure `include Sourceable` comes **after** `include Indexable` in each model so this override's `super` resolves to `Indexable#mark_indexing_failed!`.)

```ruby
  included do
    after_update_commit :broadcast_source_status_change, if: :saved_change_to_index_status?
    after_destroy_commit :broadcast_source_removed
  end

  # Indexable#mark_indexing_failed! uses update_columns, which skips the
  # after_update_commit callback above — so broadcast the change explicitly.
  def mark_indexing_failed!
    super
    broadcast_source_status_change
  end

  def broadcast_source_status_change
    broadcast_replace_to [ account, "sources" ],
      target: ActionView::RecordIdentifier.dom_id(self, :source_row),
      partial: "sources/source",
      locals: { row: SourceRow.new(self, chunks_count: chunks.count) }
    broadcast_source_counts
  end

  def broadcast_source_removed
    broadcast_remove_to [ account, "sources" ],
      target: ActionView::RecordIdentifier.dom_id(self, :source_row)
    broadcast_source_counts
  end

  private

  def broadcast_source_counts
    broadcast_replace_to [ account, "sources" ],
      target: "sources_counts",
      partial: "sources/counts",
      locals: { counts: SourceRow.counts_for(account) }
  end
```

> `broadcast_replace_to` / `broadcast_remove_to` come from `Turbo::Broadcastable`, already used across the app (`message.rb`, `chat.rb`). The row partial's outer id is `dom_id(record, :source_row)` — matches Task 5. Because `mark_indexing_failed!`'s `update_columns` fires no commit callback, the explicit call here is the *only* broadcast on that path (no double-broadcast); `update!`-based transitions broadcast once via the callback.

- [ ] **Step 4: Subscribe the index page** — add near the top of `app/views/sources/index.html.erb`:

```erb
<%= turbo_stream_from Current.account, "sources" %>
```

The counts partial already wraps its badges in `#sources_counts`, so a replace targets it.

- [ ] **Step 5: Run it green** — `bin/rails test test/models/sourceable_broadcast_test.rb` → PASS.

- [ ] **Step 6: Manual check** — open `/sources` in two tabs; in a console run a source through `mark_indexed!` / `mark_indexing_failed!` and confirm the row status and sidebar counts update live in both tabs.

- [ ] **Step 7: Commit**

```bash
git add app/models/concerns/sourceable.rb app/views/sources/index.html.erb test/models/sourceable_broadcast_test.rb
git commit -m "feat: live source status and count updates via Turbo Streams"
```

> **Scope note (documented limitation):** brand-new rows created via drag-drop update the sidebar *counts* live, and their status updates live once present, but a freshly-created row is only guaranteed to appear on the viewer's next load/navigation. Live insertion of new rows into a filtered list is deliberately out of scope (see spec §6.6) to avoid inserting a mismatched row into a filtered view.

---

### Task 10: "Load more" pagination via Turbo Stream

**Files:**
- Create: `app/views/sources/index.turbo_stream.erb`
- Test: add to `test/controllers/sources_controller_test.rb`

- [ ] **Step 1: Write the failing test** — append:

```ruby
test "load more appends the next page via turbo_stream" do
  60.times { |i| @account.texts.create!(data: "bulk #{i}") }
  get sources_url(type: "text", page: 2, format: :turbo_stream)
  assert_response :success
  assert_match "turbo-stream", @response.body
  assert_match "sources_list", @response.body
end
```

- [ ] **Step 2: Run it red** — `bin/rails test test/controllers/sources_controller_test.rb` → FAIL (missing template).

- [ ] **Step 3: Implement** — `app/views/sources/index.turbo_stream.erb`:

```erb
<%= turbo_stream.remove "sources_load_more" %>
<%= turbo_stream.append "sources_list" do %>
  <% @rows.each do |row| %>
    <%= render "sources/source", row: row %>
  <% end %>
  <% if @has_more %>
    <div id="sources_load_more" class="py-4 text-center">
      <%= link_to "Load more",
            sources_path(type: @type, status: @status, sort: @sort, q: @query, page: @page + 1, format: :turbo_stream),
            data: { turbo_stream: true }, class: "n-btn-secondary" %>
    </div>
  <% end %>
<% end %>
```

- [ ] **Step 4: Run it green** — `bin/rails test test/controllers/sources_controller_test.rb` → PASS.

- [ ] **Step 5: Commit**

```bash
git add app/views/sources/index.turbo_stream.erb test/controllers/sources_controller_test.rb
git commit -m "feat: load-more pagination for the sources list"
```

---

## Phase 6 — Full verification

### Task 11: Run the full CI suite and fix fallout

- [ ] **Step 1:** `bundle exec rubocop -a` — auto-fix style; manually resolve anything left.
- [ ] **Step 2:** `bin/rails test` — full unit/integration suite green.
- [ ] **Step 3:** `bin/rails test:system` — system tests green (needs a browser driver; if unavailable in the environment, note it and run locally).
- [ ] **Step 4:** `bin/ci` — the full gate (rubocop + brakeman + tests). Fix any Brakeman warning introduced (the `ILIKE` scopes use bind parameters, so no SQL-injection warning is expected; verify).
- [ ] **Step 5:** Manual smoke test with `bin/dev`: create one source of each type, watch it index live, fail one and retry it, search/filter/sort, drop a file, and load more with 60+ sources.
- [ ] **Step 6: Commit** any fixes.

```bash
git add -A
git commit -m "chore: satisfy rubocop/brakeman and green the full suite for sources redesign"
```

---

## Definition of done

- `/sources` shows one unified, searchable, filterable, sortable list across all four types with a counts sidebar (including Failed/Processing).
- Per-source status is visible and updates live; failed sources show a reason and a working Retry.
- Files dropped anywhere on the list upload as documents.
- "Add source" chooser reaches every type's form.
- Empty states cover first-run, per-type, per-status, and no-search-results.
- Legacy per-type index URLs redirect into the unified view.
- No migration was needed; `bin/ci` is green.
