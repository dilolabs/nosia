---
title: "RubyLLM 2.0 upgrade: migration and lifecycle integration pitfalls"
date: "2026-10-14"
problem_type: integration_issue
component: "RubyLLM persistence and vendored MCP bridge"
symptoms:
  - "Generated migration rejects integer assistant roles or valid NULL content."
  - "Deleting migrated tool conversations violates a retained legacy foreign key."
  - "Completion returns assistant prefill or system instructions without generating."
tags: [ruby-llm-2, postgresql, data-migration, lifecycle, token-accounting, mcp]
---

## Problem

Updating the dependency alone did not preserve Nosia's data or generation
semantics. Its schema differs from the generated defaults, and RubyLLM 2.0's
`complete` resumes pending work rather than always requesting a provider response.

## Migration fixes

Keep chat/message IDs, integer roles, attachments, application usage records,
and counters unchanged. Adapt the generated rename phases, not the RubyLLM core:

1. All three usage-candidate predicates must use historical assistant role **10**,
   not `'assistant'`. Keep this historical value independent of today's model.
2. Backfill and finish must accept NULL plaintext when raw JSON is blank, while
   still detecting missing or corrupted nonblank conversions. Reuse the pinned
   upstream renderer and PostgreSQL null-safe comparison:

   ```ruby
   rendered_content = RubyLLM::Generators::LegacyContentSQL.new(connection).render(
     content: quote_column(:content), raw: quote_column(:content_raw)
   )
   invalid = "raw_content IS DISTINCT FROM content_raw::jsonb OR " \
     "content IS DISTINCT FROM (#{rendered_content})"
   ```

3. Change only the obsolete `messages.tool_call_id` foreign key to
   **ON DELETE SET NULL**. RubyLLM 2.0 can delete its internal call before the
   historical result; cascading deletion would lose the result. Preserve other
   constraints and validate this replacement with retry-aware migration code.

Do not replay the application `token_usages` ledger from `ruby_llm_usages`.
They serve different purposes; replay would double-count existing history.
Historical unknown costs remain NULL, not zero or newly calculated prices.

## Generate versus complete

Empty, system-only, and assistant-ended histories without pending tool calls
are already `complete?` in 2.0. An explicit MCP prompt request therefore needs
public `generate`, followed by the ordinary tool/approval loop:

```ruby
def ask(chat, arguments: {}, &)
  include(chat, arguments: arguments)
  chat.generate(&) if chat.complete?
  chat.complete(&)
end
```

Both sampling modes explicitly call `generate` once. Do not add a fabricated
user message or force private APIs to bypass completion state.

The API has different intent: persist its actual `prompt:` as a user message,
and reject input with no pending response **before inserting private system/RAG
instructions**. Otherwise JSON can return instructions as an answer and SSE can
finish without generating.

## Regression strategy

- Preserve the real legacy schema and guard the exact disposable database before
  fixture setup. Test IDs, NULL/blank raw variants, attachments, usage/counters,
  deletion through real associations, and interruption after committed batches.
- Fake HTTP, not `complete`. Verify provider-request counts, generated model/content,
  user/assistant/system endings, streaming, tools, approvals, and cancellation.
- Test real PNG/WAV bytes through persistence and wire encoding. Keep attachments
  typed for the model, but serialize them explicitly as Base64 at JSON endpoints.
- Resource links must enforce the application's URL policy before HTTP fetches;
  adding all-block conversion can expose previously skipped fetch paths. The
  existing DNS-rebinding/TOCTOU limitation remains, not claimed eliminated.
- Verify the vendored Gemfile path exists at the Docker dependency-install layer;
  copying directory contents into the wrong destination breaks Bundler.

Tests: `test/upgrades/ruby_llm_v2.rb`, `test/lib/ruby_llm_mcp_generation_test.rb`,
`test/lib/ruby_llm_mcp_compatibility_test.rb`, API/MCP controller tests, and
`test/packaging/ruby_llm_path_dependency.rb`.

## Verification and deployment boundary

Reviewed runtime: `88a2a18`. Full suite: **466 tests / 2106 assertions, zero
failures and one accepted existing crawl error**, not an all-green result.
Migration rehearsal: **12 / 154**, passing; packaging: **2 / 8**, passing.

Use the [operator runbook](../../upgrades/ruby-llm-2-deployment.md),
[chronological evidence](../../upgrades/ruby-llm-2.md), and
[MCP patch inventory](../../../vendor/gems/ruby_llm-mcp/PATCHES.md).
Production-sized rehearsal, tested backup/restore with the matching 1.16 build,
and live authenticated interoperability remain operator gates. Rename recovery
requires restoring the database and application together; retained columns are
not a rollback copy. Cleanup is a separately approved later deployment.
