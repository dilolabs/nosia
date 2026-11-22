# Notes: Orbite UI polish

Date: 2026-11-22

## Decisions

- “Même esprit que les chats et l’application dans son ensemble (arrondis…)”: use the signed-in Orbite shell, palette and control shapes rather than creating a Notes-specific theme.
- “A” — Surface continue: keep one rounded workspace surface with quiet separators. It keeps the note in focus and avoids adding a card around each pane.

## Design

- **Workspace header:** Group the Notes title and current account as one identity block. Keep account switching available where it is today. Make “New note” the prominent filled action in the shared Orbite accent. Give search a rounded field and keep its explicit submit control. The header wraps without clipping on narrow screens.
- **Folders and note list:** Keep both on the same paper surface as the editor. Use spacing and fine separators for structure. Give rows the rounded hover and selected treatment used by chat history: a tinted background and an inset accent on the current row. Clearly distinguish folder and tag groups. In note rows, put the title first and keep the preview, date, folder context and pin indicator visually secondary without hiding them.
- **Editor and secondary views:** Make the title the strongest element in the editor and give Lexxy the readable measure and relaxed spacing of chat text. Use the chat composer's soft outline and rounded corners for the writing field without framing the whole editor pane as a card. Keep formatting, note actions, save feedback and indexing feedback distinct and easy to find. Apply the same control and empty-state styling to the folder form, folder dialog and Trash; destructive actions stay clearly labeled and secondary until confirmation.
- **Visual system:** Use existing `--orbite-*` colors in both themes. Match the existing Orbite shell radius (1.25rem on desktop), rounded controls (about .625rem) and rounded modal (about 1rem). Avoid new gradients, shadows on list rows, or motion. Keep visible keyboard focus and 44px targets on primary controls; do not use color alone to identify the current row, failures, or destructive actions.

## Behavior and scope

- Keep the responsive flows: from 64rem, three panes; from 48rem to just under 64rem, list and editor with the existing folders dialog on demand; below 48rem, one view at a time. Preserve the non-JavaScript folders link, dialog focus return, and Back to the originating folder, tag or search.
- Limit changes to Notes views, localized labels if needed, and Notes-scoped CSS. Keep the existing Turbo replacement boundaries, Stimulus targets, Lexxy form controls, and accessible names and announcements. Do not change global chat or shell styles, routes, data, authorization, autosave, indexing, or destructive-action flow.

## Verification

- Review the actual workspace at desktop (1440px), tablet (900px), and phone (375px, plus landscape) in light and dark modes. Check selected and hovered rows, text and control contrast, long French labels, empty lists, and that no viewport develops horizontal scrolling. Check that keyboard focus remains visible through search, note selection, editor actions and the folders dialog.
- Run the Notes system and request tests on a disposable test database. In particular, retain coverage for responsive navigation, Lexxy autosave and conflict recovery, index status announcements and retries, and the native/no-JavaScript paths.
