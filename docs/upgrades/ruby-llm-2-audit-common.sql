-- Included by the before/after audits inside a READ ONLY transaction.
\echo message_identity_and_retained_columns
SELECT id, chat_id, role, model_id, tool_call_id, input_tokens, output_tokens,
       cached_tokens, cache_creation_tokens, thinking_tokens, content_raw,
       created_at, updated_at
  FROM messages ORDER BY id;
SELECT count(*) AS messages FROM messages;
SELECT role, count(*) FROM messages GROUP BY role ORDER BY role;

\echo active_storage_links_and_blobs
SELECT * FROM active_storage_attachments ORDER BY id;
SELECT * FROM active_storage_blobs ORDER BY id;
SELECT * FROM active_storage_variant_records ORDER BY id;

\echo application_ledger_must_not_change
SELECT * FROM token_usages ORDER BY id;
SELECT kind, count(*), sum(input_tokens), sum(output_tokens), sum(cached_tokens),
       sum(cache_creation_tokens), sum(thinking_tokens)
  FROM token_usages GROUP BY kind ORDER BY kind;
SELECT id, input_tokens_count, output_tokens_count FROM accounts ORDER BY id;
SELECT id, input_tokens_count, output_tokens_count FROM chats ORDER BY id;
