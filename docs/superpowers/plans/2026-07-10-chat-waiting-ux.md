# Chat Waiting UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fill the blank assistant bubble with a spinner placeholder, surface a four-phase progression (Indexing → Searching → Retrieving → Generating) during the wait, and lock the composer for the whole generation — improving the send→first-token waiting experience.

**Architecture:** The placeholder reuses the existing `thinking_animation` partial rendered inside the blank bubble's content div (no new partial). The phases are `broadcast_thinking_phase` calls added at real backend boundaries in `Chat#similarity_search` and `Chat#wait_for_attached_sources!`. The composer busy state is driven by the existing `chats.generating` boolean column (made functional via `Chat#start_generation!` / `#finish_generation!`, using `update_column` to skip `Chat`'s `broadcasts_to` auto-replace), set synchronously in both create controllers, cleared in `ChatResponseJob`'s `ensure`, plus an instant Stimulus lock on `turbo:submit-start`.

**Tech Stack:** Rails 8.0, Turbo Streams (turbo-rails 2.0.23), ActionCable (PostgreSQL adapter), Stimulus 3.2, Solid Queue, Minitest + fixtures, Importmap (no Node), Tailwind CSS. Tests use `Turbo::Broadcastable::TestHelper` (`require "turbo/broadcastable/test_helper"`) — see `test/jobs/chat_response_job_test.rb` for the established pattern (it is NOT autoloaded in model-test context, so require it explicitly).

**Spec:** `docs/superpowers/specs/2026-07-10-chat-waiting-ux-design.md`

**Branch base:** This plan depends on `feat/live-stream-markdown` (the placeholder's `broadcast_streamed_content` / `_streaming_content` partial come from that branch). Work on a branch off `feat/live-stream-markdown` (or off `main` if that branch has merged by the time you start).

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `app/views/messages/_content.html.erb` | Render assistant content, or the generating placeholder when blank | Modify |
| `app/views/messages/_thinking_animation.html.erb` | Phase label/icon config + spinner markup | Modify (add `indexing`, `retrieving`, `preparing` phases) |
| `app/views/messages/_thinking.html.erb` | Standalone thinking animation shown on submit / page-load-wait | Modify (initial phase → `preparing`) |
| `app/models/chat/similarity_search.rb` | Retrieval; broadcasts Searching → Retrieving | Modify |
| `app/models/chat.rb` | `wait_for_attached_sources!` (add Indexing broadcast); `start_generation!` / `finish_generation!` | Modify |
| `app/models/chat/completionable.rb` | `complete_with_nosia` streaming loop + `broadcast_thinking_phase` | Modify (remove redundant "searching" broadcast at line 28) |
| `app/jobs/chat_response_job.rb` | Enqueue + run completion | Modify (begin/ensure → `finish_generation!`) |
| `app/controllers/messages_controller.rb` | Show-page composer submit | Modify (`start_generation!` before enqueue) |
| `app/controllers/chats_controller.rb` | Dashboard new-chat submit | Modify (`start_generation!` before enqueue) |
| `app/views/messages/_form.html.erb` | Show-page composer | Modify (`is_generating` busy state, no Stop button) |
| `app/javascript/controllers/composer_controller.js` | Enter-to-send, /skill palette, instant busy lock | Modify (add `turbo:submit-start` listener) |
| `test/models/message_placeholder_test.rb` | Placeholder broadcast test | Create |
| `test/models/chat/similarity_search_test.rb` | Searching → Retrieving broadcast test | Create |
| `test/models/chat_test.rb` | Indexing phase + start/finish_generation tests | Extend |
| `test/jobs/chat_response_job_test.rb` | Job ensure clears generating (error + success) | Extend |
| `test/controllers/messages_controller_test.rb` | `create` sets generating + form renders busy | Extend |
| `test/controllers/chats_controller_test.rb` | `create` sets generating | Extend |
| `test/system/chat_waiting_ux_test.rb` | Visual integration guard (requires Selenium harness) | Create |

**Test conventions in this repo:** Minitest, no RSpec. Existing controller/job tests use `create!` for fixtures (match that, don't introduce FactoryBot). `ActsAsTenant.current_tenant` is set in setup and cleared in teardown. Controller tests `post login_url` to authenticate and set `ActiveJob::Base.queue_adapter = :test`. The job test uses `perform_now` (not the `:test` adapter's enqueue) + `Turbo::Broadcastable::TestHelper`.

---

### Task 1: Placeholder in the blank assistant bubble

**Files:**
- Modify: `app/views/messages/_content.html.erb`
- Test: `test/models/message_placeholder_test.rb` (create)

- [ ] **Step 1: Write the failing test**

Create `test/models/message_placeholder_test.rb`:

```ruby
require "test_helper"
require "turbo/broadcastable/test_helper"

class MessagePlaceholderTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper
  include ActionView::RecordIdentifier

  def setup
    @user = User.create!(email: "ph@example.com", password: "testpassword123")
    @account = Account.create!(name: "PH Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  # A blank assistant message (ruby_llm creates content: '' before the first delta)
  # must broadcast a bubble containing the generating placeholder, not an empty bubble.
  test "a blank assistant message broadcasts a bubble containing the generating placeholder" do
    streams = capture_turbo_stream_broadcasts([ @chat, "messages" ]) do
      @chat.messages.create!(role: :assistant, content: "")
    end

    append = streams.find { |s| s["action"] == "append" && s["target"] == dom_id(@chat, :messages) }
    assert append, "expected an append of the assistant bubble to the messages container"

    html = append.inner_html
    assert_includes html, "Generating", "blank bubble should show the Generating placeholder"
    assert_includes html, "animate-spin", "placeholder should include the spinner"
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/models/message_placeholder_test.rb`
Expected: FAIL — the append's inner_html is empty (blank content renders `nil`), so `"Generating"` is not present.

- [ ] **Step 3: Implement the placeholder**

Replace the contents of `app/views/messages/_content.html.erb` with:

```erb
<% if message.response_content.present? %>
  <%== message.response_content %>
<% else %>
  <%= render "messages/thinking_animation", phase: "generating", message: "Generating response…" %>
<% end %>
```

`_content.html.erb` is rendered only for assistant messages (`_message.html.erb`'s user branch renders `content_without_context` directly), so the blank-check is assistant-scoped. `response_content` returns `nil` for blank content (via `render_markdown_content`'s `return if text.blank?`), so blank → placeholder; present → rendered markdown. Reuses the existing `thinking_animation` partial (phase "generating" already in its `phase_config`) — no new partial.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/models/message_placeholder_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/views/messages/_content.html.erb test/models/message_placeholder_test.rb
git commit -m "feat: show generating placeholder in blank assistant bubble"
```

---

### Task 2: Searching → Retrieving phases in similarity_search

**Files:**
- Modify: `app/models/chat/similarity_search.rb`
- Modify: `app/models/chat/completionable.rb` (remove line-28 "searching" broadcast)
- Modify: `app/views/messages/_thinking_animation.html.erb` (add `retrieving` + `preparing` phases)
- Modify: `app/views/messages/_thinking.html.erb` (initial phase → `preparing`)
- Test: `test/models/chat/similarity_search_test.rb` (create)

- [ ] **Step 1: Write the failing test**

Create `test/models/chat/similarity_search_test.rb`:

```ruby
require "test_helper"
require "turbo/broadcastable/test_helper"

class Chat::SimilaritySearchTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper
  include ActionView::RecordIdentifier

  def setup
    @user = User.create!(email: "ss@example.com", password: "testpassword123")
    @account = Account.create!(name: "SS Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  # similarity_search must broadcast "searching" (embed + vector SQL) then "retrieving"
  # (context fetch + relevance scoring), in order, by rendering the thinking_animation
  # partial into #thinking_animation_content. Stubs the vector search so no pgvector /
  # embedding network call fires.
  test "similarity_search broadcasts searching then retrieving, in order" do
    fake_chunk = Struct.new(:context, :augmented_context).new("ctx", "aug")
    proxy = Object.new
    proxy.define_singleton_method(:search_by_similarity) { |*| [fake_chunk] }
    acct = Object.new
    acct.define_singleton_method(:chunks) { proxy }
    @chat.define_singleton_method(:account) { acct }
    @chat.define_singleton_method(:context_relevance) { |*| true }
    @chat.define_singleton_method(:retrieval_fetch_k) { 5 }

    streams = capture_turbo_stream_broadcasts([ @chat, "messages" ]) do
      @chat.similarity_search("any question")
    end

    updates = streams.select { |s| s["action"] == "update" && s["target"] == "thinking_animation_content" }
    assert_equal 2, updates.size, "expected exactly searching + retrieving phase broadcasts"
    assert_includes updates[0].inner_html, "Searching", "first phase should be Searching"
    assert_includes updates[1].inner_html, "Retrieving", "second phase should be Retrieving"
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/models/chat/similarity_search_test.rb`
Expected: FAIL — today `similarity_search` broadcasts nothing (the only "searching" broadcast is in `completionable.rb:28`, not in `similarity_search`), so `updates` is empty.

- [ ] **Step 3: Add the new phase labels**

In `app/views/messages/_thinking_animation.html.erb`, extend the `phase_config` hash (add the three new entries; keep the existing `searching`, `generating`, `using_tool` and the default):

```ruby
  phase_config = {
    "preparing" => { icon: "💭", title: "Preparing", subtitle: "Starting up…" },
    "indexing" => { icon: "📥", title: "Indexing", subtitle: "Indexing your attachments…" },
    "searching" => { icon: "🔍", title: "Searching", subtitle: "Looking through your documents..." },
    "retrieving" => { icon: "📚", title: "Retrieving", subtitle: "Retrieving relevant context…" },
    "generating" => { icon: "✨", title: "Generating", subtitle: "Crafting the response..." },
    "using_tool" => { icon: "🔧", title: "Using tool", subtitle: "Executing action..." }
  }
```

(Icons are illustrative — adjust to taste, but keep the keys exactly `preparing`, `indexing`, `retrieving`.)

- [ ] **Step 4: Change the initial standalone thinking phase to "preparing"**

In `app/views/messages/_thinking.html.erb`, line 13, change the initial render from `phase: "searching"` to `phase: "preparing"`:

```erb
      <%= render "messages/thinking_animation", phase: "preparing", message: "Preparing…" %>
```

This avoids a "searching → indexing → searching" flicker when attachments are present (the job drives the real phases from "preparing").

- [ ] **Step 5: Add the broadcasts to similarity_search**

Replace `app/models/chat/similarity_search.rb` with:

```ruby
module Chat::SimilaritySearch
  extend ActiveSupport::Concern

  def similarity_search(question)
    broadcast_thinking_phase("searching", "Searching your documents…")
    chunks = account.chunks.search_by_similarity(question, limit: retrieval_fetch_k, chat: self).to_a
    broadcast_thinking_phase("retrieving", "Retrieving relevant context…")
    augmented_context = ActiveModel::Type::Boolean.new.cast(ENV["AUGMENTED_CONTEXT"])
    chunks.select { |chunk| context_relevance(augmented_context ? chunk.augmented_context : chunk.context, question:) }
  end
end
```

The `.to_a` forces the pgvector SQL to run at a defined point so "Searching" (embed + SQL) is visually distinct from "Retrieving" (relevance scoring over fetched chunks). Today `select` with a block already returns an Array, so `.to_a` does not change the return type — but see the open item about `chunks.pluck(:id)` downstream in `completionable.rb:88`.

- [ ] **Step 6: Remove the now-redundant "searching" broadcast in completionable**

In `app/models/chat/completionable.rb`, remove line 28:

```ruby
    # Phase 1: Searching for context
    broadcast_thinking_phase("searching", "Searching through your documents...")
    chunks = self.similarity_search(question)
```

becomes:

```ruby
    # Phase 1: Searching for context (phase broadcast now lives in similarity_search,
    # so both the chat path and the agent-skills path get the Searching → Retrieving
    # sequence consistently).
    chunks = self.similarity_search(question)
```

Keep the "generating" broadcast at line 61 unchanged.

- [ ] **Step 7: Run the test to verify it passes**

Run: `bin/rails test test/models/chat/similarity_search_test.rb`
Expected: PASS.

Also run the existing streaming test to confirm the line-28 removal didn't break `complete_with_nosia`:
Run: `bin/rails test test/jobs/chat_response_job_test.rb`
Expected: PASS (the existing streaming test stubs `similarity_search` to `[]`, so it is unaffected by the broadcast move).

- [ ] **Step 8: Commit**

```bash
git add app/models/chat/similarity_search.rb app/models/chat/completionable.rb \
        app/views/messages/_thinking_animation.html.erb app/views/messages/_thinking.html.erb \
        test/models/chat/similarity_search_test.rb
git commit -m "feat: surface Searching and Retrieving phases in similarity_search"
```

---

### Task 3: Indexing phase in wait_for_attached_sources!

**Files:**
- Modify: `app/models/chat.rb` (`wait_for_attached_sources!`)
- Test: `test/models/chat_test.rb` (extend)

- [ ] **Step 1: Write the failing test**

Add to `test/models/chat_test.rb` (if it doesn't already require the turbo helper, add `require "turbo/broadcastable/test_helper"` at the top and `include Turbo::Broadcastable::TestHelper` / `include ActionView::RecordIdentifier` in the test class — match the pattern in `test/jobs/chat_response_job_test.rb`). Add these tests:

```ruby
  test "wait_for_attached_sources! broadcasts indexing only when there are sources" do
    # No sources -> early return, no indexing broadcast.
    user_msg = @chat.messages.create!(role: :user, content: "ask")
    streams = capture_turbo_stream_broadcasts([ @chat, "messages" ]) do
      @chat.wait_for_attached_sources!(user_msg, timeout: 1.second, step: 0.1.second)
    end
    assert streams.none? { |s| s.inner_html.include?("Indexing") },
           "expected no indexing phase when there are no attached sources"

    # A pending source -> indexing broadcast fires while the poll waits.
    w = @account.websites.create!(url: "https://i.example", index_status: :pending)
    user_msg2 = @chat.messages.create!(role: :user, content: "ask2", attached_website_ids: [ w.id ])
    t = Thread.new { sleep 0.2; w.reload.update!(index_status: :indexed, indexed_at: Time.current) }
    streams2 = capture_turbo_stream_broadcasts([ @chat, "messages" ]) do
      @chat.wait_for_attached_sources!(user_msg2, timeout: 3.seconds, step: 0.1.second)
    end
    t.value
    assert_includes streams2.map { |s| s.inner_html }.join, "Indexing",
                    "expected an indexing phase when an attachment is pending"
  end
```

(If `test/models/chat_test.rb` doesn't already set up `@chat`/`@account`/`@user` and `ActsAsTenant`, add a `setup`/`teardown` mirroring `MessagePlaceholderTest` above. Inspect the existing file first and follow its pattern.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/models/chat_test.rb -n "/indexing_only_when_there_are_sources/"`
Expected: FAIL — today `wait_for_attached_sources!` broadcasts nothing.

- [ ] **Step 3: Implement the indexing broadcast**

In `app/models/chat.rb`, `wait_for_attached_sources!`, add the broadcast right after the `sources.empty?` early return (so it only fires when there is something to wait on):

```ruby
  def wait_for_attached_sources!(user_message, timeout: ENV.fetch("CHAT_INDEXING_TIMEOUT", 120).to_i.seconds, step: 1.second)
    sources = user_message.attached_websites + user_message.attached_documents
    return { ready: [], failed: [], timed_out: [] } if sources.empty?

    broadcast_thinking_phase("indexing", "Indexing your attachments…")

    deadline = Time.current + timeout
    # ... rest unchanged ...
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/models/chat_test.rb -n "/indexing_only_when_there_are_sources/"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/chat.rb test/models/chat_test.rb
git commit -m "feat: surface Indexing phase while waiting on attached sources"
```

---

### Task 4: start_generation! / finish_generation! on Chat

**Files:**
- Modify: `app/models/chat.rb` (add two methods)
- Test: `test/models/chat_test.rb` (extend)

- [ ] **Step 1: Write the failing test**

Add to `test/models/chat_test.rb`:

```ruby
  test "start_generation! sets generating; finish_generation! clears it and broadcasts unlock + cleanup" do
    @chat.start_generation!
    assert @chat.reload.generating, "start_generation! should set generating"

    streams = capture_turbo_stream_broadcasts([ @chat, "messages" ]) do
      @chat.finish_generation!
    end
    assert_not @chat.reload.generating, "finish_generation! should clear generating"

    assert streams.any? { |s| s["action"] == "replace" && s["target"] == "#{dom_id(@chat)}_message_form" },
           "finish_generation! should replace the form frame to unlock the composer"
    assert streams.any? { |s| s["action"] == "remove" && s["target"] == "thinking_animation" },
           "finish_generation! should remove a stuck thinking_animation (error-before-bubble cleanup)"
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/models/chat_test.rb -n "/start_generation/"`
Expected: FAIL — `NoMethodError: undefined method 'start_generation!'`.

- [ ] **Step 3: Implement the two methods**

Add to `app/models/chat.rb` (place them with the other generation-related methods, near `wait_for_attached_sources!` / `record_completion_usage!`; order public instance methods by invocation flow):

```ruby
  # Mark the chat as actively generating so the composer renders busy. No broadcast —
  # the create response renders the busy form, and a fresh page load mid-generation
  # reads `generating` from the DB (reconnect-safe). Uses update_column to skip this
  # model's broadcasts_to after_update_commit auto-replace (a spurious chat-partial
  # BroadcastJob that is a no-op on the show page, which has no #chat_<id> target).
  def start_generation!
    update_column(:generating, true)
  end

  # Mark generation done and broadcast the composer unlock + a thinking_animation
  # remove (no-op on success where broadcast_created already removed it; cleans up the
  # error-before-bubble case). update_column skips the broadcasts_to auto-replace; the
  # two explicit broadcasts are synchronous so the unlock is immediate.
  def finish_generation!
    update_column(:generating, false)
    broadcast_replace_to [ self, "messages" ],
      target: "#{dom_id(self)}_message_form",
      partial: "messages/form",
      locals: { chat: self }
    broadcast_remove_to self, :messages, target: "thinking_animation"
  end
```

`dom_id` is available because `Chat` includes `ActionView::RecordIdentifier` transitively via Turbo's broadcastable concern (the existing `broadcast_created` on `Message` uses `dom_id` the same way). If `dom_id` is not resolvable on `Chat` in this context, add `include ActionView::RecordIdentifier` to `Chat` (verify by running the test).

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/models/chat_test.rb -n "/start_generation/"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/chat.rb test/models/chat_test.rb
git commit -m "feat: add Chat#start_generation! and #finish_generation! for composer busy state"
```

---

### Task 5: ChatResponseJob clears generating in an ensure

**Files:**
- Modify: `app/jobs/chat_response_job.rb`
- Test: `test/jobs/chat_response_job_test.rb` (extend)

- [ ] **Step 1: Write the failing tests**

Add to `test/jobs/chat_response_job_test.rb` (inside the existing test class, which already includes the turbo helper, `ActionView::RecordIdentifier`, and the `setup`/`teardown` that sets `@chat` and bounds `CHAT_INDEXING_TIMEOUT`):

```ruby
  test "finish_generation! runs even when completion raises, clearing generating" do
    user_msg = @chat.messages.create!(role: :user, content: "ask")
    @chat.start_generation!
    assert @chat.reload.generating

    raising = -> { raise Faraday::TimeoutError, "boom" }
    Chat.define_method(:complete_with_nosia) { |*| raising.call }
    Chat.define_method(:complete_with_agent_skills) { |*| raising.call }

    begin
      assert_nothing_raised { ChatResponseJob.perform_now(@chat.id, user_msg.content, user_msg.id) }
      assert_not @chat.reload.generating, "generating must be cleared by the ensure even on error"
    ensure
      Chat.remove_method(:complete_with_nosia) if Chat.instance_methods(false).include?(:complete_with_nosia)
      Chat.remove_method(:complete_with_agent_skills) if Chat.instance_methods(false).include?(:complete_with_agent_skills)
    end
  end

  test "finish_generation! clears generating on successful completion" do
    user_msg = @chat.messages.create!(role: :user, content: "ask")
    @chat.start_generation!
    stub_completion
    ChatResponseJob.perform_now(@chat.id, user_msg.content, user_msg.id)
    assert_not @chat.reload.generating, "generating must be cleared after a successful completion"
  end
```

`stub_completion` is already defined in this test file (it stubs both `complete_with_nosia` and `complete_with_agent_skills` to create an assistant "ok"). The `teardown` already removes completion stubs via `remove_completion_stub`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/jobs/chat_response_job_test.rb -n "/clears_generating/"`
Expected: FAIL — today the job never clears `generating` (it's never set true by the job, and there's no ensure), so `generating` stays whatever `start_generation!` set (true) → `assert_not generating` fails.

- [ ] **Step 3: Wrap the completion in begin/ensure**

In `app/jobs/chat_response_job.rb`, wrap the completion call so `finish_generation!` runs on both success and error. The existing `rescue` blocks stay for logging:

```ruby
  def perform(chat_id, content, user_message_id = nil)
    Rails.logger.info "=== ChatResponseJob started for chat ##{chat_id} ==="
    chat = Chat.find(chat_id)
    user_message = user_message_id ? Message.find(user_message_id) : nil
    Rails.logger.info "User message: #{user_message&.id} - Content: #{content[0..100]}..."

    # Wait for any sources attached to the user message to finish indexing so
    # retrieval can find them; collect the ones that failed or timed out so the
    # model can be warned instead of hallucinating over them.
    excluded = if user_message
      wait_result = chat.wait_for_attached_sources!(user_message)
      wait_result[:failed] + wait_result[:timed_out]
    else
      []
    end

    begin
      if Rails.application.config.agent_skills.enabled
        result = chat.complete_with_agent_skills(content, user_message: user_message, excluded_sources: excluded)
      else
        result = chat.complete_with_nosia(content, user_message: user_message, excluded_sources: excluded)
      end
      Rails.logger.info "=== ChatResponseJob completed. Result: #{result&.id} ==="
    ensure
      # Unlock the composer and clear any stuck thinking animation, whether the
      # completion succeeded or raised. The controller set generating=true on submit.
      chat.finish_generation!
    end
  rescue Faraday::TimeoutError => e
    Rails.logger.error "=== ChatResponseJob ERROR: Timeout ==="
    Rails.logger.error e.message
  rescue Faraday::Error => e
    Rails.logger.error "=== ChatResponseJob ERROR: Network error ==="
    Rails.logger.error e.message
  rescue => e
    Rails.logger.error "=== ChatResponseJob ERROR: #{e.class} ==="
    Rails.logger.error e.message
    Rails.logger.error e.backtrace.join("\n")
  end
```

(The `ensure` runs before the outer `rescue` catches the exception — Ruby runs the `ensure` as the `begin` block unwinds, then the exception propagates to the method-level `rescue`.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/jobs/chat_response_job_test.rb`
Expected: PASS (both new tests + the existing streaming test).

- [ ] **Step 5: Commit**

```bash
git add app/jobs/chat_response_job.rb test/jobs/chat_response_job_test.rb
git commit -m "feat: clear chat generating flag in ChatResponseJob ensure"
```

---

### Task 6: Controllers set generating before enqueuing

**Files:**
- Modify: `app/controllers/messages_controller.rb`
- Modify: `app/controllers/chats_controller.rb`
- Test: `test/controllers/messages_controller_test.rb` (extend)
- Test: `test/controllers/chats_controller_test.rb` (extend)

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/messages_controller_test.rb`:

```ruby
  test "create sets generating before enqueuing the job" do
    chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
    assert_enqueued_with(job: ChatResponseJob) do
      post chat_messages_url(chat), params: { message: { content: "<p>hi</p>" } }
    end
    assert chat.reload.generating, "create should set generating before enqueuing"
  end
```

Add to `test/controllers/chats_controller_test.rb`:

```ruby
  test "create sets generating before enqueuing the job" do
    assert_enqueued_with(job: ChatResponseJob) do
      post chats_url, params: { chat: { prompt: "<p>hello</p>", model: "test-model" } }
    end
    assert Chat.last.reload.generating, "create should set generating before enqueuing"
  end
```

Under the `:test` queue adapter (set in these tests' `setup`), `perform_later` enqueues but does not run, so `generating` stays true after the controller sets it.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/messages_controller_test.rb test/controllers/chats_controller_test.rb -n "/sets_generating/"`
Expected: FAIL — `generating` is never set today.

- [ ] **Step 3: Implement — MessagesController**

In `app/controllers/messages_controller.rb`, call `start_generation!` before `perform_later` (the controller stays thin — it calls a model method):

```ruby
    @user_message.attach_website_sources_from_content!(Current.account)

    # Lock the composer for the duration of this generation. The create turbo_stream
    # response renders the form busy from this flag; the job's ensure clears it.
    @chat.start_generation!

    ChatResponseJob.perform_later(@chat.id, @user_message.content, @user_message.id)
```

- [ ] **Step 4: Implement — ChatsController**

In `app/controllers/chats_controller.rb`, likewise before `perform_later`:

```ruby
    @user_message.attach_website_sources_from_content!(Current.account)

    # Lock the composer for the duration of this generation. The redirect lands on the
    # show page with generating already persisted, so the composer renders busy; the
    # job's ensure clears it.
    @chat.start_generation!

    ChatResponseJob.perform_later(@chat.id, @user_message.content, @user_message.id)

    redirect_to @chat
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/messages_controller_test.rb test/controllers/chats_controller_test.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/messages_controller.rb app/controllers/chats_controller.rb \
        test/controllers/messages_controller_test.rb test/controllers/chats_controller_test.rb
git commit -m "feat: set chat generating flag on submit in both composer controllers"
```

---

### Task 7: Show-page composer renders busy when generating

**Files:**
- Modify: `app/views/messages/_form.html.erb`
- Test: `test/controllers/messages_controller_test.rb` (extend)

- [ ] **Step 1: Write the failing test**

Add to `test/controllers/messages_controller_test.rb`:

```ruby
  test "create turbo_stream response renders the composer busy when generating" do
    chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
    post chat_messages_url(chat),
         params: { message: { content: "<p>hi</p>" } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert chat.reload.generating
    body = response.body
    assert_includes body, "Generating", "busy composer should show the Generating state"
    assert_includes body, "disabled", "busy composer should disable the editor"
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/controllers/messages_controller_test.rb -n "/renders_the_composer_busy/"`
Expected: FAIL — the show-page form has no `is_generating` logic, so it renders the enabled editor with the "Ask anything…" placeholder; no "Generating", no "disabled".

- [ ] **Step 3: Implement the busy form**

In `app/views/messages/_form.html.erb`, add the `is_generating` logic (mirroring the dashboard form, **without** the Stop button — out of scope). At the top of the file, inside the `turbo_frame_tag` block, before the `form_with`:

```erb
<% is_generating = chat.generating %>
```

Change the editor line to disable + change placeholder when generating:

```erb
    <%= form.lexxy_rich_text_area :content, permitted_attachment_types: "application/pdf", toolbar: '{"upload":"file"}', autofocus: !is_generating, placeholder: is_generating ? "Generating…" : "Ask anything...", disabled: is_generating, data: { composer_target: "editor" }, class: "n-form-chat" %>
```

Replace the send button block with a generating-aware version (generating indicator, no Stop button):

```erb
    <%= form.button type: :submit,
        class: "n-btn-chat n-btn-chat-send",
        disabled: is_generating do %>
      <% if is_generating %>
        <svg class="h-4 w-4 animate-spin" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
      <% else %>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"
            fill="none" stroke="currentColor" stroke-width="1.8" class="h-4 w-4">
          <path stroke-linecap="round" stroke-linejoin="round"
                d="M6 12 3.269 3.125A59.77 59.77 0 0 1 21.485 12 59.77 59.77 0 0 1 3.27 20.875L6 12Zm0 0h7.5"/>
        </svg>
      <% end %>
    <% end %>
```

(The button stays a submit button but `disabled: is_generating` prevents re-submit while busy; the spinner replaces the send arrow. No Stop button — out of scope.)

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/controllers/messages_controller_test.rb -n "/renders_the_composer_busy/"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/views/messages/_form.html.erb test/controllers/messages_controller_test.rb
git commit -m "feat: show-page composer renders busy state while generating"
```

---

### Task 8: Instant composer lock on submit (Stimulus)

**Files:**
- Modify: `app/javascript/controllers/composer_controller.js`

No unit test for this JS behavior in this stack (no JS test framework configured). It is covered visually by the system test in Task 9. The stimulus controller sits on a `<div>` inside the `<form>`, so `turbo:submit-start` (which fires on the `<form>`) cannot be caught via a `data-action` on the controller's element — bind a listener on the form in `connect()` instead, matching the existing `handleKeys` pattern that resolves the form via `closest("form")`.

- [ ] **Step 1: Implement the submitStart lock**

In `app/javascript/controllers/composer_controller.js`, add a listener in `connect()` and remove it in `disconnect()`. Add the `submitStart` method.

In `connect()`, after the existing listener registrations:

```js
    this.editorTarget.addEventListener("keydown", this.boundHandleKeys)
    this.boundSubmitStart = this.submitStart.bind(this)
    this.form = this.element.tagName === "FORM" ? this.element : this.element.closest("form")
    if (this.form) this.form.addEventListener("turbo:submit-start", this.boundSubmitStart)
    this.closePalette()
```

In `disconnect()`, remove it:

```js
    this.editorTarget.removeEventListener("keydown", this.boundHandleKeys)
    if (this.form) this.form.removeEventListener("turbo:submit-start", this.boundSubmitStart)
```

Add the `submitStart` method (place it near `handleKeys`):

```js
  // turbo:submit-start fires on the <form> the instant the user submits. Lock the
  // composer in the same frame — before the server's Turbo Stream response arrives —
  // so the user sees immediate feedback that the send registered. The server then
  // re-renders the form with generating=true (busy), and finish_generation! clears it.
  submitStart() {
    if (this.editorTarget) this.editorTarget.disabled = true
    const btn = this.element.querySelector("button[type='submit']")
    if (btn) btn.disabled = true
  }
```

- [ ] **Step 2: Manually verify (if a browser is available)**

Run `bin/dev`, open a chat, submit a prompt, and confirm the composer disables instantly on click (before the server response) and re-enables when the response completes. If no browser is available in this environment, rely on the Task 9 system test and note manual verification is pending.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/composer_controller.js
git commit -m "feat: instant composer lock on turbo:submit-start"
```

---

### Task 9: System test (visual integration guard)

**Files:**
- Test: `test/system/chat_waiting_ux_test.rb` (create)

This is a visual integration guard. It requires the Selenium harness from `test/application_system_test_case.rb` (headless Chrome locally, or remote Selenium when `CAPYBARA_SERVER_PORT` is set). **If the harness cannot run in this environment (no Chrome / no remote Selenium), mark the test with `skip "requires Selenium harness"` at the top of the test body and note it in the commit message — do not block the plan on it.** The unit/integration tests in Tasks 1–7 cover the behavior; this test is the visual confirmation.

- [ ] **Step 1: Write the system test**

Create `test/system/chat_waiting_ux_test.rb`:

```ruby
require "application_system_test_case"

class ChatWaitingUxTest < ApplicationSystemTestCase
  # Stub Chat#complete to yield a known chunk on a short timer so the streaming
  # flow runs without a real LLM call. Match the stubbing approach used by any
  # existing streaming system test (none exists yet in test/system/, so adapt the
  # server-side stub pattern from test/jobs/chat_response_job_test.rb's
  # stub_chat_for_streaming, loaded into the test environment).
  setup do
    @user = User.create!(email: "syst@example.com", password: "testpassword123")
    @account = Account.create!(name: "SYST Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    visit login_url
    fill_in "Email", with: @user.email
    fill_in "Password", with: "testpassword123"
    click_on "Sign in"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "the composer locks, phases show, the placeholder appears, then content, then unlock" do
    skip "requires Selenium harness (Chrome or CAPYBARA_SERVER_PORT)" unless ENV["CAPYBARA_SERVER_PORT"] || chrome_available?

    # Create a chat and submit a prompt. (Stub Chat#complete server-side to yield
    # "## Hello\n\nworld" in small chunks on a timer — see the note above.)
    visit root_url
    # ... fill the composer and submit ...

    # The send button disables immediately after submit.
    # assert_button_state disabled

    # The thinking animation shows a phase label (Preparing / Searching / Generating).
    # assert_text /Preparing|Searching|Generating/

    # The assistant bubble shows the Generating placeholder before the first token.
    # assert_text "Generating"

    # The streamed content renders as HTML (a real <h2>, not literal "##").
    # assert_selector ".ai-response-content h2", text: "Hello"

    # The composer re-enables after completion.
    # assert_button_state enabled
  end

  private

  def chrome_available?
    return @chrome_available if defined?(@chrome_available)
    @chrome_available = system("which google-chrome chromium chromium-browser chrome >/dev/null 2>&1")
  end
end
```

Fill in the commented assertion steps with real Capybara calls once the stubbing approach is pinned down (the stubbing is the hard part — if it proves too brittle, leave the test `skip`ped and rely on Tasks 1–7). The implementer should inspect `test/test_helper.rb`'s `stub_chat_for_streaming` and decide whether to reuse it via a test-environment monkeypatch or write a minimal server-side stub.

- [ ] **Step 2: Run the system test**

Run: `bin/rails test:system test/system/chat_waiting_ux_test.rb`
Expected: PASS, or SKIP with "requires Selenium harness" if the environment can't drive a browser.

- [ ] **Step 3: Commit**

```bash
git add test/system/chat_waiting_ux_test.rb
git commit -m "test: system guard for chat waiting UX (skipped without Selenium harness)"
```

---

## Final verification

- [ ] **Run the full test suite**

Run: `bin/rails test`
Expected: all green (the new tests + the existing 202).

- [ ] **Run rubocop and brakeman**

Run: `bundle exec rubocop -a && bundle exec brakeman`
Expected: rubocop clean (or only pre-existing noise); brakeman clean (no new warnings — the `update_column` / disabled-attribute / raw-HTML patterns are pre-existing).

- [ ] **Manual smoke test (if a browser is available)**

`bin/dev` → submit a chat with an attached URL (to see Indexing → Searching → Retrieving → Generating) → confirm the composer locks instantly, the phase labels progress, the in-bubble Generating placeholder appears at handoff, the streamed markdown replaces it, and the composer unlocks on completion. Submit a chat with no attachments (Preparing → Searching → Retrieving → Generating). Trigger an error (e.g. invalid `LLM_MODEL`) and confirm the composer unlocks and no spinner is stuck.

---

## Notes for the implementer

- **`update_column`, not `update!`** for the `generating` flag — `Chat`'s `broadcasts_to` auto-fires an `after_update_commit` chat-partial replace on `update!` (a no-op on the show page but a wasteful async BroadcastJob). This is the one deviation from the spec's original `update!` wording; the spec has been amended (commit `dbb9b5f`).
- **`dom_id` on `Chat`**: `finish_generation!` uses `dom_id(self)`. If the test in Task 4 fails with `NoMethodError`, add `include ActionView::RecordIdentifier` to `Chat` (verify first — Turbo's broadcastable concern may already provide it).
- **`chunks.pluck(:id)`** at `completionable.rb:88` sits downstream of the `similarity_search` `.to_a` change. Today `select` with a block already returns an Array, so `.to_a` doesn't change the return type — but glance at that line to confirm `pluck` works on the returned value (pre-existing; not introduced by this plan).
- **Stimulus `turbo:submit-start`**: the controller is on a `<div>` inside the `<form>`, so bind the listener on the form in `connect()` (not a `data-action` on the controller element). The plan does this.
- **Lexxy `disabled:`** is passed to `form.lexxy_rich_text_area` by the existing dashboard form but has never been exercised with `generating=true`. The Task 7 test asserts the `disabled` attribute is rendered; a visual check confirms the editor actually refuses input.