# ruby_llm-mcp 1.0.1 Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the locked `ruby_llm-mcp` dependency from `0.7.0` to `1.0.1` and verify Nosia's MCP integrations remain compatible.

**Architecture:** Keep the existing unconstrained `gem "ruby_llm-mcp"` declaration. Use Bundler's conservative targeted update so the lockfile changes only for `ruby_llm-mcp` and dependencies required by `1.0.1`; modify application code only if a test exposes a real compatibility break.

**Tech Stack:** Ruby 3.3, Rails 8.2, Bundler, Minitest, MCP, RubyLLM.

---

### Task 1: Resolve ruby_llm-mcp 1.0.1

**Files:**
- Modify: `Gemfile.lock` dependency resolution for `ruby_llm-mcp`
- Do not modify: `Gemfile` unless Bundler cannot resolve the requested release without an explicit version constraint

- [ ] **Step 1: Run the conservative targeted Bundler update**

Run:

```bash
bundle update ruby_llm-mcp --conservative
```

Expected: Bundler exits successfully and updates `Gemfile.lock` to resolve
`ruby_llm-mcp` at `1.0.1`, with only required dependency changes.

- [ ] **Step 2: Inspect the lockfile diff**

Run:

```bash
git diff -- Gemfile.lock
```

Expected: The diff contains `ruby_llm-mcp (1.0.1)` and any dependency changes
required by that release, with no unrelated application or worktree files
changed.

- [ ] **Step 3: Confirm the resolved gem version**

Run:

```bash
bundle info ruby_llm-mcp
```

Expected: Bundler reports the installed `ruby_llm-mcp` version as `1.0.1`.

### Task 2: Verify MCP Compatibility

**Files:**
- Test: `test/models/mcp_server_test.rb`
- Test: `test/models/mcp_server_local_test.rb`
- Test: `test/controllers/mcp_servers_controller_test.rb`
- Test: `test/integration/activate_engine_test.rb`
- Test: `test/integration/local_engine_chat_test.rb`
- Test: `test/integration/ported_script_pages_render_test.rb`
- Test: `test/models/chat_test.rb`
- Test: `test/models/chat/completionable_test.rb`
- Test: `test/models/chat/stop_generation_test.rb`
- Test: `test/models/message_placeholder_test.rb`

- [ ] **Step 1: Run the focused MCP and RubyLLM test files**

Run:

```bash
bin/rails test test/models/mcp_server_test.rb test/models/mcp_server_local_test.rb test/controllers/mcp_servers_controller_test.rb test/integration/activate_engine_test.rb test/integration/local_engine_chat_test.rb test/integration/ported_script_pages_render_test.rb test/models/chat_test.rb test/models/chat/completionable_test.rb test/models/chat/stop_generation_test.rb test/models/message_placeholder_test.rb
```

Expected: The command exits with status 0 and reports zero failures and zero
errors.

- [ ] **Step 2: If a focused test fails, write a regression test first**

Add the smallest test to the existing test file that reproduces the reported
failure, following the surrounding Minitest and fixture conventions. Run that
test alone and confirm it fails for the compatibility issue rather than for a
setup or assertion error.

- [ ] **Step 3: Apply the smallest compatibility fix, if required**

Modify only the application file directly involved in the failing behavior.
Keep existing MCP adapter and model boundaries intact. Do not add a version
compatibility layer for behavior that the focused tests do not demonstrate.

- [ ] **Step 4: Re-run focused tests after any fix**

Run the focused test command from Step 1.

Expected: The command exits with status 0 and reports zero failures and zero
errors.

### Task 3: Run the Full Regression Suite

**Files:**
- No additional files expected unless Task 2 identifies a tested compatibility fix

- [ ] **Step 1: Run the complete Rails test suite**

Run:

```bash
bin/rails test
```

Expected: The command exits with status 0 and reports zero failures and zero
errors.

- [ ] **Step 2: Review the final worktree**

Run:

```bash
git status --short
git diff --stat
git diff -- Gemfile.lock
```

Expected: Only the intended dependency lockfile change, plus any explicitly
tested compatibility fix from Task 2, is present. Existing unrelated changes
remain untouched.
