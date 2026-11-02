# Orbite New Chat Action in History

Status: PLACEMENT APPROVED — AWAITING WRITTEN SPEC REVIEW.
The user requested the move and selected the shared-row placement. No relocation
code or test change is authorized until review of this written amendment and an
implementation plan. Date: 2026-11-02.

## Goal

Move the existing **New chat / Nouvelle conversation** action out of the saved
conversation header and into the top of `dialog#chat-history`. Put it on the
same row as Close: New chat on the left, Close on the right. This further
simplifies the chat header without removing the action.

## Approved presentation

- Remove the link and its now-empty actions container from the saved header.
  Keep the title, its existing120-character preview bound, the full account label
  in Usage, the passive token-distribution bar, all exact counts/per-kind values,
  environmental estimates and methodology/fallback notes unchanged.
- Add a compact action row at the top of History, before its scrollable content.
  Reuse the existing translated label, `new_chat_path` and `n-workspace-button`
  appearance. Do not add a second New chat action to the header.
- Keep the existing Close button, icon, identifier, accessible label, initial
  focus marker and close action. New chat and Close remain in one horizontal
  row; a long translated button label may wrap inside its own control.
- Preserve the current action's visibility scope: **saved chat pages only**.
  This is a move, not a new action on administration, account, no-account or
  new-conversation pages. Other existing account-specific New conversation
  links are outside scope and are not removed.
- The row is part of the existing dialog/panel structure, outside its existing
  scrolling list. Do not create a fixed overlay, new scrolling owner or additional
  focus controller. Without the New chat action, Close stays right-aligned.

## Interaction and accessibility

The URL, authorization, locale selection and navigation behavior of the original
link remain the same. No new route, controller, account-selection behavior,
confirmation, persistence or generation action is introduced.

The same dialog is inline History on wide screens and native modal History on
smaller screens. The relocated action must work in both presentations, in EN/FR,
light/dark,375px portrait and short landscape. Both controls retain44px minimum
targets, visible native keyboard focus and readable full labels. Keep existing
Escape, Close, focus containment and return-to-trigger behavior. Opening History
must preserve the unsent editor/draft; activating New chat retains ordinary
navigation semantics rather than inventing a new draft owner.

No Home/History controls return to the chat header. No History-item Delete
control returns. Backend routes/authorization and all earlier saved behavior stay
intact.

## Architecture and source boundaries

Expected production ownership is limited to:

- `app/views/chats/_header.html.erb`: remove the original action/container only.
- `app/views/application/_orbite_shell.html.erb`: existing shared History action
  row with the saved-chat condition; preserve Close and all shell/data actions.
- `app/assets/stylesheets/nosia/orbite_shell.css`: small scoped row/wrapping rules,
  preserving existing History density, rail containment, dialog modes and focus.

Do not redesign the premium band, change accounting/locales, add JavaScript,
modify the reader cache-geometry fix, alter dialog/navigation policy, change the
composer or introduce synthetic focusable controls. Existing header CSS may stay
unchanged if its removed-action selectors become unused; unrelated cleanup is
not part of this amendment.

Presentation-coupled request/native tests must be migrated atomically: the old
header-link assertion is replaced by absence in the header and exactly one action
in the saved chat's History row, with the same URL/label. Verify saved/new/non-chat/
no-account boundaries, actual native activation and the row's Close behavior.

Some reader/focus tests currently use the old header action as their native focus
target or geometry sampler. Replace only these obsolete targets/scenarios with
real existing transcript controls or genuine reader navigation, not fake controls,
tabindex additions, scripted focus or weakened scrolling/observer assertions.
The implementation plan must enumerate exact coupled changes before editing.
Preserve trusted Tab/Shift+Tab ownership across pending resize acknowledgments,
actual observer/frame ordering, following80px, paused anchors±1px, genuine Latest,
own-success-only resume, streaming, Stop/Retry and all draft/source/upload tests.
The six current permanent density units and rail-return regression remain intact.

## Verification requirements

1. Meaningful request/native failures for the new location before relocation code.
2. Saved header has no action; saved History has the one translated action on the
   same row as Close. Current visibility boundaries and URL stay unchanged.
3. Real keyboard/pointer activation and native Close/Escape/focus return in inline
   and modal modes; EN/FR, themes,375px and landscape targets/labels/overflow.
4. Complete visible Usage/account recovery and strict reader/draft guarantees
   despite the header no longer containing a focusable New chat action.
5. Fresh source-bound affected/full groups after the final amendment; independent
   SPEC followed by a different QUALITY reviewer. No automatic integration.

The earlier real16-context before baseline stays immutable and may be compared
to the final amended UI with the relocation declared. Do not recreate lost
History-density/security evidence or rerun old diagnostics for receipts. Actual
test counts, native originals and all known failures stay source-bound and honest.

## Preserved work and safe pause

The previous implementer is paused; no application command was active when this
steering arrived. No old-contract final gate, comparator, stage or code commit
followed the pause. Conditional27-path commit permission for that dispatch is
withdrawn pending the new plan; do not infer that adding this spec stages code.

Current HEAD is `0c771316c73e18e5a3195277eeb7d4a106ce63d8`, parent eeb9b921.
The four previously authorized punctuation changes are present: each EN/FR
estimate label includes its former literal colon and both call sites remove that
literal. This preserves output, but no punctuation build/final request/native/
localization gate has run on those bytes. The older failed request group remains
a failure, not a newly passing result.

Parent's fresh static pause checkpoint at
`/tmp/opencode/orbite-newrecovery-20261101-NLNQZUxq/new-chat-relocation-20261102-0d268f/pause-checkpoint.json`
verifies1105 source bindings (four exact punctuation deltas,1101 other entries
unchanged),11505 unchanged runtime entries and five unchanged D drafts. Actual
paired `relocation-pause-preservation.JrJ25Met` exit0 is static preservation only.
No relocation implementation or browser gate has run.

Preserve all pending code, the five documentation drafts and earlier approved
reader/localization fixes. No dotenv disclosure, process inspection/control,
DB setup/DDL, install, performed jobs/workers, live providers, unsafe unrestricted
suite, merge/push/PR or cleanup. Existing execution safety and review requirements
remain in force. Security-baseline provenance and broader final documentation/
whole-feature review remain separate pending work.

## Decisions

- User: “Déplace le bouton ‘Nouvelle conversation’ actuellement dans le header
  d’un chat … en haut de la dialog chat-history.” Rationale: relocate the existing
  action and free chat-header space, rather than remove the action.
- User selected **“Même ligne (Recommended)”** over **“Pleine largeur”** after being
  offered New chat left / Close right versus a separate full-width action.
  Rationale: keep the top of History compact on desktop and mobile.
- Preserve the existing label/style/URL and visibility conditions. Rationale:
  bounded relocation without unrelated account, navigation or draft changes.

## Review gate

Parent self-review checks complete scope, one-row placement, unchanged action
semantics and explicit strict-test migration constraints. User review of this
committed written amendment is still required before writing-plans or code.
