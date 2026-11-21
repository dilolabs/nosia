# Notes workspace

Date: 2026-11-21

## Context

Nosia already uses Lexxy in its chat and Sources editors and themes it for light and dark modes. The signed-in Orbite navigation is shared across workspaces. Nosia's configured database is PostgreSQL.

## Workspace and daily use

- Add a first-class Notes destination to signed-in Orbite navigation and a Notes shortcut to the dashboard. Keep the current account visible, with a switcher when the user belongs to more than one. Do not mix accounts.
- On wide screens, show folders and tags, the note list, and Lexxy side by side. On medium screens, open folders and tags on demand rather than shrinking the editor. On small screens, show one view at a time. From a note, return to the originating list with its folder, tag, or search intact; a direct link can return to the note's folder.
- The sidebar contains All Notes, the expandable folder hierarchy, tags in use, and Trash. A folder lists only its direct notes and puts its pinned notes first; mixed-folder views do not promote pins. A tag behaves like a virtual folder; selecting it never moves or copies notes. Lists show the title (or a localized “Untitled”), a short text preview, and the last content-edit date. Search runs across active notes in the selected account and displays the actual folder path next to each result.
- Keep New Note visible in the active views and offer New Folder in the folder navigation. Creating in a folder uses that folder; creating from All Notes, search, or a tag uses the account's General folder. A tag view prepopulates the hashtag in the draft, but the seed alone does not save the draft: a user edit is needed. Do not persist an untouched or blank new draft.
- In the editor, keep an optional title, Lexxy, a compact formatting control, a save status, and a secondary menu for Move, Pin, and Trash.
- Reuse Orbite's colors, typography, SVG icons, and light/dark themes. Use flat surfaces, a restrained green selection state, an unobscured keyboard focus, and no decorative animation.

## Organization, trash, and shared editing

- One real folder per note. A folder can be created, renamed, or moved within its account; a folder cannot become its own parent or move under a descendant. Show full paths in move dialogs. General is a permanent root folder; it cannot be renamed, moved, or trashed. Moving a note keeps its identity and hashtags but clears its pin, which applied only in the previous folder.
- Members can trash and restore notes and folders. Trashing a folder hides all descendants from active views; Trash presents the deleted branch without flattening it. Restoration returns the branch to its original location and preserves independently trashed descendants. To restore a separately trashed item whose parent is also in Trash, restore its parent branch first. Confirm folder trashing and explain its reach. Trash does not allow editing, moving, or pinning.
- Do not automatically empty Trash in the first release. Only the account owner can permanently delete a trashed note or branch, with explicit confirmation. Purging a branch also purges its independently trashed descendants.
- Autosave title and body after a brief idle period. Preserve the draft in the open editor on a failed save, allow retry, and warn before navigating away with unsaved edits. Compare content revisions on the server. If a different editor has saved a newer version, stop autosaving and offer ways to copy the current draft or load the saved version. If the note is no longer active, reject the save and preserve the draft for copying. No live co-editing or silent overwrite.
- Derive hashtags from visible text in the saved note body, not URL destinations, literal URLs, or code blocks. Normalize case and Unicode, preserve accents, and deduplicate within a note. Tags and searchable plain text update with the saved edit. Active tag collections, previews, and search never include trashed notes or notes under trashed folders.

## Persistence and account boundaries

- Use the existing Rails, PostgreSQL, Hotwire, and standalone Lexxy stack. Persist the rich-text body as allowlisted HTML to preserve editor formatting when reopened; derive plain text from that sanitized body for search, previews, and embedding input. Lexxy is a writing editor here: no file attachments, remote embeds, link crawling, or chat composer actions in the first release.
- Resolve the workspace from an account membership, then resolve every note, folder, tag, destination, and state change inside that account. Use account-qualified routes for stable links, a first-account default for the global entry, and an empty-access state when the member has no account. Existing chat ownership and API token rules are unchanged.
- Persist parent links, note-to-tag memberships, and explicit pin and trash records. An item is active only if it and its ancestor folders are not trashed. Serialize tree mutations so concurrent moves cannot create a cycle or write into a branch that has just been trashed. General is a single account-scoped system folder. Use the same active visibility rule across workspace views and retrieval.
- Use the content revision for autosave conflict checks, separate from pin, move, and index state. Retrying the first successful save of the same draft must not create a duplicate. Enqueue background indexing only after edits commit. Title/body recency, not move, pin, or indexing activity, drives the default list order.
- Use case-insensitive, literal substring search over the saved title and body text, with bounded or paginated results. Workspace search does not call an AI provider.

## Chat retrieval and vector lifecycle

- All active saved notes are eligible for the account's chat UI and authenticated OpenAI-compatible completions API. Reuse account-scoped chunks, the configured embedding provider, and the existing usage accounting. Notes remain managed in Notes; do not create duplicate Text sources or expand the Notes CRUD surface to the API. Explain in the Notes workspace that active notes may be used by chats and API clients and sent to the configured model providers.
- After a meaningful change to the saved title or body text, debounce indexing in Solid Queue. The normalized title and plain body are the embedding input; a note with no title or body text has no retrievable chunks. Metadata-only changes and formatting edits with the same extracted text do not re-embed.
- An obsolete run must not publish chunks or change the current text's index status. Check the current input and active eligibility before embedding and again when publishing. Keep provider calls outside database locks. Publish a complete replacement set atomically; do not expose partial results.
- Restrict eligible note chunks by account, active ancestry, and current indexed text before nearest-neighbor ranking, not after the result limit. Apply the same eligibility to related excerpts, citation rendering, and direct chunk access. Recheck eligibility before building a new provider request from retrieved excerpts. Chat continues with other available sources while a note is pending or failed. Distinguish indexing failure from edit failure and offer a retry without requiring a content edit.
- Chat citations identify a note and link to its account-qualified workspace URL. After a trash transaction commits, retrieval and citation requests that start afterward must exclude that note's chunks, including descendants of a trashed folder, even if the vectors remain stored for restoration. Restoring an active note reuses its current vectors when available and schedules indexing otherwise. Permanent deletion removes its chunks. Existing replies or requests already sent to a provider are not retroactively erased.

## Acceptance and delivery

- First deliver the usable Notes workspace, then wire in retrieval. Both slices are required for the first release. Do not add real-time co-editing, offline synchronization, attachment management, per-note sharing, or public links.
- Minitest model and integration coverage: deep folders and cycle prevention, account membership and cross-account rejection, owner-only purge, branch trash and restore, pin and move, normalized hashtags, literal keyword search, conflict and retry behavior, current-revision indexing and failure recovery, citations and direct chunk access, and web/API retrieval isolation. Stub provider calls. Exercise both an edit and a branch trash concurrent with indexing and verify that neither old nor partial note text enters a later request.
- System verification covers the desktop and mobile flows, account switching, keyboard navigation and focus return, save and indexing status announcements, light and dark themes, French and English, long content, and breakpoints.

## Decisions

- Make Notes a central Nosia feature, inspired by Apple Notes. Rationale: notes need a dedicated workspace, not a subsection of Sources.
- Notes are shared by account: all account members can view and edit the same folders and notes. Rationale: the account is the shared workspace and access boundary.
- Keep each note in a folder; each folder belongs to an account and may have a parent folder. Rationale: provide one real location for a note and support nested organization.
- Allow pinning a note in its folder and moving a note to another folder. Rationale: support prioritization and reorganization without copies.
- Support hashtags and let users browse notes with the same tag as if they were viewing a folder. Rationale: provide a second way to organize notes without changing their real location.
- Create and remove tags by writing and removing hashtags directly in the Lexxy text, with no separate tag field. Rationale: let users organize notes without leaving the editor.
- Provide a trash view and search within notes. Rationale: make notes recoverable and findable.
- Trashing a folder hides its entire branch; restoring the folder restores its hierarchy. Rationale: keep the structure intact during deletion and recovery.
- Use Lexxy with a very minimal interface. Rationale: reuse the existing rich-text editor and keep writing in focus.
- Save automatically after a short pause, show a discreet save status, and never silently overwrite another member's edits. Rationale: keep the writing flow uninterrupted without hiding concurrent changes.
- Choose layout A: three panes on wide screens, a collapsible folder pane at intermediate widths, and one view at a time on mobile. Rationale: make deep folder navigation direct without sacrificing editor space on smaller screens.
- The user approved the daily workspace flow: primary navigation and dashboard access, account selection, folder and tag views, account-wide search, minimal editing, and the General folder fallback. Rationale: make it easy to capture, find, and organize notes without cluttering the workspace.
- Notes must also be accessible in the account's chats, like Text and Q&A sources, and must be vectorized. Rationale: the account's assistant should be able to draw on its notes.
- Index all active, saved notes automatically. The configured embedding provider may be local or remote. Rationale: match the Sources experience without per-note opt-in, while making the data flow explicit.
- Allow the account's authenticated OpenAI-compatible completions API, as well as the Nosia chat UI, to use notes as retrieval context. Rationale: match the existing Text and Q&A behavior for authorized account clients.
- When a note moves, remove its pin but preserve its content and tags; keep General available. Rationale: a pin belongs to the context of the original folder.
- Do not automatically empty Trash in the first release. Only the account owner may purge trashed items, after confirmation. Restoring a branch does not restore independently trashed items. Rationale: protect shared content from accidental permanent loss.
- Keep the draft available on failure or conflict, provide retry or copy/load actions, and do not add live co-editing. Rationale: make autosave reliable for shared notes without silent data loss.
- Match hashtags case-insensitively and exclude URL fragments and code blocks. Rationale: avoid accidental tags while keeping normal inline hashtags frictionless.
- Keep Notes separate from Sources, with current-text indexing in the background, retriable indexing failures, and in-app citations. Rationale: preserve a dedicated workspace while keeping chat answers attributable to current content.
- Keep workspace search textual, without AI calls. Rationale: users can find saved notes even when the embedding provider is unavailable.
- Deliver the workspace first and chat/API retrieval second, both before the first release; use Lexxy without attachments in that release. Rationale: sequence the work without cutting retrieval or expanding the editor scope.
