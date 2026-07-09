# Live Stream Markdown Rendering & Coalescing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show Commonmarker-rendered markdown during chat streaming (instead of raw markdown text) and coalesce per-token Turbo Stream broadcasts into time-throttled (~150ms) full re-renders of the content div.

**Architecture:** Accumulate streamed LLM deltas in an in-memory `Message::StreamBuffer`. On a time/size cadence, render the **entire accumulated buffer** through a shared `Message.render_markdown_content` (Commonmarker, strips `<think>`) and `broadcast_replace_to` the content div. One guaranteed final flush at loop end. The API/SSE `block_given?` path is unchanged. Adds an optional `stream_buffer:` dependency-injection kwarg to `complete_with_nosia` for deterministic tests.

**Tech Stack:** Rails 8.0, Turbo Streams (turbo-rails 2.0), ActionCable (PostgreSQL adapter), ruby_llm 1.14, Commonmarker, Nokogiri, Minitest + fixtures, Solid Queue. No Node/JS changes.

**Spec:** `docs/superpowers/specs/2026-07-09-live-stream-markdown-design.md`

**One refinement from the spec (flagged):** The spec's Section 5 #4 called for a browser **system test**. This plan replaces it with a **job-level integration test** (Task 6) that asserts the same observable — rendered HTML (`<h2>`, `<strong>`, `<pre>`) landing in the broadcast stream through the real `ChatResponseJob` → `complete_with_nosia` → coalescing loop — without paying the cost of standing up the app's passwordless-auth flow in a browser (no existing system test patterns to copy, and the unit tests already prove coalescing/rendering/replace-target/block-path). A browser system test is documented as deferred. Rationale: YAGNI on auth+browser setup when the behavior is provable without it.

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `app/models/message/stream_buffer.rb` | Accumulate streamed deltas; answer "is it time to flush?" on a time/size cadence. Pure value object; owns no broadcasting. | Create |
| `app/models/message.rb` | `self.render_markdown_content` (shared markdown→HTML, strips `<think>`); `response_content` delegates; `broadcast_streamed_content` replaces `broadcast_append_chunk`. | Modify |
| `app/views/messages/_streaming_content.html.erb` | The `replace` target partial: wrapper div (`prose` + `table-wrapper` stimulus) with the rendered HTML inside. | Create |
| `app/models/chat/completionable.rb` | Replace the per-token `broadcast_append_chunk` loop with buffer + coalesced flush; add `stream_buffer:` kwarg; split block vs. non-block `complete` calls. | Modify |
| `app/views/messages/_content.html.erb` | Remove dead `delta` line. | Modify |
| `app/views/messages/_reasoning_content.html.erb` | Remove dead `delta` line. | Modify |
| `test/models/message/stream_buffer_test.rb` | Pure unit tests for the buffer (fake clock). | Create |
| `test/models/message_test.rb` | `render_markdown_content` / `response_content` / `broadcast_streamed_content` tests. | Modify |
| `test/models/chat/completionable_test.rb` | Streaming-loop wiring tests (coalescing, final flush, empty stream, block path). | Modify |
| `test/jobs/chat_response_job_test.rb` | Integration test: rendered HTML in the broadcast stream through the real job. | Modify |
| `test/test_helper.rb` | Add `stub_chat_for_streaming` helper + `StreamChunk` struct (shared by completionable + job tests). | Modify |

---

## Shared test scaffolding (used by Tasks 4 & 6)

`complete_with_nosia` runs a ruby_llm pre-amble (`with_model`, `similarity_search`, `system_prompt`, …) before the streaming loop. To test the loop without an LLM/embeddings, stub those methods on the chat instance via `define_singleton_method`. Put the helper in `test/test_helper.rb` so both `completionable_test.rb` and `chat_response_job_test.rb` reuse it.

---

### Task 1: `Message::StreamBuffer` value object

**Files:**
- Create: `app/models/message/stream_buffer.rb`
- Create test: `test/models/message/stream_buffer_test.rb`

- [ ] **Step 1: Write the failing test**

`test/models/message/stream_buffer_test.rb`:

```ruby
require "test_helper"

class Message::StreamBufferTest < ActiveSupport::TestCase
  FakeClock = Struct.new(:ticks) do
    def call = ticks.shift
  end

  def buffer(interval: 10, max_bytes: 4096, ticks:)
    Message::StreamBuffer.new(interval: interval, max_bytes: max_bytes, clock: FakeClock.new(ticks))
  end

  test "<< accumulates and text returns the full buffer" do
    b = buffer(ticks: [ 0.0 ])
    b << "hello "
    b << "world"
    assert_equal "hello world", b.text
    assert b.any?
  end

  test "flush? is false on an empty buffer" do
    b = buffer(ticks: [ 0.0, 1.0 ])
    assert_not b.flush?
  end

  test "flush? is false before the interval elapses" do
    b = buffer(interval: 10, ticks: [ 0.0, 1.0 ]) # 1.0 - 0.0 = 1s < 10s
    b << "a"
    assert_not b.flush?
  end

  test "flush? is true once the interval elapses and resets the timer" do
    b = buffer(interval: 10, ticks: [ 0.0, 10.0, 10.0 ])
    b << "a"
    assert b.flush?        # 10 - 0 = 10 >= 10
    assert_not b.flush?    # timer reset to 10.0; 10 - 10 = 0 < 10
  end

  test "flush? is true when max_bytes is reached before the interval" do
    b = buffer(interval: 1000, max_bytes: 5, ticks: [ 0.0, 1.0 ])
    b << "abcde"           # 5 bytes >= max_bytes
    assert b.flush?
  end

  test "flushing never clears the text (full re-render semantics)" do
    b = buffer(interval: 0, ticks: [ 0.0, 0.0 ])
    b << "a"
    b.flush?               # flushes (interval 0)
    b << "b"
    assert_equal "ab", b.text
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/models/message/stream_buffer_test.rb`
Expected: FAIL — `NameError: uninitialized constant Message::StreamBuffer`.

- [ ] **Step 3: Write the minimal implementation**

`app/models/message/stream_buffer.rb`:

```ruby
# Accumulates streamed LLM deltas and answers "is it time to flush?" on a
# time/size cadence. Pure value object — it never broadcasts and never clears
# its text (each flush re-renders the FULL accumulated buffer). The clock is
# injectable so tests drive timing without sleeping.
class Message::StreamBuffer
  def initialize(interval: ENV.fetch("STREAM_FLUSH_INTERVAL_MS", 150).to_i / 1000.0,
                 max_bytes: ENV.fetch("STREAM_FLUSH_MAX_BYTES", 4096).to_i,
                 clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    @interval   = interval
    @max_bytes  = max_bytes
    @clock      = clock
    @text       = +""
    @last_flush = @clock.call
  end

  def <<(delta)
    @text << delta
    self
  end

  # True when the interval has elapsed or the buffer hit the size cap.
  # Resets the flush timer; the buffer text is never cleared (full re-render).
  def flush?
    return false if @text.empty?
    current = @clock.call
    due = current - @last_flush >= @interval || @text.bytesize >= @max_bytes
    @last_flush = current if due
    due
  end

  def text = @text.dup
  def any? = @text.present?
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/models/message/stream_buffer_test.rb`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add app/models/message/stream_buffer.rb test/models/message/stream_buffer_test.rb
git commit -m "feat: add Message::StreamBuffer for coalescing streamed deltas"
```

---

### Task 2: Shared `render_markdown_content` + `response_content` delegation

**Files:**
- Modify: `app/models/message.rb:143-149` (`response_content`)
- Modify test: `test/models/message_test.rb`

- [ ] **Step 1: Write the failing tests**

Append to `test/models/message_test.rb` (inside the `MessageTest` class):

```ruby
test "render_markdown_content renders markdown to HTML" do
  html = Message.render_markdown_content("# Title\n\n**bold**")
  assert_includes html, "<h1"
  assert_includes html, "<strong>"
end

test "render_markdown_content strips think tags" do
  html = Message.render_markdown_content("ilh<think>secret</think>visible **text**")
  assert_not_includes html, "secret"
  assert_includes html, "visible"
  assert_includes html, "<strong>"
end

test "render_markdown_content returns nil for blank input" do
  assert_nil Message.render_markdown_content(nil)
  assert_nil Message.render_markdown_content("")
  assert_nil Message.render_markdown_content("   ")
end

test "render_markdown_content does not raise on incomplete markdown" do
  assert_nothing_raised do
    Message.render_markdown_content("``` unfinished code fence")
    Message.render_markdown_content("**unclosed bold")
    Message.render_markdown_content("| a | b |\n| --- |")
  end
end

test "response_content delegates to render_markdown_content" do
  message = @chat.messages.create!(role: "assistant", content: "# Hi\n\n**x**")
  assert_includes message.response_content, "<h1"
  assert_includes message.response_content, "<strong>"
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/models/message_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'render_markdown_content' for Message:Class`.

- [ ] **Step 3: Implement the shared renderer and refactor `response_content`**

In `app/models/message.rb`, replace the existing `response_content` (lines 143-149):

```ruby
  def response_content
    self.class.render_markdown_content(content)
  end
```

And add the class method (place it just above `def response_content`, near `html_to_markdown`):

```ruby
  # Shared markdown→HTML render used by both the streaming flush (which feeds
  # the in-memory buffer) and response_content (which reads persisted content).
  # Strips <think> (reasoning) so streaming output converges exactly to the
  # final render. Lenient on incomplete markdown — does not raise on an open
  # code fence or unclosed emphasis.
  def self.render_markdown_content(text)
    return if text.blank?
    doc = Nokogiri::HTML::DocumentFragment.parse(text)
    return unless doc.present?
    doc.at("think")&.remove
    Commonmarker.to_html(doc.to_html)
  end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/models/message_test.rb`
Expected: PASS (including the new tests and existing message tests).

- [ ] **Step 5: Commit**

```bash
git add app/models/message.rb test/models/message_test.rb
git commit -m "refactor: extract Message.render_markdown_content for streaming + final render"
```

---

### Task 3: `broadcast_streamed_content` + the `_streaming_content` partial

**Files:**
- Modify: `app/models/message.rb:58-64` (replace `broadcast_append_chunk`)
- Create: `app/views/messages/_streaming_content.html.erb`
- Modify test: `test/models/message_test.rb`

- [ ] **Step 1: Write the failing tests**

Add to the top of `test/models/message_test.rb` (alongside the existing `include ActiveJob::TestHelper`):

```ruby
  include ActionCable::TestHelper
  include ActionView::RecordIdentifier
```

Append these tests inside `MessageTest`:

```ruby
  def messages_stream
    Turbo::StreamsChannel.send(:stream_name_from, [ @chat, "messages" ])
  end

  test "broadcast_streamed_content broadcasts a replace of the content div with rendered HTML" do
    message = @chat.messages.create!(role: "assistant", content: "")
    clear_messages(messages_stream)
    message.broadcast_streamed_content("# Title\n\n**bold**")

    payloads = broadcasts(messages_stream).map { |m| ActiveSupport::JSON.decode(m) }
    assert_equal 1, payloads.size
    payload = payloads.first
    assert_includes payload, %(action="replace")
    assert_includes payload, %(target="#{dom_id(message, :content)}")
    assert_includes payload, "<strong>"
  end

  test "broadcast_streamed_content is a no-op for non-assistant messages" do
    message = @chat.messages.create!(role: "user", content: "hi")
    assert_no_broadcasts(messages_stream) do
      message.broadcast_streamed_content("anything")
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/models/message_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'broadcast_streamed_content'`.

- [ ] **Step 3: Create the streaming partial**

`app/views/messages/_streaming_content.html.erb`:

```erb
<%= tag.div id: dom_id(message, :content),
            class: "prose prose-sm dark:prose-invert max-w-none ai-response-content",
            data: { controller: "table-wrapper" } do %>
  <%== content_html %>
<% end %>
```

- [ ] **Step 4: Implement `broadcast_streamed_content` (replace `broadcast_append_chunk`)**

In `app/models/message.rb`, replace the `broadcast_append_chunk` method (lines 58-64) with:

```ruby
  # Re-render the full accumulated buffer to HTML and replace the content div.
  # One broadcast per flush (coalesced), formatted markdown instead of raw text.
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

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/models/message_test.rb`
Expected: PASS.

> **Fallback note:** If rendering a partial from a model test context raises (turbo renderer unavailable outside a controller), fall back to asserting count + render-correctness separately: keep `assert_no_broadcasts` for the user case and, for the assistant case, assert `broadcasts(messages_stream).size == 1` plus `assert_includes Message.render_markdown_content("# Title\n\n**bold**"), "<strong>"`. The job-level integration test (Task 6) re-confirms the payload in a full-app context.

- [ ] **Step 6: Commit**

```bash
git add app/models/message.rb app/views/messages/_streaming_content.html.erb test/models/message_test.rb
git commit -m "feat: broadcast streamed content as rendered markdown via replace"
```

---

### Task 4: Wire the coalescing loop in `complete_with_nosia`

**Files:**
- Modify: `app/models/chat/completionable.rb:4-88`
- Modify: `test/test_helper.rb` (shared stub helper)
- Modify test: `test/models/chat/completionable_test.rb`

- [ ] **Step 1: Add the shared stub helper to `test_helper.rb`**

In `test/test_helper.rb`, inside the `class ActiveSupport::TestCase` block (after `fixtures :all`), add:

```ruby
    # Stubs a Chat's ruby_llm pre-amble + streaming entry so complete_with_nosia
    # runs the real coalescing loop with canned chunks (no LLM, no embeddings).
    StreamChunk = Struct.new(:content)

    def stub_chat_for_streaming(chat, chunks:)
      chat.define_singleton_method(:mcp_tools) { [] }
      chat.define_singleton_method(:with_model) { |*| }
      chat.define_singleton_method(:with_params) { |*| }
      chat.define_singleton_method(:with_temperature) { |*| }
      chat.define_singleton_method(:with_instructions) { |*| }
      chat.define_singleton_method(:similarity_search) { |*| [] }
      chat.define_singleton_method(:system_prompt) { "x" }
      chat.define_singleton_method(:broadcast_thinking_phase) { |*| }
      chat.define_singleton_method(:answer_relevance) { |*| true }
      chat.define_singleton_method(:record_completion_usage!) { |*| }
      chat.define_singleton_method(:complete) do |&blk|
        chunks.each { |c| blk.call(c) }
        messages.last
      end
    end
```

- [ ] **Step 2: Write the failing tests**

Add to the top of `test/models/chat/completionable_test.rb`:

```ruby
  include ActionCable::TestHelper
  include ActionView::RecordIdentifier
```

Append these tests inside `Chat::CompletionableTest`:

```ruby
  def messages_stream
    Turbo::StreamsChannel.send(:stream_name_from, [ @chat, "messages" ])
  end

  def assistant_with_stubbed_update
    msg = @chat.messages.create!(role: :assistant, content: "")
    # Stop the post-loop message.update from firing broadcast_updated so
    # broadcast counts reflect only the streaming flushes.
    msg.define_singleton_method(:update) { |*| true }
    msg
  end

  test "complete_with_nosia coalesces streamed chunks into a single final flush" do
    assistant_with_stubbed_update
    chunks = %w[a b c d e].map { |s| StreamChunk.new(s) }
    stub_chat_for_streaming(@chat, chunks: chunks)
    buffer = Message::StreamBuffer.new(interval: 1000) # never time-flush mid-stream

    assert_broadcasts(messages_stream, 1) do
      @chat.complete_with_nosia("hi", stream_buffer: buffer)
    end
  end

  test "complete_with_nosia flushes per chunk when interval is zero, plus a final flush" do
    assistant_with_stubbed_update
    chunks = %w[a b c].map { |s| StreamChunk.new(s) }
    stub_chat_for_streaming(@chat, chunks: chunks)
    buffer = Message::StreamBuffer.new(interval: 0)

    assert_broadcasts(messages_stream, 4) do # 3 mid + 1 final
      @chat.complete_with_nosia("hi", stream_buffer: buffer)
    end
  end

  test "complete_with_nosia broadcasts nothing when the stream yields no content" do
    assistant_with_stubbed_update
    stub_chat_for_streaming(@chat, chunks: [ StreamChunk.new(nil), StreamChunk.new("") ])
    buffer = Message::StreamBuffer.new(interval: 0)

    assert_no_broadcasts(messages_stream) do
      @chat.complete_with_nosia("hi", stream_buffer: buffer)
    end
  end

  test "complete_with_nosia yields raw chunks to the block (API path) without turbo broadcasts" do
    assistant_with_stubbed_update
    chunks = %w[a b c].map { |s| StreamChunk.new(s) }
    stub_chat_for_streaming(@chat, chunks: chunks)
    received = []

    assert_no_broadcasts(messages_stream) do
      @chat.complete_with_nosia("hi") { |chunk| received << chunk.content }
    end
    assert_equal %w[a b c], received
  end
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bin/rails test test/models/chat/completionable_test.rb`
Expected: FAIL — `ArgumentError: unknown keyword :stream_buffer` (the loop still calls `broadcast_append_chunk` / the kwarg doesn't exist).

- [ ] **Step 4: Implement the coalescing loop**

In `app/models/chat/completionable.rb`, change the method signature (line 4) to add `stream_buffer:` before `&block`:

```ruby
  def complete_with_nosia(question, model: nil, temperature: nil, top_k: nil, top_p: nil, max_tokens: nil,
                          user_message: nil, excluded_sources: nil, stream_buffer: Message::StreamBuffer.new, &block)
```

Then replace the streaming block (lines 64-73):

```ruby
    # Phase 2: Generating the response
    broadcast_thinking_phase("generating", "Generating response...")

    if block_given?
      # API/SSE path: yield raw chunks to the caller, no turbo broadcasts.
      self.complete { |chunk| yield chunk }
    else
      # Chat UI path: coalesce deltas and re-render the full buffer as markdown.
      message = nil
      self.complete do |chunk|
        message ||= self.messages.last
        if chunk.content && message
          stream_buffer << chunk.content
          message.broadcast_streamed_content(stream_buffer.text) if stream_buffer.flush?
        end
      end
      message&.broadcast_streamed_content(stream_buffer.text) if stream_buffer.any? # final flush
    end
```

Leave the post-loop tail (`message = self.messages.last` … `record_completion_usage!(message)`) unchanged.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/models/chat/completionable_test.rb`
Expected: PASS (new streaming tests + existing `record_completion_usage!` tests).

- [ ] **Step 6: Run the job test to confirm no regression**

Run: `bin/rails test test/jobs/chat_response_job_test.rb`
Expected: PASS (it stubs `complete_with_nosia`, so the new kwarg/loop don't affect it).

- [ ] **Step 7: Commit**

```bash
git add app/models/chat/completionable.rb test/test_helper.rb test/models/chat/completionable_test.rb
git commit -m "feat: coalesce streamed chunks into throttled markdown re-renders"
```

---

### Task 5: Remove dead `delta` lines in content partials

**Files:**
- Modify: `app/views/messages/_content.html.erb`
- Modify: `app/views/messages/_reasoning_content.html.erb`

- [ ] **Step 1: Confirm no references to the `delta` local**

Run: `grep -rn "delta" app/views/messages/ app/models/ app/jobs/`
Expected: only the two `defined?(delta)` lines in `_content.html.erb` and `_reasoning_content.html.erb` (the broadcast path uses `partial:`/`html:`, never this local). No controller/job sets it.

- [ ] **Step 2: Edit `_content.html.erb`**

Replace the whole file with:

```erb
<%== message.response_content %>
```

- [ ] **Step 3: Edit `_reasoning_content.html.erb`**

Replace the whole file with:

```erb
<%== message.reasoning_content %>
```

- [ ] **Step 4: Run the affected test suites**

Run: `bin/rails test test/models/message_test.rb test/models/chat/completionable_test.rb test/jobs/chat_response_job_test.rb`
Expected: PASS (nothing rendered `delta`; views still render `response_content`/`reasoning_content`).

- [ ] **Step 5: Commit**

```bash
git add app/views/messages/_content.html.erb app/views/messages/_reasoning_content.html.erb
git commit -m "chore: remove dead delta locals from message content partials"
```

---

### Task 6: Job-level integration test — rendered HTML through the real job

**Files:**
- Modify test: `test/jobs/chat_response_job_test.rb`

This replaces the spec's browser system test (see the refinement note in the plan header). It exercises `ChatResponseJob` → `complete_with_agent_skills`/`complete_with_nosia` → the real coalescing loop → broadcasts, with only `Chat#complete` and the pre-amble stubbed (no LLM, no embeddings, no browser/auth).

- [ ] **Step 1: Inspect the existing job test setup**

Run: `sed -n '1,40p' test/jobs/chat_response_job_test.rb`
Note its `setup` (creates user/account/chat, sets `ActsAsTenant.current_tenant`, `ActiveJob::Base.queue_adapter = :test`) and that it currently stubs `complete_with_nosia`. The new test must NOT stub `complete_with_nosia`.

- [ ] **Step 2: Write the failing test**

Append inside `ChatResponseJobTest` (reuse `stub_chat_for_streaming` from `test_helper.rb`):

```ruby
  include ActionCable::TestHelper
  include ActionView::RecordIdentifier

  def messages_stream
    Turbo::StreamsChannel.send(:stream_name_from, [ @chat, "messages" ])
  end

  test "the job streams rendered markdown (not raw text) through coalesced broadcasts" do
    # A user message with no attached sources -> wait_for_attached_sources! is a no-op.
    user_msg = @chat.messages.create!(role: "user", content: "draw me a heading and code")
    assistant = @chat.messages.create!(role: :assistant, content: "")
    assistant.define_singleton_method(:update) { |*| true } # suppress post-loop broadcast_updated

    markdown = "## Heading\n\n**bold** and *italic*\n\n```\ncode\n```\n"
    stub_chat_for_streaming(@chat, chunks: markdown.chars.each_slice(6).map(&:join))

    stream = messages_stream
    clear_messages(stream)
    perform_enqueued_jobs(only: ChatResponseJob) do
      ChatResponseJob.perform_later(@chat.id, user_msg.content, user_msg.id)
    end

    payloads = broadcasts(stream).map { |m| ActiveSupport::JSON.decode(m) }
    # Coalesced: far fewer broadcasts than chunk count (~markdown.chars.size/6 ≈ 12 chunks).
    assert payloads.size < markdown.chars.size / 3, "expected coalesced broadcasts, got #{payloads.size}"
    # The final/last payload carries the fully rendered markdown (replace action, real tags).
    assert payloads.any? { |p| p.include?(%(action="replace")) && p.include?("<h2") && p.include?("<strong>") && p.include?("<pre") },
           "expected a replace broadcast with rendered <h2>/<strong>/<pre>; got:\n#{payloads.join("\n")}"
  end
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bin/rails test test/jobs/chat_response_job_test.rb`
Expected: FAIL — the existing tests stub `complete_with_nosia`; this one doesn't, so before Task 4 it would call the old per-token `broadcast_append_chunk` (raw `append`, no `<h2>`). After Task 4 it should pass; run it now to confirm it passes with the coalesced loop.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/jobs/chat_response_job_test.rb`
Expected: PASS — coalesced count and rendered `<h2>`/`<strong>`/`<pre>` present in a `replace` broadcast.

> **Note:** If `Rails.application.config.agent_skills.enabled` is true and `AgentSkill::Detector` matches the canned prompt, `complete_with_agent_skills` may branch away from `complete_with_nosia`. If so, also stub `@chat.define_singleton_method(:complete_with_agent_skills) { |*args, &blk| complete_with_nosia(*args, &blk) }` in the test (or stub `AgentSkill::Detector` to return `[]`) so the streaming path runs. Add only if the test fails on the skill branch.

- [ ] **Step 5: Commit**

```bash
git add test/jobs/chat_response_job_test.rb
git commit -m "test: job streams rendered markdown via coalesced broadcasts"
```

---

## Final verification

- [ ] **Run the full suite**

Run: `bin/rails test`
Expected: PASS (all model/job/controller tests, including the new streaming coverage).

- [ ] **Run lint/security**

Run: `bin/ci` (rubocop + brakeman + tests)
Expected: PASS. Watch for brakeman warnings on the new `<%== content_html %>` (it's Commonmarker-rendered HTML, same trust boundary as the existing `<%== message.response_content %>`; should be clean).

- [ ] **Manual smoke test (optional)**

Run: `STREAM_FLUSH_INTERVAL_MS=150 bin/dev`
Submit a chat that triggers a long assistant response. Observe: markdown formatting appears progressively (headings, bold, code blocks rendered — not literal `#`/`**`/```` ``` ````), and the network/ActionCable tab shows ~5–15 broadcasts for the response rather than one per token.

---

## Out of scope / deferred

- Browser system test (deferred — see plan header refinement note; the job-level integration test covers the same observable without auth/browser setup).
- Live-streaming the reasoning (`<think>`) dropdown.
- `update`/morph-based streaming; per-flush `table-wrapper` reconnect is accepted.
- The pre-existing `done`-column / token-footer quirk.
- Any change to the API/SSE (`block_given?`) cadence.

## Open items resolved during implementation

- `Process::CLOCK_MONOTONIC` available on MRI Linux — yes (default clock).
- `broadcast_replace_to` with `partial:` + `locals:` renders synchronously and broadcasts directly via `ActionCable.server.broadcast` (no job) — confirmed in turbo-rails 2.0.23, so `assert_broadcasts` works under any job adapter.
- Stream name for tests: `Turbo::StreamsChannel.send(:stream_name_from, [chat, "messages"])`.
```