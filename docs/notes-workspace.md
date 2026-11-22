# Notes workspace

Open **Notes** from the main navigation or the dashboard. Notes belong to the selected account, not to an individual writer: current account members can read and edit them. If you belong to more than one account, use the account switcher in Notes. A link to a note always opens it in its own account, and only for members of that account.

## Organize and find notes

- Use **All Notes** for recent edits across the account, or open a folder to see its direct notes. Folders can be nested, renamed, and moved. **General** is permanent and cannot be moved, renamed, or trashed.
- **New note** files a note in the current folder, or in General if you start from All Notes, a tag, or search. A tag view starts with the hashtag in the editor, but a blank draft or the suggested hashtag alone is not saved.
- Write hashtags such as `#research` in the note body. Tags match regardless of case and exclude code blocks and URLs. Opening a tag groups matching notes without moving or copying them.
- Use **Note actions** to pin or move a note. Pins appear first in their own folder only. Moving a note keeps its text, tags, and link, but clears its pin.
- Search checks the saved title and text of active notes across the selected account and shows each result’s folder. It works without an AI provider.

The editor supports rich-text formatting. V1 does not support file attachments or remote embeds, and Notes are managed separately from Sources.

## Import a Markdown folder

From Notes, choose **Import a Markdown folder** and use your browser’s folder picker to select a collection, such as an Obsidian vault. The preview is local: review the account, root, notes, folders, and ignored files before choosing **Upload and import**. The new notes are shared with members of that account, and indexing sends saved content to the configured provider, which may be remote.

- Each confirmed import creates a separate top-level folder. Importing the same folder again creates a new copy (for example, `Coffre (2)`) without replacing existing notes. The import preserves only branches containing Markdown.
- Import up to 100 `.md` files (case-insensitive) and 60 folders including the selected root, with at most 32 levels below it. The limits are 2 MiB per Markdown file and 4 MiB total, with up to 255 UTF-8 bytes per path component and 1,024 bytes per relative path. Formatted content is limited to 4 MiB per note and 64 MiB total.
- `.obsidian` configuration, empty folders, and non-Markdown files are not imported. Use a compatible browser; individual files, ZIP archives, attachments, embedded media, plugins, and vault synchronization are not supported.
- Supported wiki and relative Markdown links resolve to notes in the same copy. Missing, ambiguous, and heading- or block-specific references remain readable but not clickable and appear in the private report (up to 100 examples). External media is never fetched.
- If the network drops, use **Retry upload** on the same page. Leaving clears the selection; an unfinished upload that could not be resumed expires after 24 hours of inactivity. Once the upload is complete, you can reopen its private status page. An import is successful when the notes are saved, even if indexing is still pending.

If your deployment has a lower proxy request limit, set `NOTES_IMPORT_BATCH_WIRE_BYTES` to that limit in bytes. The browser sends at most 16 files and 3 MiB of Markdown per batch by default, with additional headroom for a configured lower limit. This setting does not raise or replace the proxy or server limit.

## Save, recover, and restore

The editor autosaves after a short pause. Use **Save note** to save immediately, or **Retry** after a save failure. The open editor keeps your unsaved draft and warns before you leave it. If another editor saved a newer revision or moved the note to Trash, Nosia does not overwrite it. Use **Copy draft** to keep your changes; when offered, **Load saved version** opens the newer saved text. There is no live co-editing or offline synchronization.

Members can send a note or an entire folder branch to **Trash**. Restore items to their original location; if a parent folder was also trashed, restore that folder first. Restoring a branch does not restore items that were trashed separately. Trash is not emptied automatically. Only the account owner can permanently delete a trashed note or branch after confirmation. Permanently deleting a branch also removes its separately trashed descendants.

## Indexing and AI access

Saving and indexing are separate. **Saved** means the edit is stored. The indexing status tells you whether there is text to index, indexing is in progress, the note is indexed, or indexing failed. Use **Retry indexing** to retry the last saved text without saving an open draft or creating a new revision. A pending or failed note is still readable and searchable in Notes; it is not used as new AI context until the current text is indexed.

- Nosia sends saved titles and plain text to the configured embedding provider for indexing. Relevant excerpts from active, currently indexed notes can be sent to the configured AI providers when answering account chats and authorized OpenAI-compatible API completions. Depending on your deployment, these providers can be local or remote.
- Web chat can use note excerpts only while the chat user is a member of the saved chat's account. API note retrieval requires a valid, unrevoked token bound to the same account as the completion, and its user must still be a member of that account. Retaining a token after losing membership does not preserve note access. A legacy API request that resolves to a different account cannot use notes from either account. This does not change API access to other source types.
- Trashing a note or its ancestor excludes it from new retrieval and makes its citation unavailable. Restoring it can make current excerpts available again. Permanent deletion removes the stored note and its index; it does not erase past chat messages, quotations already in answers, or requests already sent to a provider.
