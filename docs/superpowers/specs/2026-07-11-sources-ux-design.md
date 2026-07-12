# Sources UI/UX Redesign — Design Spec

**Date:** 2026-07-11
**Status:** Approved (design), pending implementation plan
**Scope:** Unify and modernize the management UI for the four knowledge-base source types — Documents, Texts, Q&As, Websites.

---

## 1. Problem

Nosia's knowledge base ("Sources") drives RAG retrieval: every source is chunked, embedded, and retrieved to answer chats. Today its management UI has grown organically and fragmented:

- **Fragmented navigation.** `/sources` shows only Documents; Texts, Q&As, and Websites live on separate pages reached by top buttons. There is no single view of the whole knowledge base.
- **No processing status.** Records carry `index_status` (`pending` / `indexed` / `failed`) and `indexed_at`, but the UI never surfaces them. Website crawls can fail silently; users cannot tell whether a source is processing, ready, or broken.
- **No search / filter / sort.** Fine at ten sources, painful at the hundreds a real account accumulates.
- **Thin metadata, weak cards.** Cards show a redundant account name plus a title — no type badge, chunk count, date, or health.
- **Weak empty states / onboarding.** No guidance for a new knowledge base or an empty type.
- **Duplicated, drifting markup.** Each type's index is near-identical copy-pasted ERB that has diverged.

**Drivers (confirmed):** both real UX friction *and* a dated look. **Scale (confirmed):** a heavy account holds **hundreds** of sources (~50–500), so search, filter, sort, and lazy-loading are required; virtualization/thousands-scale tuning is explicitly out of scope.

## 2. Goals & non-goals

**Goals**
- One unified, modern Sources experience with a single overview across all types.
- Always-visible, live per-source status, with a clear path to fix failures.
- Fast findability at hundreds-scale: search, type/status filters, sort, lazy-loading.
- Richer, consistent rows with per-type context and chunk counts.
- Strong first-run and per-filter empty states.
- Collapse four duplicated list views into one maintainable template.

**Non-goals**
- No change to ingestion/chunking/embedding pipelines or retrieval.
- No change to the per-type create/edit forms' fields (only how they are reached and how results appear).
- No thousands-scale virtualization or full-text search engine.
- No new source types.

## 3. Information architecture

Chosen layout: **app-like secondary sidebar + content pane** (approach "C"), nested inside nosia's existing chrome.

Nosia already renders a thin global icon rail (far left: Home, Accounts, Sources, Token usage) and a collapsible right-side drawer. The redesign adds a **secondary Sources sidebar** *between* the global rail and the content pane — the established "thin global rail + contextual sidebar" pattern (Linear/Gmail/Slack). The existing right drawer stays collapsed on Sources pages.

**Secondary sidebar contents**
- `All` (with total count) — default.
- **By type:** Documents, Texts, Q&As, Websites — each with a live count.
- **Needs attention:** Failed, Processing — each with a live count; hidden or shown-as-zero when empty.

**Content pane** = toolbar + dense list of rows (see §4).

**Responsive:** on mobile the secondary sidebar collapses to a dropdown / segmented control above the list. The list collapses to a single column. The global rail already becomes a bottom pill nav on mobile (existing behavior, unchanged).

## 4. The source row & toolbar

**Toolbar** (top of content pane): search input · sort control · "+ Add source" chooser.

**Row template** — one partial for all four types, driven by the `Sourceable` interface (§6). Columns:

| Element | Content |
|---|---|
| Leading icon | Per type: 📄 Document · 📝 Text · ❓ Q&A · 🌐 Website |
| Title + subtitle | `display_title` + per-type `source_subtitle` (see below) |
| Type badge | "Document" / "Text" / "Q&A" / "Website" |
| Status | Live chip: `Indexed` (green) · `Crawling…`/`Processing…` (amber) · `Failed` (red) |
| Chunks | Chunk count, or `—` while pending |
| Added | Relative date (e.g. "2d ago") |
| Actions | View · Retry (failed only) · Delete (keeps confirm) |

**Per-type `source_subtitle`:**
- Document — file size + format (e.g. "2.4 MB · PDF").
- Website — crawl progress while running ("crawled 12 / ~40 pages"); failure reason when failed ("robots.txt disallowed").
- Q&A — answer preview ("A: We offer a 30-day…").
- Text — "Pasted text · N words".

**Interactions**
- Row click opens the source detail; View / Delete are explicit shortcuts.
- **Failed rows** show a **Retry (↻)** action and a short failure reason under the title.
- **Sort** options: recently added (default), title, status, chunk count.
- **Search** scopes to the current sidebar selection (searching in "All" searches everything; in "Documents" searches only documents).

## 5. Adding sources

**Path A — explicit chooser.** "+ Add source" opens a menu with all four types (upload documents / add website / paste text / add Q&A). Each opens the existing per-type form (Turbo Frame or modal). The chooser pre-selects the type currently filtered.

**Path B — drag & drop (whole list).** Dropping files **anywhere** on the list container shows a "Drop files to add documents" overlay and uploads via the **existing `dropzone` Stimulus controller** + Active Storage direct upload. Works in any filter view.
- **Documents only** (files). Websites/Text/Q&A require typed input and remain in the chooser. Non-file drags are ignored by the dropzone.
- Multi-file drop creates multiple rows at once; each appears immediately as a `pending` row (via Turbo Stream prepend) and transitions to `indexed` live.

## 6. Backend architecture

### 6.1 `Sourceable` concern
A new concern included by `Document`, `Text`, `Qna`, `Website`, exposing a uniform row API so the row partial is type-agnostic:
- `source_type_label`, `source_type_key`
- `display_title` (falls back sensibly when the `title` column is blank)
- `source_subtitle` (implemented per model — see §4)
- `chunks_count`
- path/route helpers for show/edit/delete/retry

All four already include `Indexable` (status enum + `mark_indexed!` / `mark_indexing_failed!`) and own chunks polymorphically, and all four tables already carry `title`, `index_status`, `indexed_at`, `created_at`, `account_id`.

### 6.2 Routing & controllers
- `SourcesController#index` becomes the unified list, reading params: `type` (all|document|text|qna|website), `status` (all|indexed|pending|failed), `q`, `sort`, `page`. Sidebar links set these params.
- `Sources::{Documents,Texts,Qnas,Websites}Controller` keep `new/create/show/edit/update/destroy`. Their standalone `index` list markup is removed; those index routes redirect to `sources_path(type: …)`.
- **Retry:** add `member { post :retry }` to each of the four resources. The action re-enqueues the type's indexing/crawl job (`AddDocumentJob`, `AddTextJob`, `AddQnaJob`, `CrawlWebsiteUrlJob`) and re-broadcasts the row. (Website retry reuses the existing failed-recrawl path.)

> **Note — enqueue location:** `Text` and `Qna` currently enqueue their indexing jobs from their controllers, whereas `Document` and `Website` enqueue from the model. The plan should pick one consistent home: have `retry` call the job directly and let `Indexable` own the status broadcast, so real-time updates fire regardless of where the initial enqueue happens.

### 6.3 Listing strategy (KISS, bounded to hundreds)
- **Single-type view (common case):** a plain scoped query on one model — `Model.where(account:).search(q).with_status(s).order(sort)` with limit/offset. Fast and index-friendly.
- **"All" view:** an **in-memory merge**. Load matching rows from each model (each scoped by account/status/search), map each to a lightweight `SourceRow` value object (`Data.define`), concatenate, sort by the chosen key, and slice for the current page. Bounded to hundreds, so cost is negligible, and it handles Website's *computed* title and heterogeneous per-model search without fragile cross-table SQL.
- **Documented tradeoff:** if a knowledge base ever reaches ~10k+ sources, revisit with a SQL `UNION ALL` view or a denormalized `sources` table. Out of scope now.
- **Chunk counts:** a single grouped query over the *visible page's* rows — `Chunk.where(account:, chunkable: rows).group(:chunkable_type, :chunkable_id).count` — mapped back onto rows. No N+1, no schema change. (A `chunks_count` counter cache is a possible future optimization.)
- **Sidebar counts:** `count` per type + a grouped status count.

### 6.4 Search scopes
A `search` scope per model over its natural text column(s), using Postgres `ILIKE`:
- Document → `title`
- Text → `title`, `data`
- Qna → `question`, `answer`
- Website → `url`, `title`, `data`

Applied to the current selection only.

> **Note:** `Website#title` is a *computed* method (it parses the first `<h1>` from `data`) that overrides the `title` DB column, and that column may be blank/stale. Searching the `title` column will not necessarily match the displayed title — but searching `data` covers the same content, so results remain correct. Do not assume column-title search mirrors what the row shows.

### 6.5 Pagination / lazy-load
No pagination gem is present, and none is added. Use **"Load more" via a Turbo Frame append** (limit/offset, ~25–50 per page), consistent with the project's lazy-loading convention.

### 6.6 Real-time status (Turbo Streams)
- The index page subscribes: `turbo_stream_from Current.account, "sources"`.
- On an `index_status` transition, the **model** broadcasts (a) a replace of its row partial and (b) a replace of the sidebar-counts partial. Broadcasting from the model (hooked via `Indexable`) keeps jobs shallow, matching the existing model-broadcast pattern (`chat.rb`, `message.rb`).
- Drag-dropped document creation returns a Turbo Stream that prepends the new `pending` row; it then updates live as indexing completes. Website crawl-progress updates reuse the same row-replace broadcast.

## 7. Views & components
- `sources/index.html.erb` — page shell: `_sidebar` (type/status nav + counts), `_toolbar` (search/sort/add chooser), a `_list` Turbo Frame of rows, and the drag-drop overlay wrapping the list.
- `sources/_source.html.erb` — the single, type-agnostic row partial (replaces the four duplicated card partials).
- `sources/_sidebar.html.erb` — counts-driven navigation.
- Empty states: first-run hero dropzone with four quick-add buttons; per-filter empties with type-specific copy and the matching add action; reassuring empties for Failed ("Nothing failed — all good") and Processing.
- Stimulus: extend the existing `dropzone` controller to cover the whole list container. Filtering uses plain links (params); add a small controller only if interaction demands it.

## 8. Error handling & edge cases
- **Failed sources** are always reachable via the "Failed" sidebar filter, show a reason, and offer Retry.
- **Retry** transitions the record back to `pending` and re-enqueues; the row and counts re-broadcast.
- **Concurrent website paste** — existing `find_or_create_by_url!` race handling is preserved.
- **Blank/computed titles** — `display_title` falls back (e.g. filename for documents, first heading or URL for websites, truncated content for text/Q&A).
- **Non-file drag** onto the list is ignored.
- **Empty search / no matches** shows a "no results for '…'" state distinct from the type-empty state.

## 9. Testing (Minitest + fixtures)
- **Model:** `Sourceable` interface (`display_title`, `source_subtitle`, `chunks_count`) per type; `search` scopes; status counts.
- **Controller:** `SourcesController#index` across `type` / `status` / `q` / `sort` / `page`; each type's `retry` action re-enqueues and redirects/streams; drag-drop document create returns a `turbo_stream` that prepends a pending row.
- **System (Capybara):** sidebar filter navigation; drag-drop upload makes a pending row appear; a failed row shows Retry and recovers; live status transition updates the row without refresh.
- **Broadcast:** a Turbo Stream is broadcast on `index_status` change.

## 10. Rollout / migration
- No database migration required (all needed columns exist). `chunks_count` counter cache, if ever added, is a separate optional change.
- Old per-type index views are removed and their routes redirect into the unified index, so existing links keep working.
- Per-type `new/edit/show` forms are unchanged in fields; only entry points and result rendering change.

## 11. Open items for the implementation plan
- Exact page size for "Load more".
- Whether the Add chooser opens forms as modals or inline Turbo Frames (follow existing form conventions in the codebase).
- Precise icon set / SVGs to reuse from `app/assets`.
