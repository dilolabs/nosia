# Sources workspace

Sources manage documents, text, Q&As, and websites available to conversations in
an account. The workspace includes the list and full-page new, edit, and detail
pages. It adds no source types, bulk operations, wizard, or ingestion pipeline.

## Account context and navigation

`/sources` still uses the signed-in user's default account. An `account_id`
query parameter does not switch that account or turn the list into a
cross-account directory. `/accounts/:account_id/sources` uses the authorized URL
account. Links, creates, edits, retries, and deletes retain that context, and
membership is rechecked on subsequent requests.

Legacy new-source forms offer a filing picker containing current memberships.
Choosing an account does not change the default account, and the choice survives
a validation failure (422). Scoped new-source forms use the fixed URL account.
On every edit form, the record's account is read-only: editing is not a transfer
operation. Forged account context remains subject to the existing rejection
checks.

Without memberships, the unscoped list and legacy new pages show guidance linking
to Accounts setup instead of account-dependent controls. An unauthorized scoped
URL or inaccessible record returns 404, not setup guidance.

The shared header and left/mobile navigation remain available. Sources do not
add the unrelated chat-history drawer. The generic desktop New chat link appears
only on legacy pages; it is neither an account-targeted shortcut nor a duplicate
mobile action.

## Filters, counts, and pagination

The URL carries `type`, `status`, `q`, `sort`, and `page`. Type and status changes
retain the other selection, search query, and sort while resetting pagination.
All sources clears only the type selection. Reset clears the selections and
query and restores the recent sort.

- Types: `all`, `document`, `text`, `qna`, `website`.
- Statuses: `all`, `indexed`, `pending`, `failed`.
- Sorts: `recent`, `title`, `status`, `chunks`.

One GET toolbar combines search, status, and sort. Status and sort use the
existing automatic submission on change; search is submitted explicitly, with
no keystroke polling. Load more retains the filters and loads the next existing
50-row page.

Filter counts are account-wide, including zero values. Matches on this load is
the total matching the current request's filters, not just the number of loaded
rows or a continuously updated total. These are existing count definitions,
not a reporting change. One responsive DOM retains the seven live count IDs:
`source_count_all`, `source_count_type-document`, `source_count_type-text`,
`source_count_type-qna`, `source_count_type-website`, `source_count_status-failed`,
and `source_count_status-pending`. Narrow layouts stack the controls and row
content instead of hiding metadata.

## Upload and processing feedback

Drop documents onto the existing list dropzone or use Choose files. The existing
dropzone still owns accepted types, size limits, upload requests, per-file
states, retry/removal controls, and stable upload intent IDs. Retrying the same
intent after a successful server response is lost reuses the saved document
without queuing a second indexing job.

**Upload not confirmed. Check sources or retry.** means the server may already
have committed the document; it does not mean Not uploaded. Uploaded confirms
receipt, not Indexed. Source status reflects the actual pending, indexed, or
failed state; a pending website shows Crawling. Chunk counts use actual stored
counts, with an unknown marker when pending has zero chunks, not an invented
processing count. Failures use generic guidance unless a stored reason exists.

Unsearched lists retain matching live prepends and localized row/status/count
updates. Searched lists do not promise live prepends. Replacing a loaded row
does not continuously re-sort or re-filter the page, and the matching total
remains a load-time snapshot. Reload to reapply the query, ordering, and page
membership after processing changes.

## Forms, errors, and content

Forms retain the existing fields, validations, jobs, and route formats. Text and
Q&A forms introduce no new required business fields. Editors use the native Lexxy
toolbar with `attachments="false"`. Website editing retains the existing body-only
Markdown/frontmatter policy: saving an edited body does not preserve crawl
frontmatter, and a re-crawl regenerates it.

Save shows its pending state and prevents duplicate submission while the request
is in flight; existing success and retry notices remain. A failed save focuses
the linked error summary and connects inline errors to their fields. Non-file
values and the legacy filing choice survive a 422, including after activating
an error link. Browsers cannot restore a file selection: reselect it after a
failed add or replacement. Editing keeps the current attachment unless a
replacement is selected.

Details show a meaningful title, account, type, actual status, and metadata.
Edit is separate from opening the title; Retry appears for failed sources.
Delete requires confirmation naming the source and account. Q&A details retain
the full escaped question when a custom or truncated title differs from it.
Documents link to the original file and retain existing MIME-based previews;
there is no new DOCX converter or guarantee of native browser DOCX viewing.
Text and Q&A content remain escaped plain content. Websites retain the existing
rendering allowlist and content policy.

Presentation does not rewrite stored source content. For a failed Website HTML
draft, the editor normalizes a copy for rendering through the existing policy;
this is not a new persistent conversion.

For developers, Retry and Delete retain Turbo's CSRF handling and negotiate HTML
only for Sources action navigation. Existing POST/DELETE 302 redirects,
HTML/JSON write responses, and Load more Turbo Stream contracts are unchanged.
The Sources-only navigation adjustment in `407ae6e` supersedes the earlier native
Retry workaround; there is no global request patch or pipeline change. Reading
list, new, edit, or detail pages does not enqueue processing.

## Verification

Follow the isolated-database setup, RED/GREEN sequence, exact commands, protected
regression suites, and evidence requirements in the
[implementation plan](superpowers/plans/2026-10-24-sources-workspace-ui-ux.md).
Use fixtures and the test queue, run database-sharing suites sequentially, and
do not start live providers or ingestion workers. Preserve account isolation,
upload intent/retry behavior, existing write formats and redirects, localized
broadcasts, and Load more stream contracts when checking regressions.

Existing Task 6 application evidence includes responsive list/form/detail
screenshots in English and French, light and dark themes, long source/account
names, keyboard focus, 422 error-link focus and retained drafts, and clearance
from fixed navigation. Screenshots and measured text/border/focus contrast
records are in `/tmp/opencode/sources-workspace-852967/`; the corresponding
browser and request runs are recorded in
`/tmp/opencode/sources-workspace-task6-csrf-browser-green.log` and
`/tmp/opencode/sources-workspace-task6-csrf-request-contracts.log`.
These artifacts document earlier application checks, not new runs performed for
this documentation or a claim of a full manual accessibility audit.

Native 200% browser zoom is a separate headed/manual check and is currently
**UNVERIFIED**. Viewport sizes, device-scale overrides, and CSS zoom are not
proof of native browser zoom.

Report actual suite and scanner exits rather than calling everything green.
The existing full-suite baseline recorded one unrelated
`Chat::RequestOptionsTest` error (`augmented_context` missing), exit 1, and
duplicate-JSON-key warnings in
`/tmp/opencode/sources-workspace-baseline-full.log`. The existing Brakeman
baseline recorded two warnings (API-token mass assignment and an unmaintained
Rails dependency), exit 3, in
`/tmp/opencode/sources-workspace-baseline-brakeman.log`. This documentation does
not resolve or reverify those issues.

Later Token usage, Agent skills, and MCP workspace changes are separate work.
Existing default-account and reporting behavior remain unchanged.
