# Sources workspace UI/UX

Status: Design approved in conversation; written-spec review pending.

Date: 2026-10-24

## Relationship to the wider redesign

This is the first focused subproject in the approved Sources → Token usage →
Agent skills → MCP rollout. Shared decisions live in the
[workspace tools foundation](2026-10-24-workspace-tools-ui-ux-design.md). Later workflows require their own
approved specifications and plans; this document does not authorize their code.

## Approved foundations

- Use approach A, Balanced workspace, consistent with the dashboard's neutral/
  green surfaces, system typography, English/French copy, and both themes.
- Unscoped Sources remains a default-account tool; explicit account URLs retain
  their URL account through navigation, forms, and actions.
- Keep the shared header and left/mobile navigation; remove the unrelated
  conversation-history drawer on covered Sources pages.
- Improve visual hierarchy and existing workflow affordances, not source types,
  ingestion capabilities, permissions, or the default account preference.

## Approved coverage

- `/sources` and `/accounts/:account_id/sources`.
- Document, text, Q&A, and website new/edit routes, both legacy and account-scoped.
- Associated source detail pages reached from the list or successful saves, so
  View → Edit → Save/Cancel → Back remains coherent.
- Existing upload, search/filter/sort, Load more, live status/counts, retry, and
  delete interactions. No new standalone wizard, modal editor, source type,
  bulk action, export, ingestion pipeline, or account-transfer capability.

Apply shared styling only to the Sources pages covered here; do not preemptively
redesign the other three workflows or alter unrelated chat/account pages.

## Approved page and list design

Use one page heading, a short purpose, a visible account label, breadcrumb, and
an Add source chooser for document upload, website, text, or Q&A. Do not repeat
the account label on every row. Replace structural emoji with existing SVGs.

Place a compact type/count navigation alongside the list on wide screens and
above it as wrapping controls on narrow screens. Keep search, status selection,
and sort in a readable toolbar. Type, status, query, and sort form one URL-based
selection; changing one preserves the others and resets pagination. Clear/reset
is explicit. Search submits through the existing GET flow; no new search service
or keystroke polling is introduced.

Keep current parameter values: types document/text/qna/website plus all; statuses
indexed/pending/failed plus all; sorts recent/title/status/chunks. Selecting All
sources changes the type to all while retaining the other selections; Reset
clears the query/type/status and restores recent sorting. Sidebar counts remain
account-wide, distinct from the filtered result total. Keep stable count targets
for zero as well as nonzero values, and use one responsive navigation DOM rather
than duplicate desktop/mobile counter IDs.

Rows show a meaningful title/subtitle, source type, text-labeled indexing status,
chunk count, added time, and separated actions. On mobile, secondary metadata
stacks under the title rather than hiding type/status. Long names and URLs wrap;
they do not expand the page horizontally. Retry is visible for failed records;
The title opens the existing detail page; Edit opens the existing edit route.
Delete retains a separate confirmation. Retry, Edit, and Delete are sibling
controls, never nested inside the title link. Deletion identifies the affected
source and account, rather than relying on color or an unlabeled icon.

Use actual `pending`, `indexed`, and `failed` state. Pending websites can retain
their current Crawling label. Do not invent progress percentages or error causes:
the current sources generally do not store a detailed failure reason. Show a
generic failed explanation and retry guidance unless real record data exists.

Retain the list's file-drop area and existing uploader with a compact browse/
upload entry point, per-file feedback, retry behavior, and stable upload intent.
Uploading a document is distinct from completing its indexing. Existing type/
size behavior and server contracts remain the source of truth; this is not a
new upload-security policy or pipeline.

## Approved new/edit forms

Use a bounded main form panel with an optional help rail on desktop; stack on
mobile. Show Back, action-oriented heading, account context, grouped fields,
and Save/Cancel in predictable positions. Keep type-specific fields and current
Lexxy editing behavior; rich-text source editors remain attachment-disabled.

- Document: optional title and the current file control. Edit names the attached
  file and clearly distinguishes keeping it from selecting a replacement.
- Website: current URL/content fields and a concise explanation of existing
  crawl/indexing behavior; no new crawling configuration or progress claims.
- Text: readable content editor and existing guidance.
- Q&A: clearly paired Question and Answer fields with enough editing space.

Legacy new forms retain their existing membership-account picker, initially
using the default filing account. Choosing a filing account does not persist a
new global default. Explicit account forms show the URL account as fixed.
Editing does not offer an apparent account-transfer operation: show the record's
account as read-only, retaining current server-side ownership rules.

Use linked, focusable validation summaries plus connected inline errors. Preserve
submitted non-file values after failed saves, keep invalid sections visible, and
never imply an unretained browser file selection has been kept. Explain when a
file needs to be selected again. Save shows an in-progress state and actual
success/error feedback; do not add a separate auto-save workflow.

Use the current full-page new/edit routes, not new modal or wizard flows.
Navigation uses the existing source path/form helpers: scoped flows remain
scoped; legacy forms retain their current destinations and upload/JSON response
contracts. Existing record links that already resolve to account-scoped detail
routes keep that behavior. No arbitrary `return_to` redirect or persistent
cross-page account setting is introduced.

## Approved detail and empty states

Use the source's meaningful title rather than an ID-only page title, with account,
type/status, relevant metadata, Edit, conditional Retry, and a separately styled
Delete action. Retain current document viewing/downloads and sanitized content
rendering. Never mutate or discard source content merely to improve presentation.
Plain text remains escaped; any existing HTML rendering keeps the established
sanitizer/allowlist and editor-to-Markdown conversion rules.

Distinguish no sources, empty type, no search/filter matches, and no failed or
processing items. Offer the appropriate add action or clear filters instead of
a generic blank page. Without memberships, show account-setup guidance instead
of rendering account-dependent controls or querying a nil account.

The no-membership setup state applies to the unscoped list and legacy new forms,
with an Accounts link and no upload/create controls. It does not replace current
404 responses for unauthorized scoped URLs or inaccessible records. Where drawer
removal would drop an existing desktop New chat destination, retain that generic
route in secondary page navigation without duplicating the mobile navigation
link or silently retargeting chat creation.

## Approved architecture, data flow, and verification

Reuse SourcesController/SourceScoped, source path/form helpers, SourceRow,
Sourceable, existing partials, uploader, and Turbo updates. Add focused shared
presentation styles/partials only where justified; no new service layer, schema,
package, persistent account switcher, or broad query/ingestion refactor.
Keep the current 50-row Load more page size and hundreds-scale listing strategy.
No new pagination package, query engine, or thousands-scale optimization is part
of this presentation work.

Read pages remain read-only. Existing authorized creates/updates/retries/deletes
continue through their current routes and model/job behavior. URL account
membership is rechecked on requests, with current rejection behavior for bad or
unauthorized account/resource IDs. Keep legacy upload/JSON contracts intact.

Validation presentation surfaces the current server-side rules; it does not add
new required business fields or silently change accepted source content. Invalid
or unauthorized account/resource context uses the existing rejection path rather
than an inline error that reveals another account's records.

Preserve the existing live-update contract: matching, unsearched list views can
receive new rows and status/count replacements; searched views do not promise
live prepends because an uploaded source may not match the query. Preserve
locale-specific broadcasts and avoid duplicated DOM IDs for responsive views.
Filter/order/page membership comes from the existing list request; current row
status/count replacement does not promise continuous re-sorting or re-filtering
of a loaded page. Do not add polling or fabricate a stronger live-data guarantee.

Use Minitest/fixtures with failing tests before application edits. Verify both
route families, four source types, filter/query/sort/page composition, forms and
422 errors, read-only GETs, scoped filing rejection, retry/deletion/upload
contracts, live updates, no-account/empty states, and safe rendering. Retain the
dashboard's existing source/composer regressions. Browser verification covers
375px/tablet/desktop/narrow landscape, both themes, English/French and long names,
keyboard access, visible status/actions, error focus, reduced motion, and fixed-
navigation clearance. Native 200% zoom is separate manual evidence if available.
Use 4.5:1 minimum normal-text contrast, 3:1 for meaningful non-text controls,
visible focus, and 44px minimum touch targets for primary/row actions on narrow
screens. Measure rendered light/dark surfaces rather than assuming color names
establish contrast. Existing validation paths supply 422 coverage; do not invent
required fields merely to manufacture validation tests.
Use a dedicated test database and stub providers; never run live ingestion for
verification. Record actual suite exits and known baseline issues separately.

## Design references and acceptance

The local visual study is
`.superpowers/brainstorm/606522-1792869324/sources-balanced-workflow.html`.
It is an ignored, illustrative companion, not application code, user data, or a
required file in a clone. This written specification is authoritative, including
separate View/Edit destinations where the small study uses a combined label.

ui-ux-pro-max research verified relevant guidance for responsive layouts,
text-labeled status, submit feedback, and focusable linked validation summaries
with inline errors. Full generated design-system results were unsuitable for the
existing internal workspace and were not adopted. No fonts or packages are added.

Acceptance requires coherent list/new/edit/detail pages for all four existing
types, preserved permissions and filing behavior, composed URL filters, visible
mobile status/actions, truthful feedback, safe content rendering, and passing
focused/source/composer regression checks with honest baseline reporting.

## Decisions

- User selected **“Keep defaults (Recommended)”**, **“Visual + workflow polish”**,
  and **“A — Balanced workspace”** in the shared brainstorm.
  Rationale: improve clarity and everyday management without new cross-account
  directories or changes to existing capabilities and permissions.
- User answered **“Yes”** to the shared foundation and rollout with Sources first.
  Rationale: establish reusable visual patterns in a focused first subproject.
- User answered **“Yes”** to design section 2, the Sources presentation: coherent
  lists/filter state, mobile status, retained upload/live behavior, clearer
  type-specific forms and validation, explicit filing-account behavior, meaningful
  detail pages, and appropriate empty/setup states.
  Rationale: improve everyday source management while retaining current content,
  indexing, and account boundaries.
- User answered **“Yes”** to design section 3: reuse existing Rails/Hotwire and
  indexing flows, preserve account isolation, show truthful errors/status, retain
  navigation/live-update boundaries, and verify account/source/UI regressions.
  Rationale: keep this a safe, test-first presentation/workflow improvement rather
  than a rewrite of ingestion or account semantics.

All Sources design sections are approved in conversation. The committed written
specification still requires user review before writing-plans. No application
implementation is authorized until that gate and implementation planning are
complete.
