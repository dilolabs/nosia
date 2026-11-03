# Chat workspace

`/chats/new` opens a focused starting page. `/chats/:id` opens your saved
conversation with its fixed account, transcript, and shared composer. The
dashboard's composer and unrelated workspace navigation keep their existing behavior.

## History and accounts

Under [Orbite navigation](orbite-workspace.md#responsive-navigation), **History**
starts open inline and collapsible on chat pages at **1280 CSS pixels and wider**;
this desktop surface is nonmodal. At **768–1279px**, the rail stays visible and
History starts closed. Below **768px**, one on-demand native panel combines
navigation and History, without a bottom pill. Tablet/mobile modal panels contain
focus with an inert background and initially focus **Close**; **Escape** or
**Close** returns focus to the actual current opener, including its streamed
replacement. Inline History has no modal focus trap or new Escape policy.

History lists only your root conversations in accounts you currently belong
to—not another member's chats or child conversations. Each compact full-row link
shows one-line escaped title/account previews and a real visible localized
activity date, ordered by recent activity.
The current link has a padded highlight and `aria-current="page"`, not a visible
Current conversation annotation. Titles come from the first question, with a localized
fallback and a 120-character limit; the full question remains in the transcript.
The full account name appears in Usage. This is not a conversation-renaming
feature. History-item Delete controls are removed; backend deletion routes and
authorization remain unchanged. Empty history has localized guidance. Non-chat
pages reserve no history column and make no global history query.

The panel keeps its visually hidden localized Navigation heading, without a
duplicate logo or visible title. Saved chats alone have **New chat / Nouveau chat**
on the left of unchanged **Close** on one top row, outside the panel content's
local scrollport. Each control has one target of at least 44×44px and visible
focus. The moved link uses ordinary `new_chat_path` navigation, with no new
account policy or generation action. It is absent on new-chat, non-chat, and
no-account pages; existing global/account New chat links remain. The chat header
has no Home, History, or New chat controls.

New-chat account selection remains membership-only, with the existing default or
explicit-account behavior. Saved conversations cannot change accounts. There is
no new persisted account preference. If you have no account membership, the new
page offers **Set up an account** instead of a nonfunctional composer.

## Reading without losing your place

First opening a saved conversation starts at the latest message. Responses keep
following when you are within **80 CSS pixels of the bottom before content grows**.
Scrolling farther away pauses following. New answer content below you then reveals
**Latest message**; activate it or manually return to the bottom to resume.
Only your own successfully submitted follow-up resumes following automatically;
failed or blocked submissions, Stop, Tools/MCP changes, and activity in another
tab do not resume a paused reader.

Same-page Turbo refresh/recovery preserves following or paused intent and the
visible paragraph's position, including when the layout changes. A full browser
reload may start at the latest message. This state is temporary page state, not a
saved preference or browser-storage record.

Paused paragraphs retain the **±1px** position tolerance, including geometry-aware
cache cleanup when inline History closes; this is not a new persistence algorithm.

The [Orbite reading surface](orbite-workspace.md#conversation-and-composer) is one
explicit `#application-scroll` div inside chat main, containing context and the
transcript above a **separate reserved native composer**. Context scrolls away;
the composer never overlays messages, and mobile navigation remains reachable
with context offscreen. On other pages, `main` is `#application-scroll`. Bounded
History, editor, dialog, code, and wide-table scrolling stays local, not a second
conversation owner; reduced-motion settings are respected. This explicitly
supersedes the earlier outer-scroller, in-flow chat composer, and mobile-pill
presentation described in [compact application headers](compact-headers.md).

## Sources, reasoning, and usage

**Sources** (with a count) and **Reasoning** are independent, initially collapsed
disclosures when available. They retain existing authorized citations, source
links, and saved reasoning. Initially collapsed **Response details** shows the
existing normalized token counts and environmental estimates only for finalized
responses with token data. **Usage** is directly visible beneath the saved-chat
`h1`, in an ordinary labelled section inside the reader. It shows the full account
once, exact cached Input/Output counters and their presentation-only sum, and a
compact labelled list of every recorded kind's input and output, including zeros.
One passive, `aria-hidden` input/output composition bar replaces the table; it is
not a quota, model limit, or interactive control. Environmental estimates retain
their arithmetic, precision, and visible normal/fallback methodology notes, with
the original live broadcast target. Useful account/scope context also appears
beneath `h1`, not in header Details. Full names and notes can wrap and extend below
the fold, reached by ordinary reader scrolling—not expansion or hover. Usage and
context scroll away; neither overlays the reserved composer or adds a reader owner.
Presentation changed, not accounting or authorization.

Sources, Reasoning, and Response details retain their independent native
open/closed choices and normal focus restoration across live
replacements and same-URL Turbo morphs. There is one explicitly accepted exception:
if a live replacement and a deliberate focus move happen in the same frame,
Turbo's own focus preservation can return focus to a disclosure heading with an
ID, even if the newly focused control was removed. This race is **not fixed**, and
there is no universal promise that live updates never reclaim focus. Standard
Turbo delivery is retained—no custom delivery fork, native-focus classification,
or animation-frame gate that holds up hidden-tab delivery. The
[approved design](superpowers/specs/2026-10-28-chat-workspace-ui-ux-design.md#decisions)
records the full bounds of the **Keep Turbo** decision.

## Composer and generation

The shared [chat composer](chat-composer.md) retains the native PDF chooser and
uploaded file bytes, formatting, account/source context, `/skill` selection,
Tools, Enter to send, Shift+Enter for a line break, Send/Stop, and existing
upload/submission safeguards. Source/upload errors stay visible and block Send
where required. Opening or closing History or details does not reset or replace
your draft editor. Existing account-switch confirmation/reset rules still apply;
this does not promise restoration of browser file selections or secrets.
Saved **Tools** uses an accessible native modal with the same Add/Remove operations,
Escape/Close and focus return, including during generation.
The bounded [same-page native draft handoff](orbite-workspace.md#same-page-native-draft-handoff)
preserves text/formatting/ordinary links through a saved chat's same-full-URL morph,
including native edits during the GET, not attachment/source-bearing or
full-navigation file selections. Source, submission, Stop, and account authority
are unchanged.

Responses remain incremental, with existing preparing, indexing, searching,
retrieving, generating, tool, and thinking phases—not a new percentage or timer.
One stable, polite, atomic status region announces phase changes and completion
or stopping, not every token. **Stop** keeps any existing partial answer and unlocks
the composer. When the existing error/retry extension hook marks a response
eligible, **Retry** stays visible outside collapsed metadata. That hook was
verified with fixtures; real provider-error behavior is **UNVERIFIED**. There is no
new provider-error, cancellation, retry, or polling API.

## Verification and limits

The broader [refinement plan, Task D](superpowers/plans/2026-10-31-orbite-navigation-refinements.md)
is amended by the approved [2026-11-02 plans/specifications](orbite-workspace.md#verification-boundaries);
its older commands are not an unamended current recipe. This documentation-only
reconciliation authorizes no gate reruns. Separately authorized verification must
use the source-bound isolated selection, without live providers or workers, and
retain actual exits/counts, screenshots, contrast samples, and baseline differences
in execution evidence—not inferred passes.

Recorded browser evidence covers English/French, light/dark, actual CSS viewports
375×812, 768×1024, 1400×1000, and short 812×375, with keyboard, layout, reduced-motion,
and sampled contrast checks. Earlier focused-chat evidence included 64 base/state
captures and eight corrected Tools glyph captures, visually inspected in contact
sheets. These are not a complete human accessibility audit or proof of all
WebSocket delivery orderings.

The following compact-header results predate Orbite and remain historical.
Current [Orbite review status and limits](orbite-workspace.md#verification-boundaries)
are separate; these earlier counts are not reused as current verification.

Fresh selected verification on **2026-10-30**, at source `1347e452` with only
documentation edits pending, passed: Tailwind build; 25 focused files (**231 tests /
14,658 assertions**); five chat/browser files (**215 / 32,932**); seven workspace
browser files (**73 / 81,054**); RuboCop on all 20 Ruby files changed since the
compact-header specification; and syntax checks for the four existing workspace
controllers. Each test group had zero failures, errors, or skips and ran sequentially
in the dedicated test database. The fresh header matrix covers **176 contexts**
(eleven routes × EN/FR × four CSS viewports × two themes), including 16 saved-chat
contexts with real long transcripts; 120 other contexts use labelled synthetic
overflow. These selected gates are not the unrestricted suite.

Native **200% browser zoom** and **screen-reader operation** are separately
**UNVERIFIED**; CSS viewport/CDP device scaling proves neither. Live providers are
also unverified. The unrestricted suite was **NOT RUN / UNVERIFIED** because of an
existing unsafe robots/crawl/embedding network path. Two accepted Brakeman baseline
warnings (API-token mass assignment and Rails end-of-support) and the existing
GET `/login` waiting-scaffold setup error remain outside this change. The fresh
installed Brakeman scan on **2026-10-30**, after the Tools color and compact-header
changes, exited **3** with exactly the same two baseline warning fingerprints,
no new or removed warnings, and no scan errors. No all-tests or security-clean
claim is made. The dated [composer results](chat-composer.md#verified-results--2026-10-19)
remain historical rather than fresh verification.
