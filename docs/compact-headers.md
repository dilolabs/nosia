# Compact application headers

The global Nosia bar and page headers scroll with the content on **all pages**,
at every viewport size. Neither header is fixed or sticky, and neither reserves
permanent space above the content. The global bar is approximately 48 CSS pixels
at normal text size (49px in the recorded browser measurements); labels and
enlarged text may make it grow. This is not a fixed-height or clipped-text contract.

## Headings and controls

Page titles and actions share a compact row where space permits and wrap when
needed. Localized **Details** / **Détails** discloses secondary descriptions and
breadcrumb trails. Selected-account context, account UID and role, errors,
required guidance, and actions remain directly visible—not hidden in Details.

Saved-chat titles are bounded previews; the full first question remains in the
transcript. The full account name remains available in **Usage details**, whose
summary is outside the primary action group and whose open body takes its own
row. **History** and **Tools** retain their native dialogs and existing operations.

Language, theme, profile, Settings, logout, account navigation, and chat operations
are unchanged. Native keyboard navigation can scroll an offscreen control into
sight; it does not pin headers or continuously keep an already-focused header in
view. Deliberately activating Usage keeps its summary operable, while a layout-only
change preserves a paused reader's paragraph.

## One primary scroll surface

`#application-scroll` contains the global bar, semantic `main`, page headings,
and content. It is the single primary scroll surface on desktop, tablet, narrow,
and short screens. This supersedes the older desktop-transcript versus
narrow/short-page split. Neither `main` nor the chat transcript independently
owns primary scrolling.

Bounded editors, dialogs, and wide code/tables can still scroll locally. Existing
fixed bottom navigation and its 96px clearance are unchanged. The composer stays
in the document layout rather than covering messages.

The [chat reader](chat-workspace.md#reading-without-losing-your-place) still follows
only when within **80 CSS pixels before content grows**, preserves paused
paragraphs across layout changes and same-page recovery, and shows **Latest
message** only for real new content below. Only your own successful follow-up
automatically resumes following; failed/blocked submissions, Stop, Tools, and
other tabs do not. There is still one reader owner, not a second header controller.
The narrowly accepted [Keep Turbo focus-restoration race](chat-workspace.md#sources-reasoning-and-usage)
is unchanged; live updates are not universally guaranteed never to reclaim focus.
The [shared composer safeguards](chat-composer.md#native-editing-existing-safeguards)
remain in force.

## Verification limits

Recorded coverage includes English/French, light/dark, keyboard navigation, and
375×812, 768×1024, 1400×1000, and short 812×375 **CSS viewports**. Synthetic overflow
is explicitly labelled separately from real long conversations. Enlarging CSS
text to 200% is **not native browser zoom**. Screenshots and measured contrast are
not a complete human accessibility audit.

Native browser zoom, screen-reader operation, live-provider behavior, and the
unrestricted suite remain **UNVERIFIED**. Do not run live AI, MCP, crawl, indexing,
or worker workflows to validate this presentation change. Use the isolated,
explicit selections and retain actual commands, exits, counts, source commits,
and baseline security fingerprints in execution evidence. See the
[workspace verification limits](chat-workspace.md#verification-and-limits) for the
existing baseline exceptions; no full-suite or security-clean claim is made.
