# Chat Waiting UX — Design

**Date:** 2026-07-10
**Status:** Approved (brainstorming complete, pending implementation plan)
**Branch:** TBD (off `feat/live-stream-markdown` or `main`)

## Goal

Improve the UI/UX of the wait between sending a prompt and the first token of the
response appearing in the nosia chat. Three concrete gaps are addressed:

1. **The blank assistant bubble.** Today, when ruby_llm creates the empty assistant
   record (before the first delta), `Message#broadcast_created` removes the thinking
   animation and appends a bubble whose content div renders `response_content` — which
   is `nil` for blank content. The bubble stays empty through the LLM's
   time-to-first-token.
2. **No send feedback.** The show-page composer (`messages/_form.html.erb`) has no
   generating logic at all. Nothing tells the user the send registered until the
   server's Turbo Stream response arrives (which appends the user message + thinking
   animation and clears the input).
3. **No visible backend progression.** The phase machinery (`broadcast_thinking_phase`)
   only emits two coarse phases — "searching" (bundling embed + vector search +
   retrieve) and "generating". The real backend steps are invisible.

The fix combines a **placeholder** that fills the blank-bubble gap, a **composer busy
state** that locks the input for the whole generation, and a **four-phase progression**
that surfaces the real backend steps.

## Decisions (from brainstorming)

| Decision | Choice |
|---|---|
| Placeholder treatment | **Keep the spinner + phase text until the first token.** The thinking animation (avatar + spinner + live phase) carries the retrieval wait; at handoff the blank assistant bubble renders the same spinner + "Generating" phase label instead of nil. The bubble is never blank. (Visual-companion option A.) |
| Placeholder mechanism | **Hybrid (Approach 1 + 2).** Keep the standalone `#thinking_animation` element through retrieval (today's behavior, untouched); at `broadcast_created` render the existing `thinking_animation` partial inside the blank bubble's content div (no new partial); the first content flush replaces it. No first-flush special case (the bubble exists from creation). |
| Send feedback | **Busy state only.** No optimistic DOM injection of the user's message; the message + cleared input arrive with the server's Turbo Stream response. |
| Busy-state duration | **Until response done.** The composer stays locked for the entire generation (submit → completion), matching the existing (dead) `generating` intent on the dashboard composer. |
| Busy-state mechanism | **Hybrid (Approach A).** Instant Stimulus lock on `turbo:submit-start` (covers the submit→create-response round-trip) + server-driven clear via a functional `chats.generating` flag. |
| Phase granularity | **Indexing → Searching → Retrieving → Generating.** Four phases at real backend boundaries. Embedding is folded into "Searching" (no `Chunk::Searchable` scope split). |
| `generating` source of truth | **The existing `chats.generating` boolean column** (`db/schema.rb:150`, default false, never written today). Transient process state (is a job running?), not business state, so a boolean is appropriate. Reuses the dead dashboard UI intent. |
| Phase display surface | **The status area** (the thinking animation / in-bubble placeholder). The composer busy indicator is a simple lock; it does not mirror phase text (cramped and redundant). |
| Stop button | **Out of scope.** No Stop button anywhere; no `ChatsController#stop` action. The composer simply locks and unlocks. |

## Context (current state)

- **Submit flow:** `MessagesController#create` creates the user message, enqueues
  `ChatResponseJob.perform_later`, and responds `format.turbo_stream` via
  `messages/create.turbo_stream.erb`, which (1) appends the user message, (2) appends a
  `#thinking_animation` element rendering `_thinking` (avatar + `#thinking_animation_content`
  rendering `_thinking_animation` with initial phase "searching"), (3) replaces the form
  frame `#{dom_id(chat)}_message_form` (clears the input). **Not optimistic** — full
  server round-trip.
- **Dashboard new-chat flow:** `ChatsController#create` creates the chat + first message,
  enqueues `ChatResponseJob` (line 44), and redirects to the show page. The dashboard
  composer is for the first message only; after submit you're on the show page, so its
  generating UI is effectively vestigial.
- **Job:** `ChatResponseJob` (queue `:real_time`) is shallow — it calls
  `chat.wait_for_attached_sources!` then `chat.complete_with_agent_skills` / 
  `complete_with_nosia`. It `rescue`s Faraday/network errors for logging only. It never
  writes `generating`.
- **Retrieval steps (`Chat#similarity_search` → `Chunk.search_by_similarity`):**
  1. `RubyLLM.embed(query_text, …)` — embed the prompt (network call to the embeddings
     model; the slow part).
  2. `nearest_neighbors(:embedding, …).limit(limit)` — builds the pgvector relation
     (lazy; the SQL runs on evaluation).
  3. `chunks.select { context_relevance(…) }` — evaluates the relation (SQL runs), fetches
     each chunk's context, scores relevance.
  `similarity_search` has two callers: the chat path (`completionable.rb:29`) and the
  agent-skills path (`agent_skills/base.rb:84`).
- **Phase machinery:** `Chat::Completionable#broadcast_thinking_phase(phase, message)`
  does `broadcast_update_to self, :messages, target: "thinking_animation_content",
  partial: "messages/thinking_animation", locals: { phase:, message: }`. Today it emits
  "searching" (`completionable.rb:28`, before `similarity_search`) and "generating"
  (`completionable.rb:61`, before `self.complete`). `_thinking_animation.html.erb` has a
  `phase_config` hash with "searching", "generating", "using_tool" + a default.
- **Persistence model (load-bearing):** ruby_llm's `persist_new_message` creates the
  assistant record with `content: ''` **before** the first delta → `after_create_commit` →
  `Message#broadcast_created` removes `#thinking_animation` and appends the blank bubble.
  By then retrieval is done and the phase is "generating" (broadcast at line 61, before
  `self.complete`). So a static "Generating" label in the bubble is correct at handoff.
- **Blank assistant messages never appear on page load:** the `Message.for_user` scope's
  `with_content` clause excludes `role = 10 AND content IS NULL/''`, so a spinner rendered
  for blank content only ever appears live via `broadcast_created`, never on a fresh page
  load. No "spinner forever" risk from the placeholder itself.
- **Show-page form:** `messages/_form.html.erb` lives inside `turbo_frame_tag
  "#{dom_id(chat)}_message_form"`, has a plain submit button (`n-btn-chat-send`) that is
  never disabled, and has no generating logic. The `composer` Stimulus controller
  (`composer_controller.js`) owns Enter-to-send, URL/PDF interception, and the /skill
  palette; it has no in-flight/busy tracking.
- **Dashboard form:** `chats/_form.html.erb` has `is_generating = chat.persisted? &&
  chat.generating` logic (disabled editor, "AI is generating…" placeholder, Send→Stop
  swap via `stop_chat_path`), but `generating` is never set true and there is no
  `ChatsController#stop` action — so it is dead UI. A `post :stop` route exists.

## Design

### Section 1 — The placeholder (filling the blank-bubble gap)

The timeline today, and where the gap is:

1. Submit → `create.turbo_stream.erb` appends the user message + `#thinking_animation`.
2. `ChatResponseJob` runs: `wait_for_attached_sources!` → `complete_with_nosia`
   broadcasts phases → `similarity_search` (retrieval) → `self.complete`.
3. ruby_llm's `persist_new_message` creates the empty assistant record before the first
   delta → `Message#broadcast_created` removes `#thinking_animation` and appends a blank
   bubble (content div renders `response_content` → nil).
4. ⏳ **The gap:** a blank bubble through the LLM's time-to-first-token.
5. First flush (~150ms after the first token) → `broadcast_streamed_content` replaces the
   content div with rendered markdown. Gap ends.

The fix: keep the live thinking animation through retrieval (untouched), then at handoff
render the spinner inside the blank bubble so it is never empty.

**`app/views/messages/_content.html.erb`** — today a single `<%== message.response_content %>`.
Becomes:

```erb
<% if message.response_content.present? %>
  <%== message.response_content %>
<% else %>
  <%= render "messages/thinking_animation", phase: "generating", message: "Generating response…" %>
<% end %>
```

A blank assistant content div renders the existing `thinking_animation` partial (phase
"generating") instead of nothing. No new partial — DRY.

**`Message#broadcast_created` is unchanged.** It still removes `#thinking_animation` and
appends the bubble; the bubble now carries the spinner because `_content` renders it for
blank content.

**First flush is clean.** `broadcast_streamed_content` already does `broadcast_replace_to`
on `dom_id(message, :content)` with the `_streaming_content` partial. Since the bubble (and
its content div) exists from `broadcast_created` carrying the spinner, the first flush
simply replaces spinner → rendered markdown. No first-flush special case.

**Final render converges.** `broadcast_updated` re-renders `_message` → `_content` →
content now present → markdown. Identical to the streaming flush's last output (same
`render_markdown_content` path). No flicker.

### Section 2 — The phase progression (Indexing → Searching → Retrieving → Generating)

Four phases, each broadcast at a real backend boundary:

| Phase | Broadcast from | Covers |
|---|---|---|
| **Indexing** | `Chat#wait_for_attached_sources!` (after the no-sources guard) | The bounded poll waiting on attached websites/documents to finish indexing. Skipped entirely when there are no attachments. |
| **Searching** | `Chat#similarity_search` (before the scope call) | `RubyLLM.embed` (prompt → embedding, the network call) + the pgvector `nearest_neighbors` SQL. |
| **Retrieving** | `Chat#similarity_search` (after forcing the relation to load) | Fetching each chunk's context + `context_relevance` scoring. |
| **Generating** | `Chat::Completionable#complete_with_nosia` (existing line 61, before `self.complete`) | Time-to-first-token + streaming. |

**`app/models/chat/similarity_search.rb`** — force the relation to load so Searching (the
SQL) is visually distinct from Retrieving (relevance scoring), and broadcast between:

```ruby
def similarity_search(question)
  broadcast_thinking_phase("searching", "Searching your documents…")
  chunks = account.chunks.search_by_similarity(question, limit: retrieval_fetch_k, chat: self).to_a
  broadcast_thinking_phase("retrieving", "Retrieving relevant context…")
  augmented_context = ActiveModel::Type::Boolean.new.cast(ENV["AUGMENTED_CONTEXT"])
  chunks.select { |chunk| context_relevance(augmented_context ? chunk.augmented_context : chunk.context, question:) }
end
```

The `.to_a` eager-loads the few chunk records (retrieval_fetch_k, default small) so the
Searching SQL is distinct from the Retrieving relevance scoring. Same query/results as
today, just evaluated at a defined point. Moving "searching" in here means **both**
callers (chat path and agent-skills path) get the full Searching→Retrieving sequence
consistently.

**`app/models/chat.rb`** — add the "indexing" broadcast in `wait_for_attached_sources!`
right after the `sources.empty?` early return, so it only fires when there are attachments
to wait on:

```ruby
def wait_for_attached_sources!(user_message, timeout: ..., step: 1.second)
  sources = user_message.attached_websites + user_message.attached_documents
  return { ready: [], failed: [], timed_out: [] } if sources.empty?

  broadcast_thinking_phase("indexing", "Indexing your attachments…")
  # ... existing poll ...
end
```

**`app/models/chat/completionable.rb`** — remove the now-redundant "searching" broadcast
at line 28 (moved into `similarity_search`); keep "generating" at line 61.

**`app/views/messages/_thinking.html.erb`** — the initial render (line 13) currently
hardcodes `phase: "searching"`. Change it to a neutral **"preparing"** phase, since at
submit time we don't yet know whether indexing will happen. The job drives the real phases
from there. This avoids a "searching → indexing → searching" flicker when attachments are
present.

**`app/views/messages/_thinking_animation.html.erb`** — extend `phase_config` with the new
phases (`indexing`, `retrieving`, `preparing`) alongside the existing `searching` /
`generating` / `using_tool`, each with an icon + label.

**Handoff timing.** `broadcast_thinking_phase("generating")` fires at `completionable.rb:61`
*before* `self.complete`, so it lands on `#thinking_animation_content` (still present).
Then `self.complete` → `broadcast_created` removes the thinking animation and appends the
bubble carrying the "Generating" placeholder (via `_content`'s blank-check). The phase
transitions smoothly from the thinking animation into the bubble. No phase broadcasts fire
after handoff (the streaming loop only does content flushes), so no stale-target
broadcasts.

### Section 3 — The composer busy state (Approach A: instant entry, server-driven clear)

**Source of truth: the existing `chats.generating` column, made functional.**

**Two model methods on `Chat` (logic in the model, job stays shallow):**

- `Chat#start_generation!` → `update_column(:generating, true)`. No broadcast — the create
  response renders it (below); a fresh page load mid-generation reads `generating` from
  the DB and renders busy, so it is reconnect-safe for free. Uses `update_column` (not
  `update!`) to skip `Chat`'s `broadcasts_to` `after_update_commit` auto-replace, which
  would otherwise enqueue a spurious chat-partial BroadcastJob on every `generating`
  change (a no-op on the show page, which has no `#chat_<id>` target, but wasteful and
  contrary to the "no broadcast on start" intent).
- `Chat#finish_generation!` → `update_column(:generating, false)` **and**
  `broadcast_replace_to [self, "messages"], target: "#{dom_id(self)}_message_form",
  partial: "messages/form", locals: { chat: self }` **and**
  `broadcast_remove_to [self, :messages], target: "thinking_animation"`.
  The form-frame replace re-renders the show-page form with `generating=false` → enabled
  → the composer's busy state exits. The `thinking_animation` remove is a no-op on success
  (already removed by `broadcast_created`) and cleans up the error-before-bubble case
  (see Section 4). `update_column` skips the `broadcasts_to` auto-replace for the same
  reason as `start_generation!`; the two explicit broadcasts are synchronous (not `_later`)
  so the unlock is immediate.

**Entry — controllers.** `MessagesController#create` and `ChatsController#create` call
`@chat.start_generation!` **before** `ChatResponseJob.perform_later`. For the show-page
flow, this makes the `create.turbo_stream.erb` form-replace render the form already busy
(`generating=true`) — consistent with the client-side instant entry, no flicker, no
conflict. For the dashboard flow, the redirect lands on the show page with `generating`
persisted → the composer renders busy immediately.

**Clear — `ChatResponseJob#perform`.** Wrap the completion in `begin/ensure` so
`chat.finish_generation!` runs even when the LLM call raises. The existing `rescue` blocks
stay for logging; the `ensure` guarantees the composer unlocks.

**Show-page form — `app/views/messages/_form.html.erb`** gains the `is_generating` logic
the dashboard form already has, **minus the Stop button** (out of scope):

```erb
<% is_generating = chat.generating %>
```

- editor: `disabled: is_generating`, placeholder `is_generating ? "Generating…" : "Ask anything…"`.
- send button: when `is_generating`, render a disabled generating indicator (spinner +
  "Generating…") instead of the send arrow — not a Stop button.

**Instant client-side entry — `composer` Stimulus controller.** Add a `submitStart`
action wired to `turbo:submit-start` on the form. It disables the editor + send button in
the same frame as the click — covering the submit→create-response round-trip (the one beat
the server-side entry can't make instant). This is the only client-side piece; after the
create response arrives, the form is re-rendered with `generating=true` (server-driven),
so the busy state is then owned by the server and survives reconnects. The Stimulus entry
just bridges the round-trip gap.

**Why both the controller `start_generation!` and the Stimulus entry:** the Stimulus entry
gives same-frame feedback ("it registered my send"); the controller's `generating=true`
makes the create-response form-replace render busy (so the Stimulus entry isn't
immediately undone by the form-replace rendering an enabled form) and makes the state
reconnect-safe. They are consistent, not redundant.

**Dashboard form (`chats/_form.html.erb`):** left as-is. You're redirected to the show page
on chat create, so its generating UI is vestigial; the Stop button there is out of scope.

### Section 4 — Edge cases & error handling

- **No attachments** → `wait_for_attached_sources!` early-returns before the "Indexing"
  broadcast; flow is Preparing → Searching → Retrieving → Generating.
- **Empty retrieval (no chunks)** → "Searching"/"Retrieving" still broadcast briefly, then
  "Generating" with no context; placeholder shows until first token. Unchanged behavior,
  just phased.
- **Generation error (timeout/network) — two guarantees:**
  1. **Composer unlocks.** `ChatResponseJob#perform` wraps completion in `begin/ensure` →
     `chat.finish_generation!` runs even on raise, clearing `generating` and broadcasting
     the form-frame replace that re-enables the composer. The existing `rescue` blocks stay
     for logging.
  2. **No spinner stuck forever.** Today, an error *before* the bubble is created leaves
     `#thinking_animation` spinning indefinitely (pre-existing wart, made more visible now
     that the thinking animation persists longer). `finish_generation!` also broadcasts
     `broadcast_remove_to … target: "thinking_animation"` — a no-op on success and on
     error-after-bubble (both already removed by `broadcast_created`), but cleans up the
     error-before-bubble case. A blank bubble left by an error-after-bubble is still
     removed later by ruby_llm's `cleanup_failed_messages` (unchanged, out of scope).
- **Reconnect mid-generation** → `generating=true` is persisted, so the form renders busy
  on load; the ActionCable subscription picks up subsequent phase/content broadcasts. The
  composer unlocks when `finish_generation!`'s form-replace arrives.
- **Double-submit** → the Stimulus lock disables the composer on `turbo:submit-start`,
  preventing a second send while busy; `start_generation!` is idempotent regardless.
- **Blank assistant message on initial page load** → excluded by `Message.for_user`'s
  `with_content` scope, so `_content`'s blank-check never triggers on load. The placeholder
  only appears live via `broadcast_created`.

### Section 5 — Testing (Minitest + fixtures, behavior over implementation)

- **`Chat::SimilaritySearchTest` / `ChatTest`** — with `Turbo::Broadcastable::TestHelper`
  (`require "turbo/broadcastable/test_helper"`): stub `Chunk.search_by_similarity` to
  return fixed chunks; assert `similarity_search` broadcasts "searching" then "retrieving"
  in order (via `capture_turbo_stream_broadcasts`); assert `wait_for_attached_sources!`
  broadcasts "indexing" only when sources are present (and not when empty).
- **`Chat::CompletionableTest`** — assert the full phase sequence (indexing? → searching →
  retrieving → generating) fires in order through `complete_with_nosia` with a stubbed
  `complete`; assert "generating" is the last phase before streaming.
- **`ChatTest`** — `start_generation!` sets `generating=true`; `finish_generation!` sets
  `generating=false` and broadcasts a form-frame replace on `#{dom_id(chat)}_message_form`
  (and a remove of `thinking_animation`).
- **`ChatResponseJobTest`** — extend the existing test: with a stubbed completion that
  raises, assert `finish_generation!` still runs (generating cleared) via the ensure. The
  existing streaming test already covers the success path.
- **`MessagesControllerTest` / `ChatsControllerTest`** — `create` sets `generating=true`
  before enqueuing; the create turbo_stream response renders the form busy.
- **View** — `_content.html.erb` renders the `thinking_animation` partial (phase
  "generating") for blank assistant content, and `response_content` for present content.
- **System test** (existing `application_system_test_case.rb` harness) — submit a chat;
  observe the composer lock instantly, the phase labels progress through the status area,
  the in-bubble placeholder appear at handoff, the first streamed markdown replace it, and
  the composer unlock on completion. Phase timing may need stubbed delays to be observable.

## Files touched

| File | Change |
|---|---|
| `app/models/chat.rb` | Add `start_generation!`, `finish_generation!`; add "indexing" phase broadcast in `wait_for_attached_sources!` (after the no-sources guard). |
| `app/models/chat/similarity_search.rb` | Add "searching"/"retrieving" phase broadcasts; `.to_a` to separate SQL from relevance scoring. |
| `app/models/chat/completionable.rb` | Remove the now-redundant "searching" broadcast at line 28 (moved into `similarity_search`); keep "generating" at line 61. |
| `app/jobs/chat_response_job.rb` | Wrap completion in `begin/ensure` → `chat.finish_generation!`. |
| `app/controllers/messages_controller.rb` | `@chat.start_generation!` before `perform_later`. |
| `app/controllers/chats_controller.rb` | `@chat.start_generation!` before `perform_later`. |
| `app/views/messages/_form.html.erb` | Add `is_generating = chat.generating` logic: disabled editor, "Generating…" placeholder, generating indicator instead of send button (no Stop button). |
| `app/views/messages/_content.html.erb` | Render `thinking_animation` partial (phase "generating") for blank content; else `response_content`. |
| `app/views/messages/_thinking.html.erb` | Initial render phase → "preparing" (neutral). |
| `app/views/messages/_thinking_animation.html.erb` | Extend `phase_config` with `indexing`, `retrieving`, `preparing`. |
| `app/javascript/controllers/composer_controller.js` | `submitStart` action on `turbo:submit-start`: disable editor + send button (instant lock). |
| Tests | New/extended per Section 5. |

## Out of scope (YAGNI)

- Stop button / `ChatsController#stop` action; cleaning up the dashboard form's vestigial
  Stop button.
- Changing ruby_llm's `cleanup_failed_messages` behavior for blank bubbles left by errors.
- Live-streaming the reasoning dropdown.
- The API/SSE path (`block_given?` branch) — untouched.
- Splitting `Chunk::Searchable#search_by_similarity` to surface "embedding" as a phase
  distinct from "searching" — folded into "Searching" per the chosen granularity.

## Open items for the implementation plan

- Confirm the exact Stimulus wiring for `turbo:submit-start` on a form whose submit
  controller is on a wrapper div (the `composer` controller sits on a `div` inside the
  form, not the `<form>` itself) — the action may need to be bound on the form element.
- Confirm `form.lexxy_rich_text_area ... disabled: true` actually disables the Lexxy
  editor (the dashboard form already passes `disabled: is_generating`, so the pattern
  exists, but it has never been exercised with `generating=true`).
- Confirm the system-test harness can observe the phased broadcasts (may require stubbed
  delays or a stubbed `complete` that yields phases on a timer).
- Decide the branch base: off `feat/live-stream-markdown` (which the placeholder's
  `broadcast_streamed_content` / `_streaming_content` depend on) or off `main` after that
  branch merges.
- Confirm `chunks.pluck(:id)` at `completionable.rb:88` still works after the
  `similarity_search` change. Today `select` with a block already returns an Array, so the
  added `.to_a` does not change the return type — but the implementer should glance at this
  line (Array vs Relation `pluck`) since it sits directly downstream of the change.
- Visually confirm the `thinking_animation` partial renders cleanly inside the
  `prose prose-sm` content div when used as the placeholder — the `prose` typography
  classes may affect the spinner/label styling.