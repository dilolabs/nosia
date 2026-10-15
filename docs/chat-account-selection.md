# Choosing an account for a chat

Choose **Account** in the composer footer before sending the first message, either on the dashboard or **New Chat**. Only accounts you belong to are offered. Each new chat defaults to your first account; the last selection is not remembered.

The chosen account supplies retrieval, pasted links, PDFs, dashboard uploads, MCP tools, `/skills`, system prompts, and usage attribution. Dashboard-uploaded Sources become account resources, **not automatic message attachments**.

Changing account with a draft asks for confirmation. Confirming clears unsent text, attachment references, upload rows, and tool choices, then reloads account-specific options. **Cancel** keeps the draft. Saved sources never move or get deleted by this reset.

Wait for queued uploads and pending source registration before switching or sending. Failed registration blocks sending: retry it or reset the draft; failed dashboard upload rows can be retried or removed. A failed PDF upload may require resetting and attaching it again.

After the first message, the account is read-only. Start a new chat to use another account. This picker does not change the global account used by unrelated pages.

## Request contract

| Request | Account context |
| --- | --- |
| Dashboard or new-chat GET | Optional scalar `account_id`, checked against current membership. Missing/blank uses the first account. |
| Chat creation POST | `chat[account_id]`, with the same membership check and fallback. |
| `/chat_sources` for a new chat | `account_id` for URL or PDF registration. Missing/blank uses the first account. |
| `/chat_sources` for a saved chat | `chat_id` derives the account from a chat owned by the user, with current account membership required. A conflicting `account_id` returns 404. |
| Dashboard document upload | `document[account_id]`, checked against membership; omitted/blank retains the existing `Current.account` fallback. |
| Citation GET | `chat_id` derives the saved account with ownership and membership checks. Without `chat_id`, the first-account citation lookup remains supported; `account_id` does not select another account. |

Follow-up messages, chat controls, and MCP-session changes require both ownership and current membership. Overrides cannot reassign a saved chat. Source and MCP IDs are checked against the selected/saved account before message/chat writes; unknown or wrong-account references return 404 rather than being silently dropped.

Unknown or unauthorized explicit account/chat contexts return 404. Chat entrypoints, creation, and citation lookup also reject array/hash account/chat contexts with 404. Source endpoints have remaining malformed-context exceptions noted under **Verification results**; callers must send scalar IDs. If no account is available, chat GETs show an empty state and creation returns 422. An invalid attachable SGID returns 400 after account authorization (invalid account context still returns 404).

Background generation and form rendering use the persisted chat account, without a request session or `Current.account`. Web requests check current membership; immediately revoking an already-running generation is outside this change's scope.

There is no schema/migration, global account preference, public completion API contract, or retrieval-algorithm change.

## Engineering notes

- Account options, skills, and tools are server-rendered snapshots. Explicit tenant blocks materialize tools/skills and restore the caller's prior tenant, including on generation failure.
- Turbo draft cleanup uses a capture-phase `turbo:before-cache` handler, before Lexxy disposes its editor. Navigation and public `html[data-turbo-preview]` state make the account region inert; submission/generation use editor-local `inert` as well as `disabled` (Lexxy's attribute alone does not stop interaction). Ordinary pending sources still allow text editing.
- A canceled visit preserves the draft. After a confirmed switch encounters a transport error, the old draft is cleared and Turbo's native full-page recovery is allowed to load the intended account.
- Source coordination uses public Lexxy events, serialized `value` for attachment SGIDs, and progress-figure DOM observation. Deleting an uploading attachment can abort without `upload-end`; observing its removal releases that pending operation. Detached source publishers are pruned and listeners/requests are cleaned up on disconnect.
- Direct-upload PDF registration is idempotent per account/blob under an account row lock. Multipart uploads optionally send `document[upload_id]`: one UUID per file intent, retained for retries. The account-local metadata key `dashboard_upload_id` provides retry lookup under the same lock, without a migration. Authorization precedes lookup; retries do not replace a saved file. Filename reservation occurs before batch validation to keep upload rows and cancellation independent.
- New document indexing is published with `after_all_transactions_commit`; crawler enqueueing explicitly waits for transaction commit. Retries/rollbacks must not publish duplicate or uncommitted work. Resetting UI references never deletes already-persisted resources.

## Verification

Use a dummy key only for these isolated tests; do not substitute a live provider key or run indexing/crawl workers. Feature fixtures opt in per test and do not change global fixture discovery. Run test processes **sequentially**, since they share a database.

```sh
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test \
  test/models/chat_account_fixture_test.rb \
  test/models/chat_account_test.rb \
  test/models/document_source_registration_test.rb \
  test/controllers/chat_account_selection_test.rb \
  test/controllers/chat_account_sources_test.rb \
  test/controllers/chat_account_access_test.rb \
  test/controllers/chat_account_tools_test.rb \
  test/controllers/chat_account_citations_test.rb \
  test/jobs/crawl_website_url_job_transaction_test.rb

# ARM64 environment: bypass the incompatible bundled Selenium Manager locally.
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec ruby -rselenium-webdriver -e 'Selenium::WebDriver::Chrome::Service.driver_path = "/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path = "/usr/bin/chromium"; load "bin/rails"' -- test test/system/chat_account_selection_test.rb

AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test
```

Use the direct browser test filename above, not `test:system TEST=...`: that selector was ignored in this environment and ran unrelated legacy system tests. No global browser configuration change is needed. RuboCop here requires `RUBOCOP_TARGET_RUBY_VERSION=4.0` for the installed Ruby.

### Verification results (2026-10-15)

- Focused backend: **86 runs, 666 assertions, no failures/errors/skips**. Feature browser suite: **44 runs, 679 assertions, no failures/errors/skips**.
- Full suite: **553 runs, 2766 assertions, 2 failures, 2 errors, no skips**. The two `ComposerPartialsRenderTest` failures are old assertions for `data-composer-target` after source registration moved to `composer-sources`; these do not fail on the historical baseline. They remain unresolved, not counted as a green full suite.
- Historical baseline `60a82909`: **467 runs, 2115 assertions, 0 failures, 1 error, no skips**. Both branches exhibit the `Chat::RequestOptionsTest` double missing `augmented_context`. The feature full run also encountered a network timeout fetching `example.com/robots.txt` in `Website::CrawlableTest`; the baseline full run did not reproduce that timeout.
- Malformed-context diagnostics found unresolved gaps: `document[account_id]` as a nonempty array raises `NoMethodError` before writing; an empty array uses the existing fallback. `/chat_sources` with empty array/hash `chat_id` falls back and can create a first-account source. These require follow-up validation; they are not claims of cross-account authorization bypass or successful 404 handling.
- Broad Ruby lint: **134 files, 4 offenses**, all outside changed files (`document/chunkable.rb`: two array-spacing offenses; `message/stream_buffer.rb` and `token_usage.rb`: missing final newlines). Separate lint of all **28 changed Ruby files: no offenses**. No unrelated formatting was applied.
- `bin/brakeman --no-pager` stops at its latest-version gate (installed 8.0.4 versus 8.1.0). Using installed `bundle exec brakeman --no-pager` on both branches yields **3 identical warning fingerprints, 0 scan errors, no new warnings**: API-token mass assignment, Rails end-of-support, and inline text rendering. Dependencies and scanner configuration were not changed.
- Scripted visual smoke: **2 runs, 102 assertions, no failures/errors/skips**, across both entrypoints with two account memberships. A one-page PDF was validated with `PDF::Reader`, uploaded through Lexxy's file chooser and pasted as real file bytes through Lexxy/Active Storage POST+PUT, and compared byte-for-byte with the saved blobs. URL paste, lost-registration-response retry, account-local rows/references, refreshed skills/tools, dashboard upload not automatically attached, read-only labels, and a fixture citation click were checked with no workers/providers performed. Light/dark footer screenshots at 390 × 844 and citation/failure screenshots were captured and read. This was automated browser smoke, not human testing or native OS clipboard testing.

Local evidence is under `/tmp/opencode/task12-*`: focused/full/browser logs, baseline full log, lint JSON, baseline/feature Brakeman JSON, malformed-context probe, `task12_visual_smoke_test.rb`, per-entrypoint smoke JSON, and screenshots such as `task12-dashboard-dark-narrow.png`, `task12-new-light-narrow.png`, and `task12-new-citation.png`. The scratch smoke script runs with the same scoped Chrome paths:

```sh
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec ruby -rselenium-webdriver -Itest -e 'Selenium::WebDriver::Chrome::Service.driver_path = "/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path = "/usr/bin/chromium"; load "/tmp/opencode/task12_visual_smoke_test.rb"'
```
