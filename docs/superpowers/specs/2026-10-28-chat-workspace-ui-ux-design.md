# Chat workspace UI/UX

Status: Written specification approved by the user (“Go”); implementation planning authorized. Implementation execution is a separate gate.

Date: 2026-10-28

## Goal

Improve `/chats/new` and `/chats/:id` following the signed-in dashboard UI/UX improvements, using brainstorming and ui-ux-pro-max research.

## Current project context

- The dashboard and redesigned workspace tools use a neutral/green palette, system typography, readable headings, rounded bordered surfaces, English/French localization, and light/dark themes.
- The new-chat page currently contains a bottom-aligned composer with no introductory heading. The saved-chat page has a scrollable transcript, token totals, composer, and MCP selection modal.
- Both pages currently retain the shared right-hand conversation-history navigation, unlike the dashboard and redesigned management workspaces.
- A shared composer already implements PDF attachment, Lexxy formatting, account selection for drafts, read-only saved-chat accounts, sources, skills, Tools, Send/Stop, and upload/submission safeguards. These existing behaviors are important design constraints, not an invitation to rewrite them.
- Existing response presentation includes message bubbles, streaming/reconnect recovery, generation phases, citations, reasoning disclosures, retryable errors, and token/environmental metadata.
- The scroll controller currently scrolls to the bottom on every observed transcript mutation; reading earlier messages during streaming is a potential workflow concern to discuss.
- The working tree contains unrelated modifications and untracked files. Do not include them in design commits or alter them for this task.

## Research notes

- Python 3.13.5 is available for the ui-ux-pro-max local search scripts.
- Initial design-system search (`AI chat workspace calm`) returned a marketing hero/CTA pattern, a purple/pink palette, and wellness fonts. Those results do not fit the existing product and are rejected rather than persisted as design guidance.
- A narrower `ux` search (`chat conversation streaming`) returned the AI Interaction / Streaming guideline: show incremental responses rather than a long spinner-only wait. This fits the existing streaming implementation; preserve that capability rather than adding an artificial typewriter effect.
- Focused `ux` searches verified visible focus, unobscured focused controls, and reduced-motion guidance as relevant to chat controls and overlays.
- Searches for reader-aware autoscroll, drawer focus return/trapping, and metadata disclosure did not return a directly applicable match after one narrower retry. Any specific recommendations for those interactions are general web UX guidance informed by the existing code, not verified dataset matches. Do not adopt irrelevant anchor-scroll or heading-balance results as chat guidance.

## Decisions

- User requested: “following the UI/UX improvements on the dashboard (/), improve /chats/new and /chats/:id with @ui-ux-pro-max”.
  Rationale: extend the established dashboard direction to the new and saved conversation experience.
- User answered **“Yes”** to the browser-based visual companion.
  Rationale: compare chat layouts and mockups visually before approving a design; this does not authorize application implementation.
- User selected **“Visual + workflow (Recommended)”**: match the dashboard and polish history navigation, scrolling, disclosures, and feedback while preserving existing capabilities.
  Rationale: address day-to-day chat usability as well as appearance without expanding the conversation feature set.
- User selected **“On demand (Recommended)”** for conversation history: give the conversation more space and open history from a clearly labeled button on desktop and mobile.
  Rationale: prioritize the active conversation without removing access to previous conversations.
- User selected **“A” — Focused conversation**, also selected in the browser comparison.
  Rationale: favor a calm new-chat introduction and a reading-first saved conversation, with secondary details disclosed on demand instead of dashboard-like information panels or a dense workbench.
- User answered **“Yes”** to design section 1 — layout and navigation, after viewing refined new/saved chat, dark mobile, and on-demand history mockups.
  Rationale: approve the centered new-chat introduction, compact saved-chat context, reading-first message layout, reachable composer, and accessible private history overlay while preserving the shared shell.
- User answered **“Yes”** to design section 2 — reading, details, and feedback.
  Rationale: approve reader-aware following with Latest message recovery, secondary metadata disclosures, restrained accessible generation feedback, visible Stop/Retry/errors, and preservation of the existing composer safeguards.
- User answered **“Yes”** to design section 3 — architecture and verification.
  Rationale: retain the existing Rails/Hotwire stack and live-update contracts, keep components focused, enforce personal membership-aware history, and verify the redesigned flows with isolated tests and responsive/accessibility checks before claiming completion.
- User answered **“Go”** after being asked to review the finalized written specification committed as `7ce92e4`.
  Rationale: approve the written specification and proceed to writing the implementation plan; this does not choose an execution method or authorize skipping implementation prerequisites.
- During Task 6 review, user explicitly selected **“Keep Turbo (Recommended)”**.
  This narrowly qualifies the focus guarantees below: standard Turbo's outer ID-based focus preservation may reclaim an ID-bearing disclosure summary when a live replacement races a deliberate focus move in the same frame, including when the newly focused control is removed. Accept that upstream race only; do not claim it is fixed by application code.
  Preserve independent disclosure open/closed state, normal lost-summary focus across replacement/morph, and application-owned guards against overriding connected intentional focus, another modal, deleted answers, closed dialogs, or navigation to another chat. Hidden-tab update delays are not accepted: remove application RAF gates, timing workarounds, and native-focus classification.
  Retain the standard Turbo dependency and delivery path. No vendored Turbo fork, dependency change, custom delivery integration, or global focus monkeypatch is authorized. Record the race as a reproducible characterization alongside strict application-restorer tests; SPEC must review this amended contract before QUALITY. Task 7/8 documentation remains deferred.

## Selected approach

**A — Focused conversation** is selected. Alternatives presented were **B — Structured workspace** (stronger panel boundaries and more visible usage) and **C — Compact workbench** (tighter spacing and more visible exchanges). The user approved all three design sections and then approved the finalized written specification in `7ce92e4` with “Go”.

## Scope and non-goals

Deliver this as one focused chat-experience project covering `/chats/new`, `/chats/:id`, their message/detail presentation, on-demand history, and the accessibility of existing chat overlays. Preserve the dashboard's existing composer experience and unrelated workspace navigation when touching shared partials or styles.

Do not add conversation naming, editing, branching, sharing, search, prompt suggestions, new attachment types, model/provider settings, global account preferences, usage calculations, database tables, routes, or new generation/retry/cancellation protocols. Do not add polling beyond the existing reconnect mechanism. No application implementation is part of this specification-writing change.

## Approved design section 1 — Layout and navigation

Status: Approved by the user.

- Keep the shared application header and left navigation. Restrict the redesigned chat shell and on-demand history treatment to `/chats/new` and `/chats/:id`.
- New chat: a centered, modest introduction above the existing composer, with one clear heading and concise guidance about questions, PDFs, and account sources. Do not add prompt templates, suggestion chips, a duplicate source uploader, or dashboard reporting panels.
- Saved chat: a compact header with the existing first-question-derived conversation title (a localized fallback if blank), account name, History, and New chat. Render titles as escaped plain-text previews, at most 120 characters including the ellipsis, following dashboard recents; full question content remains available in the transcript. Treat the title as display text, not a new persisted naming capability. Keep the title as the page's single h1, not a heading on every history item.
- Use a centered reading column, comfortable message spacing, neutral assistant surfaces, and a restrained green user surface. Keep broad content such as code and tables scrollable within its own container, not the whole page.
- Keep the saved-chat composer at the bottom of the chat layout without covering the transcript. Avoid competing page/transcript scroll containers. At narrow or short viewports, reflow controls and accommodate composer expansion so messages and controls remain reachable rather than relying on the current hard-coded viewport-height subtraction.
- History is a labeled overlay/drawer, closed by default on desktop and mobile. Show the user's existing root conversations in current account memberships, ordered by recent activity with the existing stable ID tie-breaker, with plain-text title previews, account, activity time, active-conversation state, and existing confirmed deletion. Do not expose other users' chats or revoked memberships. Display a localized empty state when there are no accessible conversations. Opening a conversation uses its existing route; deletion retains the current authorization, confirmation, and redirect behavior. New chat retains its existing default-account behavior; do not introduce persistent account selection. No new search, grouping, history-loading API, or persistence of drawer state.
- Opening history moves focus into it, keeps keyboard navigation inside while modal, supports Escape and a named Close control, and restores focus to History on dismissal. Background controls are inert while open. Navigation continues to use the existing authorization checks.
- Preserve system typography, neutral/green colors, English/French, and light/dark themes. Keep History and New chat visibly labeled at narrow widths; controls wrap instead of squeezing the editor.

## Approved design section 2 — Reading, details, and feedback

Status: Approved by the user.

- Reader-aware scrolling replaces unconditional mutation-driven scrolling. On first opening a saved conversation, start at the latest message. Being at the bottom means within 80 CSS pixels of the transcript's end before an update. Scrolling farther away pauses following; manually returning to the bottom resumes it. While paused, new messages/deltas below the viewport reveal a labeled Latest message control; it returns to the bottom and resumes following. Only a successfully submitted own follow-up resumes following automatically; failed/blocked submissions do not move the reader. Incoming messages never move keyboard focus. Use immediate positioning for incremental streaming instead of repeated smooth animations; reduced motion also disables any optional navigation animation. Turbo morph/reconnect must retain the reader's position and follow/paused intent rather than treating a refresh as a new first visit. A full browser reload may start at the latest message; no persistent reading-position preference is added.
- Keep incremental streaming and the existing preparing/indexing/searching/retrieving/generating/tool/thinking states. Present the active state as concise text with a restrained optional indicator, not a spinner-only wait or new percentage/timer. Announce meaningful phase changes and completion politely, not every streamed token; make errors perceivable without relying on color.
- Keep Sources and Reasoning as independent, initially collapsed disclosures with clear text labels and source counts. Preserve citations, existing source links, tool-call content, and saved reasoning. Do not generate new explanations or change provider behavior.
- Move existing per-response token/environmental values into an initially collapsed Response details disclosure, still shown only when the existing finalized-message/token conditions apply. Put the existing chat input/output totals, kind breakdown, and environmental estimates in an initially collapsed Usage details disclosure near the saved-chat header. Retain every existing value, estimation/fallback qualification, and live update; change presentation, not accounting. Label environmental values as estimates and expose fallback explanations as readable text, not only a tooltip or asterisk. Use named Input/Output labels instead of unexplained arrows and readable text instead of tiny badges.
- Keep Stop reachable while generating and preserve the existing post-stop partial-answer and composer-unlock behavior. Keep retryable errors visible in the transcript with the existing Retry action; do not hide recovery actions inside Sources, Reasoning, or usage disclosures. Do not introduce a new retry/cancellation protocol.
- Preserve the shared composer and all current account/source/PDF/skill/Tools/formatting/keyboard/submission safeguards. Draft account selection remains membership-only; saved-chat accounts remain read-only. Opening and closing History or a disclosure must not submit, reset, or replace the draft editor.
- Existing source/upload/validation failures remain visible beside the composer and continue to block Send where required. Retain user-entered content according to current safeguards; do not imply a browser file selection or secret can be restored. On a no-membership new-chat page, show clear account-setup guidance rather than a nonfunctional composer.

## Approved design section 3 — Architecture and verification

Status: Approved by the user.

### Implementation boundaries

- Stay with Rails ERB partials, scoped Tailwind/CSS, Turbo, and small focused Stimulus behavior. Reuse dashboard/workspace tokens and the existing shared composer. No new frontend framework, package installation, schema, generation backend, or conversation capability.
- Separate the chat page shell/header, on-demand history presentation, response/detail presentation, and reader-aware scrolling. The shell composes these units; history owns only its overlay lifecycle; scrolling owns only follow/paused presentation state. Existing composer/source/account controllers continue to own editing, uploads, account changes, and submission.
- Use `Current.user.recent_conversations` and `Chat.first_questions_for` for membership-aware personal history and batched title loading rather than global/account-wide chat access or per-row title lookups. Do not alter these helpers' dashboard reporting/recents behavior. Saved-chat routes and actions retain their current ownership and membership checks. Keep unrelated pages' history navigation unchanged.
- Preserve message-ordering containers, streaming target IDs, localized stream subscriptions, in-progress reconstruction, and background composer replacement. The existing chat totals target can move into the header's Usage details content, but remains a single target for the same broadcasts. Keep disclosure triggers stable when their content updates so routine streaming/totals refreshes do not unexpectedly close them or steal focus.
- Data flow remains: authorized request renders chat/account/messages; the existing composer submits through the existing controllers/jobs; existing Turbo broadcasts update messages, phases, totals, and the composer. Reader-follow state affects only viewport behavior, never message persistence or generation state.
- History and saved-chat Tools/MCP overlays must have labels, named close controls, keyboard containment, Escape, focus restoration, and inert backgrounds while modal. They must not overlap as competing active modal layers. Improve only the accessibility/layout needed for these existing chat flows, not MCP management capabilities.

### Accessibility and responsive acceptance

- Use one meaningful page heading, labeled navigation/regions, visible focus, text labels for state, and correctly associated disclosures. Hide decorative icons from assistive technology and provide accessible names for icon-only actions.
- Verify normal text contrast of at least 4.5:1 and meaningful non-text controls/state indicators at least 3:1 in both themes. Avoid color-only status and tooltip-only explanations of usage estimates. Aim for 44 CSS-pixel targets on new page/history controls; preserve the shared composer's established behavior and audit its reachability rather than importing native-mobile sizing units.
- Check 375px, 768px, and desktop widths, a short/landscape viewport, long content/account names, English/French, light/dark, and reduced motion. No page-wide horizontal overflow; transcript, expanding editor, History, and Tools stay reachable and keyboard focus remains unobscured. Permit local horizontal scrolling for code/tables.
- Verify native 200% browser zoom separately where available. Do not present device scaling, a reduced viewport, or CSS zoom as equivalent; document unavailable checks explicitly.

### Test strategy

- Follow failing-test-first Minitest with fixtures. Add focused request/render coverage for page hierarchy, single composer/stream targets, localized empty/error states, detail values, private history and revoked-membership exclusion, and authorized actions.
- Add browser coverage for reader-follow pause/resume, Latest message, outgoing follow-up, streaming/morph/reconnect, disclosures remaining usable during live updates, modal focus/Escape/return, and draft preservation when opening/closing History. Exercise Stop, partial-answer retention, Retry, and generation unlock without a live provider.
- Re-run the existing composer, account selection/access/source/tools/citations, waiting/reconnect, dashboard, and affected workspace navigation regressions. Preserve test coverage rather than weakening selectors/assertions to conceal a regression.
- Use isolated test databases and run database-sharing suites sequentially. Use deterministic fixtures and simulated broadcasts; do not start live AI/MCP/ingestion workers, alter development data, or install/change browser-driver packages for verification.
- Build the existing Ruby-native Tailwind assets; run relevant tests/lint/security checks and compare pre-existing failures separately. Inspect screenshots for both chat pages in light/dark desktop/mobile states, History, metadata, generation, and errors. Report commands, outcomes, and verification limitations honestly; automated checks are not a complete human accessibility audit.

## Approval and delivery gates

The user approved the selected approach, all three design sections, and the finalized written specification. writing-plans has been invoked. Save and self-review a focused implementation plan, then ask the user to choose execution. Do not treat design or planning approval as permission to skip test-first execution or baseline checks.

The implementation plan must identify exact files, failing-test-first tasks, verification commands, shared-component regression coverage, and review checkpoints. Implementation remains a later gated phase; this document does not claim tests have run or the UI has changed.
