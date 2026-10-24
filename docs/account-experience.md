# Account experience

Open **Accounts**, then **View account**, to see an account's knowledge sources,
your recent conversations, account-wide usage, default system prompt, users,
and your API tokens. **New conversation** preselects that account in the existing
composer; you may still switch before the first message using its normal rules.

Documents, Texts, Q&As, and Websites open the existing source interface scoped to
that account. Filters, upload forms, retries, source links, and pagination preserve
its URL context. Visiting another account does not change a global preference or
the account in another browser tab.

## Visibility and administration

- Conversation previews/counts/history show only your root chats for this account.
  Account owners cannot inspect other members' chats through the account hub.
- API-token lists, generation, and revocation cover only your tokens in this
  account. A newly generated secret is displayed once; digests are never rendered.
- Usage on the hub and explicit account report is lifetime account-wide
  input/output. The signed-in dashboard and global `/token_usage` page aggregate
  all current membership accounts, including other members' usage; dashboard
  period totals and lifetime totals are labeled separately. Hub summaries refresh
  on navigation/reload. This is usage reporting, not a new billing system.
- Members may read the shared default system prompt. Only the account owner edits
  it, edits account details, or accesses/manages the membership directory. The hub
  shows the user count to members, not the membership directory.
- Personal prompt overrides may apply during generation. This feature does not
  change their selection rules or replace them with the shared-default preview.
- Ordinary source viewing, creation, editing, deletion, and retries remain
  available to account members; they are not owner-only administration.

## Request boundaries

Account tools use `/accounts/:account_id/...`. The route account is checked against
current membership before data lookup or mutation; a conflicting submitted account
is rejected. Outsiders, mismatched records, and malformed account context return
404; members attempting owner-only operations receive 403. Invalid forms return
422. Legacy global shared-prompt edit/update/delete routes enforce the same owner
rule.

Scoped Text, Q&A, and Website create/update tools support HTML responses, not a
new JSON API. When HTML is acceptable, it is selected explicitly, including Turbo
fallbacks or an Accept header such as `application/json, text/html;q=0.9`. A JSON
request body can still be parsed when the response accepts HTML. Explicit `.json`
URLs and JSON-only/XML-only response requests receive 406 before mutations or
ingestion jobs. Membership, raw account validation, and update-record authority
are checked first, so unauthorized or conflicting requests still receive 404.
Document JSON uploads and existing global source response behavior are unchanged.

The directory shows 24 accounts per page, ordered by name then ID. The hub shows
five recent conversations. History shows 25 per page, ordered by activity then ID
descending. Directory/history page inputs are normalized and bounded before SQL
offset calculation. Existing non-account URLs remain supported. Account creation,
editing, and the old account-settings landing page lead to the hub.

New and Edit account pages share the same centered, padded form container,
heading spacing, and semantic breadcrumb styling. New links back to Accounts;
Edit retains the account hub in its breadcrumb and Cancel link. Invalid creation
keeps the same presentation and submitted details with a 422 response.

Recent and history conversation previews are limited to 120 characters including
the Unicode ellipsis (`…`). Shorter titles remain unchanged, as do saved prompts
and the full content displayed when opening a conversation.

Revoked membership is checked on subsequent requests. Already-running jobs/streams
are not forcibly interrupted by this feature. Merely opening read pages does not
create prompts/chats/sources or start ingestion/generation/provider requests.

### Route and helper contracts

Use named routes with an explicitly authorized account, for example:

```ruby
account_path(account)                                      # Hub
account_sources_path(account, type: "document", status: "failed")
account_chats_path(account)                                # Your history
account_api_tokens_path(account)                           # Your tokens in this account
account_token_usage_path(account)                          # Account-wide reporting
```

These helpers build URLs; they do not authorize access. Controllers recheck current
membership and scope records to the route account. In source and token submissions,
raw account values are checked before strong-parameter filtering can discard a
malformed value. Hidden account fields are context, not an authorization mechanism.

`source_show_path(record)`, `source_edit_path(record)`, and
`source_retry_path(record)` use the record's own `account_id` for canonical URLs,
including source rows rendered by background broadcasts without a request.
Collection, new-source, form, filter, and pagination helpers instead preserve the
authorized request context (`@scoped_source_account`), falling back to existing
global routes when absent. `source_response_path(record)` also preserves legacy
upload response paths when no scoped request is active. Pass actual authorized
source records and the supported source types, not arbitrary request-supplied
model or helper names.

Scoped dropzones submit the authorized route account to the nested upload URL.
Legacy global dropzones retain the global upload URL and omit the account-ID
attribute, so uploads without explicit context retain the existing first-account
default. Adding `?account_id=...` to the global source list does not scope it.

`Account.overview_counts_for(accounts, user:)` expects the already-authorized,
bounded directory page. `account.conversations_for(user)` restricts root chats to
that user; callers apply the five-row hub or 25-row history bound.
`Chat.first_questions_for(chats)` expects those already-authorized, bounded rows
and batches the earliest user question (creation time, then ID), including a blank
first question rather than substituting a later one. Titles remove embedded
context and markup and use a localized fallback when blank. These model/helper
methods are not substitutes for controller authorization.

The detailed usage fragment's cache identity includes the explicit reporting
account, locale, and input/output counters, not just the ambient first account.
Usage queries temporarily establish that account's tenant and restore the previous
tenant afterward. Personal conversation/token content is not shared in this
account-wide usage fragment. No global account preference or `Current.account`
assignment is introduced.

## Verification

**Native browser zoom at 200% remains UNVERIFIED. A headed/manual browser check is
required; viewport, device-scale, or CSS emulation is not native zoom evidence.**

Use the dedicated test-only database and dummy key described in
[`superpowers/plans/2026-10-23-account-experience.md`](superpowers/plans/2026-10-23-account-experience.md).
Run processes sequentially; never reset a shared development/test database or run
live providers/ingestion workers for these checks.

### UI-correction verification: 2026-10-24

The history-preview and New/Edit presentation corrections were tested first.
History request/browser tests failed on the full-length preview; form request
tests failed on the missing breadcrumb/heading spacing. Computed browser checks
failed on desktop form width (512px versus 1343px) and mobile form top position
(150px versus 188px), before the shared presentation was implemented.

Using the dedicated environment prefix below, the fresh focused command was
`bin/rails test test/controllers/account_experience_test.rb test/controllers/accounts_controller_test.rb test/controllers/accounts/administration_test.rb test/models/account_overview_test.rb test/integration/localized_pages_test.rb`:
107 tests, 1678 assertions, no failures/errors/skips, exit 0 (seed 63137;
`/tmp/opencode/account-ui-forms-green-request.log`). The browser command below,
with `test/system/account_experience_test.rb`, passed 13 tests / 632 assertions,
no failures/errors/skips, exit 0 (seed 59460;
`/tmp/opencode/account-ui-forms-green-browser-final.log`).

Paired New/Edit screenshots at 1440×1000 and 375×812 in light and dark were read:
`/tmp/opencode/account-experience-form-{new,edit}-{1440,375}-{light,dark}.png`.
Computed form/card/field geometry, heading spacing, and breadcrumb styles match;
dark captures wait for theme transitions. Changed-test RuboCop and whitespace
checks passed. No new CSS build was needed. Existing JSON duplicate-key warnings
remain. No full-suite or security rerun is claimed for these UI corrections;
the feature-wide results below are historical, and native 200% zoom is still
unverified. Fresh specification and quality reviews remain required.

### Historical feature-wide execution: 2026-10-24 (+02:00)

Verified application/test revision: `ecfd9ce8b3a496284b2579737325d2505ddf08e1`,
Ruby 4.0.7 / Rails 8.0.5.1 / PostgreSQL. This documentation-only change follows
those checks. Full commands, self-review details, and retained earlier failures:
`/tmp/opencode/account-experience-task11-verification.md` (local evidence, not
committed). All log paths below are under `/tmp/opencode/`; sibling `.exit` files
record the actual process status.

Every test used this dedicated environment prefix, from the feature worktree:

```sh
RAILS_ENV=test DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env --
```

Focused command (append to that prefix):

```sh
bin/rails test test/models/account_overview_test.rb test/models/account_source_broadcast_test.rb test/controllers/account_experience_test.rb test/controllers/accounts test/controllers/accounts_controller_test.rb test/controllers/sources_controller_test.rb test/controllers/sources test/controllers/api_tokens_controller_test.rb test/controllers/chat_account_selection_test.rb test/controllers/chat_account_sources_test.rb test/controllers/chat_account_access_test.rb test/models/sourceable_broadcast_test.rb test/integration/localized_pages_test.rb test/internationalization/catalogs_test.rb
```

The unfiltered full-suite command was the same prefix followed by `bin/rails test`,
foreground with a 900000ms timeout, without exclusions. Each browser file below
ran separately, after the full suite, using the same prefix followed by:

```sh
bundle exec ruby -rselenium-webdriver -e 'ENV.delete("CAPYBARA_SERVER_PORT"); Selenium::WebDriver::Chrome::Service.driver_path="/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path="/usr/bin/chromium"; load "bin/rails"' -- test <explicit-file>
```

| Check / explicit browser file | Seed | Runs / assertions | Failures / errors / skips | Exit | Log |
| --- | ---: | ---: | --- | ---: | --- |
| Focused command above | 4768 | 354 / 13716 | 0 / 0 / 0 | 0 | `account-experience-task11-focused.log` |
| Unfiltered full suite | 54073 | 1038 / 18037 | 0 / **1** / 0 | **1** | `account-experience-final-suite.log` |
| `test/system/account_experience_test.rb` | 26794 | 9 / 402 | 0 / 0 / 0 | 0 | `account-experience-task11-browser-feature.log` |
| `test/system/chat_account_selection_test.rb` | 19523 | 44 / 681 | 0 / 0 / 0 | 0 | `account-experience-task11-browser-chat.log` |
| `test/system/sources_dropzone_test.rb` | 1066 | 1 / 2 | 0 / 0 / 0 | 0 | `account-experience-task11-browser-dropzone.log` |

**The full suite did not pass.** Its only error matches the explicitly accepted
Task 0 baseline: `Chat::RequestOptionsTest#test_completion_replaces_augmented_instructions_and_keeps_environment_option_defaults`,
`NoMethodError` for missing `augmented_context` on the test double, at
`app/models/chat/completionable.rb:39` and
`test/models/chat/request_options_test.rb:32` (test begins at 29). Baseline log
`account-experience-baseline.log`: seed 52426, 867 runs, 14519 assertions,
0 failures, 1 error. Both affected files remain byte-identical to `e4ec6b1`.
The final run has **zero new failures/errors** beyond that accepted error.
Existing ActiveSupport JSON duplicate-key warnings also remain.

Earlier final-verification attempts found and stopped on two integration gaps:
the four new plural keys were missing from the fixed catalog-test inventory, and
global dropzones incorrectly carried explicit account context. Separately approved
corrections preserved the plural equality/runtime guard and restored context-free
legacy uploads. The preexisting Sources browser setup was maintained to use the
existing root login page and stable field IDs, without changing production auth
or its source assertion. Earlier logs are retained with `-before-plural-fix` and
`-before-upload-fix` suffixes. Final review also led to HTML-only scoped
non-document writes rejecting unsupported response formats before side effects,
explicit HTML selection for mixed Accept headers, and long history-heading
wrapping at 375px. These corrections were separately reviewed before this rerun.
Previous final logs/report are retained with
`-before-final-format-fix-0df9f47` suffixes; none are the current results above.

### Lint, security, and self-review

```sh
git diff --check e4ec6b1
RUBOCOP_TARGET_RUBY_VERSION=4.0 bundle exec rubocop app test/controllers/account_experience_test.rb test/controllers/accounts test/models/account_overview_test.rb test/models/account_source_broadcast_test.rb test/system/account_experience_test.rb test/support/account_experience_fixtures.rb
RUBOCOP_TARGET_RUBY_VERSION=4.0 bundle exec rubocop test/internationalization/catalogs_test.rb test/system/sources_dropzone_test.rb
bundle exec brakeman --no-pager
git diff --stat e4ec6b1
git status --short
```

- Whitespace check: exit 0 (`account-experience-task11-whitespace.log`).
- Planned broad RuboCop: **exit 1**, 157 files, three preexisting offenses:
  two array-bracket spacing offenses at `app/models/document/chunkable.rb:77`
  and a missing final newline at `app/models/message/stream_buffer.rb:33`.
  Both files are byte-identical to `e4ec6b1`; no new feature offenses reported
  (`account-experience-task11-lint.log`). Supplemental correction-file lint:
  2 files, no offenses, exit 0 (`account-experience-task11-correction-lint.log`).
- Default Brakeman 8.0.4 completed 79 checks with 0 scanner errors and **2 warnings,
  exit 3**, not a clean security gate (`account-experience-task11-brakeman.log`).
  The `PermitAttributes` warning at `api_tokens_controller.rb:62` flags the same
  `permit(:account_id, :name)` expression present at the base. Actual code checks
  raw account membership/conflicts before filtering and assigns only the resolved
  account and permitted name to the current user's token, not a submitted owner.
  The other warning is end of support for Rails 8.0.5.1; `Gemfile.lock` is unchanged.
  Neither warning was introduced by this feature. No latest-version gate blocked
  scanning, no diagnostic bypass was needed, and no suppression/update was made.
- Self-review checked route authority, revoked membership, all four source
  workflows/broadcast URLs, owner-only shared-prompt administration (including
  legacy routes), personal chat/token boundaries, bounded queries/titles, explicit
  usage cache identity/tenant restoration, escaped output, and read-only GETs.
  No new blocking feature finding remained. No schema, dependency, auth migration,
  global account preference, or `Current.account` assignment was introduced.
  The final private format guard runs after membership/raw-account/record checks
  and before create/update writes, and pins HTML once negotiated. Its response
  contract is documented above; existing public model/helper contracts are unchanged.
- Existing model/helper YARD tags were checked against the implementation and
  authorized/bounded caller preconditions. No material contract discrepancy
  requiring application edits was found. Source navigation helpers have uneven
  inline tag coverage; their contracts are explained above, without adding noisy
  action/private-method comments or changing application files.

### Browser and visual evidence

Final feature-run evidence is **only lines 150–159** of
`/tmp/opencode/account-experience-task10-evidence.jsonl`, seed **26794**. Earlier
lines belong to earlier runs. A run-specific copy, screenshot hashes, and the
ten-record slice are preserved under
`/tmp/opencode/account-experience-task11-ecfd9ce-browser-26794/`.

All nine current screenshots were read: `account-experience-1440-light.png`,
`account-experience-375-light.png`, `account-experience-375-dark.png`,
`account-experience-375-light-content.png`, `account-experience-375-dark-content.png`,
`account-experience-member.png`, `account-experience-empty-hub.png`,
`account-experience-source-validation-error.png`, and
`account-experience-history-long-name-375.png`. Desktop columns, narrow long
French name/UID wrapping, distinct themes, member-only history, actionable empty
states, and preserved invalid-form details were inspected. The supplemental
light-content capture now shows the two-column source tiles and wrapped French
Q&A label; the dark-content capture shows the header, not a separate scrolled
source panel. The long-history screenshot shows the unbroken name wrapping;
at a 375px viewport its main scroll/client widths both measured 365px, with
`overflow-wrap: anywhere`. Browser assertions also check the hub breadcrumb,
New conversation, and Next history links fit and are unobscured when scrolled
into view. No broader screenshot coverage is implied.

Browser automation also exercised account navigation/composer preselection,
second-account source/history links, account edits, one-time personal-token
reveal/disappearance (without token screenshots), viewport sizes 375×812, 768×1024,
1440×1000, and 812×375, and real French language/theme controls. Real Tab/Shift+Tab
walked all 7 directory and 19 owner-hub account actions, checking reading order,
≥2px focus outlines and unobscured edge midpoints/main bounds; Enter activated
New conversation. Reduced-motion media emulation reported account-link transitions
of 0s. Composited computed-color samples met their thresholds: minimum normal text
4.95:1, icons 13.88:1, focus 4.54:1 (light) / 10.08:1 (dark). These are sampled
automated checks, not an exhaustive UI, screen-reader, or assistive-technology audit.

**Native 200% browser zoom is still UNVERIFIED.** Headless Ctrl+Add left
`innerWidth=1400`, `outerWidth=1400`, and `devicePixelRatio=1` unchanged. Viewport,
CDP, device-scale, and CSS emulation do not replace the outstanding headed/manual
200% zoom check. Documentation-specification review and the final reviewer's
confirmation of this fresh evidence are still required before integration.
