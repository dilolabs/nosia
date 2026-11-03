# Saved chat deletion

## Goal

Allow a user to delete the conversation they are viewing at `/chats/:id`, using the existing `svg/trash-bin.svg` asset and a polished interaction consistent with the Orbite workspace.

## Experience

- Add a quiet, icon-only, accessible 44px button to the right of the saved chat title. Use a red hover/focus treatment without layout shifts.
- Open a native HTML dialog styled with existing workspace colors, rounded corners, and a backdrop. Identify the conversation by its displayed title and explain that the conversation and its messages are permanently deleted.
- Provide Cancel and Delete actions in English and French. Initially focus Cancel; Escape and Cancel close the dialog and restore focus to the trigger without losing the composer draft.
- Submit a real Rails DELETE form only after confirmation. Disable repeat submission using Turbo's submission state and display a localized deleting label.
- Reuse `chat-dialog` for modal opening, focus recovery, and Turbo cache cleanup; do not introduce another JavaScript controller.
- Keep the action exclusive to saved chats. Preserve the transcript, token summary, history navigation, and responsive layout.

## Server and security

Reuse `ChatsController#destroy` and its existing `authorized_chat` lookup, which checks both ownership and current account membership. Return a 303 redirect to the existing home destination after successful deletion. Use existing dependent associations; do not add schema changes, new services, or new endpoints. Keep inaccessible chats protected by a 404 response.

## Verification

Add fixture-based integration coverage for localized markup, destructive form semantics, deletion of messages, redirect status, and denied access. Add browser coverage for opening, cancellation, Escape, focus recovery, draft preservation, confirmation, light/dark themes, and narrow screens. Update the older header test that forbids all header buttons to allow only the intentional deletion action.

## Decisions

- User requested deletion directly from `/chats/:id` using `app/assets/images/svg/trash-bin.svg`: keep the action in the saved-chat header.
- User selected “Sans maquette”: use the existing interface rather than introducing a separate mockup.
- User approved “icône trash-bin dans l’en-tête, fenêtre de confirmation accessible, suppression définitive du chat et de ses messages, puis retour à l’accueil”: implement that interaction, with Cancel focused by default and access/deletion tests.

## Scope exclusions

No paid-plan restriction (premium describes the visual treatment), bulk deletion, undo, history-row actions, or unrelated refactoring.
