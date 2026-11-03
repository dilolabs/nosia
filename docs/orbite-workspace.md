# Orbite workspace

Signed-in pages share a slim application rail and inset content surface. Home,
New chat, Accounts, Sources, usage, Settings, Profile, and sign-out keep their
existing routes and authorization. At **768 CSS pixels and wider**, the bottom
user button opens Profile, Settings, and Sign out directly above the actual rail
button, without opening History. Language and theme remain in navigation
utilities, reached through the History/navigation trigger. Below **768px**, the
user button inside native mobile navigation opens the same action list above
that visible mobile trigger. There is one nonmodal user popover and one set of
native preferences, not a duplicate menu or modal. Signed-out pages retain public
branding and controls, never private conversation history.

## Responsive navigation

On chat pages at **1280 CSS pixels and wider**, personal History is initially
open inline and can be collapsed. At **768–1279px**, the rail remains visible
and History starts closed. Below **768px**, one on-demand native panel combines
navigation and History; there is no bottom navigation pill. Other pages reserve
no history column and make no global history query.

One panel owns personal root conversations in currently authorized accounts—not
peers' or child chats. Each compact full-row link contains one-line escaped
title/account previews and a real visible localized activity date, retaining recent
ordering and localized empty guidance. Titles retain the 120-character bound and
fallback; the full question remains in the transcript and the full account in Usage.
History-item Delete controls are removed; backend deletion routes and authorization
remain unchanged.
The current link uses a padded highlight and `aria-current="page"`, without a
visible Current conversation annotation. This is not renaming, search, folders,
or pinning.
Expansion is temporary page state, not a persisted preference.

The localized Navigation heading remains visually hidden and names the panel;
the duplicated logo and visible heading are removed. Saved chats alone have a
primary **New chat / Nouveau chat** link left of unchanged **Close** on the same
top row, outside the panel content's local scrollport—not a fixed overlay. Each
control has one target of at least **44×44px** and visible focus; Close retains its
existing icon, localized name, and initial modal-focus behavior. The moved link
uses ordinary `new_chat_path` navigation, with no new account-selection policy,
confirmation, persistence, or generation action. It is absent on new-chat,
non-chat, and no-account pages; existing global/account New chat links remain.
There are no Home, History, or New chat controls in the chat header.

Tablet/mobile panels use native modal focus containment and an inert background.
Close or Escape returns focus to the current opener, including a streamed
replacement. Desktop inline History is **nonmodal**, with no modal focus trap or
new Escape policy. The shared `chat-dialog` owner is the sole modal/focus owner
for navigation and Tools. Breakpoint and
Turbo-cache cleanup must not leave a hidden focused control or an inert page.

The user action list is an ordinary list of links with native Escape and outside
dismissal, not a second modal owner. Only the **same menu node** is temporarily
moved into its invoking mobile modal, because nodes outside that modal are inert;
it returns home on close, cache, or breakpoint cleanup. Editors, History, and
streaming nodes are never moved by the user-menu owner.

## Conversation and composer

On chat routes, `#application-scroll` is an explicit reading **div inside chat
main**, containing compact context and the transcript. Context scrolls away;
the native composer occupies a separate reserved bottom sibling and never
covers messages. Long drafts scroll locally within the bounded native editor.
Mobile navigation remains available when context is offscreen and during
generation. Chats with an account retain the composer opener; no-account new chats
retain setup guidance and the global mobile navigation opener, not a decorative
active editor. On other pages, `main` itself is `#application-scroll`. History,
dialogs, editors, code, and wide tables may scroll locally; none becomes a second
conversation-reading owner.

Useful scope, account UID/role, and breadcrumbs appear directly below `h1`;
redundant descriptions are removed while unique operational guidance stays
visible. There is no header Details accordion, including for Usage. Saved-chat
Usage is a directly visible, labelled section beneath `h1` **inside the reader**.
The full account appears once and can wrap, including unspaced names. Exact
localized cached Input/Output counters retain their data source; Total is only
their presentation sum, not a new stored metric or recount. A compact labelled
list retains every recorded usage kind's input **and** output, including zero.

One passive input/output composition bar replaces the table. It is `aria-hidden`
and noninteractive, not progress, quota, remaining capacity, or a model limit.
Zero usage has a neutral unfilled bar and localized explanation; one-sided usage
has only its corresponding segment. Output has a dashed non-color distinction.
All exact counts, environmental estimates (kWh at six decimal places, gCO₂e at
two), and normal/fallback methodology notes remain ordinary visible text, not
expansion- or hover-only content. The original localized, chat/account-scoped live
broadcast target is retained; no accounting, polling, or transport owner is added.
Full names and notes may extend below the fold and are reached by ordinary reader
scrolling; there is no simultaneous-all-values-on-screen promise or fixed/clipping
height. Usage scrolls away with context. Sources, Reasoning, response details,
and Formatting remain independent disclosures.

The [reader contract](chat-workspace.md#reading-without-losing-your-place) is
unchanged: following uses the **80px pre-growth** threshold, paused paragraphs
retain the **1px** position tolerance, Latest appears only for genuine new
content below, and only a successful own submission automatically resumes
following. Geometry-aware cache cleanup retains a paused paragraph while inline
History closes; it is not a new persistence algorithm. System fonts, restrained
light/dark surfaces, bounded 16px prose,
quiet user bubbles, and open assistant answers support reading. Sources with
counts, Reasoning, response details, Usage, errors, and required guidance remain
discoverable.

The [native composer safeguards](chat-composer.md#native-editing-existing-safeguards)
remain authoritative: PDF chooser/uploaded bytes, formatting, account/source
context, Tools, Send/Stop/eligible Retry, localized incremental status, accounting
owners, and streaming identities are retained. Background busy/stopped rendering
still uses the uncached account-scoped authoritative read; presentation does not
infer a competing generation state.

### Same-page native draft handoff

The explicitly user-authorized Task 6 amendment preserves **text, formatting,
and ordinary links** in a saved chat's actual Turbo morph at the **same full
URL**. A one-shot handoff in the existing `chat-account` owner uses native editor
APIs; it adds no browser storage, cached draft HTML, or permanent form. Native
edits during the GET are included; a later edit invalidates a captured stale
payload. Busy/Stop authority, source and submission safeguards, and account
navigation remain authoritative and cancel mismatched handoffs.

This does **not** promise attachment/source-bearing draft retention, file
selections across full navigation, focus/selection persistence, or new-chat
account-reset retention. It adds no public Ruby API and is not generalized
draft persistence or an exhaustive interleaving guarantee.

## Verification boundaries

See the approved [design](superpowers/specs/2026-10-30-premium-chat-experience-design.md)
and [implementation plan](superpowers/plans/2026-10-30-orbite-premium-chat.md),
as amended by the approved
[navigation refinements](superpowers/specs/2026-10-31-orbite-navigation-refinements-design.md).
The broader **Task D** of the
[refinement plan](superpowers/plans/2026-10-31-orbite-navigation-refinements.md)
is further amended by the approved 2026-11-02
[compact-premium specification](superpowers/specs/2026-11-02-orbite-compact-premium-chat-header-design.md)
and [plan](superpowers/plans/2026-11-02-orbite-compact-premium-chat-header.md), then the
[New chat relocation specification](superpowers/specs/2026-11-02-orbite-new-chat-history-action-design.md)
and [plan](superpowers/plans/2026-11-02-orbite-new-chat-history-action.md).
Older Task D selections and historical composer commands are not an unamended
current recipe. This documentation-only reconciliation authorizes no test, build,
lint, scanner, or diagnostic rerun; any later execution needs separate authorization
and the latest source-bound isolated selection, never the unrestricted suite.
Fresh source bindings, exact commands, true exits, counts, geometry, contrast,
and inspected screenshots belong in the execution evidence manifest. Earlier
[compact-header results](compact-headers.md) are historical, not current proof.

**Review boundary at authoring (2026-11-03):** the earlier frozen uncommitted code
and five-guide reconciliation each received independent SPEC approval followed by a
different reviewer's QUALITY approval. This verification footer was prepared for
a fresh Task D code/docs SPEC review, a different QUALITY review, and final
whole-feature review; their eventual outcomes are recorded separately in the
external execution handback. No whole-feature approval, integration permission,
or execution at a future commit is implied by this record.

CSS viewports, CDP scaling, and enlarged CSS text do not establish native browser
zoom or a physical OS keyboard. Screen readers, native zoom, native tooltip
interaction, physical devices/keyboards, and live providers remain **NOT RUN**.
Native `title` attributes do not establish tooltip interaction or screen-reader
proof. Do not run the unsafe unrestricted suite, crawl/index/provider work,
or workers, or change user environment files or DEV processes for this work.

The narrow existing Turbo-native focus-restoration race and GET `/login`
waiting-scaffold setup limitation remain scoped limits—not waivers for a new
warning or failure, a full-suite pass, or a security-clean claim. The original
security baseline and the earlier recomputed baseline/source-binding artifacts
remain unavailable after restart. User-authorized **NEW** default static scans of
immutable baseline `7189d6de425122120f3fb4d7090d16a9ebb88f11` and frozen current
working source now establish an independently reviewed scoped comparison. Both used
Brakeman **8.0.4**, Ruby **4.0.7**, Rails **8.0.5.1**, the same **79** default checks,
and matching lock/configuration inputs. Baseline/current scans exited **3 / 3**;
the full comparison exited **0**. Two unwaived **High-confidence** warnings have
identical full records and source contexts: API-token mass assignment at
`app/controllers/api_tokens_controller.rb:62` and Rails end-of-support at
`Gemfile.lock:318`. No warnings were added or removed; both reports have empty
errors, ignored-warning, and obsolete-warning arrays.

All **382** actual scanner inputs remain unchanged through the later two test-only
amendments; documentation is not a scanner input. This is input continuity, not a
scan executed at the amended test bytes. The new comparison is not recovery of
lost evidence, security-clean status, runtime assurance, or a warning waiver.
Earlier failures remain failures. The **22** existing MCP duplicate-key JSON
warnings remain unsuppressed compatibility debt, not silently resolved or ignored.

**Historical record — not current retained proof:** the dated paragraph below is
preserved verbatim. Its counts and security claims describe that earlier record,
not verification of the current final source or recovery of missing artifacts.

### 2026-10-31 selected verification

At application/test source `f48760734132598ca0fdd9ca126f24cde8e36e24`, with
documentation drafts frozen, the sequential Task D selections passed:
focused **245 tests / 15,191 assertions**, chat **285 / 58,163**, workspaces
**73 / 79,641**, and navigation **37 / 1,998**, all with zero failures, errors,
or skips and exit **0**. The Tailwind build, RuboCop on **33** changed Ruby files,
seven JavaScript syntax checks, protected-source checks, and local Markdown
link/anchor checks also exited **0**. The fresh current Brakeman scan exited
**3** with exactly the two required warnings and no errors; comparison with the
user-authorized NEW immutable-baseline analysis exited **0**. The **22** existing
MCP duplicate-key warnings remain unsuppressed. Source bindings, seeds, raw true
exits, measured geometry/contrast, and inspected original screenshots are in the
execution evidence manifest. This footer was added after the gates; no execution
of a future documentation-commit SHA is implied. Unrestricted-suite, native zoom,
screen-reader, physical mobile-keyboard, live-provider, and worker verification
remain **NOT RUN**; this is not whole-feature approval or security certification.

### 2026-11-03 selected verification

Current evidence is bound to HEAD `8e9cbab943dad90e5911f3ae6ec1b4e1090bf05b`
plus uncommitted application/test changes through working-input hashes, not a
clean-commit execution. The following seven groups are disjoint; each reported
zero failures, errors, and skips, with actual true exit **0**.

| Actual group | Whole files | Tests | Assertions | Seed | Evidence |
|---|---:|---:|---:|---:|---|
| Header/requests | 14 | 148 | 14,386 | 64146 | Retained original execution |
| Full native chat | 7 | 257 | 90,616 | 63731 | Retained original execution |
| Exact system localization | 1 | 8 | 643 | 11897 | Retained original execution |
| Remaining requests | 15 | 166 | 1,613 | 64146 | New, run once |
| Remaining chat browser | 3 | 75 | 3,571 | 63731 | New, run once |
| Remaining workspaces | 7 | 73 | 79,641 | 63731 | New, run once |
| Remaining navigation | 5 | 29 | 1,355 | 63731 | New, run once |

This covers **52 unique whole files**, not one 52-file invocation: **22** completed
files are reused by bound input continuity, and **30** remaining files ran once.
The 14-file request result retains its original execution and exclusion proof for
the later changed SYSTEM test; the two subsequently amended, unselected tests and
documentation are separately bridged. Native/localization receipts likewise keep
their original execution provenance. No old receipt or source date is relabelled.

The retained ordinary **16-context** fixture shows a header reduction and earlier
transcript of **81.3125-125.5px**, with identical accounting and **0px** reader/dock
geometry deltas; this is not a claim about unlimited content. Earlier owned-source
Tailwind build and effective changed-file lint remain verified by their bound
inputs, not new full-branch lint. This footer reran no tests, build, lint, or scans
and claims no execution at a future documentation commit.

The test-safety amendment changes only queue-adapter setup/restoration and four
MCP screenshot destinations, not application behavior. All **34** old MCP PNGs
remain exact; new MCP outputs use unique evidence directories. Actual commands,
raws, true exits, seeds, source bindings, and inspected originals remain in the
external execution manifest, separate from the historical record above.

Screen readers, native browser zoom, physical devices/keyboards, native tooltip
interaction, live providers, and the unsafe unrestricted suite remain **NOT RUN**.
This dated verification record does not by itself establish the subsequent review
outcomes or grant integration permission or whole-feature approval; those outcomes
belong to the external execution handback.
