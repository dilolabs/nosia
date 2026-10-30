# Chat workspace

`/chats/new` opens a focused starting page. `/chats/:id` opens your saved
conversation with its fixed account, transcript, and shared composer. The
dashboard's composer and unrelated workspace navigation keep their existing behavior.

## History and accounts

**History** opens on demand on desktop and mobile, closed by default. It lists only
your root conversations in accounts you currently belong to—not another member's
chats or child conversations. Entries show a plain-text title preview, account,
activity time, and the current conversation, ordered by recent activity. Titles
come from the first question, with a localized fallback and a 120-character limit;
the full question remains in the transcript. This is not a conversation-renaming feature.

Opening History moves focus inside and contains keyboard navigation while the
background is inert. **Escape** or **Close** dismisses it and returns focus to
History. Opening a conversation uses its existing authorization checks; deleting
one still asks for confirmation and uses the existing home redirect. Empty history
has a localized explanation.

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

At every viewport size, `#application-scroll` is the sole primary scroll surface:
the global bar, page header, and conversation content scroll together. Neither
`main` nor the transcript scrolls independently. This supersedes the old
desktop-transcript versus narrow/short-page split; see
[compact application headers](compact-headers.md). Tablet layouts retain bottom
navigation clearance. Bounded editors, dialogs, wide code and tables scroll
locally. The composer stays in the layout rather than covering messages; short
screens may require scrolling to reach the header, answer, or composer.
Reduced-motion settings are respected.

## Sources, reasoning, and usage

**Sources** (with a count) and **Reasoning** are independent, initially collapsed
disclosures when available. They retain existing authorized citations, source
links, and saved reasoning. Initially collapsed **Response details** shows the
existing normalized token counts and environmental estimates only for finalized
responses with token data. Header **Usage details** starts collapsed and contains
the conversation's existing Input/Output counters, usage-kind breakdown, and
environmental estimates, with readable fallback/methodology explanations.
Labels and presentation changed, not calculations or authorization.

Open/closed choices and normal focus restoration are retained across live
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

Responses remain incremental, with existing preparing, indexing, searching,
retrieving, generating, tool, and thinking phases—not a new percentage or timer.
One stable, polite, atomic status region announces phase changes and completion
or stopping, not every token. **Stop** keeps any existing partial answer and unlocks
the composer. When the existing error/retry extension hook marks a response
eligible, **Retry** stays visible outside collapsed metadata. That hook was
verified with fixtures; real provider-error behavior is **UNVERIFIED**. There is no
new provider-error, cancellation, retry, or polling API.

## Verification and limits

Use the dedicated isolated test environment and sequential suite commands in the
[implementation plan](superpowers/plans/2026-10-28-chat-workspace-ui-ux.md), without
live providers or workers. Keep actual exits/counts, screenshot states, contrast
samples, and baseline differences in the execution evidence—not inferred passes.

Recorded browser evidence covers English/French, light/dark, actual CSS viewports
375×812, 768×1024, 1400×1000, and short 812×375, with keyboard, layout, reduced-motion,
and sampled contrast checks. Earlier focused-chat evidence included 64 base/state
captures and eight corrected Tools glyph captures, visually inspected in contact
sheets. These are not a complete human accessibility audit or proof of all
WebSocket delivery orderings.

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
