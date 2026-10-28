# Prompts, account members and API tokens UI/UX

Status: All five design sections approved in chat. Written specification awaiting
user review before implementation planning. Documentation only; no application
implementation is authorized or claimed here.

Date: 2026-10-28.

## Goal and authority

Continue the Balanced workspace direction from the dashboard, Sources, Token
usage, Agent skills, Accounts/Settings and MCP into the remaining requested
prompt, member and API-token screens. Improve visual consistency, context,
validation recovery and action feedback without adding capabilities or changing
permissions, account defaults or security rules.

**Shared styling does not mean shared management pages.** System prompts, account
members and API tokens remain separate resources on their dedicated pages. No
member/token lists or forms are embedded in prompt pages, and no combined
administration screen is introduced.

The [shared workspace design](2026-10-24-workspace-tools-ui-ux-design.md),
[Accounts/Settings design](2026-10-26-accounts-settings-ui-ux-design.md) and
[MCP design](2026-10-27-mcp-workspace-ui-ux-design.md) provide visual precedents,
not permission to reuse old test waivers or change their completed features.

## Scope

| Page variant | Existing path | Purpose |
| --- | --- | --- |
| Prompt directory | `/system_prompts` | Review existing saved prompts across authorized accounts |
| Prompt detail | `/system_prompts/:id` | Read one existing prompt |
| Prompt editor | `/system_prompts/:id/edit` | Edit that prompt where currently permitted |
| Account default prompt | `/accounts/:id/system_prompt` | Read the saved account default or built-in fallback |
| Account prompt editor | `/accounts/:id/system_prompt/edit` | Edit/save that account default as the owner |
| Account members | `/accounts/:id/account_users` | Owner-only membership management |
| Personal API tokens | `/api_tokens` | Create/revoke the current user's tokens |
| Account-filtered personal tokens | `/accounts/:id/api_tokens` | The same user's tokens in an authorized account context |

The user explicitly included the existing account-filtered token variant after
the shared view was identified. Preserve existing routes, verbs, lookup scopes
and working contracts. No aliases, new management destinations or new custom
controller actions are needed.

### Non-goals

- No combined prompt/member/token page, new admin hub or cross-resource editor.
- No prompt generation/testing, rich-text editor, autosave, history, reset, new
  prompt creation/deletion controls or prompt-resolution changes. Preserve the
  existing destroy endpoint rather than silently removing it.
- No invitations, user creation, email notifications, role editing, ownership
  transfer, self-leave workflow or public user-search/autocomplete endpoint.
- No token scopes, expiry, rotation, usage analytics, bulk actions, later secret
  reveal or owner management of other users' credentials.
- No new frontend framework/package, database schema, service/form/policy layer,
  API authentication redesign or token-delivery mechanism.
- No unrelated redesign, permission repair, prior-baseline suppression, merge,
  push, PR or worktree cleanup.

## Current context and isolation

The design was explored against completed MCP source at
`7339a1789aa8a6d5f7b3bfd96b02e6850e1cc348`. A documentation-only sibling worktree,
`prompts-members-tokens-design`, on branch `docs/prompts-members-tokens-ui-ux`
starts from that exact revision. The completed MCP branch/worktree and main's
unrelated work remain untouched. No application setup, dependency installation,
database preparation or test execution was needed for writing this design.

Use the actual checked-in/runtime Rails, ERB, Hotwire, Importmap, Tailwind,
Minitest/fixture and ID conventions; generic stack summaries do not authorize an
upgrade or schema change.

Important existing behavior:

- The prompt directory queries system-prompt records in the current user's
  accounts, not only their own user-specific records. Shared prompt mutations
  require account ownership; other existing prompt permissions remain unchanged.
  A user-specific label must not imply new privacy or ownership restrictions.
- Account prompt reads/edits construct an unsaved built-in fallback when no saved
  account default exists. GETs do not materialize records. Runtime prompt lookup
  prefers a user-specific prompt, then the account default, then built-in text.
- Prompt content is required. Global invalid updates currently render the read
  page; account invalid updates render the editor. Recovery polish will make
  failed edits remain on their corresponding editor without weakening validation.
- Membership management is owner-only and adds an existing user by email. Unknown
  or duplicate-user failures currently redirect and lose the entered value. The
  controller prevents removal of the owner.
- Tokens belong to their creator. Global token scope is the current user's tokens;
  the account route filters that scope and authorizes its path account. Creation
  uses an existing default/filing account, not a new API permission scope.
- Token rows persist only a digest. The existing successful-create redirect uses
  a transient one-time plaintext handoff. Saved values cannot be retrieved again.
  Retain that mechanism and API authentication rather than redesigning storage.
- Shared workspace components and an existing pinned clipboard component are
  available. Focused reuse/enhancement must not change unrelated consumers.

## Decisions

- User answered **“Yes”** to the local browser visual companion.
  Rationale: compare layouts visually before approval; this is not implementation
  permission or application verification.
- User selected **“Workflow polish (Recommended)”**: layout, context, validation
  recovery and action feedback, without new capabilities and while preserving
  permissions, account scope and security rules.
  Rationale: extend the established visual/workflow direction, not just repaint
  existing failure states.
- User selected **“Include both (Recommended)”** for global and account-filtered
  API tokens.
  Rationale: improve their shared experience while retaining their distinct list
  contexts, token ownership and existing access rules.
- User selected **“A - balanced workspace”**, with the constraint **“I don't want
  to manage API tokens and account members on the same page than system prompts.”**
  Rationale: one coherent visual language with strictly separate resource pages;
  no embedded member/token management on prompt screens.
- User answered **“Yes”** to section 1 — navigation and page boundaries.
  Rationale: approve shared shell conventions, explicit context, scoped New chat
  and preserved defaults/navigation without combining management pages.
- User answered **“Yes”** to section 2 — system prompts.
  Rationale: approve readable rows/details, truthful fallback, plain-text editing
  and recoverable invalid saves, with unchanged precedence and read-only GETs.
- User answered **“Yes”** to section 3 — account members.
  Rationale: approve a dedicated owner-only existing-user flow, protected owner
  display, contextual removal confirmation and retained-email error recovery.
- User answered **“Yes”** to section 4 — personal API tokens.
  Rationale: approve dedicated token pages, safe creation recovery, one-time
  output, truthful clipboard feedback/manual fallback and contextual revocation.
- User answered **“Yes”** to section 5 — architecture and verification.
  Rationale: reuse Rails/Hotwire, verify eight variants across locale/theme/size,
  establish fresh baselines and durable evidence, then review the written spec
  before implementation planning. Chat approval does not authorize coding.

## Selected approach

**A — Balanced workspace** uses readable rows for directories and management,
focused prompt reading/editing, and compact task forms. It follows the existing
neutral/green visual system and reflows naturally at lower density than tables.

Alternatives compared were **B — Compact management**, with aligned tables for
greater desktop density but more narrow-screen adaptation, and **C — Guided
cards**, with larger explanatory panels but more repetition and scrolling.
Neither alternative changed permissions or capabilities. The initial comparison
combined miniature excerpts only to compare styling; the revised studies show
one separate application page at a time, as explicitly requested.

## 1. Separate pages and shared navigation

- Keep the eight route variants above as distinct pages. Ordinary contextual links
  may connect them; links do not justify embedding another resource's management
  interface. The existing Settings hub and account entry points remain intact.
- Give each page one browser-tab title, one `h1` and one breadcrumb. Global prompt
  and token trails begin Home / Settings. Account tool trails begin Home /
  Accounts / account name. Detail and Edit extend their own resource trail;
  ancestors are linked and the current item is plain text with current semantics.
  Do not duplicate the shared header's title assignment.
- Make account and resource context explicit. Keep existing lookup scopes rather
  than forcing global prompt/token pages into the current default account.
  Account-route forms, links, Cancel, redirects and feedback retain that route's
  account. Body/query values cannot override the authorized path account.
- Preserve existing owner/member permissions and foreign/revoked/malformed
  context behavior. Do not add fallback to another account or change a user's
  default. Authentication/authorization failures are not ordinary field-validation
  errors and must not expose foreign identities or records.
- Reuse system typography, neutral/green surfaces, local decorative outline SVGs,
  wrapping content, English/French and light/dark themes. Translate owned labels,
  not authored account names, emails, token names or prompt content.
- Keep global header, left/mobile navigation and quiet New chat access. Global
  routes retain generic New chat; account-route New chat opens the existing
  account-preselected composer without creating a chat or changing defaults.
- Remove unrelated conversation-history drawers only on these page families,
  including editors and scoped variants. Preserve unrelated pages and their
  existing drawer/navigation behavior. Do not add mixed-resource tab panels.

## 2. System prompts

### Directory and reading

- List existing authorized saved prompt records in readable rows with account
  identity and truthful **Account default** / **User-specific** labels. Preserve
  the current record set and ordering; do not filter user-specific records to a
  new privacy model, label all of them “yours”, or expose additional personal data
  merely to distinguish rows. No new search/filter system is needed.
- Keep prompt identity/read routes reachable. If no saved records exist, explain
  that state and offer existing account navigation to review defaults. Do not
  create defaults just to fill the directory.
- Details provide one contextual Edit action where currently permitted, rather
  than duplicated competing controls. Display account and prompt type clearly.
- Use a readable text panel with preserved paragraphs, line breaks and literal
  placeholders. Escape authored content safely without rewriting stored text or
  evaluating placeholders in the UI. No member or token management appears here.
- On the account-default page, distinguish a **Saved account prompt** from the
  **Built-in default** when no row exists. Explain that user-specific prompts take
  precedence. Viewing or opening Edit does not save/materialize the fallback;
  only an explicit successful update does.
- Preserve runtime prompt selection and generation behavior. Do not claim changes
  affect only new chats or execute an AI request merely by visiting/saving.

### Editor and recovery

- Retain a plain-text, vertically resizable editor with a meaningful required
  content label, readable text size and connected help. Keep exact submitted
  content and placeholders; do not add rich-text conversion, normalization or
  other silent content changes.
- Save is primary. Cancel returns to the corresponding global/account read page.
  Controls stay in normal flow with mobile navigation clearance, not a floating
  footer. Use distinct saving feedback and duplicate-submit prevention.
- Failed validation returns **422 on the corresponding editor**, retains submitted
  text, and exposes a focused linked error summary plus inline content errors
  connected through invalid/described-by semantics. Preserve presence validation
  and ordinary native required validation. Do not move focus on every blur.
- Successful Save returns to the corresponding detail page with localized status
  feedback. Errors do not mutate the saved prompt or materialize an invalid
  fallback. Preserve the existing destroy endpoint without introducing new
  creation/deletion controls, history, reset, autosave or prompt runners.

## 3. Account members

- Keep `/accounts/:id/account_users` dedicated to membership for its named account.
  Preserve owner-only page/mutation access; do not introduce a new read-only roster
  for non-owners or widen user discovery.
- Place a compact **Add an existing user** panel above member rows. Explain that
  the email must belong to an existing Nosia user and that this is not an
  invitation. Do not create users, send email or add roles/ownership controls.
- Rows show full wrapping emails, truthful **Owner** and **You** labels where
  applicable, and clear actions in normal flow. No truncation, hover-only tooltip
  dependency or controls overlaid on content.
- Show owner protection as static explanation, not a fake disabled button. Keep
  the server-side prohibition on owner removal even for a forged request.
- Removable rows have a clearly named **Remove member** action. Retain confirmation
  behavior with the member email and account name; explain that it removes this
  membership, not the user account. Do not promise token revocation, data deletion
  or other new security effects. Cancel leaves membership unchanged.
- Failed addition returns **422 on this page**, retaining the entered email with
  a focused linked summary and an inline email error. Distinguish unknown existing
  user and duplicate membership where the current owner-authorized lookup permits
  it. Preserve native required/email validation and existing lookup semantics;
  add no public search/autocomplete endpoint or unrelated identity disclosure.
- Successful add/remove retains account context and announces localized status.
  Busy feedback prevents duplicate submission without an indefinite page lock.
  Removing a member does not delete their User record or change other accounts.
- When only the owner is listed, retain the row and explain **No additional
  members yet**, with addition still available. Do not replace it with a misleading
  completely empty roster or add bulk removal/filtering/pagination features.
- No prompt editor or API-token management is embedded on this page.

## 4. Personal API tokens

### Ownership, layout and creation

- Global scope remains `Current.user.api_tokens`; account scope remains that
  user's tokens filtered by the authorized path account. Do not show other
  members' tokens to owners, reassign tokens or introduce a new access model.
- Use a compact creation panel first in logical visual/DOM order, beside the
  wider token list on desktop and above it on mobile. The one-time result, when
  present, precedes both. Names, default-account labels and security guidance wrap.
  No prompt/member management is embedded.
- Require a recognizable name and the existing **Default account**. Global
  creation offers only authorized account choices; the account route fixes/names
  its URL account. Preserve existing account-forgery protections. The default
  account is not a new API permission scope; do not claim all possible API
  behavior is restricted to it.
- Invalid creation returns **422 on the same global/account form**, retains the
  name and authorized account selection, and uses focused linked/inline errors.
  Preserve native validation and fail closed for unauthorized/malformed context.
  A failed save persists no token row and renders no successful new-token value.
- Distinguish no personal tokens from none for this account. If the user has no
  available account, replace the unusable generation form with existing account
  setup/navigation. Preserve visibility/revocation of any already-owned tokens;
  do not auto-create accounts or change the default to make the form work.

### One-time output and copying

- After successful creation, prominently show **Copy your new token now**, with
  token name/default account context and an explicit shown-once/security warning.
  Provide a labeled read-only selectable field and visible **Copy token** button.
  A long value may scroll within its input but remains fully selectable/copyable;
  do not irretrievably ellipsize it or cause page-wide overflow.
- Keep digest generation/storage, authentication and the existing transient
  creation-to-redirect handoff. Saved rows never render plaintext or digests.
  Add no later-reveal capability, persistent client storage or new delivery system.
- Focus the creation-result heading/container as appropriate after submission;
  do not automatically copy the secret or include its value in live status text.
  Copy is an explicit user action, with **Copied** announced only after the actual
  clipboard write succeeds. Copy feedback should not unnecessarily move focus.
- If clipboard access is unavailable or rejects, announce useful manual-copy
  guidance and keep the read-only field selectable. Do not falsely show success,
  hide the only available value or require a new clipboard dependency.
- Prevent app/Turbo snapshots from redisplaying the one-time secret after leaving.
  Verify refresh and application Back navigation in the exercised browser. Do not
  add secret duplicates in logs, hidden fields or persistent browser storage.
  This does not promise erasure from an explicitly used clipboard, screenshots
  or every browser/OS internal retention mechanism.

### Revocation and feedback

- Use **Revoke token** with confirmation naming token and default account. Explain
  that clients using that token will stop authenticating. Keep existing deletion
  semantics and ownership scoping; cancel leaves the token intact.
- Success retains global/account context and provides localized status. Use
  distinct generation/revocation busy text and duplicate-submit prevention.
- No expiry, scopes, rotation, analytics, bulk actions or other new credential
  management capabilities are added.

## 5. Architecture and compatibility boundaries

Reuse Rails partials/helpers, the existing shared workspace shell, Turbo and
small focused Stimulus enhancements. Share presentation conventions without
merging domain responsibilities or resource pages. Preserve REST controllers,
model validation/domain boundaries, Importmap and local SVG assets. No new
service/form/policy layer, package, framework or schema is required.

Targeted controller/form changes for the approved 422 recovery and safe scoped
feedback are in scope. They do not authorize changing authentication, member/
prompt mutation permissions, current defaults, token authentication/storage,
prompt selection, existing working API contracts or unrelated feature behavior.
Keep existing clipboard consumers working if a scoped enhancement is needed.

Do not materialize records on reads, send invitations, start generation, introduce
polling or silently normalize authored content. Any independent security or
baseline issue discovered during planning/execution must be reported separately,
not silently repaired or accepted under this visual/workflow specification.

## 6. Verification and delivery gates

1. **Fresh baseline:** before application changes, establish isolated current
   request/model/full/browser/lint/security results. Earlier MCP findings and
   acceptance are historical clues, not waivers for this project. Report exact
   reproduced identities/messages and obtain direction before continuing with
   exceptions. Do not exclude tests, suppress findings or fix unrelated failures.
2. **Test-first behavior:** use Minitest/fixtures and local fake users/tokens.
   Cover global/scoped reads/mutations, current owner/member rules, foreign/
   revoked/malformed/no-account contexts and forged overrides. Verify unchanged
   defaults, prompt record sets/precedence/content/placeholders, read-only GETs,
   explicit-only valid fallback materialization and failed-save atomicity.
3. **Workflow coverage:** test unknown/duplicate member recovery, owner protection,
   confirmed/canceled removal, personal token ownership and digest-only storage,
   successful/failed creation, copy success/rejection/manual fallback, and no
   one-time secret restoration on refresh/app history. Use only fixture secrets;
   no real user credentials, user-creation emails or external AI requests.
4. **128-state base matrix:** exercise all eight page variants in English/French,
   light/dark and actual CSS viewports **375×812**, **768×1024**, **1440×1000** and
   **812×375**. Each combination must be unique. Empty/fallback/error/copy/busy/
   confirmation/permission cases are additional workflows, not substitute base
   states. Representative permitted views do not replace authorization tests.
5. **Interaction/accessibility:** exercise real Tab/Shift+Tab/Enter, visible
   unobscured focus, ≥44px actions, long names/emails/prompt text, mobile navigation
   clearance, reduced motion, required/email validation and genuine submit-result
   summary/field focus. Measure normal text **≥4.5:1** and meaningful nontext
   **≥3:1** against actual normal/hover/focus surfaces in both themes. Prove actual
   hover surface changes when claiming hover results. Label and restore any
   dedicated capability-emulation/session setup; do not overwrite protected drivers.
6. **Protected regressions:** recheck dashboard, Sources, Token usage, Agent skills,
   Accounts/Settings, MCP and existing prompt/member/token tests. Retain their
   substantive assertions while precisely updating any approved presentation
   expectations; do not weaken ownership, secret or behavior checks to go green.
7. **Final quality/evidence:** run focused/full/browser checks, lint/security,
   changed public Ruby YARD and documentation/link verification. Preserve actual
   commands, true exits, source/tree identity, state metadata, representative
   images and interaction samples in a durable ignored evidence directory, not
   only ephemeral `/tmp` files. Do not report accepted nonzero results as green or
   documentation commits as fresh application verification.
8. **Honest limits:** native **200% browser zoom is UNVERIFIED** without actual
   browser-zoom evidence. Viewport/input emulation is not hardware or zoom proof;
   sampled checks are not an exhaustive screen-reader/accessibility audit.
   Unexercised browsers/platforms require separate verification. The visual studies
   below are not application screenshots, tests or evidence of compliance.

After this written specification is reviewed by the user, invoke writing-plans.
Implementation requires the resulting plan and execution gates; no merge, push,
PR or worktree cleanup is authorized by design approval.

## Research and visual references

Verified local ui-ux-pro-max recommendations used as guidance, not new authority:

- `error summary validation`, domain `ux`: **Forms / Accessibility — Focusable
  Error Summary**, platform Web. Focus after failed submit, links to invalid
  fields, retained inline errors and no focus movement on blur fit these forms.
- `readable long text editor`, domain `ux`: top result **Responsive — Readable
  Font Size**, platform All. This supports readable mobile text, not a new editor
  dependency or editor-specific feature requirement.
- `destructive action confirmation`, domain `ux`: **Interaction — Confirmation
  Dialogs**, platform All. Retain confirmations and clear successful-action
  feedback; contextual wording does not require a new custom modal system.
- No verified clipboard-specific match was found after one narrower UX retry.
  General accessible feedback principles informed copy status, explicitly not
  clipboard-specific research or permission to alter token security rules.

The persisted illustrative studies are in the original MCP worktree's ignored
`.superpowers/brainstorm/20221-1793174098/` directory:
`layout-directions.html`, `separate-pages-navigation.html`,
`prompt-reading-editing.html`, `account-members-recovery.html` and
`api-token-creation-recovery.html`. Their preview choosers are design controls,
not proposed application tabs; fictional token values are not credentials.

This specification is self-contained and does not depend on an active companion
URL or those ignored files. No application boot, database setup, feature baseline,
application test run or implementation change was performed during brainstorming
or writing this documentation-only specification.
