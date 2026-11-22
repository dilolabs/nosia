# Notes: More room to write

Date: 2026-11-22

## Decisions

- “Je veux beaucoup plus d’espace pour saisir la note en hauteur.” Give the editable body more visible space, especially on short screens.
- “Réduit l’espace vertical pris par ‘Retour à la liste’, Editeur de note, ‘Actions de la note’, et le bouton ‘Mise en forme’.” Compress those controls rather than making their touch targets smaller or changing their behavior.
- “Oui” to one compact header, no separate full-screen mode, and the formatting toggle beside the body label.

## Design

- Use a single compact editor header: a Back arrow, the folder context, and the floating Note actions trigger with an ellipsis. Keep their localized accessible names. Keep the screen-reader heading for the editor region, but stop displaying the generic “Note editor” or “New note” above the editable title. The title field remains the prominent visible title; new drafts without an action menu keep the same compact layout. Long folder paths can truncate on one line while remaining fully available to assistive technology.
- Put the formatting toggle beside the Body label, not on a separate row. Keep its name, keyboard access, expanded state and the existing Lexxy toolbar. Preserve visible focus and 44px touch targets on compact controls.
- Grow the editable body with the available viewport height. Free space by moving its top up first, then use the remaining height as a writing-area minimum for short notes. Let long content and short landscape screens scroll naturally through the workspace, without a fixed overlay or a second scroll region obscuring writing or focus.
- Keep the responsive panes, filtered Back destination, floating action behavior, autosave, Save and indexing feedback unchanged. Scope the changes to the Notes editor; the folder form, Trash and global workspace controls do not change.

## Verification

- Compare the editor before and after on the same viewport: 1440×900 desktop, 900×768 tablet, 375×650 phone and 667×375 landscape. On phone and tablet check that the top of the editable body is at least one control row (44px) higher at normal zoom. On desktop check that a short note gets more visible writing space. No horizontal scrolling or clipped controls in either theme or with long French folder names.
- Use the keyboard to reach Back, Note actions, Formatting and the editor. Check that opening formatting allows the existing toolbar to work, and closing it returns the space without losing the draft. Run the Notes browser and request suites on the disposable database.
