# Recent Conversation Previews Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development or executing-plans to implement this plan. Steps use checkbox syntax for tracking.

**Goal:** Limit recent-conversation titles to 120 characters with `…`, without changing history or stored prompts.

**Architecture:** Keep the full plain-text title helper unchanged. Truncate its output only when the shared conversations partial receives `recent: true`.

**Tech Stack:** Rails ERB, Minitest fixtures, existing local Selenium browser.

## Task 1: Limit recent previews

**Files:**
- Modify `test/controllers/account_experience_test.rb`.
- Modify `app/views/accounts/_conversations.html.erb`.
- Modify `docs/account-experience.md` to describe the preview limit.

- [ ] Add the following request regression before implementation:

```ruby
test "recent conversation previews shorten long prompts without changing history or stored content" do
  chat = experience(:chats, :overview_second_chat_27)
  message = experience(:messages, :overview_second_question_27)
  prompt = "Résumé & détails " * 30
  message.update_columns(content: prompt)
  expected = "#{prompt[0, 119]}…"

  get account_path(@second)
  assert_response :success
  assert_select "[data-conversation-id='#{chat.id}'] a", text: expected
  assert_equal prompt, message.reload.content

  get account_chats_path(@second)
  assert_response :success
  assert_select "[data-conversation-id='#{chat.id}'] a", text: prompt.strip
end

test "recent conversation previews retain short and exact-limit titles" do
  chat = experience(:chats, :overview_second_chat_27)
  message = experience(:messages, :overview_second_question_27)

  [ "Short question?", "é" * 120, "é" * 121 ].each do |prompt|
    message.update_columns(content: prompt)
    get account_path(@second)
    assert_response :success
    expected = prompt.length > 120 ? "#{prompt[0, 119]}…" : prompt
    assert_select "[data-conversation-id='#{chat.id}'] a", text: expected
  end
end
```

- [ ] Run RED using the dedicated environment below and
  `bin/rails test test/controllers/account_experience_test.rb -n /previews/`.
  Confirm the long-title assertions fail because titles are not shortened.
- [ ] Before the existing conversation `link_to`, compute and conditionally trim
  its title, retaining the existing link arguments/classes and timestamp:

```erb
<% title = account_conversation_title(chat, titles: titles) %>
<% title = truncate(title, length: 120, omission: "…") if recent %>
<%= link_to title, chat_path(chat), class: "n-account-link n-account-name" %>
```

- [ ] Add one sentence to the guide: recent previews use a 120-character limit
  including `…`; history and stored prompts are unchanged. Do not overwrite the
  historical verification results or describe them as fresh results for this fix.
- [ ] Run GREEN with `bin/rails test test/controllers/account_experience_test.rb
  test/models/account_overview_test.rb` and the existing account browser class.
- [ ] Run Ruby-4-targeted lint on the changed test and `git diff --check`.
- [ ] Commit the three implementation/test/guide paths explicitly, then obtain
  independent spec review followed by code-quality review.

## Test environment

Run database tests sequentially; database and ignored CSS are already prepared.

```sh
RAILS_ENV=test DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails test <explicit-files>
```

For the browser replace the final command with:

```sh
bundle exec ruby -rselenium-webdriver -e 'ENV.delete("CAPYBARA_SERVER_PORT"); Selenium::WebDriver::Chrome::Service.driver_path="/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path="/usr/bin/chromium"; load "bin/rails"' -- test test/system/account_experience_test.rb
```

Do not run setup, providers, ingestion workers, or another worktree's database.
