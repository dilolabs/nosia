# Recent conversation previews

## Approved change

Limit the displayed first-prompt title in **Your recent conversations** to 120
characters, including a trailing `…` when shortened. Titles of 120 characters or
fewer remain unchanged. Preserve existing plain-text sanitization, blank-title
fallbacks, private chat selection, links, and activity timestamps.

Apply the limit only to the recent panel. **View history** and the saved prompt
remain unchanged. No new controls, CSS, persistence, or title-generation behavior.

## Decisions

- The user answered **“Yes”** to: “I recommend trimming recent-conversation
  previews to **120 characters with an ellipsis**, leaving the full conversation
  and history page unchanged. Does that length work for you?”
- Use the existing partial's `recent` local to keep history rendering unchanged.

## Verification

Request regressions must cover a long prompt, the 120-character boundary,
multibyte text, unchanged short titles/history, and an unchanged stored message.
Run the account request/model regressions and existing browser coverage using the
already prepared dedicated test database. Do not repair the accepted unrelated
full-suite baseline error or claim a new full-suite run without executing it.
