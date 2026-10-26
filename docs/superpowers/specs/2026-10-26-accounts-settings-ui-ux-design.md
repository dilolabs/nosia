# Accounts navigation and Settings UI/UX

Status: Written specification approved by the user's “go”; implementation planning authorized.

Date: 2026-10-26

## Requested scope

Carry the recent dashboard, Sources, Token usage and Agent skills UI/UX direction
into the breadcrumbs and Add account action on `/accounts`, the breadcrumb and
New conversation action on `/accounts/:id`, and the `/settings` experience.
Use brainstorming and ui-ux-pro-max research before implementation planning.

## Current project context

- Existing workspace styles provide neutral/green surfaces, system typography,
  explicit page headings, 44px actions, responsive layout and light/dark support.
- Accounts already has a directory and account overview. The directory has no
  breadcrumb; account detail navigation comes from a layout-level partial.
- Add account and New conversation use account-specific primary button styling,
  which differs from the newer shared workspace button treatment.
- Settings currently presents four large tiles: Agent skills, API tokens,
  MCP servers and System prompts. Three use the same code-bracket icon and none
  has a supporting description. The unrelated conversation drawer remains there.
- Account membership/owner permissions and account-preselected conversation
  creation already exist and must not be weakened by presentation work.
- Unrelated local changes existed before this work and are outside this design.

## Decisions

- User requested the specific Accounts breadcrumb/action improvements and a
  Settings UI/UX improvement using brainstorming and ui-ux-pro-max.
  Rationale: extend the recent interface work rather than invent a new visual style.
- User answered **“yes”** to the local browser-based visual companion.
  Rationale: compare breadcrumb, action and Settings arrangements visually before
  approval; this consent does not authorize application implementation.
- User selected **“Settings hub (Recommended)”**: redesign `/settings`, preserve
  Agent skills, API tokens, MCP servers and System prompts as its four destinations,
  and leave their pages unchanged.
  Rationale: keep this pass focused on navigation and presentation rather than
  expanding it into several tool redesigns.
- User answered **“A”** and selected **“Choose A — Balanced cards”** in the browser.
  Rationale: follow the dashboard's distinct, readable cards with concise
  explanations rather than the alternative compact navigation directory.
- User answered **“Yes”** to section 1: Accounts breadcrumbs, header context,
  workspace-style primary/secondary actions, responsive wrapping, and preservation
  of account panels, permissions and account-preselected conversation behavior.
  Rationale: bring the requested account entry points into the newer workspace
  presentation without changing their functionality.
- User answered **“Yes”** to section 2: the four-card Settings hub, breadcrumb,
  descriptions/distinct icons, responsive grid, localized light/dark presentation,
  and removal of its unrelated history drawer with New chat access preserved.
  Rationale: improve discovery and focus without changing destinations, account
  defaults, permissions or the destination pages themselves.
- User answered **“Yes”** to section 3: reuse of the existing presentation stack,
  isolated layout changes, unchanged permissions/account scope/error behavior,
  test-first implementation and responsive/localized/accessibility verification.
  Rationale: keep the UI improvement focused and verifiable without functional
  regressions or unrelated application changes.
- User answered **“go”** after reviewing the specification committed as `52f026b`.
  Rationale: approve the written design and proceed to writing the implementation
  plan; application execution still awaits the execution-method choice.

## Selected approach

**A — Balanced cards** is selected for Settings: four compact explanatory cards
in a two-column desktop grid and one-column narrow layout. Both proposed
approaches used the same account breadcrumb and action treatment. **B — Compact
directory** would reduce mobile scrolling but offers less visual separation.

The browser comparison is an illustrative study, not application screenshots or
accessibility/test evidence. All three design sections and the committed written
specification are approved; application implementation still awaits the
implementation plan and execution-method choice.

## Design section 1 — Accounts headers (approved)

- `/accounts`: one `Home / Accounts` breadcrumb, one Accounts page heading,
  the purpose sentence “Open an account to manage its sources and conversations.”
  and a primary Add account link with a decorative plus.
- `/accounts/:id`: one `Home / Accounts / Account name` breadcrumb, one account-name
  heading, existing UID/role context, owner-only secondary Edit account and primary
  New conversation with a decorative conversation icon.
- Breadcrumb ancestors remain links; the current page is plain text marked
  `aria-current="page"`. Separators are decorative. Long names wrap without
  hiding the full current account name or causing page-wide horizontal scroll.
- Home links to the signed-in dashboard (`user_root_path`); Accounts links to
  `accounts_path`. Labels use the current locale.
- Reuse the newer workspace primary/secondary treatment, including dark-theme
  green emphasis, 44px minimum action height and visible keyboard focus.
  Header actions wrap below the title on narrow screens; they are not fixed.
- Add account still opens the existing New account page. New conversation still
  opens the existing composer with the authorized account preselected; simply
  following the link does not create a conversation or start generation.
- Preserve directory cards, empty states, pagination and all overview panels.
  No account-data, permission, route, default-account or composer behavior changes.

## Design section 2 — Settings hub (approved)

- Use one `Home / Settings` breadcrumb, one Settings `h1`, and the concise purpose
  “Configure assistant behavior and integrations.” Preserve system typography,
  neutral/green surfaces, comfortable spacing and light/dark themes.
- Replace oversized centered tiles with four compact, fully linked cards in the
  existing order: Agent skills, API tokens, MCP servers, System prompts.
  Use two equal columns at viewport widths of 768px and above, and one column
  below 768px. Cards grow with their content rather than using a fixed height.
- Each card has a consistent outline icon, a heading, a concise explanation and a
  decorative forward chevron. The icon concepts are code/instructions, key,
  server/connection and conversation respectively. Use local SVG assets, adding
  matching key/server assets if needed rather than a new icon package.
- Use the descriptions below, with equivalent French translations. Do not
  promise owner-only editing to every viewer or imply all four tools have the
  same account scope. Keep existing localized tool names.
- Each card is one ordinary anchor and one keyboard stop. No nested buttons,
  duplicate Open links, hover-only information, status badges or count queries.
  Give the whole link a visible focus outline and stable hover treatment.
- Remove the unrelated conversation-history drawer on `/settings` only. Preserve
  the shared header, left rail and mobile navigation. Retain generic desktop
  New chat access as a quiet header link; mobile keeps its existing New chat
  navigation action without another redundant header action.
- This is a navigation hub, not an editable settings form. Add no Save action,
  search, tabs, categories, new destinations, new permissions or account switcher.
  Keep destination routes/defaults and their pages unchanged.

| Destination | Existing route helper | English description |
| --- | --- | --- |
| Agent skills | `agent_skills_path` | Manage reusable instructions and how they are triggered. |
| API tokens | `api_tokens_path` | Create and revoke your personal API access tokens. |
| MCP servers | `mcp_servers_path` | Connect external tools and resources through MCP. |
| System prompts | `system_prompts_path` | Review the instructions that guide your assistants. |

## Design section 3 — Architecture, safety and verification (approved)

### Presentation boundaries and flow

Use the existing Rails/Hotwire, ERB, Tailwind and Importmap stack. Reuse the
workspace header and action styling. Settings owns its compact linked-card
presentation and page-specific styles; Accounts retains its existing directory
and overview content. Add only the small presentation helpers/partials needed
to keep those boundaries explicit. No new frontend framework, dependency,
service object, model behavior, migration, route or asynchronous work.

For the two requested Accounts pages, the page-level header owns the single
breadcrumb. Suppress the layout's older breadcrumb on the overview only when
the replacement is rendered. Existing account New/Edit pages and nested tools
keep their own breadcrumb contracts, destinations and layout behavior; do not
restructure them or create duplicate trails through a broad layout change.

Settings continues to link to its existing four route helpers. Account actions
continue to use `new_account_path`, owner-authorized Edit account and
`new_chat_path(account_id: authorized_account.id)`. Use authorized account objects
and escaped output for names/UIDs. Do not infer an account from the Settings hub
or introduce a persistent account selection.

The existing authentication, membership, owner checks and error responses remain
authoritative. Inaccessible accounts retain their existing error behavior; no
silent fallback to another account. Existing account empty states remain. The
Settings hub's static navigation needs no new empty/loading/error state and no
counts, provider calls, MCP connection tests or data fetches for its cards.
These read pages introduce no account/chat/source mutations or enqueued jobs;
ordinary authentication/session behavior is unchanged.

### Accessibility and responsive behavior

- One `h1` per requested page; Settings card headings follow in semantic order.
  Breadcrumbs use a labeled `nav`, ordered list, ancestor links and exactly one
  current-page item. Decorative icons and separators are hidden from assistive
  technology; visible labels remain sufficient without icons or color.
- Preserve readable names, descriptions and button labels in English and French.
  Long account names/UIDs wrap rather than being clipped or shown only on hover.
  No fixed action bars or page-wide horizontal scrolling.
- All actions work with keyboard navigation, visible focus and stable hover
  treatment. Maintain at least 44px action/link targets, 4.5:1 normal-text contrast
  and 3:1 meaningful non-text/focus contrast against the rendered surfaces.
- Preserve clearance above the fixed mobile navigation and avoid obscured keyboard
  focus. Support reduced motion; no decorative animation is needed.

### Verification design

Implementation follows Minitest/fixtures with failing tests before application
edits. Cover the three requested pages' single breadcrumb/heading, exact existing
link destinations, owner/member differences, preserved account preselection and
English/French text. Verify the four Settings links, full-card anchor semantics,
and page-specific drawer suppression with desktop/mobile New chat access intact.

Regression tests cover account New/Edit and nested-tool breadcrumb consumers,
dashboard/Sources/Token usage shells, and unrelated pages retaining their drawers.
Preserve membership isolation and existing 403/404 behavior; do not change auth,
account scope or chat creation merely to simplify UI tests.

Browser checks cover 375px, tablet, desktop and narrow landscape in both themes,
English/French, long account names/UIDs, keyboard activation/focus, measured
contrast, reduced motion and mobile-navigation clearance. Verify Add account opens
the existing form, New conversation opens the composer with the intended account,
and each Settings card reaches its existing destination. Use local fixtures and
a dedicated test database; no live providers, ingestion or connection workers.

Record fresh focused/regression, relevant lint, asset-build and browser outcomes
with any blockers or preexisting failures distinguished. Do not reuse prior
redesign test evidence as proof for this change. Native 200% browser zoom is a
separate check: if unavailable, report it unverified, not simulated by viewport
or device-scale changes. Mockups are not application/browser verification.

## Research and constraints

ui-ux-pro-max's initial design-system search returned marketing hero layouts,
glassmorphism, new fonts and blue/orange branding, which do not fit this existing
workspace and were rejected. A narrower explicit style search verified
Minimalism & Swiss Style for enterprise dashboards: clear hierarchy, neutral
surfaces, functional spacing and no unnecessary decoration. Retain Nosia's
existing system font, green accent and rounded workspace surfaces rather than
copying the dataset's unrelated defaults.

Focused web UX searches support hierarchy/current-location cues, semantic heading
order, keyboard navigation and visible focus. The HTML/Tailwind stack search
supports consistent grid gaps and card padding. Dataset breadcrumb-depth advice
is not adopted as a reason to remove the navigation explicitly requested here.
No generated design-system output is persisted as an authoritative new theme.

## Visual reference

The consented comparison is `accounts-settings-layout-options.html` in the local,
ignored `.superpowers/brainstorm/81099-1793042811/` session. It compares Balanced
cards and Compact directory with shared account-header studies and illustrative
theme/narrow-width toggles. The companion is not a required clone artifact;
this specification is authoritative.

## Approval boundary and next step

The Accounts, Settings, and architecture/verification design sections and the
committed written specification are approved. writing-plans has been invoked to
create the implementation plan. No application code, tests, routes, schema or
dependencies have been changed for this design. Finish and review the plan, then
obtain the execution-method choice before application changes. Spec approval does
not authorize redesigning the Settings destinations, merging or pushing.
