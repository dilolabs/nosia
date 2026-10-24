# Signed-in root dashboard

Date: 2026-10-24

Design approved in chat; written specification awaiting user review.

## Goal

Replace the signed-in `/` landing experience with a dashboard that makes it easy
to start a conversation, understand global token usage, and reach key tools.
The signed-out root remains unchanged.

## Requested capabilities

- Start a new conversation.
- See global token-usage statistics.
- Reach Accounts, Sources, Token usage, User profile, Agent skills, API tokens,
  MCP servers, and System prompts directly.

## Usage scope

“Global” means combined account-wide usage across all accounts the signed-in user
currently belongs to, including usage by other members in those accounts. It
does not include accounts outside current membership. The dashboard must label
that scope explicitly; it must not imply these are personal-only totals.

## Conversation entry

The dashboard includes an inline composer, not only a link to `/chats/new`.
Reuse the existing composer and account-selection behavior; do not introduce a
second chat-creation or generation workflow.

## Selected layout

Approach A, **Balanced workspace**, is selected. On desktop, place the inline
composer beside a compact usage summary, followed by eight labeled destination
tiles and a compact personal recent-conversations panel. Move history into the
dashboard content rather than duplicating its full right-hand sidebar. The
shared header and left navigation remain.

The alternatives were B, **Chat first** (larger centered composer and existing
history sidebar; usage less prominent), and C, **Usage first** (large metrics
above the composer; conversation entry less prominent).

Local visual reference:
`.superpowers/brainstorm/456260-1792831020/dashboard-layout-options.html`.
This ignored prototype uses illustrative data. This written specification is
authoritative and does not require the prototype to be available in a clone.

## Approved content and navigation

- Reuse the inline composer, account picker, attachment controls, skills, and
  tools. Remove the dashboard's oversized standalone upload/dropzone area;
  preserve the existing inline PDF and source attachment workflows.
- Show input, output, and total tokens for the last 30 calendar days, a daily
  trend, and lifetime totals. Clearly label aggregate account-wide scope and
  inclusion of other members' usage.
- Provide all eight requested shortcuts with visible labels. Account-specific
  tools identify the account they open. Changing the composer account does not
  change the usage scope or silently retarget those tools.
- Show the viewer's five latest root conversations across accessible accounts,
  including account names. Suppress the duplicated conversation sidebar/drawer
  only on the dashboard; other pages retain their existing behavior.
- Stack composer, usage, shortcuts, then recents on narrow screens, using two
  shortcut columns where labels fit. Preserve neutral/green styling and both
  themes rather than introducing new branding, fonts, or a component framework.
- Change the unscoped `/token_usage` page to the same all-membership-account
  scope as the dashboard. Keep explicit account reports account-scoped and retain
  their existing access controls.

## Components and interactions

### Inline conversation composer

Render the existing `chats/form` component and its surrounding `chat-account`
behavior inside the dashboard composer panel. Preserve first-account defaults,
explicit `?account_id=` preselection, the existing `?model=` parameter,
account-change draft/reset confirmation, PDF/source attachments, skill mentions,
and existing tools. The prototype's simplified controls do not authorize a new
model picker or composer redesign.

Submission continues through `ChatsController#create`, redirecting to the new
conversation and using the current generation/job flow. `/chats/new` and account
hub conversation links remain supported. An invalid or unauthorized explicit
composer account retains its existing rejection behavior.

### Usage summary

Capture one request reference time in `Time.zone`. The 30-day window begins at
midnight 29 calendar days before that reference date and ends at the reference
time, including both endpoints and excluding records after the reference time.
Daily buckets use that same application time zone, include today, and fill
missing dates with zero.

- Main number: 30-day input plus output tokens.
- Supporting numbers: 30-day input tokens and output tokens.
- Trend: 30 daily total-token buckets, oldest to newest, with clear date bounds.
- Footer: lifetime total tokens and a link to the global Token usage page.
- Scope text: all accounts you currently belong to, including other members'
  usage; not personal-only activity.

Use the existing `TokenUsage` ledger for period totals and breakdowns. Include
completion, embedding (including source indexing), and agent-skill usage whether
or not it has a chat. Treat absent numeric values as zero. Do not separately add
cached/thinking tokens to input/output totals or invent missing historical usage.
Lifetime totals sum existing account input/output counters, consistent with the
current reporting contract. Counter-drift repair remains outside this feature.

Provide an accessible chart name, a textual period/total summary, and an
expandable table containing the same daily values. Use a simple static SVG line
chart, not a new chart library, tooltip dependency, or interactive zoom UI.

### Destination shortcuts

Use named routes, existing authorization, visible text, and consistent decorative
SVG icons. Each tile is a single semantic link, not nested interactive controls.

| Label | Destination | Scope shown to the viewer |
| --- | --- | --- |
| Accounts | `accounts_path` | Your accounts |
| Sources | `sources_path` | Existing default account, named on the tile |
| Token usage | `token_usage_path` | All your accounts |
| User profile | `profile_path` | Your profile |
| Agent skills | `agent_skills_path` | Existing default account, named on the tile |
| API tokens | `api_tokens_path` | Your personal tokens, existing behavior |
| MCP servers | `mcp_servers_path` | Existing default account, named on the tile |
| System prompts | `system_prompts_path` | Existing prompt directory and permissions |

Do not introduce a global account switcher or change these tools' controllers
into cross-account tools. Composer selection affects only the draft conversation.
The default account remains the one returned by the existing `User#first_account`.

### Recent conversations

Load at most five root chats belonging to the current user and an account in
their current memberships. Order by `updated_at DESC, id DESC`; show each chat's
account name and localized activity time. Eager-load account labels rather than
querying once per chat. Reuse batched first-question lookup
and plain-text title sanitization/fallbacks. Limit displayed previews to 120
characters including the ellipsis; never modify saved content.

Each conversation opens its existing chat URL. Provide a secondary link to
Accounts, labeled to explain that full conversation history is available by
account. Other members' conversations, child/tool chats, and revoked accounts'
chats must never appear, even for account owners or administrators.

### Global and scoped usage reports

The unscoped `/token_usage` page reports the same membership-account set and
30-day metrics as the dashboard. Also retain explicitly labeled lifetime
input/output/total reporting, kind/model breakdowns, environmental estimates,
and transparency explanations. Apply the existing estimation rules to the
authorized aggregate scope; do not introduce pricing, alter energy coefficients,
or change unrelated estimation algorithms.

Matching periods must use matching definitions and sources. The dashboard's
30-day numbers are not presented as equivalent to lifetime breakdowns. Explicit
`/accounts/:account_id/token_usage` reports retain their current scope, data
semantics, membership checks, and cache isolation. Query parameters must not
widen the global report's authorized account set.

## Architecture and data flow

- Keep the existing authenticated `DashboardsController#show` root and the
  signed-out `StaticController#index` root. No new public/API endpoint is needed.
- Add a focused, read-only reporting model under `app/models/token_usage/`,
  `TokenUsage::Report`, that accepts an already-authorized account
  relation and a reference time. It owns period totals, lifetime totals, daily
  series, and report breakdowns. Controllers select authorized scope and render;
  aggregation does not live in ERB or a new service/query directory.
- Dashboard reads request only the lightweight totals/daily series; expensive
  detailed breakdowns are evaluated only on the reporting page.
- Use membership subqueries or equivalent distinct account selection so duplicate
  joins cannot multiply usage. Do not load every account, chat, usage event, or
  source into memory or run one reporting query per account.
- Explicitly constrain every usage query to the authorized account set. If an
  ambient tenant must be relaxed to aggregate across accounts, do so in a narrow
  block, establish the explicit membership restriction, and restore the previous
  tenant afterward. A bare unscoped all-account query is not acceptable.
- Keep account-specific report fragments isolated. Initially leave cross-account
  reporting uncached except for request-local memoization; never reuse a cache
  identity based only on the first account or share private recent-chat output.
- Partition dashboard view markup into focused composer, usage, shortcuts, and
  recent-conversation partials. Adjust the shared layout only to suppress the
  dashboard's duplicated right sidebar/drawer and ensure correct scroll space.
- No schema changes, new packages, new tracking writes, background jobs, or
  provider calls are required to render the dashboard/report. Existing authorized
  chat submission and attachment actions keep their current write behavior.

## Empty states, errors, and freshness

- No usage: show real zeros, a flat/empty trend with its table, and a useful
  explanation. Do not show invented activity, growth percentages, or example data.
- No recent chats: show a short prompt to start the first conversation above.
- No memberships: render a successful dashboard with zero totals, no recent
  chats, account-setup guidance instead of the composer, and an Accounts link.
  Sources/Agent skills/MCP tiles remain visible but lead to account setup through
  Accounts rather than opening controllers that require a default account.
  Profile and the other existing directory links remain reachable. The global
  usage page must also render its empty state without a default account.
- Preserve existing composer validation, inline upload errors, authorization
  responses, and account-change confirmation. Do not broaden this task into a
  rewrite of chat error handling.
- Unexpected database failures use the existing application error path; never
  disguise a failed aggregate query as zero usage.
- Usage, recents, memberships, and destination account labels refresh on normal
  navigation/reload. No polling, dashboard-specific broadcasts, or persistent
  global account preference. Revoked memberships disappear on the next request;
  this does not cancel already-running jobs/streams.

## Visual and accessibility requirements

Preserve Nosia's system typography, neutral surfaces, green emphasis, existing
header/left rail/mobile navigation, and light/dark theme controls. No public
marketing hero, external font dependency, rebranding, or JS component framework.

Use a wide composer and narrower summary side by side when space permits, a
four-column/two-row shortcut grid on desktop, and a full-width recent panel.
On narrow screens stack composer, usage, shortcuts, then recents; use two
shortcut columns where they fit and one when enlarged/long labels require it.

Ensure text contrast of at least 4.5:1, meaningful icon/control contrast of at
least 3:1, visible keyboard focus, readable long names, sensible heading order,
localized labels/counts/dates, and reduced-motion support. Reserve scroll space
so fixed mobile navigation does not cover the composer, links, or focused
elements. Preserve existing composer focus behavior rather than forcing a new
dashboard-specific autofocus strategy.

## Verification and acceptance criteria

Use Minitest with fixtures and test-first implementation. Use a dedicated test
database, stub external providers, and never reset shared development data or
start live ingestion/provider jobs for verification.

1. Authenticated `/` shows all four panels; signed-out `/` remains unchanged.
   Opening read pages creates no chat/source/prompt/token-usage rows or jobs.
2. Two membership accounts, another member's usage, and an outsider account
   prove correct sums, inclusion of source-indexing usage, no double counting,
   and exclusion of unauthorized/revoked accounts.
3. Frozen-time tests cover the first included instant, earlier excluded events,
   today, future exclusion, application-time-zone day boundaries, missing days,
   zeros, and lifetime-versus-period definitions. Dashboard and global reports
   agree for the same data and reference time.
4. Account report regressions retain explicit account authorization, scope, and
   cache isolation. Replace obsolete tests that require the global first-account
   default with assertions for its approved all-account behavior.
5. Recents are bounded, deterministically ordered, private to the viewer, limited
   to current memberships/root chats, escaped, truncated, and linked correctly.
6. All eight shortcuts reach their intended existing destinations. Account labels
   identify default-account tools; composer preselection does not retarget them
   or change aggregate usage. No-account and no-chat states remain navigable.
7. Browser tests exercise sending from the inline composer, selected-account
   submission, attachment/skill controls and draft-reset confirmation, relevant
   validation feedback, and unchanged dedicated new-chat/account-hub entry.
8. Browser review covers 375px, tablet, wide desktop, and narrow landscape;
   light/dark themes; keyboard navigation; long localized labels; reduced motion;
   chart/table equivalence; and unobscured controls/focus. Check native 200% zoom
   manually if automation cannot establish it, reporting any unverified check
   rather than treating viewport emulation as native zoom evidence.
9. Run focused regressions, changed-file lint, and the appropriate full-suite/
   security checks during implementation. Record actual results and distinguish
   preexisting failures from new regressions; no test or feature-completion claim
   is made by this design document.

## Non-goals

No new billing/cost estimates, quotas, usage tracking, counter reconciliation,
custom date filters, live dashboard updates, global account switching, broader
tool/account-permission redesign, schema migration, or unrelated refactoring.

## Existing application context

- The authenticated root already routes to `DashboardsController#show`, which
  currently renders a conversation composer and upload dropzone.
- `/chats/new` already provides a dedicated new-conversation flow with account
  selection; account hubs can preselect an account through that flow.
- Existing global usage reporting shows `Current.account`, not an aggregate
  across every membership account. Explicit account reports already exist.
- Token usage belongs to an account, with optional chat/source references;
  existing account reporting is account-wide, not personal-only.
- Navigation uses a shared header, a collapsible left rail, a right conversation
  sidebar, and mobile bottom navigation. Every requested destination exists.
- Existing account hubs preserve personal conversation visibility and explicitly
  authorize account memberships. This feature must preserve those boundaries.

## Design research

The ui-ux-pro-max design-system search returned useful AI-workspace and KPI-card
style guidance but mixed in unsuitable public marketing-page structures, even
after a narrower retry. No complete generated design system is adopted or
persisted. General guidance for this authenticated web dashboard is to prioritize
a clear primary action, readable metrics, explicit navigation labels, keyboard
focus, responsive layout, reduced motion, and the existing Nosia visual language.

Focused searches verified that daily usage is suited to a simple SVG line chart
with an equivalent data table and summary, and that fixed navigation must not
obscure keyboard focus. Interactive zoom, hover-only values, and a chart library
are unnecessary for a 30-point overview.

## Decisions

- User: “a new dashboard on the root path (/) while connected.” Rationale: this
  is the authenticated landing page, not a replacement public homepage.
- User: “start a new conversation” and “global statistics on token usage.”
  Rationale: conversation entry and usage visibility are core dashboard jobs.
- User requested direct navigation to accounts, sources, token usage, user
  profile, agent skills, API tokens, MCP servers, and system prompts. Rationale:
  reduce reliance on discovering these destinations through nested menus.
- User accepted the visual companion (“Ys”). Rationale: compare layouts in a
  local browser before implementation.
- User selected “All my accounts (Recommended)”: “Combined account-wide usage
  across accounts you belong to, including other members’ activity; excludes
  accounts you cannot access.” Rationale: the dashboard provides a cross-account
  overview while retaining membership-based data isolation.
- User selected “Inline composer”: “Type and send your first message directly
  on the dashboard, alongside statistics and navigation.” Rationale: starting a
  conversation must not require leaving the dashboard first.
- User selected “A” in chat and option `a` in the visual companion: “Balanced
  workspace.” Rationale: give inline conversation entry, global usage, and the
  eight shortcuts comparable prominence without a second full sidebar.
- User selected “Approve” for “this dashboard content—including the matching
  all-account Token usage page.” Rationale: confirm the 30-day/lifetime usage,
  existing inline composer, eight explicit shortcuts, five personal recents,
  responsive styling, and consistent cross-account report navigation together.
- User selected “Approve” for the behavior and verification design. Rationale:
  confirm shared read-only reporting, current-membership privacy, existing chat
  workflows, no-account/empty states, accessible presentation, test coverage,
  navigation/reload freshness, and exclusion of polling/custom date filters.
