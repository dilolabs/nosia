# Make `crawl_url!` functional without Docling Serve

**Date:** 2026-07-07
**Target file:** `app/models/website/crawlable.rb`
**Status:** Design — awaiting implementation plan

## Goal

Make `Website#crawl_url!` crawl a URL and produce Markdown without depending on the external Docling Serve HTTP service. Replace the Docling call path entirely with an in-process fetch-and-convert.

## Background

Today `crawl_url!` (`app/models/website/crawlable.rb:4`) bails immediately unless `ENV["DOCLING_SERVE_BASE_URL"]` is set, then POSTs the URL to Docling Serve's async convert endpoint, polls for completion, pulls `md_content`, saves it to `self.data`, and calls `chunkify!`.

`self.data` is expected to be **Markdown**: `Website::Chunkable#chunkify!` (`app/models/website/chunkable.rb:8`) splits on Markdown heading/code-block/rule separators, and `Website#title` / `#to_html` parse `data` with `Commonmarker`.

The conversion (HTML → Markdown) is currently entirely delegated to Docling. There is no in-process HTML parser in the app — `Nokogiri`, `readability`, `reverse_markdown`, and similar are absent from the `Gemfile`. Available HTTP/parsing gems: `faraday`, `commonmarker`, `baran`, `blingfire`.

Call sites:
- `CrawlWebsiteUrlJob#perform` (`app/jobs/crawl_website_url_job.rb:6`) — `website.crawl_url!`, queued as `:background`
- `Sources::WebsitesController#create` and `#update` (`app/controllers/sources/websites_controller.rb:29,43`) — `CrawlWebsiteUrlJob.perform_later(@website.id)`
- `Api::V1::WebsitesController#create` (`app/controllers/api/v1/websites_controller.rb:10`) — calls `CrawlWebsiteUrlsJob` (plural), a class that does **not** exist. Latent `NameError` bug.

No tests exist for crawling.

## Decisions

1. **Full replacement** of Docling — no env-var fallback. If Docling is configured, it is ignored; the in-process path always runs.
2. **Whole-page conversion** — the entire fetched HTML body is converted to Markdown (no readability-style boilerplate extraction). Chunks will include nav/footer noise; accepted as a trade-off for simplicity and minimal dependencies.
3. **Conversion gem:** `html-to-markdown` (RubyGems name; `require "html_to_markdown"`; module `HtmlToMarkdown`). API: `HtmlToMarkdown.convert(html)[:content]` returns the Markdown string. Ruby 3.2+. It is a **native Rust extension** (Magnus bindings), prebuilt for Linux and macOS x86_64/arm64, with **no Nokogiri dependency**. No `base_url`/`selector` option exists in the Ruby binding, which is consistent with the whole-page choice.
4. **Failure handling:** raise on transient errors (network/timeout/5xx/conversion errors) so Solid Queue retries; log and return `nil` on terminal HTTP errors (3xx without redirect following, 4xx). Failed crawls are visible via `Rails.logger.warn`, not via persisted status.
5. **Code organization:** logic stays in the `Website::Crawlable` concern as private methods ordered by invocation flow. No service objects, no new top-level classes. `crawl_url!` remains the public API the job calls.
6. **Scope add-ons:** remove all `DOCLING_SERVE_BASE_URL` references from env/docs/compose/install files; fix the `CrawlWebsiteUrlsJob` typo; add Minitest coverage for crawling.

## Architecture

`Website::Crawlable` is rewritten as a self-contained concern. `crawl_url!` is the public orchestrator; private helpers do the fetch and the conversion. The job and controllers are unchanged — `crawl_url!` stays the public API.

### Data flow

```
CrawlWebsiteUrlJob#perform(website_id)
   └─ Website#crawl_url!
        ├─ fetch_html
        │     Faraday GET (timeout, User-Agent)
        │     raises Faraday::Error on transient  → Solid Queue retries
        │     returns body String on 2xx
        │     logs + returns nil on 3xx/4xx (terminal)
        ├─ convert_to_markdown(html)
        │     HtmlToMarkdown.convert(html)[:content]
        ├─ self.data = markdown
        ├─ self.save!
        └─ self.chunkify!   (unchanged — splits Markdown into chunks)
```

The Docling async POST → poll loop → result GET is removed. Three HTTP round-trips to an external service become one GET to the target URL plus an in-process conversion. `chunkify!` is untouched; `data` is still Markdown, so its heading separators and `Commonmarker`-based title derivation keep working.

## Components

### `crawl_url!` (public)

Orchestrates fetch → convert → persist → chunk. Returns `self` on success, `nil` on terminal failure. Guards on `url` being present (single-line early return at method start, per the project style guide).

### `fetch_html` (private)

Faraday GET to `self.url`:
- `headers["User-Agent"] = "Nosiabot/0.1"` (kept from current code)
- Read timeout `10`s, open timeout `5`s so a hung host does not stall the worker
- Faraday does not follow redirects by default. The design's default is **no redirect-following middleware**: treat 3xx as terminal-and-logged. If `faraday-follow_redirects` is already bundled in the lockfile it may be adopted during implementation; otherwise no new middleware is introduced.

### `convert_to_markdown(html)` (private)

`HtmlToMarkdown.convert(html)[:content]`. No options passed — defaults (ATX headings, fenced code, no wrapping) match what `chunkify!`'s separators expect (`\n# `, fenced code blocks). If conversion raises, the error propagates as transient → Solid Queue retries.

### Gemfile

Add `gem "html-to-markdown"`. Deployment note (for the implementation plan, not the model design): the gem is a native Rust extension. The Kamal Docker build stage must either pull the prebuilt platform gem or include a Rust toolchain. This is a deployment task, separate from the model change.

### Schema

No changes. `websites.url`, `data`, and `title` are reused as-is.

## Error handling

| Situation | Action | Rationale |
|---|---|---|
| `url` blank | `return nil` (guard) | nothing to crawl |
| `Faraday::TimeoutError` / `Faraday::ConnectionFailed` | raise | transient → retry |
| HTTP 2xx | proceed to convert | success |
| HTTP 3xx (no redirect following) | log + `return nil` | terminal; logged for visibility |
| HTTP 4xx | log + `return nil` | terminal (404 will not fix itself) |
| HTTP 5xx | raise | transient upstream → retry |
| `HtmlToMarkdown.convert` raises | raise | unexpected → retry |
| `save!` / `chunkify!` raises | raise (propagate) | DB error → retry |

Logging uses `Rails.logger.warn` with the URL and status, so failed crawls are visible without a persisted-status UI (deliberately scoped out).

## Docling cleanup

- `app/models/website/crawlable.rb` — remove the `DOCLING_SERVE_BASE_URL` guard and all Docling HTTP code
- `.env`, `.env.example` — remove the `DOCLING_SERVE_BASE_URL=` lines
- `docker-compose.yml` — remove the env passthrough
- `install.sh`, `install.ps1` — remove the templated `DOCLING_SERVE_BASE_URL` entries
- `README.md` — remove the Docling URL example, the "Docling document processing service URL" line, and the docling-serve compose file references
- `docs/ARCHITECTURE.md` — remove the "Advanced document parsing" config entry

**Deliberately left in place:** the standalone `docker-compose-docling-serve-*.yml` files. They are optional, self-contained compose files and harmless once nothing references them. Deleting them is out of scope.

## Bug fix

`Api::V1::WebsitesController#create` (`app/controllers/api/v1/websites_controller.rb:10`): `CrawlWebsiteUrlsJob` → `CrawlWebsiteUrlJob` (singular), matching the only defined job class.

## Testing

New `test/models/website_test.rb` (Minitest + fixtures, no FactoryBot):

- `crawl_url!` success: stub `fetch_html` to return fixture HTML, assert `data` becomes the expected Markdown, `save!` persists, and `chunkify!` creates chunks
- `crawl_url!` 4xx: stub the Faraday response to 404, assert `data` is unchanged, return value is `nil`, and no chunks are created
- `crawl_url!` transient: stub Faraday to raise `Faraday::TimeoutError`, assert it re-raises (Solid Queue will retry)
- `crawl_url!` blank url: returns `nil`, no HTTP call made
- `CrawlWebsiteUrlJob` test: assert it enqueues and calls `crawl_url!` (stub the model method)

Stubs target the private-method boundaries (`fetch_html`, `convert_to_markdown`) so tests do not hit the network or the native gem. A small HTML fixture lives in `test/fixtures/files/`.

## Out of scope

- JavaScript-rendered pages (parity with Docling's server-side fetch; no headless browser)
- `robots.txt` / crawl politeness / rate limiting
- Persisted crawl status or failure UI
- Main-content / boilerplate extraction (readability-style)
- Deleting the standalone `docker-compose-docling-serve-*.yml` files