# Chat composer UI simplification

**Date:** 2026-10-19

**Status:** Detailed design and written specification approved; implementation planning authorized. Application implementation has not started.

## Goal

Simplify and rethink `app/views/chats/_form.html.erb` without losing existing account selection, PDF attachment, MCP tool selection, skill discovery, source error handling, or submission safeguards.

## Decisions

- "simplifie et améliore l'UI/UX de @app/views/chats/_form.html.erb en la repensant" — the existing composer is the starting point; this is not a product-wide redesign.
- "Oui" to comparing browser mockups — use the visual companion to make layout choices tangible.
- "A" — choose the recommended single-block direction: writing area and compact action row share one surface, with the account always visible and tools disclosed on demand.
- "Aussi au compositeur des conversations existantes oui" — apply the same presentation to the new-chat and saved-conversation composers so sending the first message does not introduce a different interface.
- "Oui" to the detailed design — approve the shared single-surface presentation, compact action row, visible account, on-demand tools, Stop action during generation, secondary help, visible errors, and preservation of existing safeguards. Rationale: the simplification must remain consistent and usable throughout a conversation.
- "Ok" after the committed specification was presented for review — approve this written design and authorize the implementation-plan step, not an unplanned application change.

## Selected visual direction

- One coherent composer surface instead of nested editor/card borders and heavy shadows.
- A spacious writing area with a single clear send action.
- A compact lower action row containing PDF attachment, visible account selection, and a Tools control with its selected count.
- Account changes retain their existing confirmation and source-isolation rules.
- Tool selection opens on demand instead of permanently expanding the main form.
- Helper text, keyboard hints, and the AI disclaimer remain secondary to writing.
- On narrow viewports, the account row wraps above the remaining actions; controls and long account names must not create horizontal overflow.
- Preserve the existing neutral/green visual language and light/dark support. The English application copy shown in the mockup does not authorize a localization change.

## Scope

Redesign both `app/views/chats/_form.html.erb` and `app/views/messages/_form.html.erb`. Coordinate the account control and composer-specific styles, and remove redundant surrounding composer chrome from the dashboard/new/show containers. Do not redesign the dashboard upload panel, conversation messages, account administration, or unrelated forms.

## Interaction details

- The compact action row contains the native PDF upload action, the account control or read-only label, a Tools control with a selected count, and the send action aligned to the end.
- New chats keep the native membership-only account select. Saved conversations show the same account as read-only text, in the same position.
- New-chat tools use a compact disclosure. Saved conversations retain the existing MCP-management interaction; only the entry control is visually aligned with the new composer. Do not change tool-link persistence or introduce a second selection model.
- Do not show technical latency badges in the compact composer. Existing detailed tool management remains available.
- Use a high-contrast, stable send button without the current hover rotation. During generation, show an accessible Stop action in the same action area, reusing the existing stop endpoint and avoiding nested forms. This adds a visible stop control to the saved-message composer without changing generation/cancellation semantics.
- Keep account help available and associated with its control. Keyboard guidance and the AI disclaimer use secondary styling without competing with the input. Show the skill hint only when skills are available.
- Preserve Enter-to-send and Shift+Enter for a line break. The skill palette retains priority over submission while it is open. Do not add a second explicit Skills button to direction A.
- Keep the new-chat Tools action absent when no ready tools are available. Saved chats retain access to the existing tool-management empty state. Keep current selected/session count semantics rather than changing what the count represents.
- Registration/upload failures and server validation errors remain visibly associated with the composer, with existing retry/reset actions. Pending, submitting, switching, and generating states keep their existing safety rules.
- Use visible keyboard focus, accessible names for icon buttons, decorative SVGs hidden from assistive technology, adequate contrast in both themes, and wrapping rather than horizontal clipping at narrow widths.

## Architecture and component boundaries

| Component | Responsibility | Preserved contract |
| --- | --- | --- |
| New-chat form | Own chat creation and initial MCP selection. | `chats_path`, `chat[prompt]`, optional model, attachment namespaces, and MCP hidden-field syncing. |
| Saved-message form | Own follow-up submission and its replaceable Turbo Frame. | Existing message route, `message[content]`, attachment namespaces, frame ID, and generation state. |
| Shared composer body | Render the editor, source fields/errors, skill menu, and compact action row with explicit locals. | Existing Stimulus controllers/targets and account-specific helper data. |
| Account control | Render the selected native account select or saved read-only account label. | Membership-only choices, reset confirmation hooks, associated help, and fixed saved account. |
| Tool control | Render a compact initial-selection disclosure or open saved-chat management. | Existing MCP checkbox values/actions, selected count, and saved tool-management requests. |
| Composer-specific styles | Own the single surface, wrapping controls, focus, and theme states. | No broad changes to other editors, selects, buttons, or application forms. |

The dashboard, new-chat page, and conversation page must no longer add a second competing border/shadow around this shared surface. Their surrounding page layout and dashboard upload panel remain unchanged.

## Implementation boundaries

- Share the visual composer body through an ERB partial with explicit form/chat/field/generation context. The new-chat and message forms retain their distinct request routes, field namespaces, MCP syncing, and Turbo Frame behavior.
- Reuse Lexxy's native attachment and rich-text functionality rather than duplicating its uploader or manipulating private editor internals. The exact toolbar composition must preserve existing editing capabilities.
- Keep the PDF command connected to the real Lexxy file chooser and upload lifecycle. Existing rich-text commands remain accessible through native toolbar/selection controls, without adding a second always-visible full formatting bar. Do not replace the editor with a plain textarea.
- Scope styling to the chat composer; do not globally restyle all `lexxy-editor`, buttons, selects, or forms.
- Keep `composer`, `composer-sources`, and `chat-account` responsible for their existing behaviors. Any presentation-specific interaction must be small and avoid a parallel source/submission state machine.
- Background form replacement must retain the same visual hierarchy, explicit saved account, generation state, and DOM identifiers without depending on a request session.
- Submit Stop through the existing authenticated POST endpoint, separate from the message-submission form. A Stop control must remain usable while the editor is inert and must not submit a message or introduce nested forms. Do not add routes, controller actions, or cancellation logic.

## States and data flow

1. Render the new or saved form with explicit chat/account, input field, skills, tools, and generation context.
2. Editing, PDF upload, URL registration, and skill selection continue through the existing Lexxy and Stimulus workflows. The presentation reflects their existing pending/failure state instead of maintaining a competing copy.
3. Initial account switching continues to confirm/reset drafts and refresh account-specific options. Saved forms never expose reassignment controls.
4. Send uses the existing native form submission and duplicate-submission guard. Preserve the pending POST and cached-preview locks during the visual refactor.
5. A saved generating form shows a read-only account, an inert editor, and the reachable Stop action. Existing generation, cancellation, redirect, broadcast, and unlock behavior supplies subsequent form states.
6. Form replacement uses the same shared presentation and restores an enabled Send action only when the existing server/source state permits it.

Source failures keep their Retry source/Reset draft actions; changing presentation must not silently remove a failed reference or enable sending. Render server validation errors only when present, in an identifiable error region rather than an always-empty list. Do not change controller validation responses or add a new validation subsystem.

## Responsive and accessible presentation

- Support 375px-wide viewports without horizontal scrolling. On narrow screens, place the account context on its own lower-area row above PDF/Tools/Send. Let the composer grow vertically rather than clipping controls.
- Bound very long account/tool labels without allowing them to overlap or shrink the send control; keep the full name available through the native control or accessible label.
- Keep normal/help text at least 4.5:1 against its actual background, and meaningful non-text controls/focus indicators at least 3:1 where applicable. Test both themes rather than inferring dark-mode results.
- Give Send/Stop controls at least a 40-by-40 CSS-pixel hit area, and PDF/Tools/account controls a minimum height of 36 CSS pixels, with visible keyboard focus. Keep visible help text at least 12 CSS pixels. Icon-only Send/Stop actions need explicit accessible names; do not rely on hover titles alone.
- Tool disclosure and saved-management entry remain keyboard operable. The disclosure must fit the narrow viewport and must not become clipped by the composer container.
- Remove the send-button rotation. Avoid unnecessary movement and honor reduced-motion preferences for any remaining presentation animation.
- Keep English application copy and existing fonts/icons; this change does not introduce localization or branding dependencies.

## Verification

- Add rendering tests for both forms, their distinct hidden-field namespaces, the selected/read-only account, error regions, and generation actions before changing the templates.
- Cover no account, no ready tools, no skills, and saved-form rendering without request-scoped `Current` context. Verify that the Stop control does not create nested forms and submits the existing stop action rather than a message.
- Browser-check real PDF upload, pasted links, `/skill` selection, MCP selection/management, send/stop/unlock, and the existing pending/failure/submission/account-switch safeguards.
- Verify 375px and wider layouts, long account/tool names, keyboard navigation, light/dark contrast, and reduced-motion behavior.
- Re-run the existing account-isolation/browser/history regression suite and relevant composer/broadcast tests. The existing full-suite test-double error is a baseline constraint, not permission to weaken tests.

## Preservation boundaries

- No account-resolution, membership, persistence, retrieval, or API changes.
- Preserve Lexxy rich text and its real PDF upload workflow, pasted source registration, `/skill` palette, hidden attachment fields, and MCP field syncing.
- Preserve pending/error/submission/generation locks, cancellation/retry/reset behavior, and Turbo cache/history isolation.
- Keep the no-account empty state and accessible form labels/errors.
- Do not introduce a frontend framework, dependency, or build pipeline.

## Visual reference

Selected option: **A — Un seul bloc**, from the ignored mockup `.superpowers/brainstorm/2157-1792409305/composer-directions.html`.

The mockup is a design reference, not working application code. The requirements above also define saved-conversation and generation states that were explained and approved in the detailed design.

## Review and execution gate

The user approved the visual direction, scope, detailed design, and committed written specification in conversation. The `writing-plans` skill has been invoked to create the test-first implementation plan. Application execution remains subject to its workflow selection and failing-test gates.
