# Signed-in dashboard

When signed in, `/` opens your workspace dashboard. The public signed-out root
is unchanged. Start a conversation directly in the existing composer, choose
its account, and use its PDF, source, skill, and tool controls normally.
The compact knowledge-source upload control retains upload/retry/removal and
account-switch safeguards without the former oversized upload area.

## Usage scope and dates

The overview combines account-wide usage across every account you currently
belong to, including other members' usage and source-indexing embeddings.
It is not a personal-only activity report. Accounts outside current membership
are excluded; revoked memberships disappear on the next request.

Input, output, total, and the daily line cover 30 calendar dates in the Rails
application time zone: midnight 29 dates before today through the request's
reference time, including both endpoints and excluding future events. Missing
days are zero-filled. Expand Daily token values for the same values in a table.
The footer's lifetime total comes from the existing account counters.

The global `/token_usage` page uses the same account set and period definition.
Lifetime breakdowns/environmental estimates are labeled separately. Explicit
`/accounts/:account_id/token_usage` pages remain account-specific; their existing
authorization, reporting semantics, and cache isolation remain intact.
No new token tracking, billing calculation, counter repair, or polling is added.

## Navigation and privacy

All eight destinations are visible: Accounts, Sources, Token usage, User profile,
Agent skills, API tokens, MCP servers, and System prompts. Sources, Agent skills,
and MCP servers retain their existing default-account behavior; the tiles name
that account. Selecting another account in the composer changes only the draft,
not global usage or those tool destinations. Other directories keep their
existing ownership and permission rules.

The recent panel shows at most five of your root conversations in accessible
accounts, with account names and activity times. Other members' conversations
are private even when you own the account. Previews are plain text and at most
120 characters; opening a conversation shows its full saved content. Browse
Accounts for complete per-account history. The dashboard replaces its duplicate
right history drawer; other pages keep their existing navigation.

Without memberships, the dashboard shows account-setup guidance and zero usage.
Default-account tool tiles lead to Accounts instead of broken destinations;
Profile and existing directory links remain reachable.

## Verification procedure

Use the dedicated test-only database and explicit environment commands in
`superpowers/plans/2026-10-24-signed-in-dashboard.md`. Run database-sharing suites
sequentially and never start live providers/ingestion workers for browser tests.
Inspect the produced root screenshots and contrast records in both themes,
verify keyboard order/unobscured controls and the daily table, and report actual
suite exits and any preexisting failures separately.

Native 200% browser zoom requires a separate headed/manual check. A small
viewport, device-scale override, or CSS zoom does not establish native zoom.
Record any unavailable manual check explicitly rather than implying coverage.
