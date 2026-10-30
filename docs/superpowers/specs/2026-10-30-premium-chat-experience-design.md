# Premium chat experience

Status: **Design sections approved; finalized specification awaiting user review before planning.**

Date: 2026-10-30

## Goal

Define **Orbite**, a substantially more polished experience for `/chats/:id`, with
a coherent shared application shell and a matching `/chats/new` entry point.
Translate the user's Apple reference into clarity, material restraint, typographic
precision and confident interaction—not a copied brand, decorative glass layers
or gratuitous animation. Prioritize conversation space and an always-accessible
composer while retaining the application's existing capabilities.

## Decisions

- User: “re-propose une nouvelle UI/UX polish haut de gamme pour les chats
  (/chats/:id) … avec @ui-ux-pro-max”.
  Rationale: start a new design exploration rather than integrate the previous
  approved branch immediately.
- User: “Tu peux décider de modifier le layout de fond pour toutes les pages
  avec par exemple une sidebar avec l'historique des chats … ChatGPT … Le Chat”.
  Rationale: permit a shared-shell exploration; the particular layout was then
  selected explicitly as Orbite below.
- User: “Soit créatif et propose du premium façon Apple.”
  Rationale: propose distinct, designed directions instead of minor spacing changes.
- User answered “Oui” to comparative browser mockups.
  Rationale: use a separate local visual companion to choose a direction before
  approving the detailed design or implementation.
- User: “C”, choosing **Orbite** from the three comparative mockups.
  Rationale: develop the application rail, separate history column and inset
  conversation canvas. This selected the direction before the subsequent design
  approvals, not a dark-only default or permission to implement.
- User selected “Toujours accessible (Recommended)” for the composer.
  Rationale: reserve a dedicated composer area at the bottom of the conversation
  panel, accessible during reading and never covering messages. This explicitly
  replaces the current in-flow composer placement for the proposed chat design.
- User answered “Oui” to the proposed Orbite shell/navigation section: shared
  application rail; collapsible desktop chat history; no permanently open history
  on other pages; initially collapsed history on tablet; one on-demand mobile
  navigation/history panel; no competing mobile bottom bar; both existing themes.
  Rationale: approve the overall information architecture before its visual finish
  and detailed interaction/verification contract.
- User answered “Oui” to Orbite's proposed visual finish: graphite/sage and
  chalk/mineral themes, system typography around 16px, open assistant prose,
  restrained user bubbles, sculpted native composer and discoverable metadata.
  Rationale: approve the visual language without adding product capabilities or
  treating prototype colors/dimensions as verified production measurements.
- User answered “Oui” to the final interaction/data/validation section: compact
  context scrolling with messages; a separately reserved composer; stable drafts
  and reader intent; native mobile navigation; unchanged private history,
  accounts, PDF, sources, streaming, Stop/Retry and accounting; isolated testing.
  Rationale: approve the functional design before finalizing this written spec.

These chat approvals authorize this specification, not application implementation.
The user must still review the finalized committed document before writing-plans.

## Existing baseline and boundaries

The starting application baseline is the preserved prior chat/header work on
`feat/chat-workspace-ui` at
`7189d6de425122120f3fb4d7090d16a9ebb88f11`; it has not been merged or published.
That baseline uses a compact scrolling global bar, an icon navigation rail,
private on-demand History, one application scroll surface and a flow composer.

Preserve membership/account isolation, private personal history, actual uploads,
composer safeguards, source/reasoning/usage access, streaming, Stop/Retry, token
accounting, localization, themes, accessible focus and the established reader
contracts unless an explicit design decision changes presentation behavior.
The user-owned environment and development processes remain untouched.

## Alternatives considered

Three visual directions were compared; the user selected **C — Orbite**:

1. **Atelier — initial recommendation, not selected:** an integrated application/history sidebar, open
   conversation canvas, restrained mineral/green surfaces and precision typography.
   Gains immediate access to recent conversations and a coherent shell; costs
   desktop width and requires a considered collapsed/mobile mode.
2. **Folio — not selected:** a compact navigation rail and a reading-first editorial conversation.
   Gains focus and room for long answers; history takes an extra gesture and the
   typography is more opinionated.
3. **Orbite — selected:** an application rail, separate history column and inset conversation
   canvas. Gains explicit hierarchy for intensive work; introduces more navigation
   density and a wider application-shell change.

Mockups use fictional content and call no application API. The approved decisions
and requirements below are authoritative; exploratory screenshots are visual
references, not literal pixel contracts or permission for additional features.
Desktop/mobile and light/dark previews do not establish production behavior or
accessibility verification.

## Composer decision

The composer remains accessible in its own bottom area of the conversation panel,
not as an overlay over messages. The transcript has the available reading area
above it. This changes the previous in-flow presentation, not generation,
submission, upload, account isolation or reader-follow semantics. Reading and
reflow ownership are defined in section 3 below and implemented by one reader owner.
Compact top headers must not regain the tall, permanently reserved space that
motivated the preceding amendment.

## Approved design section 1 — shell and navigation

- Shared slim application rail on signed-in pages; keep the existing destinations
  and native language/theme/profile/settings/logout capabilities.
- Desktop chat routes gain a separate collapsible personal-history column and an
  inset conversation canvas. Other pages share the visual shell without carrying
  a permanently open chat-history column or losing their existing actions.
- Replace duplicated global/chat header chrome with a single compact context row;
  preserve the product identity and directly readable account context. The top
  context must not recreate a tall pinned obstruction.
- On tablet, history is initially collapsed to protect reading width. On mobile,
  application navigation and history share an on-demand panel instead of two
  permanent columns or competing bottom navigation/composer overlays.
- Keep both themes and the user's existing theme preference. The selected dark
  Orbite screenshot does not imply a forced dark-only application.

### Scope and responsive composition

The shared signed-in shell is one presentation change, not independent chat,
account or administration feature work. All signed-in pages use the slim rail and
coherent inset content surface. Chat routes additionally render personal history;
other pages do not reserve a chat-history column. `/chats/new` shares the shell,
retaining its account picker and no-account setup guidance. Signed-out pages keep
their authentication behavior and accessible branding/language/theme controls;
they never render private history or account context.

| CSS viewport width | Application navigation | Chat history |
| --- | --- | --- |
| 1280px and wider | Persistent slim rail | In-layout column, initially open, collapsible |
| 768–1279px | Persistent slim rail | Initially closed; on-demand native modal panel |
| Below 768px | No permanent rail | One native modal containing app navigation and history on chat pages |

Use a roughly 64px rail and 240px history column as desktop composition targets,
not permission to shrink controls or create horizontal overflow. Closing desktop
history returns its space to the canvas. Crossing a breakpoint must not leave
hidden focused content, an inert page, duplicate interactive IDs or two competing
navigation panels. Existing open/closed intent survives same-page live updates;
fresh-page defaults follow the table. No new persisted sidebar preference is added.

### Navigation coverage

- Retain the existing Home/dashboard, New chat, Accounts, Sources, token usage,
  Settings and Profile destinations and existing sign-out method/confirmation
  behavior. Scoped page actions keep their existing account context and URLs.
- Place theme, native locale selection and profile/settings/logout access in the
  rail's utility/profile area and the mobile panel, with explicit accessible names.
  Controls must not become hover-only or depend on an unlabeled icon.
- Replace the old signed-in global bar, duplicate icon menu, mobile bottom pill and
  legacy chat-history drawers with this coherent navigation. This supersedes the
  old 49px global-bar/96px bottom-pill clearance arrangement for the replaced shell;
  it does not authorize deleting page-owned tools, administration actions or forms.
- API tokens, system prompts, agent skills, MCP, account administration and existing
  page breadcrumbs/back/actions remain reachable through their existing routes.
  This work adds no navigation capability or route and must inventory moved
  actions before removing their previous container.
- Provide a persistent navigation opener in the mobile chat composer's utility
  area so navigation remains reachable after the compact context has scrolled
  away. Other mobile pages retain an explicit navigation opener in their page
  chrome. No extra fixed bottom navigation competes with the composer.

## Approved design section 2 — materials, conversation and composer

- Graphite/sage dark surfaces and chalk/mineral light surfaces; green is a restrained
  brand accent, not a saturated wash. Distinguish shell, inset canvas and composer
  through tonal steps, fine decorative edges and a restrained ambient shadow.
- Use the system font stack, including platform-native typography when available;
  no remote font dependency or unlicensed platform font distribution. Target 16px
  conversation text, 1.6–1.75 line height and roughly 65–75 characters per line on
  desktop. Do not stretch prose across the whole available canvas.
- Small, directly readable title/account context. User messages use a quiet
  right-aligned filled surface; assistant answers read directly on the canvas,
  without a heavy card around every message or an invented display heading.
  Existing Markdown headings remain driven by actual response content.
- Sources with their count, Reasoning and response details stay discoverable and
  operable without hover. Usage retains its existing data and a compact entry.
- An approximately 18–20px rounded composer surface with a genuinely editable
  native editor. Its own bottom zone does not overlap messages. PDF, native
  Formatting, account context, Tools, Send and Stop retain existing capabilities;
  no duplicated toolbar or replacement upload/submission state machine.
- Preserve keyboard-visible focus, minimum 44px targets for the redesigned
  controls, text contrast at least 4.5:1 and meaningful icon/control contrast at
  least 3:1. Subtle short transitions must respect reduced motion; do not animate
  every streamed token or depend on heavy blur to establish hierarchy.

Prototype copy, identities and content remain fictional and are not new product
features. This finish does not add chat renaming, folders, pinning, global search,
sharing, model selection or changes to generated answer content.

## Approved design section 3 — interaction, data boundaries and validation

### Reading and input

- On chat routes, one primary reading surface contains the compact context row
  and transcript; its context scrolls away with the messages. The composer occupies
  a separate reserved bottom area of the canvas, not an overlay. A history list or
  bounded editor may scroll locally without becoming a second conversation owner.
- This intentionally replaces the former single application-wide outer scroller
  arrangement on chat routes so the approved composer can remain accessible.
  Other pages keep one clear page-content scroller with their headings in flow.
  Do not leave an empty header slot or restore duplicated top bars.
- Preserve 80px pre-growth follow intent, shared user/assistant paragraph anchors,
  Latest only for genuinely new content below, and successful-own-follow-up-only
  automatic resume. Sidebar reflow, native details, same-page morph and responsive
  changes must preserve the established input/geometry ownership distinctions.
- Long drafts scroll within the bounded native editor; native formatting and
  upload/status areas must not grow without bound or hide Send/Stop. Short screens
  and the on-screen keyboard must not turn the composer into a message overlay.
- Closing desktop history must keep an operable reopen trigger. Mobile navigation
  starts closed, uses native modal focus/inert behavior, dismisses with Escape or
  an explicit close control and returns focus to the appropriate current opener.
  Tools remains separately accessible with its established modal ownership.
- If the conversation has no usable account or editor is unavailable under an
  existing guard, show the existing guidance/disabled state rather than an active
  decorative composer. New-chat account selection and saved-chat fixed account
  behavior must not be conflated.

### Component and state boundaries

| Unit | Responsibility and inputs | Boundary |
| --- | --- | --- |
| Shared shell/navigation | Existing signed-in context and route helpers; rail, utility controls, inset page frame | No global chat-history query, generation state or composer coordination |
| Chat navigation | Existing authorized personal history and title-preview locals supplied on chat routes | One authoritative history dataset; current-item and deletion/confirmation semantics preserved |
| Conversation reading surface | Compact context, transcript and existing reader/disclosure/feedback behavior | One primary content scroller and measured reader owner; history/editor/dialog scrolling remains local |
| Composer zone | Existing explicit form/chat/account/source/upload/generation locals and native editor | Presentation and native delegation, not a replacement upload/submission state machine |
| Mobile navigation panel | The same authorized destinations/history plus native modal focus/inert behavior | No leaked hidden focus, duplicate editor, duplicate stream targets or competing modal owner |

Reuse the Rails/ERB, Turbo, Stimulus and importmap stack. New presentation markup
and focused navigation behavior are permitted; a new JavaScript framework,
bundler, service layer, dependency or parallel client-side business-state store is
not required or in scope. Existing public controller/model responsibilities and
authorization remain unchanged. Hidden responsive content must not duplicate the
authoritative composer or broadcast target identities.

### Data flow and failures

- Reuse existing personal membership-scoped root-chat history and existing title
  previews from the chat request context. Do not copy the legacy unscoped layout
  history query into the new shared shell. No other member's chat, child-chat
  leakage or cross-account content. Retain localized empty history, current-item
  indication, account/date context, bounded escaped first-question previews and
  the full question in the transcript. Preserve deletion authorization,
  confirmation and the existing redirect; do not introduce renaming or folders.
- The server remains authoritative for messages, account context, permissions,
  generation, usage and Stop. Existing Rails/Hotwire boundaries, broadcast target
  identities, localized streams and background-renderable explicit locals remain;
  no new API, persistence, generation protocol or competing UI state machine.
- Opening navigation, changing theme or opening details does not reset the draft
  editor or upload/submission state. Existing intentional navigation/account-reset
  confirmations and browser file-selection limits still apply.
- Preserve real phase feedback, partial answers on Stop, source/upload failures,
  blocked-send safeguards and Retry only when the existing hook allows it. Errors
  and required guidance remain visible outside collapsed decorative metadata.
- Preserve one stable polite status region and meaningful localized phase changes,
  not a live announcement per token. Read busy/stopped truth from the existing
  authoritative composer payload, including the reviewed uncached chat/account
  scoped freshness read for workers loaded before a remote Stop. Do not restore
  stale-root completion classification or change accounting calculations.
- Keep the documented narrow Turbo-native focus-restoration exception; do not
  promise all-orderings immunity, fork stream delivery or add timing gates that
  stall hidden-tab updates.

### Validation and acceptance

Validate English/French, both themes, desktop/tablet/mobile/short landscape, long
labels, open native formatting/details, modal focus and real pointer/keyboard
paths. Measure content/composer/control bounds, text and non-text contrast, visible
focus, 44px redesigned targets and the unchanged 1px paused-paragraph tolerance.
Protect actual uploads, source/account guards, streaming/morph, authoritative
cross-tab Stop feedback, native input/resize ordering and real Usage/new-content
overlaps rather than silently weakening the prior regressions.

Use isolated, sequential, explicitly safe test selections. No live providers,
MCP/crawl/index workers or unsafe unrestricted suite. Native browser zoom,
screen-reader operation, physical/mobile-keyboard behavior and live integration
checks must be reported separately if not actually performed. Existing accepted
login/security limitations remain scoped; no new failure or warning is waived.

| Acceptance area | Required evidence |
| --- | --- |
| Shared shell | All signed-in header/navigation families retain destinations, page actions and one meaningful h1 where one exists; signed-out controls remain available without private data |
| Responsive layout | EN/FR × both themes at 375×812, 768×1024, 1400×1000 and 812×375; breakpoint transitions; no document/canvas horizontal overflow or masked clipping |
| Reading/composer geometry | Exactly one primary conversation scroll owner; compact context scrolls away; composer remains in its own area; last message, long draft, upload/format controls and Send/Stop remain reachable |
| Reader behavior | Existing 80px pre-growth semantics and 1px paused-paragraph tolerance across user/assistant growth, history reflow, resize, details, native input, stream/morph and own-submit outcomes |
| Navigation and focus | Genuine native Tab/held Shift+Tab, Enter/Space, pointer activation, close/Escape, focus return after opener replacement and responsive/cache cleanup; no new focus-steal exception |
| Real safeguards | Actual upload bytes, source errors, account/URL race guards, Tools, partial Stop, eligible Retry, distinct-worker cross-tab unlock feedback and existing totals/target identity |
| Visual accessibility | Measured text ≥4.5:1; meaningful icon/control contrast ≥3:1; visible ≥2px keyboard focus; redesigned targets ≥44×44px; reduced-motion behavior and readable long labels |
| Evidence integrity | Actual commands, exits, source commits, screenshots inspected and static warning fingerprints; no fabricated full-suite, native-zoom, screen-reader, mobile-keyboard or live-provider pass |

Existing layout assertions tied specifically to the replaced outer scroller,
global bar, bottom pill or on-demand-only desktop history require intentional
contract migration. Preserve their safety/accessibility outcomes and all unrelated
behavioral cases; do not loosen reader, hit-testing or accounting assertions to
make the new layout pass. Follow test-first reproduction for new behavior and
regressions. Defer execution commands and task sequencing to the implementation
plan rather than treating this specification as permission to run tests now.

## Scope exclusions and retained limits

No schema, routes, authentication, permissions, generation protocol, accounting,
provider integration or new product capabilities are added. No remote fonts,
heavy animation library, custom Turbo receiver, polling workaround or hidden-tab
delivery gate is introduced. Do not expand prototype-only affordances into new
features or modify generated answer text.

The previous accepted narrow Turbo-native ID restoration race remains documented
in [Chat workspace](../../chat-workspace.md#sources-reasoning-and-usage). The
existing GET `/login` waiting-scaffold error, two accepted Brakeman baseline
warnings and unsafe unrestricted-suite limitation are not repairs in this UI
scope. Verify selected safe checks and warning fingerprints without running live
AI/MCP/crawl/index workers. User-owned `.env` files and running development
processes remain untouched.

## References and status

- Existing behavior: [Chat workspace](../../chat-workspace.md),
  [Chat composer](../../chat-composer.md),
  [Chat account selection](../../chat-account-selection.md).
- Prior presentation boundary intentionally superseded where stated above:
  [Compact headers](../../compact-headers.md).
- Visual exploration: `.superpowers/brainstorm/692705-1793349584/` (local ignored
  companion artifacts). The written requirements stand alone if those artifacts
  are unavailable. No prototype is a production verification result.

No application implementation, build, database operation or runtime suite has
been performed for this design finalization.

## Required next gates

The design sections are approved in chat. Commit and review this finalized
document, ask the user to review the written specification, and wait for explicit
approval. Only then invoke writing-plans to create the implementation plan. The
written-spec approval and subsequent implementation-plan/execution gates must not
be skipped; no merge, push, PR or cleanup is authorized automatically.
