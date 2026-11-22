# Notes: Compact folder tree

## Decisions

- “Positionner le chevron à gauche du nom d’un dossier parent et retirer le texte ‘Sous-dossiers’” — put the expander and the folder name on the same row to remove the extra line on every branch.
- “Oui” to keeping two distinct controls: the chevron expands the branch and the name opens the folder.

## Design

- In the Notes sidebar, show a right-pointing chevron on collapsed parents and a down-pointing chevron on expanded parents. Align leaf names in the same column without showing a chevron.
- Keep separate controls: the chevron expands or collapses; the name opens the folder. Keep native keyboard and no-JavaScript behavior, retain the existing localized expander label for assistive technology, and preserve visible focus and 44 × 44 CSS pixel touch targets. Remove “Subfolders” as visible text only.
- Keep child indentation, automatic expansion of the selected folder’s ancestors, and current-folder highlighting. Limit the change to the Notes sidebar tree, including the tablet drawer and mobile folders view; leave Trash and other navigation unchanged.

## Verification

- In Chromium, check that the chevron and name occupy one row, have separate focus and click targets, and that toggling reveals children without navigating. With JavaScript disabled, open and close a branch by keyboard and open the parent through its link.
- Open a nested folder directly and check that its ancestors are expanded and that it is highlighted. At narrow width and in the tablet drawer, verify deep nesting and long names do not cause horizontal overflow. Run the Notes browser and request coverage plus the view-copy audit on the disposable test database.
