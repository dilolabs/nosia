# Chat account selection

**Date:** 2026-10-14

**Status:** Design approved; awaiting user review of the written spec.

## Goal

Allow a user to choose the account associated with a chat so similarity search retrieves context from the intended account rather than always using the user's first account.

The selected account is the boundary for the whole conversation: retrieval, attachments, MCP tools, skills, system prompts, and token usage.

## Context

- `Chat` already belongs to an account; no new relationship is required.
- `Chat::SimilaritySearch#similarity_search` already searches through `chat.account.chunks`.
- `ChatsController#create` always assigns `Current.account`, which resolves to `Current.user.first_account`.
- Source forms already allow selection from `Current.user.accounts`; `ApplicationController#filing_account` resolves these selections with membership checks.
- Composer source registration, typed URL attachment, MCP selection, and new-chat skill hints currently use `Current.account`. Those paths must follow the selected chat account.
- Both the dashboard and the new-chat page render the shared chat form.
- The dashboard also uploads documents independently through `Sources::DocumentsController#create`; its uploads must carry the selected account without becoming automatic message attachments.
- Citation links open `ChunksController#show`, which currently searches only `Current.account.chunks`.
- Background composer-unlock broadcasts already render without a request session; the account label and account-specific UI must preserve that property.

## Decisions

- "Allow the user to select the account he wants to use to search by similarity in the right account." Rationale: the persisted chat account should identify the intended retrieval boundary.
- "Yes" to the optional browser visual companion. Rationale: compare account selector placement visually before choosing a layout.
- "At creation (Recommended)." The user chooses the account before the first message; it stays fixed for the conversation. Rationale: avoid combining answers and retrieved context from different accounts within one chat.
- "All resources (Recommended)." Retrieval, attachments, MCP tools, skills, system prompts, and token usage follow the selected account. Rationale: a chat must use one consistent account boundary, not a separate search-only account.
- "First account (Recommended)." Preselect the user's first account for each new chat; do not remember the last selection. Rationale: preserve the existing default without adding global account switching or preference storage.
- "Chat picker (Recommended)." Put the selector in the chat composer, without introducing a global account switcher. Rationale: solve account-specific conversations without changing unrelated pages.
- "B." Use the composer-footer layout, with a read-only account label in the same location after the first message. Rationale: keep account selection compact and alongside the chat's tool controls.
- "Reset draft (Recommended)." Confirm before clearing unsent text, attachment references, and tool selections when changing accounts. Saved sources stay in their original account; nothing is moved or deleted. Rationale: avoid mixed-account drafts and ambiguous rich-text attachments.
- "Approve" for design section 1: footer picker, first-account default, confirmed draft reset, selected-account dashboard/composer uploads, and fixed account after chat creation. Rationale: validates the end-to-end account-selection flow before defining security and verification.
- "Approve" for design section 2: membership checks, rejection of wrong-account resource IDs, saved-chat account authority, upload coordination, working citations, and Minitest/system coverage. Rationale: validates the isolation safeguards and verification scope.

## Scope and non-goals

This is one feature: choosing and consistently honoring a chat's account across existing chat entry points and follow-up interactions.

- No database migration, separate search-account association, or account preference storage.
- No global account switcher or change to `Current.account`.
- No account reassignment for existing chats or migration of existing chats/sources.
- No cross-account retrieval or changes to embedding, ranking, relevance checks, or orphaned-chunk handling.
- No redesign of account administration, source-management pages, token dashboards, or MCP configuration pages.
- No changes to the public completion API's account-selection contract.
- No service/query/policy layer; use the existing Rails controllers, models, associations, helpers, and focused Stimulus behavior.

## User experience

### New chat

Place a labeled native account select in the composer footer, alongside MCP controls, on both the dashboard and new-chat page. Use existing input styling, visible keyboard focus, and a wrapping footer layout on narrow screens. Offer only the signed-in user's accounts. Preselect `Current.user.first_account`; keep the account visible even when there is only one choice.

Include brief helper text: "Searches and attachments use this account."

### Changing accounts before sending

Selecting a different account loads a fresh account-scoped page through the existing dashboard/new-chat GET route using an `account_id` query parameter. Preserve unrelated entry-point parameters, such as a model choice, when navigating.

If there is unsent text, composer attachment activity, dashboard uploaded-source activity, or an MCP selection, ask for confirmation before navigating. Explain that the draft and tool choices will clear while saved sources remain in the previous account.

- **Cancel:** restore the previous picker value and keep the draft, references, upload list, and tool choices intact.
- **Confirm:** clear the editor, attachment references, upload list, tool choices, and skill menu; render fresh options for the new account.
- **Empty draft:** switch without confirmation.

Never move or delete persisted documents/websites during a switch. Account switching is not source deletion. Returning through Turbo history must not mix one account's references or tool choices into another account's composer.

Disable switching and sending while composer source registration or dashboard uploads are queued/in progress. Each source request captures its account context when it starts. Failed source registration remains visible and prevents silently sending an unregistered attachment; retry successfully or remove/reset the failed source before sending.

### Persisted conversation

Sending creates the chat and its first message with the selected account. Replace the picker with read-only text, such as "Account: Research team", in the same footer location. Keep it visible during generation, on reload, and after composer-unlock broadcasts.

All follow-up messages retain that account. A client-supplied account field cannot reassign a saved chat. Existing chats keep their stored account without a backfill.

### No available account

If the user has no account memberships, show "You need access to an account to start a chat." Disable composing/uploading/sending and reject chat/source creation with 422 rather than calling associations on a missing account.

## Architecture and responsibilities

| Unit | Responsibility and interface | Dependencies |
| --- | --- | --- |
| Dashboard/new-chat controllers | Resolve an optional GET `account_id` through user memberships; initialize the unsaved chat with the selected/default account. | Signed-in user and existing account associations. |
| Shared new-chat composer | Render the footer picker, selected account's MCP options and skills, and submit `chat[account_id]`. | Unsaved chat with explicit account, account helpers. |
| Focused account-selection behavior | Confirm/reset drafts, navigate to fresh account context, and coordinate pending-source state. | Picker, existing composer/dropzone activity, Turbo navigation. |
| Composer and dashboard uploads | Include explicit account/chat context, track pending requests, and expose failures. | Existing source endpoints; selected account or persisted chat. |
| Chat/message/MCP controllers | Authorize the account/chat and validate resource IDs before persistence or generation. | Membership-scoped accounts and account-scoped source/tool associations. |
| Chat generation and broadcasts | Use the saved `chat.account` for retrieval, prompts, skills, usage, and composer rendering. | Persisted chat; no request-scoped `Current` required. |
| Citation rendering and chunk controller | Resolve cited chunks through the authorized chat account. | Message's chat and its account's chunks. |

Keep shared account-resolution/authorization logic close to the existing controller patterns. Extend only the paths needed by chat account selection, rather than refactoring unrelated source administration.

Models using `acts_as_tenant` must respect the explicitly selected account; where needed, use a bounded account-specific tenant context. Do not bypass tenant checks with broad unscoped queries or globally redefine the current account.

## Account-resolution contract

| Request | Authoritative account |
| --- | --- |
| Dashboard/new-chat GET | Membership-checked `account_id`; absent/blank defaults to `Current.user.first_account`. |
| New-chat POST | Membership-checked `chat[account_id]`; absent/blank preserves the first-account fallback. |
| New-chat `/chat_sources` POST | Membership-checked top-level `account_id`; absent/blank preserves the existing default. |
| Saved-chat `/chat_sources` POST | Top-level `chat_id` identifies a chat owned by the user whose account membership is still valid; use its stored account. Reject a conflicting supplied account ID. |
| Dashboard document upload | Send `document[account_id]` to the existing membership-checked document filing path. |
| Saved-chat messages/MCP actions | Authorized chat's stored account; no account override can change it. |
| Cited chunk GET | Supply `chat_id` and resolve the chunk through the owned, membership-authorized chat's account. Without chat context, retain the existing default-account lookup. |

Resolve and validate all attachment/MCP identifiers against the authoritative account before creating the chat, first/follow-up message, or MCP linkage and before enqueueing generation. A resource from another account is invalid even if the user also belongs to that other account.

Scope `Message#similar_chunks` to `chat.account.chunks` and pass chat context from citation links. This prevents unrelated IDs from being rendered as this chat's evidence and makes second-account citation links work.

## Data flow

1. Render a new-chat entry point with a selected/default membership-authorized account.
2. Render that account's MCP choices and slash-command skills.
3. File pasted URLs, PDF registrations, and dashboard uploads into that account using explicit context.
4. Submit the selected account plus draft/tool/reference values. Authorize the account and validate referenced resources before persistence.
5. Save the chat, selected MCP links, and first message. Extract typed URLs into `chat.account`, then enqueue the existing generation flow.
6. The worker reads the saved account for similarity search, system prompts, skills, and usage attribution. No browser session is needed to choose an account.
7. Follow-up source requests, messages, tool actions, broadcasts, and citations derive context from the saved chat, regardless of the user's first account.

Do not rewrite the retrieval algorithm: its existing `account.chunks` association already supplies the necessary retrieval boundary. Add behavioral tests to preserve it.

## Authorization and error handling

- Resolve account IDs through `Current.user.accounts`, never a global account lookup.
- Persisted-chat web actions require ownership plus current membership in the chat's account. Apply the same rule to show, stop, destroy, follow-up messages, source registration, MCP actions, and citation access.
- Unknown/unauthorized accounts, chats, chunks, and wrong-account attachment/tool IDs return 404. Reject these before creating chat/message/tool records or enqueueing generation; do not silently drop invalid IDs or fall back to another account.
- Missing account context for a new-chat request retains the first-account fallback; an explicit invalid ID never falls back.
- A malformed/expired attachment SGID retains the existing 400 response. Valid context with invalid source data uses the existing validation response.
- JSON source failures return an error response that the composer can surface. Pending or failed registration must not quietly become a successful send.
- When switching accounts, existing saved sources remain in their original account. Already uploaded Active Storage blobs are not treated as chat/message side effects, and this feature adds no blob cleanup policy.
- Background rendering must use `chat.account`, not `Current.session`/`Current.account`. Existing generation retry, cancellation, streaming, and source-indexing behavior otherwise remain unchanged.
- This feature checks membership when authorizing web requests; immediate interruption of an already-authorized running generation on membership revocation is outside scope.

## Verification and acceptance criteria

Use Minitest and account/membership fixtures, not RSpec or factories. Stub external AI/MCP responses and control embedding vectors so tests are deterministic and exercise actual account-scoped retrieval rather than a fake implementation that merely returns the desired account's chunks.

### Controller/model coverage

- Both entry points render a footer picker restricted to memberships and defaulting to the user's first account.
- Selecting a second account persists it on a new chat; omitted/blank account context retains the existing default.
- The chat account cannot be changed after persistence; posted follow-up overrides do not alter it.
- Invalid account/chat IDs and wrong-account attachment/MCP IDs produce 404 without chat/message/tool linkage or generation-job side effects.
- A user who no longer belongs to a saved chat's account cannot use its web actions or citations.
- Pasted URLs, typed URLs in initial/follow-up messages, PDF source registration, and dashboard uploads file into the selected/saved account.
- MCP lists/add/remove operations and slash-command choices use the selected/saved account; another account's tools/skills do not leak into the composer.
- With relevant chunks in two accounts, retrieval and cited evidence include only chunks from the chat account, including when the other account has a closer vector match.
- System prompt selection and completion/query-embedding usage retain the chat's account attribution.
- A second-account citation opens successfully through chat context; wrong-chat/wrong-account citation requests fail.
- No-membership users see the empty state and cannot create chat sources/chats.
- Composer-unlock broadcasts still render the correct read-only account label with `Current.session` unset.

### System coverage

- Footer picker works on the dashboard and new-chat page, including keyboard access and narrow layouts.
- Account change refreshes tools/skills and resets an approved draft; cancel preserves all draft state.
- Already saved sources stay in the previous account after a switch.
- Pending uploads/source requests prevent account switching and sending; failures remain visible and cannot silently lose an attachment.
- Sending, follow-up messages, reload, and background unlock all show a read-only account name.

Run targeted controller/model/system tests, then the Rails test suite and relevant lint checks during implementation. No application tests were run as part of this design-only brainstorm.

## Alternatives considered

1. **Per-chat composer picker — selected.** Focused change, clear conversation boundary, no new global account state.
2. **Start chat from an account page — not selected.** Clear context, but extra navigation and less convenient existing dashboard/new-chat entry points.
3. **Global account switcher — not selected.** Could align all application pages, but requires broader account-state and navigation changes outside this feature.

## Visual reference

Approved layout: **B — composer footer**, from `.superpowers/brainstorm/315631-1792007130/account-picker-placement.html`. Mockups are ignored scratch artifacts; the requirements above are the durable specification.

## Review gate

Both design sections were approved in conversation. The user must now review this committed written spec before the writing-plans skill is invoked. That review authorizes planning, not application implementation.
