-- PostgreSQL 1.16 schema. Capture only after stopping every affected writer.
-- Output contains private conversation/attachment data: store securely.
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SELECT current_database();
\ir ruby-llm-2-audit-common.sql

\echo registry_identity
SELECT id, provider, model_id FROM models ORDER BY id;
SELECT id, model_id AS ruby_llm_model_id FROM chats ORDER BY id;

\echo expected_content_after_conversion
-- Same PostgreSQL expression and Unicode whitespace set as the 2.0.0 renderer.
-- Nonblank structured raw content wins; blank raw preserves original plaintext.
SELECT id, content_raw AS raw_content,
       CASE WHEN content_raw::text NOT IN ('null', 'false', '[]', '{}')
                  AND btrim(content_raw #>> '{}',
                    U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000') <> ''
            THEN content_raw::text ELSE content END AS content
  FROM messages ORDER BY id;

\echo expected_tool_calls_and_results
SELECT t.id, t.tool_call_id, t.name, t.arguments, 'Message' AS message_type,
       t.message_id, t.thought_signature,
       CASE WHEN r.id IS NOT NULL THEN 'Message' END AS result_type,
       r.id AS result_id, t.created_at, t.updated_at
  FROM tool_calls t LEFT JOIN messages r ON r.tool_call_id = t.id ORDER BY t.id;

\echo expected_historical_provider_usages
-- Candidate rule includes assistant role 10 even when every bucket is NULL.
SELECT m.id AS message_id, m.chat_id, coalesce(mm.provider, cm.provider) AS provider,
       coalesce(mm.model_id, cm.model_id) AS model, m.input_tokens, m.output_tokens,
       m.cached_tokens AS cache_read_tokens, m.cache_creation_tokens AS cache_write_tokens,
       m.thinking_tokens, m.created_at, m.updated_at
  FROM messages m
  LEFT JOIN models mm ON mm.id = m.model_id
  LEFT JOIN chats c ON c.id = m.chat_id
  LEFT JOIN models cm ON cm.id = c.model_id
 WHERE m.role = 10 OR m.input_tokens IS NOT NULL OR m.output_tokens IS NOT NULL
    OR m.cached_tokens IS NOT NULL OR m.cache_creation_tokens IS NOT NULL
    OR m.thinking_tokens IS NOT NULL
 ORDER BY m.id;
COMMIT;
