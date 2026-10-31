# Orbite premium History density

Status: FINAL DESIGN — user selected A with the refinements below; written-spec
review and implementation planning are still required before application changes.

Date: 2026-10-31

## Context

The user requests a more premium `chat-history` interface that shows more
conversations at the same screen height, using ui-ux-pro-max. This amends the
active Orbite feature before final acceptance. The five existing documentation
drafts remain unstaged and preserved. Refinement D has returned evidence, but its
parent audit, independent reviews and documentation commit remain pending.

The current inline panel is 240 CSS pixels wide. Its one-column row grid places
the 44px trash action below the title, account and date. The former text Delete
label no longer requires that separate full-width row.

## Selected design

### A — Editorial list, without introductory chrome

Use a compact two-column row: the conversation link and its context on the left,
and a separate nonshrinking trash button on the right. Retain the existing panel
width, Orbite palette, restrained dividers, current-link emphasis and comfortable
interior padding. Do not make text or hit targets smaller to achieve density.

Remove the visible History heading, “Historique des conversations” / “Conversation
history”, and the explanatory “Vos conversations…” / “Your conversations…” text.
Keep the existing hidden Navigation heading, dialog name and localized History
section accessible label. Do not remove the empty-state message or mobile
navigation links. The independent close cross remains reachable.

### Single-line titles with visual ellipsis

Every History title occupies at most one visual line. Apply CSS ellipsis only
when it exceeds its available width; fitting titles have no additional ellipsis.
Do not shorten the title string in Ruby or JavaScript. A shrinkable title area
and nonshrinking 44px action column prevent overlap.

Keep the complete existing display-title string in the link's DOM and expose it
through the native `title` attribute for pointer hover. Keyboard and touch users
can activate the ordinary link to open the conversation, where the existing
wrapping `h1` displays that same title without this History-only clipping. Native
hover text is supplementary, not the only way to recover the display title.
Do not add a custom tooltip, disclosure button, focus owner or new JavaScript.

“Complete display title” means the current `chat_workspace_title` result. That
helper already limits the preview to 120 characters. Its existing bound and
localized fallback remain unchanged; this work does not promise the entire first
message as a title.

### Single-line accounts and intact dates

Place the account and localized timestamp below the title, on a shared metadata
line where space permits. Account names also occupy at most one visual line,
using CSS ellipsis only when too long. Keep the complete account name in the DOM
and on its native `title` attribute. Activating the conversation link also makes
the existing full account name available in that conversation's wrapping header;
do not rely on pointer hover alone or introduce a custom tooltip.

Reserve space for the localized date rather than clipping it to fit the account.
At narrow widths, allow the metadata layout to place the date on its own line.
Do not ellipsize the date, hide metadata on hover or impose a fixed row height
that cuts it off. Dates retain their semantic `time` and ISO `datetime`. Only the
title and account label receive single-line visual truncation; both source
strings remain intact.

### Minimal implementation boundary

This is server-rendered ERB and scoped Orbite CSS work, plus coupled request and
native system-test updates. Expected production touchpoints are the History
items partial, the shell's visible History heading and the two Orbite stylesheets.
Keep existing authorized data, order, title helper, routes, deletion form and
confirmation source unchanged. No controller/model/job/JavaScript/schema/locale
or dependency change is part of this design.

## Preserved contracts

- Hidden Navigation heading and dialog accessible naming; independent close cross.
- Complete display-title and account-name strings in the DOM, account context and
  existing localized date formatting. The new CSS ellipsis expressly supersedes
  the prior requirement that History titles and account names wrap and remain
  visually complete in the list; it does not authorize date truncation.
- Current-link `aria-current`, visible state and real interior padding.
- Separate, accessible, at-least-44px close and trash controls with visible focus.
- Native confirmed deletion and correct authorized conversation target.
- Personal membership-scoped History, escaping and account isolation.
- EN/FR, both themes, mobile access, reduced motion and native keyboard behavior.
- Language/theme access and directly anchored user menu, without a second owner.
- All reviewed reader, scroll, composer, source, upload, streaming and accounting
  behavior, including the 80px policy and 1px paused-paragraph tolerance.

## Verification and sequencing

Before production changes, write and run failing tests for the absent visible
heading/help, single-line title/account ellipsis, complete accessible display
title/account values and compact side-by-side trash placement. Migrate the
earlier full-title/account-wrap tests only at those superseded boundaries;
preserve their complete source text, date, width, target size, native focus/hit,
current-state padding, deletion and privacy protections.

Measure actual before/after fully visible conversation counts using identical
application fixtures, panel dimensions, viewport, locale and theme. The ordinary
sample must show strictly more complete rows in both inline and modal History;
do not substitute the static mockup counts for that result. Long account names
remain one-line previews while their underlying text stays complete. Let the
date wrap when needed rather than promising a fixed height at every text scale.

Exercise actual short and overflowing titles in EN/FR and both themes, at
desktop, tablet, small mobile and landscape widths. Verify one visual line for
each title/account label, ellipsis styling confined to those labels, complete
display-title/account DOM/name and hover values, intact date text, 44px controls,
independent deletion/confirmation, current-link padding, no horizontal overflow
and trusted Tab/Shift+Tab/Enter/Escape behavior.
Keep reduced-motion, modal ownership, opener focus recovery and protected
reader/composer regression checks. Source and tests need fresh SPEC then QUALITY
reviews, followed by refreshed D documentation, safe final gates, current-source
security comparison and independent whole-feature review. No automatic integration.

No application or test source has changed for this amendment. Obtain user review
of this written spec, then invoke writing-plans before implementation. Preserve
the five existing documentation drafts and original evidence throughout.

## Visual exploration evidence and limitations

The consented loopback companion at `http://localhost:61120` serves only external
files under `/tmp/opencode/orbite-history-visual-N28heh/` with synthetic content.
No Rails application, database, provider or worker is started for these previews.
If the companion expires, its HTML remains available for a new local session.

The original comparison showed a reconstruction of current rows, A and B. Its
ordinary synthetic counts were 2/4/3 at 240px and 2/6/4 at 352px in 640px previews.
The user selected A, then expressly requested heading/help removal and one-line
title clipping. Original files and the two actual browser choice events remain
preserved; B is not part of the selected design.

The revised `history-editorial-single-line-v2.html` displays the requested A in
both themes. `verify-single-line-v2.rb` checked five isolated mockup samples:
normal and long labels at 240/352px, plus 375px-wide presentation. It checks
single-line ellipsis CSS, full DOM/hover titles, actual clipping for overflowing
examples, metadata containment, nonoverlapping 44px actions and reduced motion.
The normal synthetic sample shows 7 complete rows, and the long-account sample
4, at equal 640px preview heights. Measurements are in
`single-line-v2-geometry.json`; normal and long-label original screenshots were
opened. These are mockup results, not application acceptance or real-device,
screen-reader or native-tooltip verification.

The first revised-mockup verifier incorrectly required short titles to clip even
when they fit a wide panel. A separate browser trace proved normal widths
260/260px and overflowing long titles 559–677/260px, all one 21px line. The
verifier was corrected at that assertion and supplemented with long wide-panel
examples; the mockup CSS was not changed. The failed result and diagnostic are
recorded separately, not relabelled as a pass.

The user then requested account-name ellipsis as well. The latest screen is
`history-editorial-single-line-v3.html`; v1/v2 and their evidence remain preserved.
`verify-single-line-v3.rb` passed six standalone mockup samples, checking both
labels' one-line/ellipsis/full DOM and native-title values, positive account
width, untruncated dates, separate 44px trash controls, no horizontal overflow and
reduced motion. Its synthetic normal and long-label counts are 6 complete rows
at 240px and 7 at 352px in the same 640px previews. The count differs from v2
because v3's metadata sizing reserves room for each account preview and lets the
date move below it when space is insufficient. Measurements are in
`single-line-v3-geometry.json`; actual long-label originals at both widths were
opened. These counts are still mockup-only, not application acceptance.

ui-ux-pro-max's initial density query had no verified density-specific match after
one retry. A later targeted query verified the Content / Compact Label Overflow
guidance: preserve full-value recovery beyond pointer hover. Applicable
HTML/Tailwind guidance supports a shrinkable single-line label with nonshrinking
actions. These recommendations are applied as plain HTML/CSS principles, not as
authorization for a new framework.

## Decisions

- User: “Améliore l'UI/UX de la dialog chat-history en la rendant premium avec
  @ui-ux-pro-max, en permettant de voir plus de chats sur la même hauteur d'écran”.
  Rationale: improve visual polish and increase same-height information density.
- User: “Oui” to a browser-based visual comparison of the current organization
  and more compact premium directions. Rationale: choose the visual layout before
  changing the application. This is not implementation or design approval.
- User: “A en retirant l'en-tête "Historique des conversations" et le texte
  "Vos conversations..." en-dessous”. Rationale: select the editorial list and
  recover height by removing redundant visible introductory chrome.
- User: “en coupant les titres pour les faire tenir sur une ligne maximum avec
  des "..." éventuellement à la fin si coupés / trop longs”. Rationale: make
  title height predictable and increase density; this supersedes the previous
  no-title-truncation proposal. This decision does not change accessibility or
  title-source rules; account truncation was separately requested next.
- User: “Coupe aussi le nom des comptes trop longs avec des "..." à la fin si
  nécessaire”. Rationale: keep account labels compact as well. This expressly
  supersedes the previous untruncated-account proposal, while preserving full
  underlying names, dates, accessible text and existing account access rules.
