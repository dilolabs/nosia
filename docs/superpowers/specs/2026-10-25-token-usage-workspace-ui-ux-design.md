# Token usage workspace UI/UX

Status: Design sections approved in conversation; user review of this written specification is pending. Implementation is not authorized.

Date: 2026-10-25

## Relationship to the wider redesign

This is the next focused subproject after the dashboard and Sources. It follows
the approved [workspace tools foundation](2026-10-24-workspace-tools-ui-ux-design.md)
and the established neutral/green presentation. Agent skills and MCP remain
separate subprojects with their own detailed designs, specifications and plans.
This document does not authorize their routes or application changes.

The scope is `/token_usage` and `/accounts/:account_id/token_usage`. Improve
hierarchy, readability, navigation, disclosures and accessibility without
changing report definitions, account permissions or stored usage.

## Selected approach and reading order

The user selected **Overview first** and **A — Overview + detail rail**.

- On desktop, give the overview and activity trend the dominant main panel, with
  secondary lifetime information and environmental estimates in a narrower rail.
- Put the existing model and usage-type breakdowns below that overview. Keep the
  complete methodology available in a clearly named native disclosure.
- On mobile, stack overview/trend, secondary information, breakdowns, then
  methodology. Do not hide metrics to fit the viewport.
- Retain system typography, neutral surfaces, green emphasis, English/French
  localization and light/dark themes. Do not add fonts or a component framework.

The alternatives were a compact, equally weighted metric strip and a tabbed
report. Neither was selected: the chosen layout emphasizes the main reading task
without hiding the secondary information behind mode switches.

## Scope and time-period presentation

### Global report

`/token_usage` retains its existing current-membership aggregate, including other
members' account-wide usage. It is not personal-only usage or a directory of all
accounts in the installation. Query parameters must not widen that account set.

Keep the existing `TokenUsage::Report` definitions:

- Recent input/output/total values come from the usage ledger in the existing
  thirty-calendar-day window: local midnight 29 calendar days before the request
  reference date through the reference time, inclusive. Future records remain
  excluded by that existing report window.
- The daily series contains those same thirty local dates, chronologically
  ordered and zero-filled by the current reporting model.
- Lifetime input/output/total values remain the existing account-counter sums,
  not a replacement ledger recount. Existing lifetime breakdowns and estimates
  retain their current sources and policy.

Present the recent total prominently, with supporting recent input/output values
and its exact date bounds. Show lifetime totals, including their input/output
detail, separately in the secondary area; do not imply they share the recent
chart's period.

### Account report

`/accounts/:account_id/token_usage` retains its authorized URL account and
membership check. The report is account-wide, not restricted to the viewer's own
conversations. It never changes the user's default account or falls back to it
when an explicit account is inaccessible.

This existing report differs from the global overview. Its headline values are
lifetime account counters, while its recent activity uses the current rolling
lower-bound query (`created_at > 30.days.ago`) and existing date grouping. Do not
replace it with the global report's calendar window, add that report's upper
bound, or synthesize a new thirty-day headline total for visual symmetry.

The account page therefore emphasizes its labeled lifetime total/input/output
values, with a separately labeled recent activity chart. The secondary rail shows
its existing environmental estimates and scope/context, without duplicating the
same lifetime counters in another card.

For both routes, chart points, the daily table and displayed dates must describe
the same supplied data. The account chart must not drop returned date buckets
or force them into the global report's thirty-date template. Date-key
normalization and SVG coordinates are presentation work, not permission to change
the queries, period cutoffs or aggregation rules.

## Page header and navigation

Use one page heading, a short purpose and a visible scope label: **All your
accounts** or **Account: name**. Supporting text explains that usage includes
other members' activity within the authorized account set.

Reuse the workspace header/navigation pattern. The global report has its normal
home/tool context; the scoped report retains the account breadcrumb and a useful
Back destination to that account. Do not introduce an account switcher,
date-range selector, arbitrary return destination or persistent account setting.

Suppress the unrelated conversation-history sidebar/drawer on these report pages
only. Preserve the shared header, left rail and mobile navigation. Retain the
generic desktop New chat destination where removing the legacy global drawer
would otherwise remove it; do not duplicate the mobile action or silently
retarget conversation creation to the report's account. Other pages retain their
existing navigation and drawers.

## Metrics, trend and detailed content

### Exact quantities and accessible trend

Show exact locale-formatted token quantities, not only compact K/M notation.
Input/output/total labels, units and periods remain explicit. Long labels, model
identifiers and large values must remain readable without page-wide overflow or
loss of the underlying quantity.

Keep a small, static SVG trend with an accessible name/description, understandable
date bounds and an accessible daily-values table. Use the same series for the
chart and table; the table can use a keyboard-operable native disclosure. Values
must not require pointer hover, a tooltip or color discrimination to understand.
No chart library, zoom, forecasting, percentage-change claims or real-time chart
interaction is added.

### Breakdowns and environmental estimates

Keep the current top-five model breakdown and usage-type breakdown, clearly
labeled as lifetime data. Preserve every currently supplied row, quantity,
per-model energy value and actual fallback indicator. Bars supplement the text;
they do not replace exact values or imply the five models are the complete model
catalog. Long model names wrap instead of being available only through truncation
or hover.

Environmental values retain the existing top-five model plus embedding-energy
policy, units, precision, coefficients and CO2 conversion. This is not a repair
of estimation algorithms, counter drift, coverage or historical records. Label
energy/CO2 as **estimates**, not measured consumption, billing, savings or proof
of environmental impact. Do not give lifetime estimates the recent chart's
period label.

Keep a short estimate caveat visible alongside the values. Show fallback status
only when the existing data reports it, with text explaining its meaning rather
than relying on an unexplained asterisk or color alone. The full methodology
disclosure retains existing sources/links, lifecycle and measurement caveats,
dataset snapshot information and fallback explanation. Do not discard that
content to shorten the page.

## Architecture and data flow

Reuse the current Rails/Hotwire, Importmap, Tailwind and static-SVG stack. The
responsibilities are deliberately narrow:

| Unit | Input and responsibility | Boundary |
| --- | --- | --- |
| Existing controller/scoping | Resolve the authorized global membership set or explicit URL account | No new permissions, account preferences or report routes |
| Existing reporting paths | Supply current recent/lifetime data and estimates | Keep `TokenUsage::Report`, account calculations and estimation policy intact |
| Token usage workspace partials | Arrange supplied data, scope, periods, rail and disclosures | Own report-page presentation rather than changing the dashboard's layout |
| Shared header and numeric chart helper | Render explicit locals and numeric series | Preserve Sources/dashboard consumers; no ambient-account guessing |
| Scoped lifetime fragments | Cache eligible lifetime presentation with existing account/locale/counter identity | Never reuse account fragments across unauthorized scopes |

Leave the dashboard's overview presentation unchanged. Avoid indiscriminate
changes to shared partials consumed by dashboard/account views; use focused report
presentation rather than introducing a new service or duplicating reporting
calculations in templates.

Scope new styles to the Token usage workspace rather than global heading,
statistic, chart or disclosure selectors. Reusing a helper must not change the
dashboard or Sources appearance, interaction, or markup contracts.

Read pages remain read-only: no ledger/counter/source/chat writes, enqueued jobs,
provider calls or new tracking. Do not add schema, packages, background work,
report endpoints, pricing, quotas, exports or unrelated refactoring.

## Freshness, empty states and errors

Normal navigation/reload reads the existing authorized reporting paths. Do not
introduce polling or promise live totals. Preserve account/locale isolation and
counter-based invalidation for lifetime fragments, with an updated presentation
cache version when markup changes. Keep recent activity, the daily table and
time-dependent period labels outside a lifetime-counter-only cached fragment;
they must not display an expired date window merely because counters are unchanged.
The global report remains uncached as in the current reporting path.

- Genuine no-usage data shows actual zero quantities and a clearly explained
  empty/flat trend. Do not fabricate growth, activity, savings or measurements.
- With no memberships, the global page remains a successful zero/empty report
  and offers the existing Accounts destination instead of requiring a default
  account. Methodology remains available.
- No recent activity does not imply zero lifetime use. Keep legitimate lifetime
  totals and breakdowns visible even when the recent series is empty/flat.
- Malformed, unauthorized or revoked scoped account context retains the existing
  404 response; it does not become another account's report or a setup page.
- Unexpected query failures use the existing application error path. Never catch
  them and present a successful zero report. A declared estimation fallback is
  distinct from a database failure.

## Accessibility and verification

Use semantic heading levels, labeled scope/periods, exact quantities and readable
units. Native daily-data and methodology disclosures must work with the keyboard
and expose their state. Decorative SVGs are hidden from assistive technology;
meaningful controls have visible/accessibly named text. Do not use structural
emoji or make static statistic cards look clickable.

Require at least 4.5:1 normal-text contrast and 3:1 meaningful non-text/control
contrast on rendered light/dark surfaces. Keep visible focus and at least 44px
targets for primary/disclosure actions on narrow screens. Test long names/values,
reduced motion and clearance above fixed mobile navigation, without hiding data.

Implementation uses Minitest/fixtures and failing tests before application edits.
The plan must verify:

1. Both route families, current-membership/global versus explicit-account scope,
   query-parameter forgery, revoked membership, malformed IDs and no default-account
   changes. Ambient tenant context and account cache isolation remain safe.
2. Existing recent/lifetime calculations and distinct period definitions, including
   boundary dates/times, global zero-filled days and all account query buckets.
   Chart, daily table, dates and visible quantities agree without changing queries.
3. Zero/no-membership/no-recent-but-lifetime-use states, truthful estimate and real
   fallback labels, complete model/kind/methodology content and read-only requests.
4. Locale/counter-based lifetime cache behavior and recent/date output refreshing
   independently, without cross-account fragment or stale-window leakage.
5. Dashboard metrics/presentation and Sources/unrelated navigation regressions,
   including preserved New chat access and unchanged drawers on unrelated pages.
6. Browser checks at 375px, tablet, desktop and narrow landscape; English/French,
   both themes, large values/long names, keyboard disclosures, visible focus,
   measured contrast and fixed-navigation clearance.

Use a dedicated test database and local/provider-free fixtures; do not run live
ingestion, provider or queue workers. Record actual focused/full/browser/lint/
scanner results and true exits. A fresh baseline must distinguish existing issues
from new regressions; previous Sources evidence is not a new verification claim
or a waiver of failures introduced here.

Native 200% browser zoom is separate manual evidence if available. Otherwise leave
it explicitly unverified; device metrics or CSS scaling are not substitutes.
Illustrative browser mockups are not application screenshots, contrast proof,
test results or a full manual accessibility audit.

## Design references

The consented local study is `token-usage-layout-options.html`, created in the
Sources worktree's ignored `.superpowers/brainstorm/964951-1792955045/` session.
It contains illustrative global-report values and a light/dark toggle, not live
data. It is not a required file in a clone; this written specification is
authoritative, including the distinct account-report presentation.

ui-ux-pro-max research verified responsive breakpoint testing, mobile-first
layout/grid spacing, and a line chart for a small daily series with a textual/table
alternative. Analytics-hierarchy/disclosure searches returned no verified
analytics-specific match after a retry; the existing dashboard supplies that
general hierarchy guidance. Unrelated chart libraries, hover/zoom interactions,
blue branding, alerts and forecasting recommendations were not adopted.

## Decisions

- User requested Token usage, Agent skills and MCP improvements following the
  dashboard using brainstorming and ui-ux-pro-max. The approved foundation orders
  delivery after Sources as Token usage → Agent skills → MCP.
  Rationale: independently reviewed subprojects rather than one oversized redesign.
- User answered **“Yes”** to a local visual companion for Token usage layouts and
  light/dark variants. Rationale: compare spatial arrangements before approval;
  companion consent is not implementation permission.
- User selected **“Overview first (Recommended)”**: totals, reporting scope and
  activity trend lead, with breakdowns and methodology secondary.
  Rationale: understand usage at a glance without losing detailed information.
- User answered **“A”**, also selecting A in the browser: **Overview + detail rail**.
  Rationale: emphasize the overview while keeping secondary lifetime information
  and environmental estimates visible, not hidden behind tabs.
- User answered **“Yes”** to design section 1: desktop overview/rail, mobile
  stacking, global/account scope and existing distinct time windows, shared
  navigation without unrelated drawers, and no new calculations, switcher or
  date filters. Rationale: consistent presentation without false period equivalence.
- User answered **“Yes”** to design section 2: exact locale-formatted metrics,
  static SVG plus daily-values table, secondary lifetime/estimate information,
  top-five model and usage-type detail, fallback caveats and complete methodology.
  Rationale: preserve exact data, accessibility and estimation transparency.
- User answered **“Yes”** to design section 3: existing reporting paths and
  permissions, dashboard isolation, genuine empty states/404/error behavior,
  normal reload and safe cache freshness, plus the accessibility/verification
  design. Rationale: improve presentation without new capabilities or hidden
  changes to reporting, privacy or data integrity.

## Approval boundary and next step

All three design sections are approved in conversation. This specification must
now be committed, self-reviewed and reviewed by the user. Only after the user
approves the written specification may writing-plans create an implementation
plan. No Token usage application implementation, Agent skills/MCP redesign,
merge into main or push is authorized by this document.
