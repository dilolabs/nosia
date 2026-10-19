# Chat composer

New chats (dashboard and `/chats/new`) and saved conversations share one composer surface. Its lower row contains PDF attachment, Formatting, account context, Tools, and Send. New chats use the membership-only account picker; saved conversations keep their account read-only. During generation, Stop submits the existing authenticated cancellation POST through a separate hidden form with an explicit button form owner. It neither sends another message nor nests forms.

## Native editing, existing safeguards

- **Formatting** reveals the original Lexxy toolbar on demand, including its native overflow menu. There is no copied toolbar template. **Ctrl/Command+K** opens native link editing.
- **PDF** synchronously delegates to the native toolbar's upload command and real chooser/upload lifecycle; it is not a second uploader.
- **Enter** sends only from editable content; **Shift+Enter** inserts a line break. An open `/skill` palette takes priority. Enter on toolbar controls or inside the link URL field does not send a message.
- Account/source context, upload tracking, registration failure/retry, draft reset confirmation, pending submission, and Turbo cache/history protections remain owned by `chat-account`, `composer-sources`, and `composer`. `composer-chrome` only presents/delegates controls; it does not maintain another upload or submission state machine.
- Editor actions become inert during submission, account navigation, and generation. Pending/failed sources continue to block Send under the existing coordinator rules. Stop and saved-conversation MCP management remain reachable during generation. New-chat Tools stays account-specific; saved Tools opens the existing management modal.
- Shared partials receive explicit form/chat/field/generation locals. Background form replacement uses the saved chat account without requiring a request session.

## Styling boundaries

`app/assets/stylesheets/nosia/composer.css` scopes neutral/green light/dark tokens and controls under `.n-chat-composer`; this is not a global rebrand. Its import in `app/assets/tailwind/application.css` is deliberately **unlayered**: layered utilities cannot override the engine's unlayered editor chrome through specificity alone.

Below 640px the account context wraps above the remaining actions. Tools is bounded by the composer action row **at every width**, not just mobile, and long tool labels wrap inside a scrollable panel. Preserve visible keyboard focus, theme contrast, readable help, 40px Send/Stop targets, long-label bounds, and reduced-motion rules when changing this component.

Regression-test synchronization matters: native `details` toggle events are queued, so wait for Formatting to open before simulating submission. After Stop, wait for enabled Send, no Stop, and `generation-busy=false` before inspecting Tools. For background unlocks, assert enabled DOM attributes rather than rejecting the word `disabled` (which also matches legitimate `aria-disabled=false`). These are presentation-test adjustments, not changes to the approved account/source behavior.

## Verification commands

Use an isolated test database and run database/browser processes sequentially. The following dummy key is for tests only; do not start AI, MCP, crawl, or indexing workers. Tailwind uses the Ruby-native build, without installing Node or changing package/driver configuration.

```sh
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 RAILS_ENV=test bin/rails tailwindcss:build

AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test \
  test/integration/chat_composer_ui_test.rb \
  test/integration/composer_partials_render_test.rb \
  test/controllers/chat_account_selection_test.rb \
  test/controllers/chat_account_sources_test.rb \
  test/controllers/chat_account_access_test.rb \
  test/controllers/chat_account_tools_test.rb \
  test/controllers/chat_account_citations_test.rb \
  test/controllers/chat_account_url_race_test.rb \
  test/controllers/chats_controller_test.rb \
  test/controllers/messages_controller_test.rb \
  test/controllers/chat_sources_controller_test.rb \
  test/models/chat_account_fixture_test.rb \
  test/models/chat_account_test.rb test/models/chat_test.rb

# ARM Linux: use installed Chromium/chromedriver for this process only.
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec ruby -rselenium-webdriver -e \
  'Selenium::WebDriver::Chrome::Service.driver_path = "/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path = "/usr/bin/chromium"; load "bin/rails"' \
  -- test test/system/chat_composer_ui_test.rb test/system/chat_account_selection_test.rb

AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test
RUBOCOP_TARGET_RUBY_VERSION=4.0 bundle exec rubocop \
  $(git diff --name-only d1c1206f5ecba84f187cbc254f00e0e65888c57c..HEAD -- '*.rb')
bin/brakeman --no-pager
bundle exec brakeman --no-pager
```

Pass browser files directly to `test`; `test:system TEST=...` does not reliably select these files in this environment. Compare Brakeman warning **fingerprints** against the feature base (`d1c1206`), not merely warning totals; do not upgrade or suppress warnings to pass a presentation change.

## Verified results — 2026-10-19

- Ruby-native Tailwind build passed. Focused rendering/controller/model tests: **170 runs, 1,308 assertions**, no failures/errors/skips.
- Both browser files: **66 runs, 1,819 assertions**, no failures/errors/skips, retaining all 44 original account/source/history cases. These exercise real PDF chooser delegation and saved file bytes as well as keyboard, source, tool, Stop, and unlock workflows.
- Additional temporary Capybara smoke: **3 runs, 783 assertions**, no failures/errors/skips. Physically clicked native Bold, Italic, heading, lists, link, background highlight, multiline code, table, divider, Undo/Redo at desktop and 375px, using overflow where needed; checked preserved text and unchanged message counts. Inspected screenshots for dashboard/new/saved, both themes, 375px/768px/desktop, Tools, errors, pending submission, Stop, and unlock. The 200% desktop reflow check used 700 CSS pixels at 2× device scale for a 1400px viewport, not an OS/browser-settings zoom audit.
- All **5 changed Ruby files** passed RuboCop. Broader `rubocop app` still reports **4 pre-existing offenses** in `document/chunkable.rb`, `message/stream_buffer.rb`, and `token_usage.rb`, identical at the feature base.
- `bin/brakeman` was blocked by its latest-version gate (installed 8.0.4 versus 8.1.0). The installed scanner completed without scan errors: **3 existing warnings**, with identical fingerprints at the feature base and no new warnings (source text rendering, API-token account mass assignment, Rails end-of-support).
- Full suite: **UNVERIFIED_TIMEOUT**. The standard command reproduced the existing `Chat::RequestOptionsTest` double missing `augmented_context`, then exceeded its 600-second limit without a summary. An unchanged retry was capped at 720 seconds and cleanly terminated with SIGTERM to its tracked test process; it also produced no final count (command exit 1). The timeout cause was not established; no full-suite pass or absence of other failures is claimed. Some unrelated crawl tests depend on external robots.txt availability; do not silently stub them to claim a clean suite.

Scripted geometry, contrast, keyboard, and screenshot checks are not a complete human accessibility audit. The native table-context strip can extend beyond its content box at 375px; the command smoke does not establish viewport bounds for every native floating widget. No native OS-clipboard or live-provider behavior is claimed. Temporary verification scripts, logs, and screenshots belong outside tracked files.

See the approved [design](superpowers/specs/2026-10-19-chat-composer-ui-design.md), historical [implementation plan](superpowers/plans/2026-10-19-chat-composer-ui.md), and [account-selection documentation](chat-account-selection.md) for the preserved behavioral contracts.
