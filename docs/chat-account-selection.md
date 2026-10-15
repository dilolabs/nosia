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

Unknown or unauthorized explicit account/chat contexts return 404. Account/chat context IDs must be scalar: arrays, hashes (including empty collections), and booleans return 404 before source writes or blank-context fallback. Missing, nil, or blank scalar new-chat contexts retain their default; matching saved-account overrides are allowed, but conflicting ones return 404. If no account is available, chat GETs show an empty state and creation returns 422. An invalid attachable SGID returns 400 after account authorization (invalid account context still returns 404).

Background generation and form rendering use the persisted chat account, without a request session or `Current.account`. Web requests check current membership; immediately revoking an already-running generation is outside this change's scope.

There is no schema/migration, global account preference, public completion API contract, or retrieval-algorithm change.

## Engineering notes

- Account options, skills, and tools are server-rendered snapshots. Explicit tenant blocks materialize tools/skills and restore the caller's prior tenant, including on generation failure.
- Turbo draft cleanup uses a capture-phase `turbo:before-cache` handler, before Lexxy disposes its editor. Navigation and public `html[data-turbo-preview]` state make the account region inert; submission/generation use editor-local `inert` as well as `disabled` (Lexxy's attribute alone does not stop interaction). Ordinary pending sources still allow text editing.
- A canceled visit preserves the draft. After a confirmed switch encounters a transport error, the old draft is cleared and Turbo's native full-page recovery is allowed to load the intended account.
- Source coordination uses public Lexxy events, serialized `value` for attachment SGIDs, and progress-figure DOM observation. Deleting an uploading attachment can abort without `upload-end`; observing its removal releases that pending operation. Detached source publishers are pruned and listeners/requests are cleaned up on disconnect.
- Direct-upload PDF registration is idempotent per account/blob under an account row lock. Multipart uploads optionally send `document[upload_id]`: one UUID per file intent, retained for retries. The account-local metadata key `dashboard_upload_id` provides retry lookup under the same lock, without a migration. Authorization precedes lookup; retries do not replace a saved file. Filename reservation occurs before batch validation to keep upload rows and cancellation independent.
- New document indexing is published with `after_all_transactions_commit`; crawler enqueueing explicitly waits for transaction commit. Retries/rollbacks must not publish duplicate or uncommitted work. Resetting UI references never deletes already-persisted resources.
- New Website inserts use a `requires_new` savepoint. A concurrent URL insert's `RecordNotUnique` is rescued after that savepoint rolls back, so looking up the winner does not query an aborted outer chat transaction. Only the winner publishes a crawl; the existing crawl job policy still waits for the outer commit and cancels publication on rollback. Validation, defaults, and failed-source retries are unchanged.
- Optional source context IDs are shape-checked before `present?` or account comparison. Dashboard document creation applies the same guard before the existing filing-account helper; the generic helper's behavior on other source pages is unchanged.

## Verification

Use a dummy key only for these isolated tests; do not substitute a live provider key or run indexing/crawl workers. Feature fixtures opt in per test and do not change global fixture discovery. Run test processes **sequentially**, since they share a database.

```sh
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec ruby -Itest -e 'require "./test/models/website/crawlable_test"; Website::CrawlableTest.setup { @website.define_singleton_method(:robots_allowed?) { true } }; load "bin/rails"' -- test \
  test/models/website_find_or_create_by_url_test.rb \
  test/models/website_test.rb \
  test/models/website/crawlable_test.rb \
  test/models/sourceable_test.rb \
  test/models/sourceable_broadcast_test.rb \
  test/models/source_row_test.rb \
  test/jobs/crawl_website_url_job_test.rb \
  test/controllers/chat_sources_controller_test.rb \
  test/models/chat_account_fixture_test.rb \
  test/models/chat_account_test.rb \
  test/models/document_source_registration_test.rb \
  test/controllers/chat_account_selection_test.rb \
  test/controllers/chat_account_sources_test.rb \
  test/controllers/chat_account_access_test.rb \
  test/controllers/chat_account_tools_test.rb \
  test/controllers/chat_account_citations_test.rb \
  test/jobs/crawl_website_url_job_transaction_test.rb \
  test/integration/composer_partials_render_test.rb \
  test/controllers/chat_account_url_race_test.rb

# ARM64 environment: bypass the incompatible bundled Selenium Manager locally.
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec ruby -rselenium-webdriver -e 'Selenium::WebDriver::Chrome::Service.driver_path = "/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path = "/usr/bin/chromium"; load "bin/rails"' -- test test/system/chat_account_selection_test.rb

AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec ruby -Itest -e 'require "./test/models/website/crawlable_test"; Website::CrawlableTest.setup { @website.define_singleton_method(:robots_allowed?) { true } }; load "bin/rails"' -- test --seed 12564
```

Use the direct browser test filename above, not `test:system TEST=...`: that selector was ignored in this environment and ran unrelated legacy system tests. No global browser configuration change is needed. RuboCop here requires `RUBOCOP_TARGET_RUBY_VERSION=4.0` for the installed Ruby.

The process-local setup above keeps the legacy crawler test off live `example.com/robots.txt`; its page-fetch connection is already stubbed. It changes only that test's Website instances, not application/shared test configuration. The concurrency regression itself has no stubs: two connections coordinate via queues after the loser's uniqueness SELECT and assert a real `PG::UniqueViolation`.

### Verification results (2026-10-15)

- Focused backend, Website/crawler/source, and legacy composer rendering tests after the concurrency fix: **199 runs, 1337 assertions, no failures/errors/skips**. Feature browser suite rerun: **44 runs, 679 assertions, no failures/errors/skips**.
- Concurrent URL regression before the savepoint fix: **3 runs, 18 assertions, 0 failures, 2 errors** (`PG::InFailedSqlTransaction` in actual chat creation and later-rollback scenarios); outside-transaction recovery passed. After the fix: **3 runs, 54 assertions, no failures/errors/skips**, including a separate seed-1 rerun after the full suite. Selected-second-account creation produces one chat/user message/generation job, normalized winner Website IDs, a generating chat, a redirect, and one winner-only crawl. Outer loser rollback publishes no additional crawl; normal new-source commit/rollback publication and validation remain covered. A post-process database check found no remaining race Websites, opted-in fixture users/accounts/memberships/models, chats, or sessions.
- Malformed-source regression run before controller changes: **76 runs, 485 assertions, 21 failures, 1 error**; after correction: **76 runs, 555 assertions, no failures/errors/skips**. Empty/nonempty arrays/hashes and booleans now return 404 for new/saved URL/PDF registration and dashboard uploads, without source/chat/message/link writes, generation-state changes, or jobs. Nil/blank scalar defaults and upload idempotency remain covered. The legacy composer structural assertions now follow `composer-sources` ownership while preserving hidden-field namespaces and editor checks.
- Full suite: **619 runs, 3278 assertions, 0 failures, 1 error, no skips**. Its only error is the existing `Chat::RequestOptionsTest` double missing `augmented_context`; the full suite is not claimed green. The first attempt exceeded the tool's 120-second limit and stopped; the sequential rerun with a larger limit completed in 285 seconds.
- Historical baseline `60a82909`: **467 runs, 2115 assertions, 0 failures, 1 error, no skips**, with the same `augmented_context` error. An earlier feature run hit a network timeout fetching `example.com/robots.txt` in `Website::CrawlableTest`; the latest focused/full runs used the instance-only offline setup above. Neither unrelated issue was changed.
- All **32 changed Ruby files** relative to `60a82909`: **no offenses**; the four Ruby files in this correction also passed separately. Application lint (`rubocop app`): **128 files, 4 unchanged offenses** (`document/chunkable.rb`: two array-spacing offenses; `message/stream_buffer.rb` and `token_usage.rb`: missing final newlines). An unrestricted repository scan also inspected **354 files with 235 offenses**, all outside changed files, including legacy migrations and fixture schema formatting. No unrelated formatting was applied.
- `bin/brakeman --no-pager` stops at its latest-version gate (installed 8.0.4 versus 8.1.0). Using installed `bundle exec brakeman --no-pager` on both branches yields **3 identical warning fingerprints, 0 scan errors, no new warnings**: API-token mass assignment, Rails end-of-support, and inline text rendering. Dependencies and scanner configuration were not changed.
- Scripted visual smoke: **2 runs, 102 assertions, no failures/errors/skips**, across both entrypoints with two account memberships. A one-page PDF was validated with `PDF::Reader`, uploaded through Lexxy's file chooser and pasted as real file bytes through Lexxy/Active Storage POST+PUT, and compared byte-for-byte with the saved blobs. URL paste, lost-registration-response retry, account-local rows/references, refreshed skills/tools, dashboard upload not automatically attached, read-only labels, and a fixture citation click were checked with no workers/providers performed. Light/dark footer screenshots at 390 × 844 and citation/failure screenshots were captured and read. This was automated browser smoke, not human testing or native OS clipboard testing.

Latest concurrency-fix verification logs and lint/security/cleanup output use `/tmp/opencode/finalreview-url-race-*`; earlier controller-correction evidence uses `/tmp/opencode/task12-correction-*` and retained historical baseline evidence uses `/tmp/opencode/task12-baseline-*`. The scratch smoke script is `/tmp/opencode/task12_visual_smoke_test.rb`, with per-entrypoint smoke JSON and screenshots such as `task12-dashboard-dark-narrow.png`, `task12-new-light-narrow.png`, and `task12-new-citation.png` in the same directory. That visual smoke was rerun after the controller corrections (not this model-only fix) using the same scoped Chrome paths:

```sh
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec ruby -rselenium-webdriver -Itest -e 'Selenium::WebDriver::Chrome::Service.driver_path = "/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path = "/usr/bin/chromium"; load "/tmp/opencode/task12_visual_smoke_test.rb"'
```
