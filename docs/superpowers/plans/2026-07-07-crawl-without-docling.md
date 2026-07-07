# crawl_url! Without Docling Serve — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Docling Serve dependency in `Website#crawl_url!` with an in-process fetch (Faraday) + HTML→Markdown conversion (`html-to-markdown` gem), and remove all Docling references from the repo.

**Architecture:** `Website::Crawlable` is rewritten so `crawl_url!` fetches the page via Faraday, converts the body to Markdown with `HtmlToMarkdown.convert(html).content` (the gem returns a `ConversionResult` object, not a Hash), saves to `data`, and calls the existing `chunkify!`. Transient failures (network/timeout/5xx) raise so `CrawlWebsiteUrlJob` retries via `retry_on`; terminal failures (3xx/4xx) log and return nil. Logic stays in the concern as private methods ordered by invocation flow — no service objects.

**Tech Stack:** Ruby, Rails 8, Faraday, `html-to-markdown` (native Rust/Magnus + rb-sys gem; source-only, needs Rust + libclang-dev at Docker build time), Minitest, Solid Queue.

**Spec:** `docs/superpowers/specs/2026-07-07-crawl-without-docling-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `Gemfile` | Modify | Add `gem "html-to-markdown"` |
| `Gemfile.lock` | Regenerate | Lock the new gem |
| `app/models/website/crawlable.rb` | Rewrite | `crawl_url!` orchestrator + private `fetch_html`, `faraday_connection`, `convert_to_markdown` |
| `app/jobs/crawl_website_url_job.rb` | Modify | Add `retry_on` for transient Faraday errors |
| `app/controllers/api/v1/websites_controller.rb` | Modify | Fix `CrawlWebsiteUrlsJob` → `CrawlWebsiteUrlJob` typo |
| `test/models/website_test.rb` | Create | Tests for `crawl_url!` (success, 4xx, 5xx, timeout, blank url) |
| `test/jobs/crawl_website_url_job_test.rb` | Create | Test that the job calls `crawl_url!` |
| `.env`, `.env.example` | Modify | Remove Docling env var |
| `docker-compose.yml` | Modify | Remove Docling env passthrough |
| `install.sh`, `install.ps1` | Modify | Remove dead Docling install plumbing |
| `README.md` | Modify | Remove Docling section + env table row |
| `docs/ARCHITECTURE.md` | Modify | Remove Docling config entries |
| `Dockerfile` | Modify (conditional) | Add Rust toolchain only if the native gem doesn't ship prebuilt linux binaries |

---

## Task 1: Add the `html-to-markdown` gem

**Files:**
- Modify: `Gemfile` (after line 78, the `faraday` line, to keep the Nosia-dependency block alphabetical-ish)
- Modify (regenerated): `Gemfile.lock`

- [ ] **Step 1: Add the gem to the Gemfile**

Add after the `faraday` line (line 78):

```ruby
gem "html-to-markdown" # HTML to Markdown converter (native Rust/Magnus extension) [https://github.com/xberg-io/html-to-markdown]
```

- [ ] **Step 2: Install and lock the gem**

Run: `bundle install`
Expected: gem installs. If it tries to compile a Rust extension and fails locally, install a Rust toolchain (`rustup` / `cargo`) — the gem builds via Magnus. Note whether the lockfile pulled a prebuilt platform gem (`*-x86_64-linux` / `*-aarch64-linux`) or a source gem.

- [ ] **Step 3: Smoke-test the gem loads and converts**

Run:
```bash
bundle exec ruby -e 'require "html_to_markdown"; puts HtmlToMarkdown.convert("<h1>Title</h1><p>Body</p>").content'
```
Expected: prints Markdown containing `# Title` and `Body`. This locks the `.content` API the implementation depends on. Note: the gem returns a `HtmlToMarkdownRs::ConversionResult` object (with `.content`, `.metadata`, `.warnings` methods), **not** a Hash — do not use `[:content]`.

- [ ] **Step 4: Verify the production Docker image still builds (native-gem deployment check)**

The `html-to-markdown` gem is **source-only** on linux (no prebuilt platform gems), so the Docker build must compile its native extension. Compilation needs (a) a recent Rust toolchain and (b) `libclang` for rb-sys's bindgen. The `Dockerfile` build stage has `build-essential git pkg-config libffi-dev libyaml-dev` but neither.

Update the `Dockerfile` build stage: add `libclang-dev` to the apt install, and add a rustup-installed Rust toolchain (Debian's `cargo` is rustc 1.85, too old — a transitive dep needs rustc 1.88+):

```dockerfile
# Install packages need to build gems
RUN apt-get update -qq && \
    apt-get install -y build-essential git pkg-config libffi-dev libyaml-dev libclang-dev && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install Rust toolchain (Debian cargo is too old for html-to-markdown's deps)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"
```

Run: `docker build -t nosia-crawl-check .` (free disk first with `docker system prune -af --volumes` if the builder is near full).
Expected: build succeeds. Remove the test image afterwards (`docker rmi nosia-crawl-check`) to reclaim space.

- [ ] **Step 5: Commit**

```bash
git add Gemfile Gemfile.lock Dockerfile
git commit -m "feat: add html-to-markdown gem for in-process HTML conversion"
```

---

## Task 2: Rewrite `Website::Crawlable` (TDD)

This is the core change. Tests go through the public `crawl_url!` and stub the `faraday_connection` seam (no network, no WebMock dependency). One test → implement → pass → next test.

**Important test constraint:** `chunkify!` → `chunks.create!` triggers a `before_save :generate_embedding` (real `RubyLLM.embed`), which is not testable in this environment (it stack-overflows via httpx/association-scope recursion). The existing `Chunk::VectorizableTest` deliberately avoids triggering it. So the success test **stubs `chunkify!`** and asserts it was called, rather than running it for real and asserting `chunks.count > 0`. The 4xx/5xx/timeout/blank tests never reach `chunkify!`, so they're unaffected.

**Files:**
- Create: `test/models/website_test.rb`
- Rewrite: `app/models/website/crawlable.rb`

- [ ] **Step 1: Create the test file with a success test (RED)**

Create `test/models/website_test.rb`:

```ruby
require "test_helper"

class WebsiteTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "wt@example.com", password: "testpassword123")
    @account = Account.create!(name: "WT Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @website = @account.websites.create!(url: "https://example.com/page")
  end

  def stub_connection(status:, body: "")
    response = Struct.new(:status, :body).new(status, body)
    response.define_singleton_method(:success?) { status.between?(200, 299) }
    connection = Object.new
    yield(connection) if block_given?
    connection.define_singleton_method(:get) { |*_args| response }
    @website.define_singleton_method(:faraday_connection) { connection }
    response
  end

  test "crawl_url! converts and persists a fetched page, then chunkifies" do
    stub_connection(status: 200, body: "<h1>Title</h1><p>Body text</p>")
    chunkified = []
    @website.define_singleton_method(:chunkify!) { chunkified << true; nil }

    @website.crawl_url!

    assert_equal true, @website.reload.data.present?
    assert_includes @website.data, "# Title"
    assert_includes @website.data, "Body text"
    assert_equal [ true ], chunkified
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/models/website_test.rb`
Expected: FAIL — `crawl_url!` still returns early (Docling guard) or `faraday_connection` undefined; `data` stays nil.

- [ ] **Step 3: Rewrite `crawl_url!` with private helpers (GREEN)**

Replace the entire contents of `app/models/website/crawlable.rb` with:

```ruby
module Website::Crawlable
  extend ActiveSupport::Concern

  def crawl_url!
    return unless url.present?

    html = fetch_html
    return unless html

    self.data = convert_to_markdown(html)
    save!
    chunkify!
    self
  end

  private

  def fetch_html
    response = faraday_connection.get(self.url) do |request|
      request.headers["User-Agent"] = "Nosiabot/0.1"
    end

    return response.body if response.success?

    if (500..599).cover?(response.status)
      raise Faraday::ServerError, "upstream #{response.status} for #{self.url}"
    end

    Rails.logger.warn("crawl_url! terminal status=#{response.status} url=#{self.url}")
    nil
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
    Rails.logger.warn("crawl_url! transient #{error.class} url=#{self.url}")
    raise
  end

  def faraday_connection
    Faraday.new do |builder|
      builder.options.timeout = 10
      builder.options.open_timeout = 5
    end
  end

  def convert_to_markdown(html)
    HtmlToMarkdown.convert(html).content
  end
end
```

Note: this removes the `DOCLING_SERVE_BASE_URL` guard and all Docling HTTP code.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/models/website_test.rb`
Expected: PASS.

- [ ] **Step 5: Add a 4xx terminal test (RED)**

Append to `test/models/website_test.rb` (inside the class):

```ruby
  test "crawl_url! returns nil on terminal 4xx and creates no chunks" do
    stub_connection(status: 404, body: "")

    assert_nil @website.crawl_url!
    assert_nil @website.reload.data
    assert_equal 0, @website.chunks.count
  end
```

- [ ] **Step 6: Run the new test**

Run: `bin/rails test test/models/website_test.rb`
Expected: PASS immediately (the `fetch_html` branch already logs and returns nil for 4xx). If it fails, fix `fetch_html` so non-success, non-5xx returns nil.

- [ ] **Step 7: Add a 5xx transient test (RED)**

Append:

```ruby
  test "crawl_url! raises on 5xx so the job can retry" do
    stub_connection(status: 503, body: "")

    assert_raises(Faraday::ServerError) { @website.crawl_url! }
    assert_nil @website.reload.data
  end
```

- [ ] **Step 8: Run the new test**

Run: `bin/rails test test/models/website_test.rb`
Expected: PASS (the 5xx branch raises `Faraday::ServerError`).

- [ ] **Step 9: Add a timeout transient test (RED)**

Append:

```ruby
  test "crawl_url! re-raises network timeouts" do
    connection = Object.new
    connection.define_singleton_method(:get) { |*_args| raise Faraday::TimeoutError }
    @website.define_singleton_method(:faraday_connection) { connection }

    assert_raises(Faraday::TimeoutError) { @website.crawl_url! }
  end
```

- [ ] **Step 10: Run the new test**

Run: `bin/rails test test/models/website_test.rb`
Expected: PASS (the `rescue` re-raises `Faraday::TimeoutError`).

- [ ] **Step 11: Add a blank-url test (RED)**

Append:

```ruby
  test "crawl_url! returns nil when url is blank and never fetches" do
    @website.update!(url: nil)
    sentinel = Object.new
    sentinel.define_singleton_method(:get) { |*_args| raise "should not be called" }
    @website.define_singleton_method(:faraday_connection) { sentinel }

    assert_nil @website.crawl_url!
  end
```

- [ ] **Step 12: Run the new test**

Run: `bin/rails test test/models/website_test.rb`
Expected: PASS (the `return unless url.present?` guard short-circuits before `fetch_html`).

- [ ] **Step 13: Run rubocop on the changed files**

Run: `bundle exec rubocop app/models/website/crawlable.rb test/models/website_test.rb`
Expected: no offenses (fix any, then re-run).

- [ ] **Step 14: Commit**

```bash
git add app/models/website/crawlable.rb test/models/website_test.rb
git commit -m "feat: crawl_url! fetches and converts in-process without Docling"
```

---

## Task 3: Add `retry_on` to `CrawlWebsiteUrlJob`

The spec's failure model raises transient errors so Solid Queue retries. `ApplicationJob` has no `retry_on` by default, so the job must declare it.

**Files:**
- Modify: `app/jobs/crawl_website_url_job.rb`

- [ ] **Step 1: Add `retry_on` for the transient Faraday errors**

Replace `app/jobs/crawl_website_url_job.rb` with:

```ruby
class CrawlWebsiteUrlJob < ApplicationJob
  queue_as :background

  retry_on Faraday::TimeoutError,
           Faraday::ConnectionFailed,
           Faraday::ServerError,
           wait: 30.seconds,
           attempts: 5

  def perform(website_id)
    website = Website.find(website_id)
    website.crawl_url!
  end
end
```

- [ ] **Step 2: Verify the job loads**

Run: `bundle exec ruby -e 'require "faraday"; require_relative "app/jobs/crawl_website_url_job.rb"; puts CrawlWebsiteUrlJob'`
If environment loading is awkward, instead run: `bin/rails runner "puts CrawlWebsiteUrlJob.retry_on_present?"` — or simply rely on the job test below. Skip if the runner is hard to drive; the test in Task 4 covers it.

- [ ] **Step 3: Commit**

```bash
git add app/jobs/crawl_website_url_job.rb
git commit -m "feat: retry CrawlWebsiteUrlJob on transient fetch errors"
```

---

## Task 4: Test `CrawlWebsiteUrlJob` calls `crawl_url!`

**Files:**
- Create: `test/jobs/crawl_website_url_job_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/jobs/crawl_website_url_job_test.rb`:

```ruby
require "test_helper"

class CrawlWebsiteUrlJobTest < ActiveJob::TestCase
  test "perform finds the website and calls crawl_url!" do
    fake = Minitest::Mock.new
    fake.expect(:crawl_url!, true)

    Website.stub(:find, fake) do
      CrawlWebsiteUrlJob.perform_now(123)
    end

    assert_mock fake
  end
end
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `bin/rails test test/jobs/crawl_website_url_job_test.rb`
Expected: PASS. `Website.stub(:find, fake)` returns the mock, `perform_now` calls `crawl_url!` on it, and `assert_mock` verifies the expected call was made.

- [ ] **Step 3: Commit**

```bash
git add test/jobs/crawl_website_url_job_test.rb
git commit -m "test: CrawlWebsiteUrlJob calls crawl_url!"
```

---

## Task 5: Fix the `CrawlWebsiteUrlsJob` typo in the API controller

`Api::V1::WebsitesController#create` calls `CrawlWebsiteUrlsJob` (plural) — a class that does not exist.

**Files:**
- Modify: `app/controllers/api/v1/websites_controller.rb:10`

- [ ] **Step 1: Fix the typo**

In `app/controllers/api/v1/websites_controller.rb`, change line 10:

```ruby
# from
CrawlWebsiteUrlsJob.perform_later(website.id)
# to
CrawlWebsiteUrlJob.perform_later(website.id)
```

- [ ] **Step 2: Verify no plural reference remains**

Run: `grep -rn "CrawlWebsiteUrlsJob" app/`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add app/controllers/api/v1/websites_controller.rb
git commit -m "fix: Api::V1::WebsitesController enqueues the correct crawl job"
```

---

## Task 6: Remove Docling references from env, compose, and install files

All `DOCLING_SERVE_BASE_URL` and Docling plumbing is removed. The `install.sh` docling path is already dead code (`ADVANCED_DOCUMENTS_UNDERSTANDING` is never set from any CLI arg, so `USE_DOCLING` is always `false`), so removing it changes no real install behavior.

**Files:**
- Modify: `.env`, `.env.example`, `docker-compose.yml`, `install.sh`, `install.ps1`

- [ ] **Step 1: Remove from `.env` and `.env.example`**

In both `.env` and `.env.example`, remove the two-line block:
```
# Optional: Docling Serve Configuration
DOCLING_SERVE_BASE_URL=
```
(and the surrounding blank line if it leaves a double blank).

- [ ] **Step 2: Verify**

Run: `grep -ni docling .env .env.example`
Expected: no output.

- [ ] **Step 3: Remove from `docker-compose.yml`**

Remove the two lines (currently lines 52 and 110):
```
      - DOCLING_SERVE_BASE_URL=${DOCLING_SERVE_BASE_URL}
```

- [ ] **Step 4: Verify**

Run: `grep -ni docling docker-compose.yml`
Expected: no output.

- [ ] **Step 5: Remove Docling plumbing from `install.sh`**

In `install.sh`:
- `generate_docker_compose()`: drop the `use_docling="$2"` param line (line 143) and remove the `DOCLING_SERVE_BASE_URL` env line in the `web` and `solidq` heredocs (lines 196, 253). Delete the entire `# Add docling-serve service if enabled` block (lines 268-285) and the `# Add docling-data volume if enabled` block (lines 303-306). The function now takes no args.
- `setup_env()`: drop `local use_docling="$1"` (line 311); shift the remaining locals so the signature is `setup_env(system_ram, gpu_vram)`. Remove the `DOCLING_SERVE_BASE_URL=` block in the variable setup (lines 400-402) and the `# Optional: Docling Serve Configuration` / `DOCLING_SERVE_BASE_URL=${DOCLING_SERVE_BASE_URL}` lines in the `.env` heredoc (lines 455-456).
- `do_install()`: remove `PLATFORM=$(get_platform)` (line 532), the `USE_DOCLING`/`ADVANCED_DOCUMENTS_UNDERSTANDING` block (lines 537-541), and update the two calls to `generate_docker_compose "$PLATFORM" "$USE_DOCLING"` → `generate_docker_compose` and `setup_env "$USE_DOCLING" ...` → `setup_env "$DETECTED_SYSTEM_RAM_GB" "$DETECTED_GPU_VRAM_GB"` (lines 544, 547).
- If `get_platform` has no other callers, remove its definition too. Verify first:

Run: `grep -n "get_platform" install.sh`
If only the definition and the (now-removed) call site matched, delete the `get_platform()` function. If other callers exist, leave it.

- [ ] **Step 6: Verify `install.sh`**

Run: `bash -n install.sh && grep -ni docling install.sh`
Expected: `bash -n` prints nothing (syntax OK) and the grep prints nothing.

- [ ] **Step 7: Remove Docling plumbing from `install.ps1`**

Remove every line referencing Docling in `install.ps1`:
- the `$DOCLING_SERVE_BASE_URL = ""` declaration and its `# Docling configuration` comment (lines 374-375)
- the `DOCLING_SERVE_BASE_URL=` env passthroughs in the compose heredocs (lines 189, 246)
- the `# Optional: Docling Serve Configuration` / `DOCLING_SERVE_BASE_URL=${DOCLING_SERVE_BASE_URL}` lines in the `.env` heredoc (lines 425-426)

- [ ] **Step 8: Verify `install.ps1`**

Run: `grep -ni docling install.ps1`
Expected: no output.

- [ ] **Step 9: Commit**

```bash
git add .env .env.example docker-compose.yml install.sh install.ps1
git commit -m "chore: remove Docling Serve env and install plumbing"
```

---

## Task 7: Remove Docling references from docs

**Files:**
- Modify: `README.md`, `docs/ARCHITECTURE.md`

- [ ] **Step 1: Remove the Docling section from `README.md`**

Delete the `#### With Docling Document Processing` section (currently lines 211-232), including the `docker compose -f docker-compose-docling-serve-*.yml` examples and the `DOCLING_SERVE_BASE_URL=http://localhost:5001` example. Also remove the env-table row (line 282):
```
| `DOCLING_SERVE_BASE_URL` | Docling document processing service URL | empty | `http://localhost:5001` |
```
Also check the "Advanced Installation" TOC entry (README.md:70) and any anchor reference — if the Docling section was the only content under "Advanced Installation", remove that TOC line too; otherwise leave the TOC line and the remaining advanced-install content.

- [ ] **Step 2: Verify README**

Run: `grep -ni docling README.md`
Expected: no output.

- [ ] **Step 3: Remove Docling entries from `docs/ARCHITECTURE.md`**

Delete the advanced-parsing Docling block (currently lines 294-297):
```
- Advanced parsing: Docling serve integration (optional)
  - NVIDIA GPU: `docker-compose-docling-serve-nvidia.yml`
  - AMD GPU: `docker-compose-docling-serve-amd.yml`
  - CPU-only: `docker-compose-docling-serve-cpu.yml`
```
And the config entry (line 848):
```
- `DOCLING_SERVE_BASE_URL`: Advanced document parsing
```

- [ ] **Step 4: Verify ARCHITECTURE.md**

Run: `grep -ni docling docs/ARCHITECTURE.md`
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/ARCHITECTURE.md
git commit -m "docs: remove Docling Serve references"
```

---

## Task 8: Full verification

- [ ] **Step 1: Confirm no Docling references remain anywhere in the repo**

Run: `grep -rni docling --exclude-dir=.git --exclude-dir=log --exclude-dir=tmp .`
Expected: no output. (The standalone `docker-compose-docling-serve-*.yml` files do not exist in the repo, so nothing should match.)

- [ ] **Step 2: Run the full test suite**

Run: `bin/rails test`
Expected: all green, including the new `WebsiteTest` and `CrawlWebsiteUrlJobTest`.

- [ ] **Step 3: Run the full CI gate**

Run: `bin/ci`
Expected: rubocop, brakeman, and tests all pass. Fix anything that surfaces.

- [ ] **Step 4: Final commit (if any fixes were needed)**

If Step 1-3 required fixes, commit them:
```bash
git add -A
git commit -m "chore: verification fixes for crawl-without-docling"
```

---

## Notes for the implementer

- **Test isolation:** tests stub `faraday_connection` per-instance via `define_singleton_method`, so no global Faraday stubbing or WebMock is needed. No network calls occur in the suite.
- **`chunkify!` is untouched** — it already expects Markdown, which is what `convert_to_markdown` produces.
- **The native gem is the main deployment risk.** Task 1 Step 4 is mandatory: the production Docker image must build. The gem is source-only on linux, so the Dockerfile build stage needs a Rust toolchain (rustup) AND `libclang-dev` (for rb-sys bindgen). Debian's `cargo` (rustc 1.85) is too old — use rustup.
- **`retry_on` attempts:** 5 attempts with 30s wait is a starting point; tune if needed. After attempts are exhausted, ActiveJob re-raises (the job fails visibly in mission_control-jobs).
- **Out of scope (per spec):** JS-rendered pages, robots.txt, persisted crawl status, readability-style main-content extraction, deleting nonexistent standalone Docling compose files.