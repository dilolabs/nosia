# Accounts navigation and Settings

Accounts uses a Home → Accounts breadcrumb. An account overview adds the current
account name and retains its UID and your role. Add account opens the existing
account form. New conversation opens the composer with that account selected;
opening it does not send a message or start generation. Edit account remains
available only to the owner. Visiting accounts does not change a default account.

Settings is a navigation hub, not a settings form. Its four linked cards are:

- Agent skills: reusable instructions and their triggers.
- API tokens: your personal API access tokens.
- MCP servers: external tools and resources through MCP.
- System prompts: instructions that guide assistants.

Each destination retains its existing account/personal scope and permissions.
The hub does not add account switching, shared management permissions or new
destinations. Cards have distinct local icons, descriptions and one link each.

Settings uses two columns from 768px and one below that width. The unrelated
conversation-history drawer is absent on Settings; desktop New chat remains in
its header, and mobile retains the existing navigation action. Account forms,
nested tools and unrelated destination-page drawers are unchanged.

The three pages retain English/French, light/dark themes and keyboard navigation.
Long account names and labels wrap. Browser verification includes layout, focus,
contrast and clearance above mobile navigation. Native 200% browser zoom must be
reported separately from viewport emulation; it remains **UNVERIFIED**.

See [Account experience](account-experience.md) for permissions/data boundaries
and the [approved design](superpowers/specs/2026-10-26-accounts-settings-ui-ux-design.md)
for scope and acceptance requirements.
