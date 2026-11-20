# MCP workspace

MCP servers are managed within one account. Unscoped pages use and name your
existing default account; `/accounts/:account_id/mcp_servers` and the corresponding
catalog URLs retain their explicit account. Visits do not change the default.
Existing member permissions apply; another account’s records are not accessible.

Browse catalog is the main addition path; Add custom server remains available.
Server rows separate availability for conversations from the last recorded
connection state. Filters do not change records. Catalog “Added” does not mean
connected, and Save/Add do not automatically test or connect a server.

Details include Overview, Tools, Prompts and Resources. Capability browsing is
read-only; schemas can be expanded. Tabs support keyboard navigation and hash
links, and the sections remain readable without JavaScript. There are no new
tool/prompt test runners. Unavailable counts are not reported as zero.

Blank credential edits keep saved values; entering a replacement replaces only
that field; explicit removal clears it on Save subject to required-field rules.
Saved secrets are not shown or restored after failed submissions. Public fields
remain on invalid forms with linked and inline errors. Built-in and stdio
deployment restrictions are preserved; no raw configuration editor is provided.

Test saved configuration is separate from Save. It uses saved values, ignores
unsaved edits, and returns to server details. Connection actions show busy/result
feedback without continuous polling. Delete removes this account’s configuration,
not the external service, and still requires confirmation.

## Connect with OAuth

1. In the account’s MCP workspace, choose **Streamable HTTP** and **OAuth**.
   Enter the provider’s public HTTPS MCP endpoint and save. Save/Add never
   starts consent or contacts the server.
2. On the server’s details page, choose **Authorize with OAuth**. Complete
   provider consent in the same signed-in Nosia browser session that started
   it. If the attempt expires, or you switch sessions, start again from the
   server’s details.
3. A successful callback returns to that account and connector with localized
   feedback. If the connector is enabled for chats, you can select it from
   **Tools** without running a separate connection test.

The workspace shows **Authorization required**, **Authorized**, or **Reconnect
required** for the current member, independently of the account’s shared
**Enabled for conversations** setting. Each member grants access separately.
Testing the saved connection, browsing capabilities, and executing workspace tools
use only the acting member’s grant. In a conversation, including background
turns, Nosia uses the saved chat owner’s grant for the chat’s account and checks
that the owner is still a member. It never substitutes the viewer’s grant,
another member’s grant, or a shared token. If a linked connector is unavailable,
the chat can continue without it. The link is preserved under **Unavailable
tools** and can be removed from the chat.

**Reconnect with OAuth** starts fresh consent from **Reconnect required**; **Clear
my authorization** instead removes that grant. To replace a still-usable grant,
first choose **Disconnect my authorization**. Disconnect forgets only your
local grant. It does not revoke consent at the provider, turn off the shared
switch, or affect other members. To revoke provider-side access, use the
provider’s own controls. Changing the connector’s endpoint or authentication
mode retires its saved grants. If the new configuration uses OAuth, each member
must authorize it again.

The workspace and chat controls and feedback are available in English and
French. For example, the French workspace shows **Autoriser avec OAuth** and
**Reconnexion requise**, and the chat shows **Outils indisponibles**. The
provider’s consent page has its own language settings.

### Provider and deployment requirements

- OAuth requires public HTTPS for the Streamable HTTP MCP endpoint and for
  the OAuth discovery, dynamic client registration, browser consent, and token
  endpoints. Their hostnames must resolve only to public addresses. If Nosia
  reports that the provider does not register apps automatically, use a
  compatible connector or ask the provider to enable dynamic registration. A
  provider that requires a pre-registered client ID or secret is not supported,
  and no named provider is guaranteed. The flow uses the web browser; there is
  no separate desktop handoff or support for additional OAuth modes or custom
  scopes.
- Set `NOSIA_URL` to the exact public HTTPS origin users open in their browser:
  scheme and host, plus the port if non-default, without a path, query, or
  fragment. For `NOSIA_URL=https://nosia.example.org`, the exact callback is
  `https://nosia.example.org/mcp/oauth/callback`. A local-only or private origin
  does not work for OAuth.
- Keep the existing Active Record encryption settings
  (`ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`,
  `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`, and
  `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`). Use the same keys across web
  and workers and carry them forward on upgrade; do not generate new keys for
  an existing deployment. Nosia encrypts stored OAuth credentials using these
  settings.
- Keep callback query strings and OAuth consent redirect `Location` values out
  of reverse-proxy, access, and observability logs. Wherever request or
  response headers or bodies are captured, exclude OAuth tokens (including
  access and refresh tokens), client secrets, and signing material. If those
  values cannot be reliably redacted, disable the corresponding capture.
  Rails-side filtering does not sanitize upstream logs. Preserve
  `Cache-Control: no-store` and `Referrer-Policy: no-referrer` on OAuth
  responses through the proxy.

Static authentication (none, bearer token, or API key) is still available.
Plain `http://` is allowed for legacy static compatibility only, and the
endpoint must still resolve only to public addresses. Plain HTTP does not
encrypt credentials or MCP data in transit. Prefer HTTPS.

## Migrate a legacy SSE connector

Legacy SSE transport is unavailable. Nosia preserves the connector record and
its chat links but does not use it for tools. Ask the provider for its
**Streamable HTTP** endpoint. Edit the existing connector, explicitly change
both the transport and the URL, and save. Then test the saved static
configuration or authorize with OAuth, as appropriate. Do not assume the old
SSE URL will work. Event-stream responses within **Streamable HTTP** are still
supported; it is the separate legacy SSE transport that was removed.

See the [deployment and rollback procedure](DEPLOYMENT.md#rubyllm-22-and-mcp-oauth-upgrade)
before upgrading an existing installation.

## Maintenance notes

The pinned RubyLLM 2.2.3 can send native MCP HTTP diagnostics to its unscoped
logger, bypassing the quiet MCP context. The temporary, approved shim suppresses
those calls only during an active MCP operation in the current fiber. Ordinary
inference logging and other fibers are unchanged. Remove the shim when the
pinned upstream release routes those diagnostics through the context logger and
`test/lib/mcp_native_logging_test.rb` passes without the shim.

Faraday may do a preliminary DNS lookup while evaluating environment proxy
settings. That lookup does not select the socket destination: the MCP adapter
always connects directly to its own validated, pinned IP, retaining the original
hostname for HTTPS verification. Neither the adapter nor the logging shim
changes global proxy, HTTP, or logging settings.

## Workspace accessibility

The workspace supports English/French and light/dark themes, narrow layouts,
keyboard navigation and mobile navigation clearance. Native 200% zoom and any
unexercised browser/platform require separate verification; viewport emulation is
not proof and sampled checks are not an exhaustive accessibility audit.

See the [approved design](superpowers/specs/2026-10-27-mcp-workspace-ui-ux-design.md)
for scope, decisions and acceptance requirements.
