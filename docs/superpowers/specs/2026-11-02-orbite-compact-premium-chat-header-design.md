# Orbite compact premium chat header

Status: APPROVED — the user reviewed and approved this written scope on
2026-11-02. An implementation plan is required before premium code edits.

Date: 2026-11-02

## Goal and context

Make the saved conversation's `.n-chat-header` more compact and refined while
keeping every existing accounting value and explanatory note directly visible.
The selected direction is **B — a simplified structured band with one global
input/output distribution bar**, replacing the visual table, not its information.
Retain Orbite's restrained green palette, system font and light/dark identity.

The current header already omits Home and History and retains New chat, title,
account and live Usage. That removal and preceding History work are uncommitted
and paused; preserve them and the five existing documentation drafts. This is a
bounded presentation amendment, not a new generation, accounting or quota system.

This amends the [header-removal plan](../plans/2026-11-02-orbite-chat-header-without-home-history.md)
and only the header-specific preview/recovery boundaries of the
[History density design](2026-10-31-orbite-history-density-design.md), not the
History list itself.

## Decisions

- User: “améliore l'UI/UX du header (n-chat-header) de
  @app/views/chats/_header.html.erb par du premium”. Rationale: improve the chat
  header, not redesign unrelated workspaces.
- User: “Oui*” to the browser visual companion. Rationale: compare mockups before
  choosing a direction; mockups are not application verification.
- User: “Plus compact”. Rationale: give the conversation more room, rather than
  enlarge the header into an analytics dashboard.
- User: “Tout garder visible” after being offered collapsible Usage details.
  Rationale: compact the arrangement, not hide the table's data, estimates or
  explanatory content behind an accordion.
- User: “B en simplifiant encore plus, peut-être avec une / des jauges plutôt
  qu'un tableau pour illustrer la consommation en jetons / tokens ?”. Rationale:
  retain the subtle band, simplify its content and replace tabular presentation
  with a clearer visual representation.
- User: “Une barre globale (Recommended)”. Rationale: one input/output
  distribution is more compact than one gauge for each usage kind.
- User: “Oui” to the revised B mockup; companion selection also recorded
  “Cette version B me convient”. Rationale: approve that visual direction,
  including visible per-kind lines, full account once in Usage and the single
  distribution bar. Written-spec review remains a separate gate.
- User: “Oui” after being asked to review this committed specification at
  `25432fc`. Rationale: approve the written scope and proceed to implementation
  planning; this does not waive test-first execution or source preservation.

## Selected visual design

### Identity and action

Keep the saved conversation's semantic `h1` and existing New chat link in a
compact row. The title remains the unchanged `chat_workspace_title` preview:
single-line visual ellipsis where necessary, the existing 120-character helper
bound and localized fallback, and the full original question in the transcript.
Do not add a renaming control or make native hover the sole full-value recovery.

Show the **full account name once within the header context**, in Usage beneath
the title. Remove the duplicate clipped toolbar account preview. The complete
account must remain visible, wrap even for unspaced names and be available to
keyboard/touch users without a tooltip or another control.

New chat keeps its existing route, localized text, native link behavior, at least
44×44px target and visible focus. Home and History stay absent from the
header; no share, settings, menu, quota or decorative status action is added.
New/no-account chats do not acquire an empty decorative band or fake metrics.

### One compact Usage band

Use a subtle Orbite-toned surface with restrained rounding and spacing, not
separate cards for individual metrics. Retain the labelled Usage section and its
existing `chat-usage-details` and `chat-usage-summary` identities.

The token group contains:

- Exact localized **Input / Output** counters, visibly labelled.
- A clearly named **Total tokens**, the sum of those same two displayed counters.
- One thin horizontal bar showing the input/output shares of that total.
- Visible ordinary lines for every recorded usage kind, each retaining its
  exact input **and** output value, including zero. Replace the visual table with
  meaningful list/definition semantics, not anonymous chart-only marks.

Alongside it on sufficiently wide screens, retain the complete environmental
estimate label, energy in kWh, CO₂e in grams and the current normal/fallback
method note. Stack these groups on narrow screens. Keep all actual kinds and
explanatory text; do not shorten the data to match the mockup's sample rows.

The full account, counts and notes are readable without expansion, hover,
horizontal page scrolling or interaction with the bar. Keep readable typography
and 44px action targets; do not manufacture compactness by shrinking text.

### What the bar means

This is **composition, not progress or capacity**:

- For positive total `T = input + output`, shares are `input / T` and
  `output / T`, using those exact current counters.
- No budget, quota, remaining-token count, model context limit, invented maximum,
  threshold warning or “percentage consumed” is introduced.
- At zero total, show zero counters, the localized empty-use explanation and a
  neutral unfilled bar. Avoid division by zero or a misleading filled gauge.
- Input-only/output-only data produces the corresponding single filled segment;
  do not invent a minimum visible share for a zero category.
- Exact numbers stay visible; do not replace them with rounded K/M abbreviations
  or values available only on hover. The bar need not display percentages.

The bar repeats the labelled numeric data and can be hidden from accessibility
APIs. It is not focusable and must not use `progressbar` semantics. Labels and a
non-color distinction supplement the segment colors; no circular chart, canvas,
chart library, tooltip or additional keyboard stop is needed.

## Architecture and data flow

Retain Rails-rendered HTML and scoped Orbite CSS. Expected production touchpoints
are `app/views/chats/_header.html.erb`,
`app/views/chats/_token_totals.html.erb`, header-scoped rules in
`app/assets/stylesheets/nosia/orbite_chat.css` and any necessary EN/FR labels.
The implementation plan must enumerate coupled tests and documentation explicitly.
Do not add a service, controller, model API, dependency or JavaScript state owner.

Keep `dom_id(chat, :token_totals)` as the existing live replacement root. The
current `TokenUsage#broadcast_token_totals` continues to replace that partial;
each render updates counts, proportions, kind lines and estimates together.
Retain the existing locale/account scoping and useful total/kind data hooks.
No new request, polling timer, stream transport or token-by-token accounting
promise is introduced.

Use the existing cached input/output counters and `Chat#token_totals_by_kind`
as they are used today. Presentation must not recount persisted usage, reconcile
cached counters with the kind breakdown or change the source of accounting
truth. Energy/CO₂e arithmetic, precision and fallback selection stay unchanged.
Only the displayed aggregate sum and its visual proportions are presentation
arithmetic, not a new charge, limit or recorded metric.

## Responsive behavior, errors and accessibility

The band remains inside the existing reading surface and scrolls away with
context. It is not sticky and has no arbitrary fixed/clipping height. Names,
kind labels, localized numbers and notes may wrap; compactness is a layout goal,
not a fixed-height promise for unlimited data or enlarged text.

Preserve the existing single reader, reserved composer and navigation/modal
owners. Header growth and live replacements must retain the 80px pre-growth
following rule, paused paragraph's ±1px anchor, genuine-content Latest behavior
and own-success-only resume. Do not compensate for a test failure by editing
reader algorithms, moving focus, forcing scroll or weakening its oracle.

Use semantic heading/context/list markup, both EN/FR locales and both themes.
Maintain readable normal-text contrast of at least 4.5:1, meaningful graphical
contrast of at least 3:1 and visible focus of at least 2px on real controls.
Respect reduced motion; no animated consumption meter is necessary.

There is no new network operation or error lifecycle. Keep existing errors,
generation authority, reconnection/recovery and busy/stopped presentation.
Do not replace unavailable provider information with fabricated limits or new
status claims, or introduce another live region announcing every token.

## Explicit supersession and preserved boundaries

This approved design direction proposes superseding only these presentation
contracts after written-spec approval and planning:

1. The duplicated toolbar account preview: show the full account once in Usage.
2. The Usage table: show every kind's input/output as visible semantic lines.
3. The prior byte-frozen token partial's **presentation markup**, to add the
   total/distribution and line layout while retaining its live root and values.
4. Header-scoped CSS and necessary localized labels/coupled test selectors.

It does **not** supersede full information visibility, account isolation,
escaping, root-conversation History, removed deletion/Home/History UI, external
mobile navigation, live accounting correctness or any backend authorization.
Do not restore old table assertions by hiding a duplicate table in the DOM.

All production JavaScript, routes, models, jobs, schema, fixtures, runtime config,
dependencies, composer/dock and message rendering stay unchanged for this
amendment. PDF bytes, source guards, Formatting, Tools, streaming, Stop/Retry,
native drafts and the reader/focus invariants remain protected. Existing five
documentation drafts and unfinished code changes must be preserved, not reset.

## Verification required after planning

Write meaningful failing Minitest coverage for the new presentation before
production edits. Migrate only the superseded account/table/header selectors;
preserve numeric, accounting, privacy and genuine native-input assertions.

Verify exact input/output/total and per-kind values for empty, mixed-kind,
single-sided and large-count cases; full normal/fallback notes and precision;
correct proportions and zero handling; one full account, no table/accordion,
one live root and no additional focus stop. Exercise the actual localized
TokenUsage replacement, not synthetic client-side counter updates.

Check EN/FR, light/dark, reduced motion, long/unspaced account and title values,
and 375×812, 768×1024, 1400×1000 and 812×375 CSS viewports. Verify no overlap or
hidden information, real New chat target/focus, context scrolling away, paused
anchors and native keyboard/resize/recovery. Run the full affected native reader
and draft selections under the reviewed isolated local environment.

Record actual same-fixture header/transcript geometry before/after any new
height-reduction claim. Mockup dimensions, shorter sample notes or historical
pre-header results are not proof. Retain raw true exits, seeds, current-source
bindings and inspected original screenshots. Unexpected failures stop execution;
no tolerance change or green-subset substitution is authorized.

No live providers/workers, queue drains, unrestricted suite, DB setup/DDL,
dependency installation, environment disclosure or development-process control.
Do not rerun completed historical work merely to recreate lost evidence. Native
zoom, screen readers and physical-device checks remain NOT RUN unless separately
performed. Known scoped warnings/limits are not a security-clean claim.

## Design record and next gate

The approved visual reference is the external local companion screen
`header-b-single-distribution.html` under
`/tmp/opencode/orbite-header-premium-20261102/screens/`. Its counts/account are
synthetic examples, not stored accounting or native application evidence.
The specification above, not a temporary companion's lifetime, defines scope.

The previous implementation stays paused and uncommitted; no premium
application/test edit or application gate has been performed during design.
The user has reviewed and approved this committed written scope; writing-plans
is now active. Do not bypass the implementation plan, stage existing code or
integrate/push/open a PR automatically.
