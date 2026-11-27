# Notes: Orbite action dropdowns

Date: 2026-11-22

Follow-up to the [Notes Orbite polish](2026-11-22-notes-orbite-polish-design.md).

## Decisions

- “Remplace également ces menus accordéons par une meilleure UI/UX dans le style orbite”: use the same rounded surfaces, colors and focus treatment as Orbite.
- “Je ne veux pas que cela décale le contenu … comme une liste select stylisée”: opening an action list must leave the surrounding content and page scroll position in place.
- “Oui” to using this pattern for note actions, folder actions and the account switcher, while keeping the hierarchy chevrons. Those controls reveal nested content, not a command list.

## Interaction

- Replace the note and folder action disclosures with labeled buttons and decorative chevrons. Open a rounded list anchored to the button and painted above the page. The list uses ordinary links and buttons, not a native select or an ARIA menu: these are commands, not choices submitted as a field value.
- Keep the available commands and their permissions. The note menu offers pin/unpin, move and Trash; the folder menu offers edit and Trash. Move keeps its existing destination picker and explicit submit; opening it must not expand the page. The folder trash and permanent-delete flows keep an explicit confirmation before submitting. In Trash, use a labeled confirmation trigger rather than an inline disclosure for permanent deletion; keep Restore and existing Trash branch expansion.
- Apply the same floating pattern to the account switcher when there is more than one account. Keep the active account visible in the trigger and marked in the list. A single account is still plain text. Keep folder-tree and Trash branch disclosures.
- Keep the dropdown usable on phone, tablet and desktop in both themes. Use the available space above or below the trigger, constrain the panel to the viewport, and scroll options inside the panel if needed. Opening or dismissing it must not reflow or scroll the workspace. Use at least 44px targets, visible focus and readable long (including translated) labels. Tab reaches the controls; Escape and outside click dismiss the list, and closing via Escape returns focus to the trigger.

## Integration and verification

- Prefer native popovers plus existing Orbite visual styles. Keep the behavior scoped to Notes and enhancement light: no new global UI component or JavaScript dependency. Preserve the existing routes, verbs, permissions, Turbo replacement boundaries, unsaved-draft safeguards and accessible native action paths when JavaScript is disabled.
- Add browser coverage that checks a note and account dropdown opens without changing content coordinates or scroll position, remains reachable near viewport edges, and closes with Escape and outside click. Cover viewport widths of 1440px, 900px and 375px, both themes, keyboard focus return, long account labels, and actions after an autosave refresh.
- Verify account switching, edit, pin/unpin, move and both cancel/confirm flows without weakening existing draft protection or owner restrictions. Run Notes browser and request tests on the disposable database.
