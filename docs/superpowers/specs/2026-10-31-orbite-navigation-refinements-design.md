# Orbite navigation refinements

Status: APPROVED — the user approved this written scope on 2026-10-31.

Date: 2026-10-31

## Context

This amends the approved Orbite design before final verification. Task 7 is paused;
its five documentation drafts and existing evidence must be preserved. Earlier
test and security results do not establish acceptance of these new changes.

## Approved design

### Useful context below the page title

Remove the `n-header-details` accordion presentation. Useful context appears
directly below the corresponding `h1`, with restrained typography and wrapping.
Keep account, role, scope, useful breadcrumb/return links and accounting data.
Remove descriptions that merely repeat the title or instructions already visible
next to the relevant control. Retain unique operational or safety guidance.

This includes chat Usage: retain its live totals, per-kind table, estimates,
explanatory notes and broadcast identity, but display them without a header
accordion. Do not remove accounting or introduce another hidden details panel.
Sources, Reasoning, response details and native editor formatting are not part
of this accordion removal.

Context remains in the existing reading/content surface and scrolls away; it
must not create a fixed header, cover messages or displace the reserved composer.

### Lean History panel

Remove the duplicated logo and the visible `n-orbite-panel-heading` header.
Retain the localized Navigation heading as visually hidden text and preserve the
dialog's accessible name through its heading reference.

Keep an independently reachable icon-only close button in the upper-right corner.
Its cross is decorative; its localized accessible name remains Close/Fermer.
Preserve Escape dismissal, native modal behavior and current-opener focus return.

Use a trash icon instead of the visible Delete chat text. Retain the localized
accessible name, native confirmed deletion, correct conversation target and
authorization. Remove the visible Current conversation annotation; keep
`aria-current="page"` on the active link and its visual highlight.

Give the highlighted link real horizontal and vertical padding, so its text never
touches the background edge. Keep long titles, account/date context and the delete
action readable and nonoverlapping. Icon hit targets remain at least 44 by 44 CSS
pixels with visible keyboard focus in both themes.

### Direct rail user menu

At widths where the rail is visible, clicking its bottom-left
`workspace-utilities-trigger` opens the existing user-menu actions immediately,
above that same button. It must not first open History or move focus to the
inner `dropdownUser` button. Keep Profile, Settings and Sign out destinations and
semantics unchanged.

Position the menu against the actual invoking rail button, constrained to the
viewport and clear of rail scrolling/clipping. Native keyboard activation,
Escape, outside dismissal, correct expanded state and focus return must work.
Do not add a second modal/focus owner or duplicate interactive IDs.

Below the rail breakpoint, retain a reachable user-menu entry within mobile
navigation and anchor its menu to the visible mobile trigger. Language and theme
remain reachable through the navigation utilities; this change does not remove
or duplicate those native preferences.

## Preserved boundaries

- EN/FR, light/dark themes, reduced motion and readable long labels.
- Membership-scoped personal root History, escaped previews and confirmed deletion.
- Existing routes, authorization, source/account guards and generation accounting.
- Single reading surface and separately reserved native composer.
- Real PDF uploads, native formatting, Send/Stop/Retry and authoritative worker state.
- The 80px pre-growth follow policy, 1px paused-paragraph tolerance and genuine Latest.
- Same-chat native draft preservation, cancellation and source-bearing exclusions.
- User-owned environment and development processes; no live providers/workers.

## Verification and sequencing

Amend the implementation plan only after the written design is approved. Write
and run targeted tests before changing production behavior. Migrate tests coupled
to the superseded header accordion and visible labels without dropping their
underlying accounting, scope, keyboard, focus or reader protections.

Verify the direct user menu with History both expanded and collapsed, on chat and
non-chat pages, and verify the mobile fallback. Check icon names, target sizes,
contrast, padding, hit tests, long labels, modal naming and native focus recovery.
Exercise the compact landscape viewport as well as mobile, tablet and desktop.

Use independent SPEC then QUALITY reviews. Refresh Task 7 documentation, source
bindings, security comparison and final safe test selections after these changes.
Existing Brakeman recovery evidence remains historical evidence for its exact
source, not a pass for future amendments. Do not merge, push or open a PR.

## Decisions

- User: replace `n-header-details` accordions with useful text beneath `h1`, or
  remove useless text. Rationale: reduce unnecessary interaction and visual noise.
- User: remove the duplicated History header logo and visible Navigation title,
  retaining the title for accessibility. Rationale: avoid redundant chrome.
- User: replace Fermer with a cross and Supprimer la conversation with a trash
  icon. Rationale: make secondary actions compact without losing accessible names.
- User: remove Conversation en cours because the current link is highlighted.
  Rationale: avoid repeating the same visible state; retain semantic currentness.
- User: add space inside the current History highlight. Rationale: improve legibility.
- User: open the user menu directly above the bottom-left rail trigger, not above
  its inner navigation-utilities trigger. Rationale: make the clicked control the
  immediate and correctly positioned opener.
- User approved: keep live Usage visible below the chat title rather than hiding or
  removing it. Rationale: accounting is useful context and must remain discoverable.
- User approved: keep language/theme utilities and the mobile user-menu entry reachable.
  Rationale: the rail change must not remove existing controls on smaller screens.
