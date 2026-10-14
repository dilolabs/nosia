-- PostgreSQL 2.0 schema. Run before restarting writers, first before load_models.
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SELECT current_database();
\ir ruby-llm-2-audit-common.sql

\echo registry_identity
SELECT id, provider, model_id FROM ruby_llm_models ORDER BY id;
SELECT id, ruby_llm_model_id FROM chats ORDER BY id;

\echo expected_content_after_conversion
SELECT id, raw_content, content FROM messages ORDER BY id;

\echo expected_tool_calls_and_results
SELECT id, tool_call_id, name, arguments, message_type, message_id, thought_signature,
       result_type, result_id, created_at, updated_at FROM ruby_llm_tool_calls ORDER BY id;

\echo expected_historical_provider_usages
SELECT message_id, chat_id, provider, model, input_tokens, output_tokens,
       cache_read_tokens, cache_write_tokens, thinking_tokens, created_at, updated_at
  FROM ruby_llm_usages
 WHERE message_type = 'Message' AND chat_type = 'Chat'
   AND operation = 'chat' AND status = 'succeeded' ORDER BY message_id;
COMMIT;

-- Additional 2.0-only gates: these do not have identical before output.
BEGIN READ ONLY;
\echo historical_usage_totals_by_identity
SELECT provider, model, count(*), sum(input_tokens), sum(output_tokens),
       sum(cache_read_tokens), sum(cache_write_tokens), sum(thinking_tokens)
  FROM ruby_llm_usages GROUP BY provider, model ORDER BY provider, model;
\echo must_be_zero_before_any_new_provider_work
SELECT count(*) AS priced_historical_usages FROM ruby_llm_usages
 WHERE input_cost IS NOT NULL OR output_cost IS NOT NULL OR cache_read_cost IS NOT NULL
    OR cache_write_cost IS NOT NULL OR thinking_cost IS NOT NULL OR total_cost IS NOT NULL;
SELECT message_type, message_id, count(*) FROM ruby_llm_usages
 WHERE operation = 'chat' AND status = 'succeeded'
 GROUP BY message_type, message_id HAVING count(*) <> 1;
SELECT id FROM messages WHERE raw_content IS DISTINCT FROM content_raw;
\echo phase_journal_and_schema_versions
SELECT task, last_id, completed FROM ruby_llm_v2_backfills ORDER BY task;
SELECT version FROM schema_migrations
 WHERE version IN ('20261014152719', '20261014152720', '20261014152721') ORDER BY version;
\echo indexes_and_foreign_keys
SELECT tablename, indexname, indexdef FROM pg_indexes
 WHERE schemaname = 'public' AND tablename IN
   ('chats', 'messages', 'ruby_llm_models', 'ruby_llm_tool_calls', 'ruby_llm_usages', 'token_usages')
 ORDER BY tablename, indexname;
SELECT conrelid::regclass AS source, conname, confrelid::regclass AS target,
       pg_get_constraintdef(oid) AS definition, convalidated
  FROM pg_constraint WHERE contype = 'f' AND connamespace = 'public'::regnamespace
 ORDER BY conrelid::regclass::text, conname;
COMMIT;
