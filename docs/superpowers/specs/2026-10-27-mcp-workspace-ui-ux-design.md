# MCP workspace UI/UX design

Status: Written specification approved by the user's “Go”; implementation
planning authorized. Application changes still require the execution gates.

Date: 2026-10-27

## Goal and authority

Continue the dashboard, Sources, Token usage, Agent skills and Settings workspace
direction through MCP server management, discovery, configuration and connection
feedback. Make existing workflows coherent without adding tool/prompt runners.

This is the focused MCP design promised by the approved
[shared workspace specification](2026-10-24-workspace-tools-ui-ux-design.md).
Its Balanced workspace, explicit account context, preserved defaults, scoped MCP
routes and existing-flow coverage carry forward. This document defines the MCP
details; chat approvals do not bypass the written-spec review and planning gates.

## Scope

| Screen | Existing unscoped path | Purpose |
| --- | --- | --- |
| Servers | `/mcp_servers` | Scan and manage the current account's servers |
| Catalog | `/mcp_catalog` | Discover existing templates/integrations |
| Catalog setup | `/mcp_catalog/:id` | Configure a selected catalog entry |
| Server detail | `/mcp_servers/:id` | Inspect configuration/capabilities and connection results |
| Add custom server | `/mcp_servers/new` | Use the same improved form as Edit |
| Edit server | `/mcp_servers/:id/edit` | Update configuration and availability |

The user clarified that `/mcp/servers/:id` meant the existing detail route.
Do not add that alias. Add the previously approved account-scoped server/catalog
families under `/accounts/:account_id/mcp_servers` and
`/accounts/:account_id/mcp_catalog`, including their existing related operations.
Preserve legacy URLs and connection/tool JSON contracts. New controller/routing
boundaries follow the repository's REST-resource conventions, not new custom
controller actions.

Covered operations are existing create/update/delete, catalog activation,
connection testing, connect/disconnect and read-only capability browsing. Preserve
working tool execution elsewhere, including chat usage and the existing JSON
endpoint; do not introduce a testing UI for tools, prompts or resources.

### Non-goals

- No cross-account MCP directory, account switcher, persistent account preference
  or new permissions/owner-only restrictions.
- No new transports, connector integrations, protocol upgrades, background polling,
  automatic retries, bulk actions, analytics or generalized connector refactor.
- No new frontend framework, packages, database schema, raw JSON/environment
  editor, Save-and-test flow or test-unsaved-configuration capability.
- No unrelated dashboard, Sources, reporting, Skills, Settings or chat redesign.
- No secret-display/reveal feature, remote icon fetching or arbitrary HTML/SVG
  from catalog metadata.

## Current context and constraints

Design was explored on the completed Accounts/Settings checkout `02883d5`.
This documentation worktree starts from main at
`ea09e57291c767e913ac1d2a3d4fca8e138733dd`, which includes that feature. The relevant
MCP routes, controllers, models, templates, helpers and Stimulus sources are
unchanged between those revisions. Main's unrelated working changes were left
untouched; the Accounts/Settings branch is not repurposed.

The checkout uses ERB, Turbo/Stimulus, Importmap, existing workspace CSS and
Minitest/fixtures. Use the actual checked-in/runtime versions and ID conventions,
not generic stack descriptions as a reason to change dependencies or schema.

Important existing behavior:

- MCP currently resolves unscoped requests through `Current.account`; scoped MCP
  routes are absent. Agent skills provides a relevant account-scoping precedent.
- Tools/Prompts Test buttons have no handlers. The server-detail Stimulus
  controller only switches panes. Tool execution itself already exists elsewhere.
- Connection tests already have HTML redirects, JSON responses, busy labels and
  result panels. Edit's separate test uses saved configuration and returns to
  server details without saving the edits.
- Catalog setup is metadata-driven. Activation errors currently redirect to the
  catalog and discard input. Ready detail requests can already fetch capabilities
  from a remote server; tests must not contact actual services.
- Built-in `local` integrations use the engine registry. YAML catalog entries may
  use stdio and encrypted environment configuration. Deployment-disabled stdio
  and endpoint safety guards must remain enforced.
- Visual examples used simplified data. Actual template/registry definitions,
  transport types, field classifications and capabilities remain authoritative;
  mockups do not authorize changing those definitions.

## Selected approach

**A — Scan-friendly rows**: use readable server rows for management and cards for
catalog discovery. This extends the existing Balanced workspace rather than
introducing an operations-console aesthetic.

Alternatives compared were **B — Integration cards** on both surfaces (more visual
recognition, but more repetition and scrolling) and **C — Compact inventory**
(faster aligned comparison for large collections, but denser and less naturally
responsive). All options used catalog-first creation and the same account/capability
boundaries. The user selected A in both chat and the browser.

## 1. Shared shell and account navigation

- Reuse shared workspace headings, system typography, neutral/green surfaces,
  English/French and light/dark themes. Each screen has one page title, one `h1`
  and one breadcrumb, with ancestors linked and the current item plain and marked
  current. Do not duplicate the shared header's browser-tab title assignment.
- Unscoped trail: Home / Settings / MCP servers. Scoped trail: Home / Accounts /
  account name / MCP servers. Extend it with Catalog / template, server name,
  New server, or server name / Edit as appropriate.
- Unscoped pages explicitly name the default account; scoped pages name their URL
  account. Every link, form, activation, connection action, redirect and Cancel
  retains the same context. Generic unscoped New chat keeps existing behavior;
  scoped New chat uses the existing composer with that account preselected.
- Resolve scoped membership from the path and server lookups through the resolved
  account. Body/query `account_id` cannot override it. Foreign, malformed or
  revoked contexts fail closed without writes, enumeration or fallback to another
  account. Keep existing member permissions and never change a user's default.
- For users without an account, unscoped list/catalog/New entry points show an
  account-setup state with the existing Accounts/create-account paths, not active
  MCP mutation controls. Existing-record detail/edit and mutation requests without
  authorized context return not found. Do not auto-create an account.
- Remove unrelated conversation-history drawers only on these MCP screens,
  including their scoped forms/details. Preserve the global header, left/mobile
  navigation, relevant New chat actions and unrelated page drawers.

## 2. Server management

- **Browse catalog** is the single primary creation entry; **Add custom server**
  remains clearly available as a secondary action.
- Rows show a linked server name, transport, safe endpoint/command summary,
  availability and connection status separately. Preserve tags and historical
  latency when present. Long names, tags and endpoint text wrap without clipping.
- Do not expose authentication, headers, environment values or command arguments
  in summaries. Endpoint presentation excludes credential-bearing userinfo/query
  data; never make a summary into an automatic external fetch.
- Keep Open/Edit and quick Connect/Disconnect access. Move Delete into the
  server-detail danger area rather than competing with row actions.
- Preserve GET filters for status, enabled state and transport, including built-in
  local transport. Ignore unsupported filter values; a valid false/disabled filter
  must not be mistaken for an absent filter. Reset clears the filters, not account
  context. Do not add a search engine or new bulk management.
- Distinguish **no servers in this account** (Browse catalog and Add custom server)
  from **no matching filters** (Reset filters). Neither state changes records.

## 3. Catalog discovery and setup

- Retain current category/entry order, descriptions and capability labels in
  wrapping cards. Use consistent local outline icons instead of structural emoji,
  with a safe local fallback for unknown entries/categories. Icons beside text
  are decorative; do not invent vendor logos or interpret metadata as SVG/HTML.
- Cards expose their title, complete useful description, capability labels and
  action without overlapping badges or nested interactive controls.
- **Added to this account** is not **Connected**. An added template offers a
  management link rather than a disabled fake button: link to the matching server
  when exactly one exists, otherwise to this account's server list. Keep the
  template identity/details reachable. No new duplicate-activation policy is
  introduced; model validation remains authoritative for direct/repeated POSTs.
- Unadded entries retain explicit configuration-free Add or Configure-and-add
  paths. Visiting a card/template never activates, tests or connects a server.
- Setup names the selected integration, its purpose and destination account. Its
  capabilities describe the template, not a verified live server. Required fields
  have meaningful labels and connected help; show an explicit ready-to-add state
  when no configuration is required.
- Added templates show management instead of a redundant activation control on
  setup as well. Existing cancellation and explicit POST behavior remain scoped.
- Failed activation re-renders the selected setup form with safe error recovery,
  rather than throwing the user back to the catalog. Missing/invalid templates
  retain a safe account-specific recovery path without exposing another account.

## 4. Server details, connection controls and capabilities

### Identity and action hierarchy

Keep name, account, transport and enabled/disabled availability visible. Connection
state is separate; historical connection/check time and measured latency must not
claim continuous health monitoring.

Connect is primary when not ready; Test connection is primary when ready. Edit
remains secondary. Test connection is still available when not ready; Disconnect
is a clearly labeled secondary connection action when ready. These retain their
current meanings, not a new connection lifecycle.

Group connection controls and their result near the top. A submitted request shows
a stable busy label and disables locally conflicting connection controls for that
server until completion. Do not create a distributed lock or permanently lock the
UI solely because a stored status says connecting. Retain an explicit recovery
path and do not add polling or automatic tests/retries.

Use one contextual success/status or failure/alert panel with useful recovery
guidance. HTML diagnostics are escaped and safe: no credentials, raw configuration,
headers, stack traces or secret echoes. Use a generic actionable message when safe
diagnostic text cannot be established. Preserve existing JSON response contracts;
do not silently redesign that API as part of presentation redaction.

### Sections and capability states

- Retain Overview, Tools, Prompts and Resources. Enhance the existing switcher
  progressively: proper tab/panel roles and associations, selected state, roving
  focus, Left/Right wrapping, Home/End, and Enter/Space activation. Arrow/Home/End
  move focus; Enter/Space activates. Tab/Shift+Tab enter/leave the tablist normally.
- Valid `#overview`, `#tools`, `#prompts`, `#resources` links survive refresh and
  browser navigation; unknown fragments fall back to Overview. Without JavaScript,
  ordinary anchors and labeled readable sections remain, rather than hidden content.
  Tab changes do not execute operations or add provider requests.
- Tools show existing names/descriptions and disclose available schemas under
  expandable details. Prompts show names/descriptions, variables and textual
  required indicators. Resources show wrapped URI, description and MIME type as
  read-only text; do not fetch a resource's contents merely by browsing.
- Remove the inactive Tools/Prompts Test buttons. Preserve working tool execution
  contracts and chat usage; do not add runners, result editors or resource viewers.
- Distinguish not connected/not loaded, successful empty results and failed
  capability lookups. Unknown/unavailable counts are not zero. A failed lookup
  must not claim that a server supports no tools/prompts/resources. Independent
  successful sections remain usable if another lookup fails.
- Expose truthful lookup outcomes without changing public tool-execution return
  values. Reuse the existing ready-detail discovery work, at most once per
  capability kind per request; no row-by-row discovery, extra probes or retries.

### Destructive action

Delete server lives in a separate danger area with the existing confirmation,
clear server/account identity and normal scoped authorization. Explain removal
of this account's configuration without implying deletion of the external service.
Do not introduce an owner-only restriction or remove the existing deletion flow.

## 5. Forms, credentials and recovery

### Layout and transport behavior

Use a readable main form column with grouped Connection, Authentication and
Availability fields; tags/notes form an optional organization disclosure. A short
desktop help rail becomes ordinary stacked content on narrow screens. Save/Cancel
stay in normal flow with mobile bottom clearance, not a floating action footer.

Show relevant fields for supported HTTP/SSE, stdio or local transport. HTTP uses
endpoint/applicable authentication; stdio keeps executable/arguments where the
deployment allows it. Explain unavailable stdio without enabling it or bypassing
endpoint guards. Transport changes must not silently clear hidden credentials.
Do not stringify/lose stored array/hash connection data on an unchanged edit.

Built-in local integrations retain local transport and their registered field
definitions instead of being coerced into HTTP. Preserve catalog-managed encrypted
environment/connection values not represented by the form; no raw JSON/environment
editor is added. A missing registry definition gets an unavailable-configuration
notice while preserving existing configuration and safe basic editing, not a
destructive generic replacement.

### Credential rules

| Existing credential input | Save behavior |
| --- | --- |
| Blank; no removal selected | Keep the saved credential |
| Replacement supplied | Replace only that credential |
| Explicit Remove saved credential selected | Clear only that credential, subject to required-field validation |
| Removal and replacement both supplied | Show an actionable field error; do not guess |

Never prefill/display a saved secret, silently clear it because it was hidden, or
overwrite unrelated encrypted configuration keys. Required template fields still
apply; this is not approval to turn required credentials into optional ones.
Existing configured state can be shown without showing the value.

After a failed save/activation, retain only declared non-secret values. Secret and
password inputs remain empty with re-entry guidance. Do not serialize secrets
into response values, hidden fields, flash/session data, browser storage or Turbo
page snapshots. Respect metadata classification: `kchat_team_name` is currently
declared secret despite its label; kDrive `drive_id` is a non-secret string. Do
not reclassify fields or discard encryption to make form repopulation convenient.

### Validation and actions

- Create/update/activation failures remain on their corresponding form. Use a
  focusable linked error summary after failed submission plus specific inline
  errors connected with `aria-describedby`/invalid state. Keep help associations,
  meaningful required labels and normal browser validation. Open any disclosure
  containing an error. Do not move focus on every blur.
- Edit retains its separate **Test saved configuration** action. Persistent adjacent
  copy explains that it does not save/test the edits and navigates to details,
  leaving unsaved edits behind. Do not silently test unsaved values or nest the
  connection-test form inside the edit form.
- Save/Add and connection tests have distinct busy feedback and duplicate-submit
  prevention. Saving or adding configuration never automatically tests/connects
  the server; existing endpoint validation remains in effect.
- New Cancel returns to the current-context server list; Edit Cancel returns to
  this server's details; catalog Cancel returns to the current-context catalog.
  Successful Save/Add returns to this server's details in the same context.

## 6. Architecture and compatibility boundaries

Reuse existing workspace components, Rails partials/helpers, Turbo and focused
Stimulus enhancements. Domain behavior for safe credential updates and capability
outcomes stays in focused model methods/concerns; thin controllers own HTTP and
authorized context. Do not introduce service/form/policy directories, a new
frontend system or generalized connector machinery.

Small targeted changes needed for account scoping, truthful outcomes, safe field
updates and form recovery are in scope; a purely cosmetic patch cannot satisfy
those approved requirements. Keep engine registration, encryption, transport
clients, existing connection methods, JSON field/status/binary-tool serialization
and execution behavior compatible. Do not change catalog IDs, protocols, stored
capability meanings, existing account defaults or connector dependencies.

Application-owned interface/catalog text is English/French. Preserve escaped
extension-provided descriptions and metadata values; translating a label must
not mutate a catalog definition or engine registration.

## 7. Verification and delivery gates

1. Start from a fresh isolated MCP baseline before application changes. Earlier
   Accounts/Settings failures or waivers are historical clues, not acceptance for
   MCP. Report reproduced issues and obtain direction; do not fix, exclude,
   suppress or waive unrelated failures by assumption.
2. Follow Minitest/fixtures red-green-refactor. Request/model tests cover scoped
   and unscoped reads/mutations, foreign/revoked/malformed/no-account contexts,
   forged account overrides, all existing operations, unchanged defaults and JSON
   contracts, credential keep/replace/remove/failed-save behavior, no secret echoes,
   transport safeguards and truthful capability outcomes. Use local registrations
   and doubles, not real credentials, provider requests or external processes.
3. Browser coverage includes all six screens in English/French, light/dark and
   exact CSS viewports 375×812, 768×1024, 1440×1000 and 812×375 landscape. Exercise
   empty/filter/error states, supported transport variants, catalog recovery,
   saved-configuration testing and busy/success/failure feedback in addition to
   the base layout matrix.
4. Test real Tab/Shift+Tab/Enter and tab-widget keys, correct navigation/preselection,
   visible unobscured focus, comfortable 44px actions, long names/URLs/schema text,
   form-summary focus/inline errors, reduced motion and mobile navigation clearance.
   Measure actual normal/hover/focus surfaces independently in both themes: normal
   text ≥4.5:1, meaningful non-text ≥3:1. Prove that hover-gated surfaces actually
   changed when claiming hovered contrast; preserve honest capability-emulation
   labels and restore any dedicated browser setup after use.
5. Recheck dashboard, Sources, Token usage, Agent skills, Accounts/Settings and
   relevant current MCP tests. Run the full suite, current lint/security gates
   and focused public-API/YARD/documentation checks. Preserve raw commands, true
   exits, state metadata and representative screenshots; do not report accepted
   nonzero gates as green or weaken assertions to match new markup.
6. Native 200% browser zoom is UNVERIFIED unless checked using actual browser zoom;
   viewport/device emulation is not proof. Sampled browser verification is not an
   exhaustive screen-reader/accessibility audit. No new application verification
   has been run or claimed while writing this design-only specification.

After written-spec approval, invoke writing-plans for a focused implementation
plan with review checkpoints, test-first tasks, public Ruby YARD and MCP docs.
Implementation requires that plan and the applicable execution gates. No merge,
push, PR, unrelated fixes or worktree cleanup is authorized by this design.

## Research and visual references

Reviewed local ui-ux-pro-max results, using the existing visual system rather than
generating/replacing a global design system:

- `error summary validation` (UX): Web / Focusable Error Summary, connected inline
  error messages and focus after failed submission fit configuration recovery.
- `async connection status feedback` (UX): Submit Feedback and contextual status
  fit explicit connection checks. Generic loading advice does not authorize polling.
- `responsive grid` (html-tailwind), after one empty query: consistent grid gaps
  and content-preserving breakpoints fit the forms/catalog. The dataset's 4.3 tag
  is not a reason to upgrade this checkout's Tailwind.
- The tabs query returned only general keyboard advice and one narrower retry
  found no specific match. Tab semantics instead use the directly reviewed
  [W3C APG Tabs Pattern](https://www.w3.org/WAI/ARIA/apg/patterns/tabs/), including
  manual activation and proper tab/panel associations.

Companion comparisons and section previews informed approval. They are static
design examples, not application verification or a source of live server data.
This specification is self-contained and does not depend on an active local URL.

## Decisions

- Carry forward the prior **Balanced workspace**, **Keep defaults**,
  **Visual + workflow polish** and **All existing MCP flows** decisions from the
  shared specification, including explicit account-scoped MCP routes.
  Rationale: complete the agreed rollout without changing scope/default semantics.
- User answered **“Yes”** to the MCP-specific local visual companion.
  Rationale: compare layouts visually without authorizing application changes.
- User selected **“Existing route (Recommended)”** for server details.
  Rationale: improve `/mcp_servers/:id`; do not add `/mcp/servers/:id`.
- User selected **“No new runners (Recommended)”** for the inactive Test controls.
  Rationale: remove nonfunctional Tools/Prompts buttons, improve browsing and
  existing connection actions, and preserve working execution elsewhere.
- User selected **“Catalog first (Recommended)”** for adding a server.
  Rationale: Browse catalog is primary; Add custom server stays clearly secondary.
- User answered **“A”**, also selecting `a` in the browser comparison:
  **Scan-friendly rows**.
  Rationale: rows for management, cards for discovery, readable at varied widths.
- User answered **“Yes”** to section 1: Navigation, list and catalog.
  Rationale: approve shared shell/account context, wrapping rows, existing filters,
  catalog cards/icons, distinct empty states, separate deletion and MCP-only drawer
  suppression.
- User answered **“Yes”** to section 2: Server details and connection feedback.
  Rationale: approve state-aware actions/results, historical health labels,
  accessible sections, expandable schemas and truthful unknown/empty/error states.
- User answered **“Ye”** (affirmative) to section 3: Configuration forms and recovery.
  Rationale: approve transport-aware forms, credential keep/replace/remove, safe
  validation recovery, scoped catalog setup and saved-configuration-only testing.
- User answered **“Yes”** to section 4: Architecture and verification.
  Rationale: reuse Rails/Hotwire and existing contracts, preserve account safety,
  require fresh MCP baselines and accessible responsive checks, then write and
  commit this specification for review before planning or implementation.
