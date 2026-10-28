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

The workspace supports English/French and light/dark themes, narrow layouts,
keyboard navigation and mobile navigation clearance. Native 200% zoom and any
unexercised browser/platform require separate verification; viewport emulation is
not proof and sampled checks are not an exhaustive accessibility audit.

See the [approved design](superpowers/specs/2026-10-27-mcp-workspace-ui-ux-design.md)
for scope, decisions and acceptance requirements.
