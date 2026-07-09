# Live Stream Markdown Rendering & Coalescing — Design

**Date:** 2026-07-09
**Status:** Approved (brainstorming complete, pending implementation plan)
**Branch:** `feat/live-stream-markdown`

## Goal

Optimize the chat live-stream response so that:

1. **Markdown-formatted content is shown during streaming** instead of raw markdown text. Today the user sees literal `#`, `**`, and ```` ``` ```` while tokens arrive; formatting only "pops" at the very end.
2. **The live stream is coalesced** — fewer, longer broadcasts instead of one Turbo Stream broadcast per LLM token (hundreds per response).

Both goals are served by a single change: accumulate streamed deltas in an in-memory buffer and, on a time-throttled cadence, render the **entire accumulated buffer** through Commonmarker and broadcast a single `replace` of the content div.

## Decisions (from brainstorming)

| Decision | Choice |
|---|---|
| Progressive rendering | **Full re-render each flush.** Every flush renders the entire accumulated buffer through Commonmarker and replaces the content div. Output converges to correct as text arrives; transient imperfections (literal `**` until the closing `**` lands, a growing code block) are accepted. Simplest and most robust; matches how most streaming AI UIs feel. |
| Flush trigger | **Time-based**, decoupled from the LLM's variable token rate. |
| Flush cadence | **~150ms** (`STREAM_FLUSH_INTERVAL_MS`, default 150), plus a guaranteed final flush at loop end. ~5–15 broadcasts per typical response vs. hundreds today. Chosen to minimize DB writes / WebSocket frames; slightly chunkier visual updates accepted. |
| Size cap | `STREAM_FLUSH_MAX_BYTES` (default 4096) forces a flush on a single large burst. Does **not** clear the buffer. |
| API/SSE path | **Untouched.** The `block_given?` branch (OpenAI-compatible `Api::V1::CompletionsController`) still yields raw `chunk.content` per token to `response.stream`. Only the chat-UI `elsif` branch changes. |
| Reasoning (`ilh`/`think`) | **Final-only.** `render_markdown_content` strips `think`, so raw `ilh` text no longer appears inline during streaming (an improvement over today). The reasoning dropdown still populates only at the final `broadcast_updated`. Live-streaming reasoning is cut as YAGNI. |
| Broadcast action | **`broadcast_replace_to`** of the content div (full re-render semantics). Not `update`/morph — the per-flush `table-wrapper` Stimulus reconnect is trivial and morph tuning is YAGNI. |
| Buffer home | **`Message::StreamBuffer`** — a small focused value object under `Message::`, not concern methods on `Message`. Owns accumulation + flush-timing only; no broadcasting. Time source injectable for tests. |
| Interrupted stream | The loop raises into `ChatResponseJob`'s `rescue`; the final flush line is not reached. The user retains the last periodic flush (≤150ms old). `ruby_llm`'s `cleanup_failed_messages` later removes the blank partial bubble. No extra error-time flush. |
| System test | Included (the first `test/system/` test, brings Capybara/Selenium config along). |

## Context (current state)

- **Streaming flow:** `ChatResponseJob` (queue `:real_time`) → `Chat#complete_with_agent_skills` (falls back to `complete_with_nosia` when no skill matches) → `Chat::Completionable#complete_with_nosia` calls `self.complete do |chunk|` (ruby_llm's streaming `complete`, one `Chunk` per SSE delta). The chat-UI branch calls `message.broadcast_append_chunk(chunk.content)`.
- **Per-token broadcast:** `Message#broadcast_append_chunk` does `broadcast_append_to [chat, "messages"], target: dom_id(self, "content"), html: chunk_content` — appends **raw, unrendered markdown text** to the content div, **one Turbo Stream broadcast per token**.
- **Persistence model (load-bearing):** ruby_llm's `persist_new_message` creates the assistant record with `content: ''` **before** chunks stream (so `messages.last` is the empty assistant bubble). During streaming the DB `content` is **not** touched — accumulated text lives only in ruby_llm's in-memory message. At the end `persist_message_completion` calls `save!` → `after_update_commit` → `Message#broadcast_updated` re-renders the whole assistant partial via `to_partial_path` (`messages/_assistant.html.erb`), which is when `response_content` (Commonmarker → HTML) finally runs.
- **Target DOM:** `dom_id(message, :content)` — a `div.prose.prose-sm.dark:prose-invert.max-w-none.ai-response-content[data-controller="table-wrapper"]`. Identical in `app/views/messages/_assistant.html.erb` and `_message.html.erb`; the broadcast path renders `_assistant.html.erb` (ruby_llm's `to_partial_path` resolves assistant role to `messages/assistant`).
- **Markdown rendering already exists:** `Commonmarker.to_html`, used by `Message#response_content` (`app/models/message.rb:143-149`). The container already has `prose` classes. The gap is rendering during streaming, not rendering itself.
- **Stimulus:** `scroll_controller` (MutationObserver → auto-scroll on DOM change), `table_wrapper_controller` (wraps rendered `<table>` in a scrollable wrapper; comment notes "dynamically added tables (streaming)"), `message-ordering_controller` (orders nodes by `data-created-at`). All already handle streamed DOM changes.
- **Tests:** The streaming path is currently untested — `test/jobs/chat_response_job_test.rb` stubs `complete_with_nosia`; `test/models/chat/completionable_test.rb` only covers `record_completion_usage!`; `test/system/` does not exist.

## Design

### Section 1 — The streaming loop

The only streaming emit loop is `Chat::Completionable#complete_with_nosia` (`app/models/chat/completionable.rb:64-73`). The `agent_skills` path falls back to it; the API/SSE path passes a block and is left untouched.

Today:

```ruby
self.complete do |chunk|
  message = self.messages.last
  if block_given?
    yield chunk
  elsif chunk.content && message
    message.broadcast_append_chunk(chunk.content)
  end
end
```

Becomes:

```ruby
buffer = Message::StreamBuffer.new
message = nil
self.complete do |chunk|
  message ||= self.messages.last
  if block_given?
    yield chunk
  elsif chunk.content && message
    buffer << chunk.content
    message.broadcast_streamed_content(buffer.text) if buffer.flush?
  end
end
message&.broadcast_streamed_content(buffer.text) if buffer.any? # guaranteed final flush
```

- `message ||= self.messages.last` fetches the assistant record once instead of per-chunk (removes a query per token).
- The API/SSE `block_given?` branch is unchanged.
- `Message#broadcast_append_chunk` is removed (replaced by `broadcast_streamed_content`).

### Section 2 — `Message::StreamBuffer` and the shared renderer

**`app/models/message/stream_buffer.rb`** — a value object that accumulates deltas and answers "is it time to flush?" It owns no broadcasting.

```ruby
class Message::StreamBuffer
  def initialize(interval: ENV.fetch("STREAM_FLUSH_INTERVAL_MS", 150).to_i / 1000.0,
                 max_bytes: ENV.fetch("STREAM_FLUSH_MAX_BYTES", 4096).to_i,
                 clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    @interval   = interval
    @max_bytes  = max_bytes
    @clock      = clock
    @text       = +""
    @last_flush = clock.call
  end

  def <<(delta)
    @text << delta
  end

  # True when the interval has elapsed or the buffer hit the size cap.
  # Resets the flush timer; the buffer text is never cleared (full re-render).
  def flush?
    return false if @text.empty?
    due = now - @last_flush >= @interval || @text.bytesize >= @max_bytes
    @last_flush = now if due
    due
  end

  def text = @text.dup
  def any? = @text.present?

  private

  def now = @clock.call
end
```

- `clock` is injectable so tests drive timing without `sleep`.
- Env-overridable cadence (`STREAM_FLUSH_INTERVAL_MS`, `STREAM_FLUSH_MAX_BYTES`).

**Shared renderer** — refactor `Message.response_content` so the streaming flush and the final render share one path (streaming output must converge exactly to the final output):

```ruby
# app/models/message.rb
def self.render_markdown_content(text)
  return if text.blank?
  doc = Nokogiri::HTML::DocumentFragment.parse(text)
  return unless doc.present?
  doc.at("think")&.remove
  Commonmarker.to_html(doc.to_html)
end

def response_content
  self.class.render_markdown_content(content)
end
```

- Same logic as today (strip `ilh`/`think`, `Commonmarker.to_html`), extracted to a class method so it works on the **in-memory buffer** (never `message.content`, which stays empty until `persist_message_completion`).
- `render_markdown_content` is lenient on incomplete markdown (open code fence, unclosed `**`) — it does not raise.

**`Message#broadcast_streamed_content`** (replaces `broadcast_append_chunk`):

```ruby
def broadcast_streamed_content(text)
  return unless assistant?
  html = self.class.render_markdown_content(text)
  return unless html
  broadcast_replace_to [ chat, "messages" ],
    target: dom_id(self, :content),
    partial: "messages/streaming_content",
    locals: { message: self, content_html: html }
end
```

### Section 3 — Broadcasts, the streaming partial, and Stimulus

**New partial `app/views/messages/_streaming_content.html.erb`** — reproduces the exact wrapper from `_assistant.html.erb:34` / `_message.html.erb:43` so the `replace` lands on the same target id:

```erb
<%= tag.div id: dom_id(message, :content),
            class: "prose prose-sm dark:prose-invert max-w-none ai-response-content",
            data: { controller: "table-wrapper" } do %>
  <%== content_html %>
<% end %>
```

- Root element `id` == the broadcast `target` (`dom_id(message, :content)`), so `broadcast_replace_to` swaps it in place.
- `<%== %>` (raw) — `content_html` is already Commonmarker-rendered HTML, same as `<%== message.response_content %>` today. No new trust boundary; no `sanitize` added (assistant output was already rendered raw via Commonmarker pre-change).

**Why `replace` over `update`/morph:** `replace` swaps the whole content div each flush. This reconnects the `table-wrapper` Stimulus controller every ~150ms (its `connect` is trivial — `wrapTables` + a `MutationObserver`), and `wrapTables` re-runs on freshly rendered tables. Predictable and simple. `update`/morph would avoid the reconnect but adds Turbo-morph tuning for marginal gain — YAGNI given the "fewer broadcasts" priority.

**Stimulus interactions (no controller changes):**
- `scroll_controller` — `MutationObserver` (subtree) fires on each content-div swap → smooth auto-scroll. Same trigger as today's per-chunk appends, ~10× less often. No regression.
- `table-wrapper_controller` — re-wraps any `<table>` from rendered markdown each flush; already designed for streamed tables.
- `message-ordering_controller` — orders by `data-created-at`; unaffected (the message node isn't reordered, only its content div is swapped).

**Consistency with the final render:** the last streaming flush renders `render_markdown_content(buffer)` where `buffer` == full content. Moments later `persist_message_completion` saves that same content → `after_update_commit` → `broadcast_updated` re-renders `_assistant.html.erb`, whose content div renders `response_content` == `render_markdown_content(content)`. Identical HTML — the content div does not flicker on the final swap; the final swap's only visible change is adding sources / reasoning dropdown / token footer around it.

**Guaranteed final flush** (`message&.broadcast_streamed_content(buffer.text) if buffer.any?`) covers the tail (last ≤150ms of deltas) so there is no gap before `broadcast_updated` fires. Idempotent with the subsequent full re-render (same HTML).

### Section 4 — Edge cases, error handling, small cleanups

**Edge cases:**
- **No chunks / empty stream:** `buffer.any?` is false → no final flush; the empty assistant bubble stays as today. `flush?` returns false on an empty buffer, so no spurious mid-stream broadcasts.
- **`message` never resolves:** `message ||= self.messages.last` keeps `message` nil only if ruby_llm yields a chunk before creating the assistant record (it doesn't — `persist_new_message` fires on `on_new_message` before the first delta). The `message&.` guard on the final flush covers it regardless.
- **Interrupted/error stream:** the loop raises out of `complete_with_nosia` into `ChatResponseJob`'s `rescue`; the final flush line is never reached; the user retains the last periodic flush (≤150ms old). `ruby_llm`'s `cleanup_failed_messages` later removes the blank partial bubble. No partial/invalid HTML is broadcast — Commonmarker is lenient on incomplete markdown.
- **`answer_relevance` warning** (`completionable.rb:78`): appends a note to `content` and `update!`s → another `broadcast_updated`. Unchanged; the streaming flushes have already stopped (loop over), so no interaction.
- **API/SSE path (`block_given?`):** untouched — still yields raw `chunk.content` per token to `response.stream`. The buffer is only fed in the `elsif` branch.

**Small targeted cleanups (in files we're already touching):**
- `app/views/messages/_content.html.erb` and `_reasoning_content.html.erb` each have a dead `<% if defined?(delta) %>` line. `delta` is never set on the broadcast path (broadcasts use `html:`/`partial:`, not this local). Remove both lines.

**Out of scope (YAGNI):** live-streaming the reasoning dropdown; `update`/morph-based streaming; the pre-existing `done`-column / token-footer quirk; any change to the API/SSE cadence.

### Section 5 — Testing

Focused Minitest tests, behavior over implementation, injected dependencies for determinism (no `sleep`).

**1. `Message::StreamBufferTest`** (pure unit, no Rails):
- `<<` accumulates; `text` returns the full buffer; `any?` reflects presence.
- `flush?` is false before the interval, true after; false on an empty buffer.
- `max_bytes` forces a flush before the interval elapses.
- flushing never clears the text (full re-render semantics) — `text` keeps growing across flushes.

**2. `MessageTest`** — `render_markdown_content`:
- strips `ilh`/`think` and renders markdown → HTML; `blank?` → `nil`.
- incomplete markdown doesn't raise (open ```` ``` ```` fence, unclosed `**`).
- `response_content` delegates to it (regression: same output as before for a finished message).

**3. `Chat::CompletionableTest`** — the wiring, with `assert_broadcast_on` against `[chat, "messages"]`:
- Stub `chat.complete` to yield fake `Chunk` objects (`Struct.new(:content)`).
- **Coalescing:** inject a `StreamBuffer` whose `flush?` is stubbed to a deterministic pattern → assert broadcast count is flush count + 1 final, **not** one-per-chunk.
- **Correct action/target:** each broadcast is a `replace` on `dom_id(message, :content)` carrying `render_markdown_content` HTML (not a raw `append`).
- **Block path:** when called with a block (API/SSE), **no** turbo broadcasts occur — the block receives each chunk.

  Determinism: `complete_with_nosia` takes an optional `stream_buffer:` kwarg defaulting to `Message::StreamBuffer.new` — dependency injection for testability, no change to existing call sites (`ChatResponseJob`, `agent_skillable`, the API controller all still call without it).

**4. System test** (integration guard — the first `test/system/` test, so it brings the Capybara/Selenium config along):
- Stub `Chat#complete` to yield a known markdown string in chunks (e.g. `## Heading\n\n**bold**\n\n\`\`\`\ncode\n\`\`\``); submit a chat; assert the assistant bubble shows **rendered** HTML (a real `<h2>`, `<strong>`, `<pre>`) rather than literal `##`/`**`/```` ``` ```` text, and that it converges to the final formatted render.

## Files touched

| File | Change |
|---|---|
| `app/models/chat/completionable.rb` | Replace the `complete do \|chunk\|` emit loop with buffer + coalesced flush; add optional `stream_buffer:` kwarg. |
| `app/models/message.rb` | Add `self.render_markdown_content`; refactor `response_content` to delegate; replace `broadcast_append_chunk` with `broadcast_streamed_content`. |
| `app/models/message/stream_buffer.rb` | New — the buffer/flush-timing value object. |
| `app/views/messages/_streaming_content.html.erb` | New — the `replace` target partial (wrapper div + rendered HTML). |
| `app/views/messages/_content.html.erb` | Remove dead `delta` line. |
| `app/views/messages/_reasoning_content.html.erb` | Remove dead `delta` line. |
| `test/models/message/stream_buffer_test.rb` | New — buffer unit tests. |
| `test/models/message_test.rb` | Add `render_markdown_content` / `response_content` regression tests. |
| `test/models/chat/completionable_test.rb` | Add streaming-wiring tests (coalescing, action/target, block path). |
| `test/system/...` | New — first system test for rendered streaming output. |

## Open items for the implementation plan

- Confirm `Process::CLOCK_MONOTONIC` is available on the production runtime (MRI Linux — yes).
- Confirm the Capybara/Selenium system-test harness (`application_system_test_case.rb`, driven browser) boots cleanly as the first system test, or defer #4 if setup is heavy.
- Confirm `broadcast_replace_to` with a `partial:` + `locals:` renders the partial's root element id matching the `target:` (turbo-rails semantics) during the implementation spike.