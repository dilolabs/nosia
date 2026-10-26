# Agent skills workspace

## Account context

`/agent_skills` manages the current default account and names it explicitly.
`/accounts/:account_id/agent_skills` manages the account in that URL after a
membership check on every request. Settings opens the default-account tool;
the account overview's Agent skills link opens the scoped tool.

Creating, editing, viewing, enabling, disabling and deleting retain that route
family and account. Back and Cancel return to its list. Navigation never sets a
persistent account preference; submitted account IDs cannot move a skill.
Foreign, revoked or invalid account/record URLs return 404. A missing legacy
default account instead gets setup guidance on list/new.

## Managing skills

Rows show a description excerpt, tags, execution/trigger settings, priority,
RAG requirement and Enabled/Disabled. Ordering remains priority descending,
creation ascending. Counts refer only to the displayed account.

Use View for the full description/settings and complete raw SKILL.md. Edit opens
the native source form. Enable/Disable saves explicit intent and reports the
confirmed result; it does not execute or verify the skill. Ruby still requires
its configured implementation class.

Deletion lives on details. Its confirmation names the skill/account and explains
that recorded executions are deleted too. Cancelling does nothing. The existing
PATCH `/agent_skills/:id/toggle` remains available for compatibility; new browser
controls use POST/DELETE enablement resources instead.

## Writing and editing

The definition remains plain SKILL.md text with YAML frontmatter. Examples are
placeholders, not inserted content. Execution mode, trigger mode and Enabled are
visible; priority and RAG sit in Advanced settings. Collapsing Advanced does not
remove its submitted fields.

New defaults remain LLM, Explicit, Enabled, priority 0 and RAG off. Content is
required on creation; existing edit validation has not been tightened. Failed
validation retains submitted source/settings, exposes advanced errors, focuses
a linked summary and leaves the saved record unchanged.

The existing parser merges metadata but fills name, description and mode fields
only when nil. Editing frontmatter does not automatically rename or re-describe
an existing skill; the saved identity is shown read-only. There is no synchronized
preview or automatic source reformatting. RAG retains its existing metadata /
checkbox precedence: keep both consistent and clear any frontmatter requirement
as well when turning it off. Unexpected parser exceptions have not been redesigned.

Interface labels/help/messages support English/French and light/dark. Authored
names, descriptions, tags, instructions and machine enum values are not translated.
The API, runtime invocation and model validation behavior remain unchanged.

## Verification

The [specification](superpowers/specs/2026-10-26-agent-skills-workspace-ui-ux-design.md)
defines the account/content/accessibility contract. The
[implementation plan](superpowers/plans/2026-10-26-agent-skills-workspace-ui-ux.md)
records the actual execution revision, commands, exits, review results and any
limitations when implementation completes. Mockups are not browser-test evidence;
native 200% browser zoom is a separate check from viewport resizing.
