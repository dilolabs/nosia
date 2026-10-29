# Compact application and page headers

Status: Design approved in conversation; finalized written specification awaiting user review before implementation planning.

Date: 2026-10-29

## Goal

Give primary content substantially more vertical space by reducing both the global
Nosia bar and page headers throughout the application, not just on chat routes.

## Decisions

- User: “La taille du header est beaucoup trop importante d'autant plus qu'il est fixé au premier plan, j'ai besoin de beaucoup plus d'espace en hauteur pour le chat”.
  Rationale: prioritize conversation height rather than persistent header chrome.
- Asked whether the scope was the conversation header, the global Nosia bar, or both,
  the user answered: “Les deux en-têtes, sur toutes les pages et pas uniquement les pages de chat”.
  Rationale: apply the density improvement consistently across the application.
- User answered “Oui” to the proposed global 48px bar, compact title/actions,
  collapsed secondary information and headers scrolling with content instead of
  remaining fixed.
  Rationale: reclaim vertical space during reading throughout the application.

## Current context

- The global bar has a 64px minimum height and lives outside the content scroll area.
- The saved-chat header stacks navigation, a title, account context and Usage details
  outside the transcript, so its full height remains reserved during desktop reading.
- Shared workspace headers, dashboard and account headers use different templates;
  a chat-only CSS override would not meet the newly confirmed scope.
- Existing accessible controls, responsive behavior, language/theme/profile actions,
  account context, live usage targets and chat reading anchors must be preserved.

## Approved design

- Reduce the global bar to approximately 48px at normal text size, without forcing
  a clipped fixed height when labels wrap or text is enlarged. Preserve the logo,
  language selector, theme toggle and signed-in user menu with usable controls.
- Across shared workspaces, dashboard, account and chat pages, reduce heading
  margins and group the title and primary actions in a compact row when space
  permits. Wrap on narrow screens instead of clipping or shrinking controls.
- Collapse secondary descriptive/contextual information behind a named native
  disclosure where it currently adds permanent header rows. Keep required form
  guidance, errors, security context and primary actions directly visible.
- Both the global bar and page headers scroll out with their content. Do not keep
  an empty reserved header area above an independently scrolling content panel.
  Do not replace fixed headers with JavaScript auto-hide animations or timers.
- Retain one meaningful page h1. Long text must not force a permanently tall
  header; preserve access to full context without relying on hover-only tooltips.
- Preserve keyboard focus visibility, accessible control sizes, localization and
  both themes. Do not trade usable controls for smaller visual measurements.

## Layout and behavior boundaries

The layout must have a clear primary vertical content scroller on every page.
Place top headers in its scrolling flow rather than just removing CSS `fixed` or
`sticky` while leaving them outside that scroller. Local horizontal code/table
scrolling and bounded editor/dialog scrolling remain valid.

This amendment supersedes the prior unchanged-global-header boundary and any chat
scroll-container placement that would keep a header permanently reserved. It does
not change reader-follow semantics: retain the pre-growth 80px threshold, paused
paragraph anchors, Latest message and success-only own-follow-up resume. Adapt
scroll ownership to the actual new layout without introducing a competing owner.

Preserve composer safeguards and reachability, account isolation, History/Tools
modal ownership, localized broadcasts, message IDs/order, live totals targets,
disclosure state/focus and phase feedback. Do not change generation, accounting,
authentication, routes, schemas, dependencies or navigation capabilities. Existing
bottom navigation is outside this top-header request; preserve its clearance.

## Verification requirements

- Capture before/after header heights and usable content bounds at normal text
  size. Verify the global bar is approximately 48px and the chat gains vertical
  space without removing controls or meaningful information.
- Scroll enough content on chat, dashboard, shared workspace and account pages;
  assert both top headers move out of the viewport and no empty header slot remains.
- Check English/French and both themes at 375px, 768px, desktop and short landscape
  sizes. Verify wrapping, long titles, keyboard focus and modal/menu reachability.
- Re-run reader anchors/following, streaming/morph, composer/source/account guards,
  background unlock/Stop, disclosures, and affected global workspace regressions.
- Keep isolated, sequential test execution and retained true-exit evidence. Do not
  run live providers/workers or the known unsafe unrestricted test suite.
- Report native zoom and screen-reader checks separately; viewport emulation is
  not evidence of either. Retain the accepted narrow Turbo-native focus exception
  and existing baseline security/login-test limitations without broadening them.

## Boundaries and next gate

This is a new layout amendment to the chat-workspace work. No application changes
have been made for it. The user approved the design in conversation; review this
written specification next, then write the implementation plan before coding.

The separate background-Stop announcement correction at `8cc53f3` still awaits its
specification, quality and final-review follow-up. No merge, push, PR or cleanup
has been authorized. User-owned environment files and development processes remain
untouched.
