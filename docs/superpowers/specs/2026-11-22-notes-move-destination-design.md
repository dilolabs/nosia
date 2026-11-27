# Notes: Follow the destination after moving a note

## Decisions

- “Lorsque je déplace une note, je veux aussi être redirigé dans le dossier de destination de la note.” A successful Move should switch the workspace context to the saved destination rather than retain the source folder, search, tag, or page.
- “Oui” to keeping the moved note open in its destination and making “Back to list” open that folder’s list.

## Behavior

- Keep the moved note open, with its destination highlighted in the folder tree and the destination’s notes in the list. On mobile, “Back to list” opens that destination’s list. Clear the previous search, tag, page and view because they belong to the previous context.
- Use the existing Move response, so the result also works without JavaScript. Cancelled, denied, or failed moves keep existing behavior, including draft protection and account scoping. Pin and unrelated actions keep their current return destinations.
- Test the successful redirect from a source folder and a filtered view, including the mobile return link, and retain regression coverage for an unavailable or unauthorized destination.
