# Token usage workspace

The existing Token usage routes use the neutral/green workspace shared with
Sources. Reports are read-only and use normal navigation/reload, not live polling.

## Scope and periods

- `/token_usage` aggregates account-wide activity across your current memberships,
  including other members' activity. Its main overview uses the existing 30 local
  calendar dates: midnight 29 days before the reference date through request time,
  inclusive. Future records are excluded. The chart/table have 30 zero-filled days.
- `/accounts/:account_id/token_usage` requires current membership in the URL
  account. Its headline is lifetime input/output account counters. Its separate
  recent activity keeps the existing exclusive `created_at > 30.days.ago` cutoff
  and SQL `DATE(created_at)` grouping, with no added upper bound or zero filling.
  Every returned date bucket is displayed, including future buckets if present.
- Lifetime totals remain account counters, not a ledger recount. Model/type
  breakdowns remain lifetime ledger data; counter drift is not repaired here.
- Query parameters do not change report scope, authorization or the default
  account. Inaccessible/revoked/malformed account context retains the existing 404.

## Reading and navigation

The overview and activity lead. Desktop adds a secondary rail; mobile stacks the
same information without hiding metrics. Global lifetime counters appear in the
rail; account lifetime counters are not duplicated there. Model and usage-type
breakdowns follow, then the complete methodology disclosure.

The static SVG and keyboard-operable daily table use the same chronological data.
Quantities are exact and locale-formatted, not K/M abbreviations. Empty recent
activity does not erase lifetime usage. With no memberships, the global report
still succeeds with zero values and an Accounts link.

The report omits unrelated conversation drawers while retaining shared desktop
and mobile navigation. Scoped Back returns to the account hub. The global desktop
New chat link keeps its generic existing destination; viewing an account report
does not silently select that account for a new conversation.

## Environmental estimates

Energy and CO₂e are estimates, not measured consumption, billing or savings.
Preserve the existing top-five-model plus embedding-energy policy, coefficients,
six-decimal kWh and two-decimal gCO₂e. Actual fallback flags have readable labels
and the existing asterisk explanation; a zero report does not invent fallback.

The full methodology retains Ecologits/compar:IA links, ISO 14044/lifecycle and
measurement caveats, the Comparia dataset/license/snapshot (2 July 2026), and the
fallback explanation. No model-provider request is needed to read a report.

## Freshness and cache boundaries

Scoped lifetime headline/estimate/breakdown fragments use locale, explicit
account, input/output counters and `usage-workspace-v1` section identity. Recent
activity, its table and period/date labels are outside those fragments. Global
report rendering remains uncached. An unchanged counter does not freeze a rolling
activity window; this does not add a repair policy for out-of-band lifetime edits.

The dashboard's shared overview and legacy standalone summary partials are not
redesigned. Reporting queries, estimator algorithms, writes, jobs and permissions
are unchanged. Database failures remain errors, not successful zero reports.

## Verification

Use the dedicated test-database commands and task gates in the
[implementation plan](superpowers/plans/2026-10-25-token-usage-workspace-ui-ux.md).
New request/helper/cache/system tests cover both scopes, distinct periods, all
date buckets, exact values, empty states, content, read-only behavior and cache
isolation. Existing dashboard/Sources/composer/navigation suites remain guards.

The browser matrix exercises English/French, light/dark, 375px, tablet, desktop
and narrow landscape, long names/large values, native keyboard disclosures,
visible focus, measured contrast and fixed-nav clearance. Read the execution
record for actual counts, exits, screenshots opened and accepted baseline issues.
Viewport emulation is not native 200% zoom. Native zoom remains unverified unless
separately recorded, and these checks are not a full assistive-technology audit.

Agent skills and MCP are later independently approved subprojects. No new report
filters, dates, account switchers, quotas, billing, exports or forecasts are added.
