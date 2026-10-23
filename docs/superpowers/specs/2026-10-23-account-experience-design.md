# Account index and account detail experience

**Date:** 2026-10-23
**Status:** Design approved; awaiting user review of the committed specification.

## Requested outcome

Redesign the accounts index and add an account show page. Users should be able
to start a conversation for an account and discover its sources (documents,
texts, Q&As, websites), past conversations, users, system prompt, account editing,
their account API tokens, and account token usage.

## Existing application context

- The accounts index currently offers Rename and Settings but no account show page.
- The requested entities already exist; this work should first define their
  navigation and presentation rather than invent replacement subsystems.
- New-chat entry already supports an explicitly selected, membership-checked account.
- `Current.account` resolves to the user's first account. Sources and token usage
  currently depend on that context, so linking to existing unscoped pages cannot
  be assumed to preserve the account being viewed.
- Saved conversations currently require both ownership and account membership.
- Account membership management is owner-only. API tokens currently belong to the
  signed-in user and carry an account reference; plaintext secrets display once.
- Account settings and account system-prompt pages already exist.
- Preserve the existing Rails/Hotwire stack, neutral/green visual language, and
  light/dark theme support unless a later explicit design decision changes this.

## Chosen approach

Chosen scope: an overview hub with useful summaries, recent conversations, and
a New conversation action. Full sources, users, prompts, API tokens, and usage
workflows open dedicated account-scoped pages rather than being rebuilt inside
one persistent workspace. “Account edition” means editing the existing account
name and identifier, not subscription tiers or billing. The selected visual
direction is A, Balanced overview. All three design sections have been approved;
implementation remains gated on written-spec review and implementation planning.

Alternatives considered: B, Conversation-first, gives the chat action more space
but makes account detail harder to scan; C, Management dashboard, favors metrics
and uniform administration tiles but feels less conversational. A balances the
requested knowledge, conversation, and administration information without
replacing the existing tools.

Conversation previews, counts, and history must include only the signed-in
user's chats for the viewed account. Account owners do not gain access to other
members' chats through this hub.

Account details editing, shared system-prompt editing, and membership management
are owner-only. Members retain access to their own API tokens and account-wide
usage. Enforce these permissions on requests as well as in visible actions;
existing direct edit/update endpoints cannot bypass the owner restriction.

The initial ui-ux-pro-max design-system search and its narrower retry returned
marketing/landing-page structures, not an authenticated account workspace. No
verified product-specific design-system match was found; those generated
palettes and layouts are not adopted. Use the existing app design language and
focused, verified UX guidance for the forthcoming account layout.

## Page experience

### Accounts index

- Compact account cards, ordered by name, with account name/identifier, Owner or
  Member role, source count, and the signed-in user's conversation count.
- Separate View account and New conversation links; no nested links or invisible
  whole-card click targets. New conversation preselects that account.
- Add account remains visible on desktop and mobile.

### Account overview

- Breadcrumb Accounts → account name. Header shows name, identifier, role,
  prominent New conversation, and owner-only Edit account.
- Two-column desktop layout: source breakdown and five recent conversations in
  the wider column; token summary, shared prompt preview, users, and personal API
  tokens in the secondary column. Stack in that order on small screens.
- Each of Documents, Texts, Q&As, and Websites links to its filtered account
  source list. Show processing/failed counts when nonzero, with appropriate links.
- Conversation rows show a title and last activity, with View history for the
  full account-specific list. Label the list as the user's conversations.
- Usage shows lifetime input/output totals across the account; link to the
  existing detailed usage experience, including its 30-day breakdown and impact.
- Show the shared account prompt preview as Account default, not a promise of the
  effective personal prompt. Personal overrides may apply to chat generation.
- Owners see membership management; members see the member count but not a
  directory of emails or a management link. Everyone sees only their own API-token
  count and management link. Members can read, but not edit, the account prompt.
- Retain global navigation but hide the duplicate global conversation drawer on
  the index, hub, and account-scoped tool pages so cross-account history and an
  unscoped New chat action are not confused with account-specific content.

## Navigation and account boundaries

- Add the account show route at `/accounts/:id`. Account tools have explicit
  `/accounts/:account_id/...` URLs for sources, source operations, conversation
  history, personal API-token management, and token usage. Retain the existing
  nested users and shared-prompt pages; account editing uses the existing form.
- Authorize the route's account through the signed-in user's memberships before
  querying any content. Use that same authorized account for counts, resources,
  form targets, redirects, pagination, upload/retry requests, and stream subscriptions.
- Keep this context request-local and explicit; do not change `Current.account`,
  store a global last-selected account, or make other tabs switch accounts.
- Reuse existing controllers/model APIs, source/usage/token templates, source
  row helpers, and Hotwire behavior rather than building parallel implementations.
  Introduce focused controller scoping and owner checks where shared. New actions
  use REST resources; no services layer, frontend framework, or schema change.
- Source create/edit/delete/retry, all four source types, filter/sort/search,
  pagination, form cancel links, and drag/drop retain the viewed account. On a
  scoped form the account is fixed; a conflicting submitted account is rejected.
  Broadcast source links derive their account from the record, not request state,
  so background renders cannot silently revert to the user's first account.
- New conversation uses the existing `/chats/new?account_id=...` contract; it
  preselects, rather than permanently locks, the account until first send. Existing
  account-switch confirmation and draft-reset rules remain unchanged.
- Conversation history shows only the signed-in user's root chats for the account,
  ordered by `updated_at` descending, then ID for stable ties. Show five on the
  hub and paginate the full list at 25 per page using ordinary accessible links.
  Reuse the current saved-chat show path and its ownership/membership checks.
- Account creation and successful account editing return to the account hub;
  editing Cancel returns to the hub. The old account settings landing URL redirects
  to the hub. Source, prompt, token, and membership workflows retain an Accounts →
  account → tool breadcrumb with a working account link.
- Other existing non-account routes remain supported with their current default
  context. New account-scoped navigation does not depend on those defaults.
- Shared-prompt ownership restrictions also apply to legacy global prompt
  edit/update/delete endpoints, not just the new hub's buttons. Personal prompt
  selection/generation behavior is not changed by this feature.
- Scoped API-token lists intersect account and current-user ownership, fix the
  creation form to that account, and return to the scoped list after create/revoke.
  Keep the existing one-time secret display; no secret or digest appears on the hub.
- Authenticated nonmembers, mismatched record/account pairs, and malformed or
  conflicting account IDs return 404 without writes. A member requesting an
  owner-only operation gets 403, with no redirect loop. Revoked membership is
  checked again on subsequent requests; revoking an already-running stream/job is
  outside this work's scope.

## Quality and verification

### Empty states and failures

- No accounts: explain the workspace model and offer Add account.
- No sources: show zero counts and offer Add source. A conversation can still be
  started without sources. Existing source forms remain the ingestion interface.
- No conversations: explain that history is private and offer New conversation.
- No personal API tokens: show zero and link to generation for this account.
- No usage: display zero input/output totals without empty chart scaffolding on
  the hub. Existing detailed usage reporting retains its empty behavior.
- Missing shared prompt: preview the shipped default without creating a database
  record on GET. Editing/saving remains the explicit write path.
- Invalid forms retain their inputs and visible validation feedback, remain in
  the same account context, and return 422. Destructive operations keep existing
  confirmation behavior. Unauthorized requests never queue jobs or mutate data.

### Accessibility and visual behavior

- Retain the existing app typography and neutral/green palette. Use existing SVG
  assets for new account UI icons, consistent focus styles, real links/buttons,
  semantic headings, and useful accessible names. Decorative icons are hidden
  from assistive technology; role/state is never conveyed by color alone.
- Ensure text contrast of at least 4.5:1 and meaningful UI/focus contrast of at
  least 3:1 independently in light and dark themes. Use comfortable 44 CSS-pixel
  action heights as a design target, without confusing native point/dp rules with
  web accessibility requirements.
- Keyboard order follows visual/DOM order. Actions work without a pointer and
  focus is not hidden behind navigation. No new animated charts or motion effects;
  any transitions honor reduced motion.
- Check the hub/index at 375, 768, and 1440 CSS-pixel widths; check phone landscape,
  long names/identifiers, French labels, and browser zoom at 200%. Do not clamp
  account names so aggressively that the only identification is lost.
- The current application layout disables browser zoom via viewport metadata;
  remove that restriction as a directly relevant accessibility fix. Scope other
  layout changes to the account experience rather than redesigning app chrome.
- English and French copy use the project's I18n conventions.
- Verified ui-ux-pro-max guidance used: Accessibility / Keyboard Navigation,
  Interaction / Focus States, and Feedback / Empty States. The progressive
  disclosure searches did not produce a verified match and are not adopted.

### Data flow and performance

- Render the hub server-side as a snapshot, refreshed on navigation/reload; no
  new polling, broadcast aggregates, or client-side state store. Existing source
  lists retain their live updates with the correct account context.
- Paginate the index at 24 accounts per page, ordered by name then ID. Count
  summaries for visible accounts with grouped queries, not per-card queries.
- Scope each summary to the authorized account and current user where required.
  Use existing cached account token counters. Bound recent history to five rows
  and eager-load/select the title information without a query per conversation.
- Paginated history uses 25 root chats per page, with stable ordering. Preserve
  the existing first-user-message title behavior and use Untitled conversation
  when no usable title exists. No new conversation search system is included.
- No external provider requests, ingestion, or background generation occurs merely
  by visiting the index, hub, history, usage, tokens, or prompt pages.

### Verification strategy

- Minitest with fixtures; use a member of two accounts, another member in the
  same account, an owner, and an outsider, with distinct records/totals per account.
- Request coverage for index/show/history, second-account scoping on every linked
  tool, all four source types, creation/edit/cancel/redirect/pagination, scoped
  source uploads/retries, malformed/conflicting account references, revoked
  membership, and no write/job side effects on rejected requests.
- Permission coverage for member versus owner reads/mutations, legacy shared
  prompt edit/update/destroy bypass attempts, private conversations, and personal
  API-token visibility/create/revoke/one-time reveal. Owners never gain access to
  others' chats or API tokens.
- Regression coverage for existing unscoped source, usage, token, account-settings,
  prompt, and chat entrypoints. Test account-aware source links after background
  broadcasts, without relying on Current or a browser session during rendering.
- Query checks cover index grouped counts and history title loading, guarding
  against per-card/per-row N+1 queries. Tests run without real provider calls.
- System coverage for index → hub → new conversation in a non-first account,
  source-type navigation, history resumption, admin versus member views, account
  editing return path, and token management in the viewed account.
- Browser checks cover responsive themes, French, long content, zoom, keyboard
  navigation/focus, and empty states. Run focused tests, relevant existing suites,
  lint, and security checks before claiming implementation is complete; distinguish
  unrelated existing failures from new regressions.

## Scope boundaries

This is one account-navigation and account-context feature over existing tools,
not a rebuild of those tools. No new billing/tiers, source types, ingestion or
retrieval algorithms, shared conversations, personal-prompt generation rules,
token analytics, account deletion/ownership transfer, global account switching,
provider management, new packages, or database migrations. Existing non-REST
actions are not broadly refactored; new resources follow REST conventions.

## Implementation boundaries

- **Account index/hub:** `AccountsController#index/show` authorize membership,
  collect bounded model-backed summaries, and render focused ERB partials.
  `Account` and existing associations/model APIs own account data access; no
  business-logic service objects or monolithic view helpers are introduced.
- **Account-scoped tools:** route/controller scoping resolves one authorized
  account and passes it explicitly to existing source and reporting code. Shared
  guards enforce owner permissions before loading other users or writing state.
  Existing sources/usage/token templates are shared with account-aware paths and
  form targets rather than copied into competing implementations.
- **Conversation history:** an account-nested REST index reads the current user's
  root chats for that account; existing chat show/create contracts remain the
  authority for saved-chat access and new-conversation generation.
- **Presentation:** focused account partials and existing design primitives own
  cards, summary panels, empty states, and breadcrumbs. Use normal Rails links and
  forms, with Turbo/Stimulus only where existing interactions already require it.
- **Broadcast source rendering:** source account identity is available from the
  persisted record, independent of request context. Reuse existing per-account,
  localized stream names and keep rendered operations account-specific.

## Acceptance criteria

1. A member can open a non-first account from the index, see only its summaries,
   and start a conversation with that account preselected.
2. All four source-type links open the correct filtered account list, and source
   reads/writes/uploads/retries, filters, pagination, and live-rendered links never
   fall back to another account.
3. Hub and full history show only the user's conversations for the viewed account;
   another member's chat is absent even when the viewer owns the account.
4. Account users, shared prompt, account editing, personal API tokens, and token
   usage are discoverable with the approved member/owner visibility and request
   permissions. Usage is account-wide; chats and API tokens remain personal.
5. Creating/editing an account and following cancel/breadcrumb/return links follows
   the approved hub-centered navigation without changing the global account.
6. Empty states, light/dark themes, French, keyboard navigation, responsive layouts,
   and browser zoom are usable, with no new frontend framework or package.
7. Visiting the hub and read-only tools does not create prompts/sources/chats,
   enqueue ingestion or generation, or call a model provider.
8. The focused account/context/authorization suites and relevant regressions are
   verified before implementation completion, with unrelated baseline failures
   explicitly identified rather than hidden.

## Decisions

- **“Yes” to the visual companion.** Use browser mockups for visual choices and
  keep requirements and permission questions in the conversation.
- **“Overview hub (Recommended).”** Show summaries and recent conversations,
  with New conversation prominent; reuse dedicated account-scoped tools instead
  of building an integrated workspace.
- **“My chats only (Recommended).”** Preserve existing conversation privacy in
  previews, counts, and history, including for account owners.
- **“Edit account details.”** Account edition means the existing name and
  identifier form; subscription plans and billing are out of scope.
- **“Owner-only administration.”** Only the owner edits account details and the
  shared system prompt or manages membership; members retain personal API-token
  management. This intentionally tightens the current detail/prompt editing rules.
- **“A.”** Use the Balanced overview layout with compact account-index cards,
  sources/recent conversations as primary content, and usage/administration as
  supporting content.
- **“Approve page design.”** Accept the detailed index/hub content, responsive
  stacking, member visibility, shared-default prompt label, and suppression of the
  duplicate global conversation drawer on account pages.
- **“Approve navigation.”** Accept explicit account-scoped tool workflows,
  unchanged global account selection, private paginated history, reusable existing
  interfaces, hub return paths, and request-enforced permissions including legacy
  shared-prompt routes.
- **“Approve design.”** Accept empty-state behavior, bounded server-rendered
  summaries/lists, accessibility including browser zoom, verification coverage,
  and scope boundaries; proceed to a committed written specification for review,
  not directly to implementation.
