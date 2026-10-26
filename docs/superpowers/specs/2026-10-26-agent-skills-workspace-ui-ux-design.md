# Agent skills workspace UI/UX

Status: Written specification approved by the user (“Go”); implementation planning
authorized. Application execution still requires the plan execution handoff.

Date: 2026-10-26

Exploration base: `6cd1dd03b78a6723a8c31e947f381bda9bf5af1d`.

## Goal and delivery boundary

Make existing Agent skills easier to scan, inspect and manage, with clear routes
to creation and editing. Cover the legacy default-account list, details, new/edit
forms and actions, plus equivalent explicit account-scoped browser routes.

This is the Agent skills cycle of the approved
[workspace-tools foundation](2026-10-24-workspace-tools-ui-ux-design.md).
Sources and Token usage precede it; MCP remains a separate subsequent design,
written-specification review, planning and implementation cycle.

Preserve authored content, existing permissions, account isolation, model/parser
behavior, execution/trigger modes, priority, RAG/enabled controls and runtime
invocation. Do not add search/filter/sort controls, pagination behavior, bulk
operations, execution history UI, import/export, versioning, live previews,
readiness tests, provider calls, jobs, schema changes or dependencies.

## Selected approach and foundation

**Management-first, A — Structured rows** is selected. Align settings and state
for comparison without turning the page into a dense operations console. Keep a
separate complete details page; stack meaningful row content on narrow screens.

Alternatives considered were **B — List + detail pane**, convenient for repeated
inspection but more complex to navigate, and **C — Descriptive cards**, familiar
for small collections but harder to compare and more scroll-intensive.

Reuse the approved Balanced workspace: system typography, neutral/green palette,
English/French, light/dark themes, comfortable density, shared navigation and
relevant New chat access. Suppress unrelated conversation-history drawers only
on covered Skills pages. Do not redesign unrelated tools or account pages.

## 1. Navigation and account context

### Route families and account authority

- Legacy prefix: `/agent_skills`; label **Default account: {name}**.
- Scoped prefix: `/accounts/:account_id/agent_skills`; label **Account: {name}**.

Both families provide list, details, new/edit, create/update/delete and explicit
enable/disable flows. Legacy routes keep their existing default-account behavior.
Global Settings keeps its existing Agent skills entry. Add a small Agent skills
link in the account overview's existing configuration area for scoped discovery.
No account picker, persistent switcher or new owner-only permission is introduced.

Resolve scoped account identity from route path parameters and recheck current
membership on every request. Query/body account values are not account selectors
and cannot retarget an action. Keep account_id out of permitted skill attributes;
do not transfer records. Invalid/unauthorized/revoked accounts and skills outside
the authorized account return 404, never a fallback to the default account.

Run skill reads, validations, saves and dependent deletion within a request-bounded
tenant context for the authorized account, restored after success or failure.
Still scope every skill lookup through that account's association. Do not change
Current.account's contract, set a persistent preference, add a global default
scope or use unscoped lookups to bypass authorization.

If no legacy default account exists, list/new show account-setup guidance rather
than an unusable form. Other no-account record/action requests return 404 without
mutation. A valid account with no skills instead gets the ordinary empty state.

### Navigation and outcomes

- Legacy breadcrumb: Home → Agent skills → current detail/form, as applicable.
- Scoped breadcrumb: Accounts → account → Agent skills → current detail/form.
- Use the skill name for details context and localized task headings for new/edit.
  Reuse account/workspace layouts without duplicate breadcrumbs or page h1s.
- Create/View/Edit/Enable/Disable/Delete, form submission, Back and Cancel retain
  the originating route family and authorized account. Back/Cancel return to that
  family's list. Successful saves and state/deletion actions return there with
  truthful feedback, preserving the existing list-return workflow.
- Failed validation renders the form in the same route family/account with 422;
  it does not redirect to default-account routes. No arbitrary return URL is used.
- The list has one primary Create skill entry. Retain relevant existing New chat
  access, account-aware where already supported, without duplicating scoped
  layout controls. Keep all unrelated navigation/drawers unchanged.

## 2. Structured rows, details and actions

### List

Use one semantic list with linked row headings, not a split pane or duplicated
desktop/mobile interactive markup. Desktop aligns skill, behavior, state and
actions; narrow layouts stack the same labeled information.

Each row shows:

- Linked name, a short description excerpt and optional existing tags. Retain
  the existing 140-character description excerpt rule; full text is on details.
- Execution mode, trigger mode, priority and RAG requirement.
- Enabled/Disabled text and visible View, Edit and Enable-or-Disable actions.

Preserve `priority DESC, created_at ASC` ordering. Show localized total/enabled
counts for this authorized collection, not runtime-success or cross-account
metrics. Long names, descriptions and tags wrap rather than breaking the page.
Do not translate, rewrite or silently discard authored values.

Navigation uses real links; mutations use form buttons. Do not make an entire
row clickable around nested controls or rely on icon-only actions. Status/counts
reflect confirmed saved state after the response, not optimistic client state.

### Details and deletion

Edit is the primary details-page action; Back returns to the same list. Show the
full description and optional tags, labeled settings, enable/disable, then complete
saved SKILL.md as safely escaped raw text with preserved whitespace. No rendered
Markdown, live parsing, source transformation, hidden source or provider calls.

Move deletion off repetitive list rows into a separate destructive-action section
on details. Preserve the existing capability and dependent execution cleanup.
Confirmation names the skill and authorized account and explains that recorded
skill executions are also deleted. Cancel performs no mutation; successful
deletion returns to the same list. Confirmation is keyboard-accessible and
navigation/focus remain predictable.

Enabled/Disabled describes configuration, not readiness or verified execution.
Explain that Ruby skills also require their configured implementation class.
Do not call runnable?/constant lookup during rendering to invent readiness
statuses, or offer a new execution/test control.

## 3. New/edit form and content semantics

New and edit share a grouped form. On desktop, a main **Skill definition** editor
sits beside a smaller **Behavior** column. On narrow screens, stack definition,
behavior, advanced settings and actions in DOM order. Save/Cancel remain in
normal flow, not a fixed bar covering content or mobile navigation.

### Definition and behavior

- Keep a plain, resizable, labeled monospace SKILL.md textarea. No editor library,
  preview, live parser, automatic formatting or source rewriting.
- Preserve source through rendering/submission under existing persistence rules.
  Opening the form or changing locale performs no write. Keep the current
  localized placeholder/example convention; examples never become real field
  values automatically. Explain frontmatter name syntax and account-local
  uniqueness; machine keys and enum values remain unchanged.
- Execution mode, trigger mode and Enabled remain visible, with concise localized
  help, including Ruby's implementation-class requirement.
- Put priority (integer 0–100) and Requires RAG context in native **Advanced
  settings**, closed initially unless it contains validation errors. Collapsed
  fields remain submitted; they are not disabled or omitted.
- Preserve current new-record defaults: LLM, Explicit, Enabled, priority 0,
  RAG false. Existing records load saved values rather than replacement defaults.
- Edit shows saved name and description read-only as context, not new editable
  fields. Explain that editing frontmatter does not automatically rename or
  re-describe an existing skill. Do not add hidden synchronization. Preserve the
  current permitted browser parameters and separate API behavior.

### Parser/validation compatibility

The current AgentSkill::Parser is the behavior baseline, not its unused validation
helper or a new client parser. Preserve fill-only-if-nil behavior for name,
description, execution and trigger; metadata merge; and RAG boolean conversion
and precedence. Do not promise that controls override all metadata. RAG help
explains keeping frontmatter consistent with the checkbox, including clearing a
requirement set there when turning it off. Show actual saved settings after
submission rather than a prediction of parsed values.

Required-content labeling follows actual validation: required on create, without
adding a nonblank update requirement. Do not impose new mandatory description or
YAML rules. This UI pass does not redesign unexpected YAML parsing failures or
broadly swallow exceptions.

## 4. Feedback, errors and accessibility

- **Empty/setup:** a valid account with no skills gets concise guidance and one
  scoped/default Create skill action. Missing legacy account setup and invalid
  scoped-account responses remain distinct.
- **Outcome feedback:** put Skills-specific messages in page flow, announce them
  accessibly and do not duplicate global flash announcements. Feedback must not
  cover controls or steal focus unexpectedly. Other pages keep existing behavior.
- **Failed validation:** retain submitted source/settings, return 422, and render
  a focusable linked summary above the form plus specific inline errors. Focus
  the summary after failed submission, not ordinary GETs or while typing. Connect
  labels, hints and errors to inputs and expose invalid state accessibly.
- **Derived errors:** name/description errors from frontmatter link to the content
  textarea, not nonexistent inputs. Base/form errors without an editable target
  remain summary text. Safely escape every message.
- **Advanced errors:** open the disclosure if enclosed fields are invalid. Summary
  links reveal any enclosing disclosure before focusing an input, even if the
  user manually closed it. Native disclosure remains keyboard usable.
- **Pending/failure:** disable the submitted action and show localized progress
  text appropriate to saving/updating/enabling/disabling/deleting. Re-enable on
  failed/cancelled client submission. No optimistic success, automatic toggle
  retry or claim that a provider operation is running. Known failures get truthful
  errors; unexpected faults stay observable rather than becoming success.
- **Semantics:** one page h1, logical headings, semantic lists/definition lists,
  visible focus, meaningful control names and text statuses. Decorative SVGs are
  hidden from assistive technology. No hover-only information or color-only state.
- **Contrast/targets:** verify both themes independently: normal text at least
  4.5:1, large text and meaningful control boundaries/icons at least 3:1. Row and
  mutation controls have at least 44 CSS-pixel hit areas; inline links are spaced
  comfortably. Respect reduced motion; no new required animation.
- **Reflow/localization:** long source/errors/names/tags and French strings remain
  usable on narrow screens and at 200% browser zoom. Wrap text or contain source
  overflow without page-level horizontal scrolling. Fixed navigation and feedback
  may not obscure information/actions. Translate wrappers, not authored content
  or machine enum values.

## 5. Architecture and verification

### Focused Rails units

- Keep CRUD in thin AgentSkillsController actions. A focused AgentSkillScoped
  concern shares authorized account/record resolution with state controllers,
  using AccountScoped's existing membership helper and path-parameter authority.
- New UI actions use singular enablement resources in both route families:
  POST `/:agent_skill_id/enablement` under the appropriate collection prefix
  enables; DELETE the same URL disables. AgentSkills::EnablementsController
  handles create/destroy over the existing enabled attribute. This is an HTTP
  resource, not a new persistence record or state engine.
- Preserve PATCH `/agent_skills/:id/toggle` and its flip-and-list-redirect behavior
  through a small REST-action adapter, AgentSkills::TogglesController#update.
  New UI forms express explicit enable/disable intent. No scoped compatibility
  toggle URL is needed because no scoped browser routes currently exist.
- Reuse workspace heading, account layout, neutral/green styles and compatible
  form/error patterns. Small Skills row/detail/form/feedback partials and
  context-aware path helpers have explicit responsibilities. Scope layout/flash
  conditions to Skills; do not refactor unrelated tools merely to share lines.
- Add only small Stimulus enhancements where Rails/Turbo/native HTML do not
  suffice for focus, disclosure or pending feedback. The server remains the
  source of truth; no client data model, polling, readiness probes or new framework.
- Keep business behavior in existing models; no app/services or new bundler.
  Preserve parsing, validation, invocation, runtime selection, API URLs/inputs/
  serialization and dependent cleanup. No schema/dependency/job changes.

### Required later verification

These are implementation requirements, not claims that application tests ran
during design. Establish a fresh baseline on the eventual implementation branch
before edits; verify that its source contracts still match this exploration base.
Use the checkout's actual supported Ruby/database configuration. Earlier Token
usage findings are not waivers for Skills failures. Report any changed contract
or blocker before implementing a conflicting plan.

Use Minitest, fixtures and red–green development. Coverage must include:

1. **Routes/scoping:** every legacy/scoped list/detail/form/CRUD/enablement route,
   legacy toggle compatibility, correct redirects, counts/order, setup/empty
   states, non-owner members under existing permissions, and invalid/foreign/
   revoked membership. Include a second authorized account, not only the default.
2. **Isolation:** forged query/body account values, malformed route IDs,
   cross-account record IDs and tenant restoration after failures. Prove scoped
   creation/actions cannot touch another account or change default preference.
3. **Compatibility/safety:** characterize exact source preservation on read/form/
   failed validation, fill-only-if-nil identity/modes, metadata merge, RAG casting/
   precedence, defaults and current create/edit constraints. Test HTML/script in
   raw source, headings, confirmations, metadata and errors; use safe escaping or
   existing safe formatting without rewriting stored content. Locale changes
   preserve authored values and machine enums. Retain API/runtime regression tests.
4. **No unintended work:** GETs write nothing and enqueue no jobs. Normal CRUD and
   enable/disable do not invoke providers/skills or create token/execution records;
   deletion performs only existing dependent execution cleanup. Stub external
   work in tests; never call a real model/provider.
5. **Browser workflows:** create/edit/details/enable-disable, cancelled/confirmed
   deletion, keyboard navigation, error-summary focus, reopening advanced errors,
   retained inputs and pending feedback. Check EN/FR × light/dark, desktop/tablet/
   375px mobile, long content and navigation clearance. Verify actual 200% browser
   zoom separately from viewport resizing or CSS scaling; explicitly report any
   unavailable check rather than claiming it passed.
6. **Regression/tooling:** focused tests, Skills/API/localization/layout regressions,
   full Rails tests/system tests, Tailwind build, changed-file RuboCop and Brakeman.
   Applicable commands: `bin/rails test`, `bin/rails test:system`,
   `bin/rails tailwindcss:build`, `bin/rubocop`, `bin/brakeman --no-pager`.
   Record exact results and distinguish fresh pre-existing issues from regressions.
   Obtain independent feature review after implementation under the approved plan.

## Design research and evidence limits

ui-ux-pro-max's verified Web **Table Handling** guidance supports mobile-safe
stacking/contained overflow. Its **Focusable Error Summary** and **Error Placement**
guidance support connected inline errors, linked summaries and focus after failed
submission. Responsive-padding guidance is applicable generically; the dataset's
Tailwind 4.3 label does not authorize upgrading this checkout's Tailwind version.

The disclosure search and one narrower retry found no verified disclosure-specific
match. Native advanced disclosure is general design guidance consistent with the
approved foundation, not a claimed dataset recommendation. Unrelated search
results (bulk actions, autoplay) were not adopted.

Local mockups illustrated layout, detail and form hierarchy in light/dark. They
are discussion artifacts, not implementation, contrast measurements or browser
verification evidence. The companion subsequently idle-expired. This document is
self-contained and does not depend on that local server or its ignored files.

## Decisions

- User requested **“Following the dashboard, improve the UI/UX of agent skills
  (/agent_skills, /accounts/:id/agent_skills, new and edit routes), MCP servers
  (/mcp_servers, /accounts/:id/mcp_servers, new and edit and sub routes)”** with
  **brainstorming** and **ui-ux-pro-max**.
  Rationale: continue the approved rollout, with Skills and MCP handled separately.
- The approved foundation retains **default-account legacy tools**, adds explicit
  scoped Skills/MCP routes without a persistent preference, uses **visual +
  workflow polish**, and selects **Balanced workspace**.
  Rationale: improve consistency without changing capabilities or permissions.
- User answered **“Yes”** to the local companion for Skills layout/light-dark
  comparisons.
  Rationale: compare hierarchy visually; this is not implementation consent.
- User selected **“Manage skills (Recommended)”** as the primary workflow.
  Rationale: prioritize scanning existing skills and settings while retaining
  complete creation/editing workflows.
- User answered **“A”**, corroborated by the browser selection: **Structured rows**.
  Rationale: make settings comparable with readable descriptions and visible
  actions, separate details and a mobile stack.
- User answered **“Yes”** to section 1: navigation and account context.
  Rationale: make account identity and in-context routes explicit without changing
  preference, membership rules or unrelated navigation.
- User answered **“Yes”** to section 2: list, details and actions, including deletion
  on details and no new search/filter/bulk controls.
  Rationale: support scanning, preserve full content and make deletion deliberate.
- User answered **“Yes”** to section 3: grouped forms, advanced priority/RAG,
  read-only saved identity and preserved parser/default/validation behavior.
  Rationale: clarify authoring without synchronization promises or source rewriting.
- User answered **“Yes”** to section 4: feedback, errors and accessibility.
  Rationale: make recovery and actions understandable without hidden information,
  obscured controls, optimistic success or automatic toggle retries.
- User answered **“Yes”** to section 5: Rails architecture and verification.
  Rationale: isolate the UI changes, retain legacy compatibility, and verify account
  safety/content preservation on a fresh baseline before claiming completion.
- User answered **“Go”** after reviewing the committed specification `ea1564d`.
  Rationale: approve the written design and authorize writing the Skills plan,
  not skip the execution-choice or fresh-baseline gates.

## Approval and next gate

All five design sections and the committed written specification are approved.
Inline and fresh-context specification reviews approved `ea1564d` without issues.
The user's “Go” authorized writing-plans, which has been invoked for Skills.
No application setup, database changes, provider calls or implementation have
occurred during design/planning. No merge into main or push is authorized here.

Finish and review the implementation plan, then offer the execution-method choice.
Application work begins only after that handoff and its fresh-baseline gate.
MCP remains its own subsequent cycle.
