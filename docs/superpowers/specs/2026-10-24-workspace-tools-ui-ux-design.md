# Workspace tools UI/UX — shared foundation and rollout

Status: Written specification approved by the user (“Go”); Sources planning authorized.

Date: 2026-10-24

## Goal

Improve the UI/UX of Sources, Token usage, Agent skills, and MCP servers after
the signed-in dashboard work. Cover relevant list/detail pages, new/edit forms,
and agreed MCP subflows with a coherent experience. Use brainstorming and
ui-ux-pro-max research before implementation planning.

## Agreed account behavior

- Unscoped Sources, Agent skills, and MCP pages retain their existing
  default-account behavior. Make the managed account explicit in the interface.
- Add explicit account-scoped Agent skills and MCP routes, which are absent in
  the current checkout. Preserve that account through forms and actions rather
  than introducing a persistent global account preference.
- Global Token usage retains its existing membership-wide aggregate behavior;
  explicit account reports remain account-specific. Visual redesign does not
  imply changing reporting definitions or permissions.

## Scope and delivery boundaries

The agreed depth is visual consistency plus workflow polish: improve hierarchy,
lists, forms, filters, validation, loading/status feedback, and disclosure of
advanced settings while preserving existing capabilities and permissions.

The request spans four workflows. A shared foundation and focused delivery order
are approved: Sources, Token usage, Agent skills, MCP. The first focused design is
[Sources workspace UI/UX](2026-10-24-sources-workspace-ui-ux-design.md).
Token usage, Agent skills, and MCP receive separate detailed designs, written-spec
reviews, and plans when their turns begin. This shared specification does not
authorize implementing those later workflows or a single oversized redesign.

## Selected visual approach

**A — Balanced workspace** is selected: follow the dashboard's neutral/green
visual language with comfortable information density, explicit page/account
context, scan-friendly lists, focused form sections, and optional desktop help
rails. Use the presentation appropriate to each tool rather than making every
resource a card or every page a table. Stack naturally on narrow screens.

Alternatives presented were **B — Compact operations** (denser desktop-oriented
tables and controls) and **C — Calm, focused pages** (larger explanatory sections
with more scrolling). Selecting A approves this direction, not the detailed
design or implementation.

## Approved shared foundation

- Preserve the shared header/left navigation, system typography, neutral/green
  palette, English/French localization, and light/dark themes.
- Give each tool a clear page heading, concise purpose, visible account or global
  reporting scope, breadcrumb, and one primary creation/action entry point when
  applicable. Keep secondary/destructive actions distinct.
- Suppress the unrelated conversation-history drawer on the redesigned tool
  pages, including their covered forms/detail/subflows. Preserve navigation and
  drawers on unrelated pages; retain relevant existing New chat entry points.
- Use consistent toolbar, status, empty-state, feedback, and form patterns with
  current Rails partials/styles; do not introduce a new frontend framework.
- Forms have readable grouped sections, connected inline validation plus a
  focusable linked error summary, retained non-file/non-secret input after failed
  saves, and clear Save/Cancel actions. Do not claim a browser file selection or
  secret has been retained when it has not. Narrow layouts stack without hiding
  meaningful status or covering actions with fixed navigation. Advanced sections
  must expose errors. Workflow-specific specs define their field behavior.
- Unscoped account tools clearly name the current default account; scoped routes
  retain their URL account across links/forms/actions and recheck membership.
  Account navigation is not a new persistent account preference.
- Deliver focused subprojects in the approved order Sources, Token usage,
  Agent skills, MCP. Establish the shared foundation with Sources, then reuse it.
  Each subproject gets its own approved specification and implementation plan;
  this shared specification records decisions rather than authorizing a single
  oversized implementation.

MCP coverage includes all existing related flows: catalog browse/add, server
details, Tools/Prompts/Resources views, connection testing, connect/disconnect,
and feedback for existing tool actions. This is not approval to add capabilities
that the current application does not implement.

## Current project context

- Rails/Hotwire/ERB with Importmap and Tailwind; existing neutral/green dashboard,
  system typography, English/French localization, and light/dark themes.
- Sources already has account-scoped lists and document, text, Q&A, website,
  and retry routes, including existing upload/status/filter workflows.
- Agent skills currently has content editing, execution/trigger settings,
  priority, RAG-context and enabled controls.
- MCP currently includes configuration, authentication, connection feedback,
  tools/prompts/resources views, connect/disconnect and tool execution actions,
  plus a separate catalog. Existing-flow coverage is agreed; its detailed design
  is deferred to the MCP subproject.
- Existing auth, membership checks, data isolation, secrets handling, and user
  content must not be weakened by presentation changes.

## Decisions

- User answered **“Yes”** to a local browser-based visual companion.
  Rationale: compare layouts and mockups visually during design; this does not
  authorize application implementation.
- User selected **“Keep defaults (Recommended)”**: unscoped Sources, Agent skills,
  and MCP pages keep existing default-account behavior with clear labels; add
  explicit account-scoped Skills/MCP routes and preserve context through forms
  and actions. Token usage keeps its existing global and account report scopes.
  Rationale: improve consistency and account clarity without turning these tools
  into cross-account directories or changing the established default account.
- User selected **“Visual + workflow polish”** rather than mostly cosmetic
  changes or a broader capability redesign.
  Rationale: improve day-to-day usability, forms, filters, feedback, and advanced
  setting disclosure while preserving existing capabilities and permissions.
- User selected **“All existing MCP flows”**, including the catalog and existing
  Tools, Prompts, and Resources views alongside connection/action feedback.
  Rationale: make the current MCP experience coherent end to end, without adding
  new server or tool capabilities as part of the visual redesign.
- User answered **“A”**, also selecting A in the browser comparison:
  **Balanced workspace**.
  Rationale: extend the dashboard's readable, task-focused layout consistently
  across tools without the density of an operations console or excessive scroll
  of the spacious alternative.
- User answered **“Yes”** to design section 1: the shared foundation and rollout
  Sources → Token usage → Agent skills → MCP, including focused per-workflow
  specifications/plans and removing the unrelated chat-history drawer from the
  covered tool pages.
  Rationale: carry the dashboard's clarity through each workflow, preserve account
  boundaries, and deliver manageable, independently verified improvements.

## Design status

The shared foundation and the first Sources design were committed in `0a58bbe`
and reviewed by the user, who answered “Go” to starting the Sources plan.
writing-plans has been invoked for Sources only.
No application code, routes, schema, dependencies, or permissions have been
changed for this redesign. Approval here does not skip the independent design,
written-spec review, planning, or verification gates for later workflows.
