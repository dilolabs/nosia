# Notes: Compact workspace header

Date: 2026-11-22

## Decisions

- “Aligné sur la charte graphique notamment des sources (`/sources`)”: reuse the shared workspace typography and button styles so Notes feels consistent with Sources.
- “Garder le principe du dropdown pour changer de compte”: keep the current account beside the workspace title and preserve the existing account dropdown for members of multiple accounts.
- “Non, plus compact en fait”: use the compact layout instead of giving the account and search permanent rows of their own.

## Design

- Put **Notes** and the account control together, the search in the flexible space, and the actions at the end when they fit. Use the shared workspace title, primary button, and secondary control styles without introducing an extra card or changing the rest of the workspace. Keep **New note** as the only filled action.
- Let the header wrap on smaller screens. The account goes under the title when the pair cannot fit, search gets its own line when needed, and the actions wrap without clipping. Preserve visible labels, keyboard focus and touch targets. Keep the current account indicated in the dropdown; show its name as text without a dropdown when there is only one account.
- Preserve search submission, existing URLs and filters, account switching, the Folders and Tags fallback link, and the current visibility of **Import** and **New note** in Trash. Do not change Sources, the Notes panes or editor, routes, permissions, or stored data.

## Verification

- Verify the wide and narrow layouts in Chromium at 1440, 900 and 375 pixels, in light and dark modes. Exercise a long account name and French labels to check wrapping and horizontal overflow.
- Verify keyboard access to the account switcher, Escape dismissal and focus return, switching accounts, and that search and note actions remain reachable.
