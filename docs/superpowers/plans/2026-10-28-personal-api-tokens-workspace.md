# Personal API Tokens Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve the two dedicated personal-token pages, including recoverable creation, truthful one-time copying and contextual revocation.

**Architecture:** Retain Current.user token scopes, AccountScoped guards, digest generation and the existing plaintext flash handoff. Render small form/result/row partials; a token-only subclass of the pinned clipboard controller adds rejection and snapshot handling without changing other clipboard consumers.

**Tech Stack:** Existing Rails/ERB, Turbo, Importmap/Stimulus, Tailwind and Minitest/fixtures; no model, authentication, route, dependency or schema changes.

---

Prerequisite: [shared preparation](2026-10-28-settings-tools-workspace.md) is verified.
Use the [approved specification](../specs/2026-10-28-prompts-members-tokens-ui-ux-design.md).
Only the current user's tokens are managed, even by an account owner. Default
account means the existing filing/default account, not a new permission scope.

## Task T1: Separate global/scoped forms, rows and one-time result

**Modify:** `app/controllers/api_tokens_controller.rb`, `app/views/api_tokens/{index,_form}.html.erb`.
**Create:** `app/views/api_tokens/{_created,_token}.html.erb`,
`test/controllers/api_tokens_workspace_test.rb`.

- [ ] **Step 1: Add the complete request regression file.**

```ruby
require "test_helper"
require_relative "../support/settings_tool_fixtures"

class ApiTokensWorkspaceTest < ActionDispatch::IntegrationTest
  include SettingsToolFixtures
  setup { sign_in_overview }

  test "two bilingual shells preserve personal scope and separate management" do
    %i[en fr].each do |locale|
      [ api_tokens_path, account_api_tokens_path(@second) ].each do |path|
        assert_no_difference [ "ApiToken.count", "Prompt.count", "Chat.count", "AccountUser.count" ] do
          get path, headers: { "Accept-Language" => locale.to_s }
        end
        assert_response :success
        assert_select "main h1", text: I18n.t("nosia.tokens.title", locale: locale), count: 1
        assert_equal css_select("main h1").first.text, css_select("head title").first.text
        assert_select "main .n-workspace-header nav", count: 1
        assert_select "main nav [aria-current=page]", count: 1
        assert_select "[data-token-row]", count: path == api_tokens_path ? 2 : 1
        assert_select "[data-token-row] h3", text: @other_token.name, count: 0
        assert_select "#drawer-right, #accordion-right-actions", count: 0
        assert_select "[data-settings-tool] [data-member-row], [data-settings-tool] textarea[name='prompt[content]']", count: 0
        refute_match(/translation missing|missing translation/i, response.body)
        [ @own_token, @other_token ].each { |token| refute_includes response.body, token.token_digest }
      end
    end
    get api_tokens_path
    assert_select "#api_token_account_id option[value=?]", @foreign.id, count: 0
    assert_select ".n-workspace-header a[href=?]", new_chat_path
    get account_api_tokens_path(@second)
    assert_select "select[name='api_token[account_id]']", count: 0
    assert_select "input[type=hidden][name='api_token[account_id]'][value=?]", @second.id
    assert_select ".n-workspace-header a[href=?]", new_chat_path(account_id: @second.id)
    assert_equal @first, @user.reload.first_account
  end

  test "invalid creation retains submitted name and authorized account without output" do
    %i[en fr].each do |locale|
      [ api_tokens_path, account_api_tokens_path(@second) ].each do |path|
        assert_no_difference("ApiToken.count") do
          post path, params: { api_token: { name: " \n ", account_id: @second.id } }, headers: { "Accept-Language" => locale.to_s }
        end
        assert_response :unprocessable_entity
        assert_select "form[action=?]", path
        assert_select "#api_token_name[value=?][aria-invalid=true][aria-describedby='api_token_name_help api_token_name_error']", " \n "
        assert_select "[data-form-errors-target=summary][tabindex='-1'] a[href='#api_token_name']"
        if path == api_tokens_path
          assert_select "#api_token_account_id option[selected][value=?]", @second.id
        end
        assert_select "[data-token-reveal]", count: 0
        assert_nil flash[:created_api_token]
      end
    end
  end

  test "successful global and account creation preserves digest and show-once handoff" do
    [ api_tokens_path, account_api_tokens_path(@second) ].each_with_index do |path, index|
      name = "<script>Deploy #{index}</script>"
      assert_difference("ApiToken.count", 1) do
        post path, params: { api_token: { account_id: @second.id, name: name } }
      end
      assert_redirected_to path
      plain = flash[:created_api_token]
      token = @user.api_tokens.find_by!(name: name)
      assert_equal ApiToken.digest(plain), token.token_digest
      assert_equal token, ApiToken.authenticate_token(plain)
      assert_nil token.plain_token
      follow_redirect!
      assert_select "[data-token-reveal] #created_api_token[value=?][readonly]", plain
      assert_select "[data-token-reveal]", text: /#{Regexp.escape(name)}/
      assert_select "[data-token-reveal]", text: /#{Regexp.escape(@second.name)}/
      assert_select "[data-token-reveal] #created_api_token_status", text: ""
      assert_select "main script", count: 0
      assert_select "meta[name=turbo-cache-control][content=no-cache]"
      assert_equal 1, response.body.scan(plain).size
      refute_includes response.body, token.token_digest
      get path
      assert_select "[data-token-reveal]", count: 0
      refute_includes response.body, plain
      refute_includes response.body, token.token_digest
    end
  end

  test "forged accounts foreign tokens and revoked contexts retain fail-closed boundaries" do
    [ @foreign.id, [ @second.id ], { id: @second.id } ].each do |id|
      assert_no_difference("ApiToken.count") do
        post api_tokens_path, params: { api_token: { account_id: id, name: "forged" } }
      end
      assert_response :not_found
    end
    assert_no_difference("ApiToken.count") do
      post account_api_tokens_path(@second), params: { api_token: { account_id: @first.id, name: "mismatch" } }
    end
    assert_response :not_found
    [ api_token_path(@other_token), account_api_token_path(@second, @other_token) ].each do |path|
      assert_no_difference("ApiToken.count") { delete path }
      assert_response :not_found
    end
    get account_api_tokens_path(@foreign), params: { account_id: @second.id }
    assert_response :not_found
    experience(:account_users, :overview_owner_second).destroy!
    get account_api_tokens_path(@second)
    assert_response :not_found
    assert_no_difference("ApiToken.count") do
      post account_api_tokens_path(@second), params: { api_token: { name: "revoked" } }
    end
    assert_response :not_found
    assert_equal @first, @user.reload.first_account
  end

  test "member manages only own tokens and revocation retains context and authentication semantics" do
    sign_in_overview(@member)
    get account_api_tokens_path(@second)
    assert_select "[data-token-row] h3", text: @other_token.name
    assert_select "[data-token-row] h3", text: @own_token.name, count: 0
    assert_select "form[action=?] button[data-turbo-confirm=?]", account_api_token_path(@second, @other_token), I18n.t("nosia.settings_tools.revoke_confirm", name: @other_token.name, account: @second.name)
    assert_difference("ApiToken.count", -1) { delete account_api_token_path(@second, @other_token) }
    assert_redirected_to account_api_tokens_path(@second)
    assert_equal I18n.t("nosia.settings_tools.token_removed"), flash[:notice]
    assert_nil ApiToken.authenticate_token("overview-member-secret")
    assert @user.api_tokens.exists?(@own_token.id)
  end

  test "no available account replaces only generation while owned tokens stay revocable" do
    @user.account_users.destroy_all
    get api_tokens_path
    assert_response :success
    assert_select "[data-token-setup] a[href=?]", new_account_path
    assert_select "form[action=?] input[name='api_token[name]']", api_tokens_path, count: 0
    assert_select "[data-token-row]", count: 2
    assert_difference("ApiToken.count", -1) { delete api_token_path(@own_token) }
    assert_redirected_to api_tokens_path
    sign_in_overview(@no_account)
    get api_tokens_path
    assert_select "[data-token-empty]", text: I18n.t("nosia.settings_tools.tokens_empty")
    sign_in_overview
    @empty.account_users.grant_to(@user)
    get account_api_tokens_path(@empty)
    assert_select "[data-token-empty]", text: I18n.t("nosia.settings_tools.tokens_empty_account")
    assert_equal 0, @no_account.reload.accounts.count
  end
end
```

- [ ] **Step 2: Record RED.**

```bash
source .superpowers/settings-tools-env.sh
record tokens-red rails_test test test/controllers/api_tokens_workspace_test.rb
```

Expected: absent workspace/result/form semantics, global failure still redirects.
Do not mistake an invalid test fixture or syntax error for feature RED.

- [ ] **Step 3: Make only these controller replacements.**

Replace `index` with:

```ruby
  def index
    @api_tokens = token_scope.includes(:account)
    @api_token = Current.user.api_tokens.new(account: @account)
    if flash[:created_api_token].present?
      @created_api_token = token_scope.find_by(token_digest: ApiToken.digest(flash[:created_api_token]))
    end
  end
```

Replace the `elsif @account` / `else` failure branches of `create` with just:

```ruby
    else
      @api_tokens = token_scope.includes(:account)
      render :index, status: :unprocessable_entity
    end
```

The success redirect and `flash[:created_api_token]` remain byte-for-byte the
existing handoff. No extra secret/id/name flash entries. The GET only resolves
safe result context from the current user's authorized list. Failed-save in-memory
`plain_token` is never rendered. Replace only the redirect in `destroy`:

```ruby
    redirect_to token_index_path, notice: t("nosia.settings_tools.token_removed")
```

Keep all four private scoping/parameter methods unchanged. Do not add account
fallbacks, unauthorized selection recovery or changes to token authentication.

- [ ] **Step 4: Replace/add these four templates.**

`app/views/api_tokens/index.html.erb`:

```erb
<div class="n-workspace n-settings-tool" data-settings-tool data-settings-screen="<%= @account ? 'account-tokens' : 'tokens' %>">
  <%= render "settings_tools/header", title: t("nosia.tokens.title"), description: t("nosia.settings_tools.tokens_description"), scope_label: @account ? t("nosia.workspace.account", name: @account.name) : nil, trail: settings_tool_trail(resource: t("nosia.tokens.title"), path: @account ? account_api_tokens_path(@account) : api_tokens_path) %>
  <%= render "settings_tools/feedback" %>
  <% if @created_api_token %><%= render "created", token: @created_api_token, plain: flash[:created_api_token] %><% end %>
  <div class="n-settings-tool-token-layout">
    <% if @account || Current.user.accounts.exists? %>
      <%= render "form", api_token: @api_token %>
    <% else %>
      <section class="n-workspace-panel" data-token-setup><h2 class="n-workspace-section-title"><%= t("nosia.settings_tools.setup_account") %></h2><p class="n-workspace-help"><%= t("nosia.settings_tools.setup_account_help") %></p><%= link_to t("nosia.settings_tools.setup_account"), new_account_path, class: "n-workspace-link" %></section>
    <% end %>
    <section class="min-w-0 space-y-4"><h2 class="n-workspace-section-title"><%= t("nosia.settings_tools.personal_tokens") %></h2>
      <% if @api_tokens.any? %><ul class="n-settings-tool-rows !list-none" role="list"><%= render partial: "token", collection: @api_tokens, as: :token %></ul>
      <% else %><p class="n-settings-tool-message" data-token-empty><%= t(@account ? "nosia.settings_tools.tokens_empty_account" : "nosia.settings_tools.tokens_empty") %></p><% end %>
    </section>
  </div>
</div>
```

`app/views/api_tokens/_form.html.erb`:

```erb
<%# locals: (api_token:) %>
<%= form_with model: api_token, url: @account ? account_api_tokens_path(@account) : api_tokens_path, class: "n-settings-tool-form", data: { controller: "form-errors html-form", action: "click->form-errors#focusField invalid->form-errors#revealInvalid:capture turbo:before-fetch-request->html-form#requestHTML" } do |form| %>
  <%= render "settings_tools/errors", items: settings_tool_errors(api_token, targets: { name: "api_token_name", account: @account ? nil : "api_token_account_id" }) %>
  <section class="n-workspace-panel space-y-4"><h2 class="n-workspace-section-title"><%= t("nosia.settings_tools.create_token") %></h2>
    <div><%= form.label :name, t("nosia.settings_tools.token_name"), class: "n-settings-tool-label" %>
      <%= form.text_field :name, required: true, class: "n-settings-tool-input", aria: settings_tool_field_aria("api_token_name", invalid: api_token.errors[:name].any?) %>
      <p id="api_token_name_help" class="n-workspace-help"><%= t("nosia.settings_tools.required") %></p>
      <% if api_token.errors[:name].any? %><p id="api_token_name_error" class="n-settings-tool-error"><%= api_token.errors.full_messages_for(:name).join(" ") %></p><% end %>
    </div>
    <div><% if @account %><p class="n-settings-tool-label"><%= t("nosia.settings_tools.default_account") %></p><%= form.hidden_field :account_id, value: @account.id %><p><%= @account.name %></p>
      <% else %><%= form.label :account_id, t("nosia.settings_tools.default_account"), class: "n-settings-tool-label" %>
        <%= form.collection_select :account_id, Current.user.accounts, :id, :name, { prompt: true }, { required: true, class: "n-settings-tool-input", aria: settings_tool_field_aria("api_token_account_id", invalid: api_token.errors[:account].any?) } %>
        <p id="api_token_account_id_help" class="n-workspace-help"><%= t("nosia.settings_tools.account_help") %></p>
        <% if api_token.errors[:account].any? %><p id="api_token_account_id_error" class="n-settings-tool-error"><%= api_token.errors.full_messages_for(:account).join(" ") %></p><% end %>
      <% end %>
    </div>
    <%= form.submit t("nosia.settings_tools.generate"), class: "n-workspace-button n-workspace-primary", data: { turbo_submits_with: t("nosia.settings_tools.generating") } %>
  </section>
<% end %>
```

`app/views/api_tokens/_token.html.erb`:

```erb
<%# locals: (token:) %>
<li class="n-settings-tool-row" data-token-row>
  <div><h3 class="n-workspace-section-title" data-token-title><%= token.name %></h3><p class="n-workspace-help"><%= t("nosia.settings_tools.default_account") %>: <%= token.account.name %></p><p class="n-workspace-help" data-token-security><%= t("nosia.settings_tools.token_security") %></p></div>
  <%= button_to t("nosia.settings_tools.revoke"), @account ? account_api_token_path(@account, token) : api_token_path(token), method: :delete, class: "n-workspace-button n-workspace-danger", data: { turbo_confirm: t("nosia.settings_tools.revoke_confirm", name: token.name, account: token.account.name), turbo_submits_with: t("nosia.settings_tools.revoking") } %>
</li>
```

`app/views/api_tokens/_created.html.erb`:

```erb
<%# locals: (token:, plain:) %>
<% content_for :head do %><meta name="turbo-cache-control" content="no-cache"><% end %>
<section class="n-workspace-panel n-settings-tool-reveal space-y-4" data-token-reveal tabindex="-1" aria-labelledby="created_api_token_title" data-controller="token-reveal" data-action="turbo:before-cache@document->token-reveal#clear pagehide@window->token-reveal#clear" data-token-reveal-success-content-value="<%= t('nosia.settings_tools.copied') %>" data-token-reveal-copying-value="<%= t('nosia.settings_tools.copying') %>" data-token-reveal-failure-value="<%= t('nosia.settings_tools.copy_failed') %>">
  <h2 id="created_api_token_title" class="n-workspace-section-title"><%= t("nosia.settings_tools.created_title") %></h2>
  <p><%= token.name %> · <%= t("nosia.settings_tools.default_account") %>: <%= token.account.name %></p>
  <p id="created_api_token_help" class="n-workspace-help"><%= t("nosia.settings_tools.created_help") %></p>
  <div class="n-settings-tool-copy"><div><label for="created_api_token" class="n-settings-tool-label"><%= t("nosia.settings_tools.secret_label") %></label><input id="created_api_token" type="text" readonly value="<%= plain %>" class="n-settings-tool-input" aria-describedby="created_api_token_help" data-token-reveal-target="source"></div>
    <button type="button" class="n-workspace-button" data-action="token-reveal#copy" data-token-reveal-target="button"><%= inline_svg "svg/clipboard.svg", aria_hidden: true, class: "h-5 w-5 shrink-0" %><%= t("nosia.settings_tools.copy") %></button>
  </div>
  <p id="created_api_token_status" role="status" aria-live="polite" class="n-workspace-help" data-token-reveal-target="status"></p>
</section>
```

The only plaintext occurrence is the labeled field. No `data-*`, hidden input,
live message, saved row or result-context field duplicates it. Cache exclusion is
limited to responses actually displaying the creation result.

- [ ] **Step 5: Precisely migrate the affected legacy request assertions.**

In `LocalizedPagesTest`'s French token test, retain creation/digest/refresh checks;
replace its five old clipboard/heading/action assertions with:

```ruby
assert_select '#created_api_token[data-token-reveal-target=source][readonly][value=?]', plain
assert_select '[data-token-reveal-success-content-value=?]', I18n.t("nosia.settings_tools.copied", locale: :fr)
assert_select "button[data-action='token-reveal#copy']", text: I18n.t("nosia.settings_tools.copy", locale: :fr)
assert_select "[data-token-row] button", text: I18n.t("nosia.settings_tools.revoke", locale: :fr)
assert_select "h2", text: I18n.t("nosia.settings_tools.created_title", locale: :fr)
```

Replace only the final failed-name-create flash assertion with:

```ruby
assert_response :unprocessable_entity
assert_select "#api_token_name[aria-invalid=true]"
assert_select "[data-form-errors-target=summary] a[href='#api_token_name']"
assert_select "[data-token-reveal]", count: 0
```

In `SettingsWorkspaceTest`'s old drawer-preservation loop, remove only
`api_tokens_path` (the prompt slice already removed prompts); keep `new_chat_path`.
Append:

```ruby
get api_tokens_path
assert_response :success
assert_select "#accordion-right-actions, #drawer-right", count: 0
assert_select "[data-settings-tool] .n-workspace-header a[href=?]", new_chat_path
assert_select ".lg\\:hidden a[href=?]", new_chat_path
```

In the prompt plan's replacement `AccountExperienceTest` global-tools loop, add
`tokens = path == api_tokens_path`; change these three expressions only:

```ruby
assert_select "nav[aria-label='Breadcrumb']", count: prompts || tokens ? 1 : 0
assert_select "#accordion-right-actions, #drawer-right", count: sources || report || prompts || tokens ? 0 : 2
if sources || report || prompts || tokens
```

Its existing fallback workspace selector already yields `[data-settings-tool]`
for both tokens/prompts. Keep all source/report and scoped-navigation assertions.
The old `ApiTokensControllerTest` regex/digest/refresh test is unchanged.

In `test/controllers/accounts/scoped_tokens_usage_test.rb`, keep every test and
all scoping/malformed/revoked/ownership/authentication/count/usage assertions.
Change only these display/recovery expectations:

- Replace all token-heading selectors `assert_select "h2", text: /second token/`,
  `/first token/` and `/member token/` with their respective expressions:

```ruby
assert_select "[data-token-row] [data-token-title]", text: /second token/
```

```ruby
assert_select "[data-token-row] [data-token-title]", text: /first token/
```

```ruby
assert_select "[data-token-row] [data-token-title]", text: /member token/
```

- Replace the two old clipboard selectors with:

```ruby
assert_select "#created_api_token[readonly][data-token-reveal-target=source][value='#{plain}']"
```

```ruby
assert_select "[data-token-reveal]", count: 0
```

- Rename `global token routes retain the personal account picker and invalid redirect`
  to `global token routes retain the personal picker and recover invalid creation`.
  Inside its existing no-difference block, replace only the redirect/alert pair:

```ruby
assert_response :unprocessable_entity
assert_select "#api_token_name[aria-invalid=true]"
assert_select "#api_token_account_id option[selected][value='#{@second.id}']"
assert_select "[data-form-errors-target=summary] a[href='#api_token_name']"
```

The later successful global revocation still redirects as before. No usage
presentation, request account rules or other test bodies change.

- [ ] **Step 6: Verify request GREEN and commit.**

```bash
record tokens-request-build rails_test tailwindcss:build
record tokens-request-green rails_test test test/controllers/api_tokens_workspace_test.rb test/controllers/api_tokens_controller_test.rb test/controllers/accounts/scoped_tokens_usage_test.rb test/models/api_token_test.rb test/controllers/account_experience_test.rb test/controllers/settings_workspace_test.rb test/integration/localized_pages_test.rb test/internationalization/catalogs_test.rb
record tokens-request-lint mise exec ruby@4.0.7 -- bundle exec rubocop app/controllers/api_tokens_controller.rb test/controllers/api_tokens_workspace_test.rb test/controllers/accounts/scoped_tokens_usage_test.rb test/controllers/account_experience_test.rb test/controllers/settings_workspace_test.rb test/integration/localized_pages_test.rb
git diff --check
git add app/controllers/api_tokens_controller.rb app/views/api_tokens test/controllers/api_tokens_workspace_test.rb test/controllers/accounts/scoped_tokens_usage_test.rb test/controllers/account_experience_test.rb test/controllers/settings_workspace_test.rb test/integration/localized_pages_test.rb
git diff --cached --check
git commit -m "feat: Improve separate personal token pages and creation recovery"
```

This commit has server-rendered copy controls but does not claim working clipboard
enhancement until T2. Review both tasks as one resource slice before advancing.

## Task T2: Truthful copying and snapshot-safe result lifecycle

**Create:** `app/javascript/controllers/token_reveal_controller.js`,
`test/system/token_reveal_test.rb`. **Modify:** only selectors/action labels in
`test/system/api_tokens_test.rb` and `test/system/account_experience_test.rb`.
Do not change the vendor clipboard, its global registration or other consumers.

- [ ] **Step 1: Write the browser tests before the controller.**

```ruby
require "application_system_test_case"
require_relative "../support/settings_tool_fixtures"

class TokenRevealTest < ApplicationSystemTestCase
  include SettingsToolFixtures

  setup do
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: AccountExperienceFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"
  end

  test "copy waits for actual completion keeps focus and never announces the secret" do
    create_token
    assert_selector "[data-token-reveal]:focus"
    plain = find("#created_api_token").value
    page.execute_script(<<~JS)
      window.testClipboardWrites = [];
      Object.defineProperty(navigator, 'clipboard', {configurable:true, value:{writeText(value) {
        window.testClipboardWrites.push(value);
        return new Promise(resolve => { window.finishTestCopy = resolve; });
      }}});
    JS
    button = find("button[data-action='token-reveal#copy']")
    button.click
    assert_selector "button[data-action='token-reveal#copy'][aria-disabled=true]", text: "Copying…"
    assert_selector "#created_api_token_status", exact_text: ""
    refute_includes find("#created_api_token_status").text, plain
    assert_equal [ plain ], page.evaluate_script("window.testClipboardWrites")
    page.execute_script("window.finishTestCopy()")
    assert_selector "#created_api_token_status", text: "Copied."
    assert_selector "button[data-action='token-reveal#copy'][aria-disabled=false]"
    assert_selector "button[data-action='token-reveal#copy']:focus"
    assert_equal plain, find("#created_api_token").value
  end

  test "rejected and absent clipboard keep selectable manual copy and never show success" do
    create_token
    plain = find("#created_api_token").value
    [ "{writeText() { return Promise.reject(new Error('denied')); }}", "undefined" ].each do |clipboard|
      page.execute_script("Object.defineProperty(navigator, 'clipboard', {configurable:true,value:#{clipboard}})")
      click_button "Copy token"
      assert_selector "#created_api_token_status", text: I18n.t("nosia.settings_tools.copy_failed")
      assert_no_text "Copied."
      assert_field "created_api_token", with: plain, readonly: true
      find("#created_api_token").click
      page.send_keys([ :control, "a" ])
      assert_equal plain.length, page.evaluate_script("document.activeElement.selectionEnd-document.activeElement.selectionStart")
      refute_includes find("#created_api_token_status").text, plain
    end
  end

  test "refresh and application back do not restore the one-time value or snapshots" do
    create_token
    plain = find("#created_api_token").value
    page.refresh
    assert_no_selector "[data-token-reveal]", visible: :all
    refute_includes page.html, plain
    create_token
    second_plain = find("#created_api_token").value
    find(".n-workspace-header nav a[href='#{account_path(@second)}']").click
    assert_current_path account_path(@second)
    page.go_back
    assert_current_path account_api_tokens_path(@second)
    assert_no_selector "[data-token-reveal]", visible: :all
    refute_includes page.html, second_plain
    refute page.evaluate_script("[localStorage,sessionStorage].some(s=>Object.entries(s).some(([k,v])=>k.includes(arguments[0])||v.includes(arguments[0])))", second_plain)
  end

  private
    def create_token
      visit account_api_tokens_path(@second)
      fill_in "api_token_name", with: "Browser deploy"
      click_on "Generate"
      assert_selector "[data-token-reveal]"
    end
end
```

The breadcrumb click is real application/Turbo navigation, not a scripted location
assignment. Browser Back must return to the account-token page without its value.

- [ ] **Step 2: Record browser RED.**

```bash
record token-reveal-red browser_test test/system/token_reveal_test.rb
```

Expected: no result focus, no completed-copy feedback, snapshot lifecycle missing.
Native clipboard permission is replaced only in this isolated fake-token browser;
these tests exercise promise success/rejection, not OS clipboard integration.

- [ ] **Step 3: Add the scoped clipboard enhancement.**

`app/javascript/controllers/token_reveal_controller.js`:

```javascript
import Clipboard from "@stimulus-components/clipboard"

export default class extends Clipboard {
  static targets = ["status"]
  static values = { copying: String, failure: String }

  connect() {
    super.connect()
    this.generation = 0
    this.element.focus()
  }

  disconnect() {
    this.generation++
  }

  async copy(event) {
    event.preventDefault()
    if (this.buttonTarget.getAttribute("aria-disabled") === "true") return
    const generation = this.generation
    this.buttonTarget.setAttribute("aria-disabled", "true")
    this.buttonTarget.textContent = this.copyingValue
    this.statusTarget.textContent = ""
    let message
    try {
      if (!navigator.clipboard?.writeText) throw new Error("unavailable")
      await navigator.clipboard.writeText(this.sourceTarget.value)
      message = this.successContentValue
    } catch {
      message = this.failureValue
    } finally {
      if (this.element.isConnected && this.generation === generation) {
        this.statusTarget.textContent = message
        this.buttonTarget.innerHTML = this.originalContent
        this.buttonTarget.setAttribute("aria-disabled", "false")
      }
    }
  }

  clear() {
    this.generation++
    this.sourceTarget.value = ""
    this.sourceTarget.removeAttribute("value")
    this.element.remove()
  }
}
```

Stimulus inherits the existing source/button targets and success-content value;
its normal eager-loader discovers the new filename. No manual global registration
or dependency pin is needed. No auto-copy, persistent storage, copied-secret log,
timeout reset or focus movement on copy completion. Copy uses `aria-disabled`
with an explicit duplicate-action guard so disabling the action does not cause
native disabled-button blur. Server-submit buttons still use Turbo's native
disabled state. Do not weaken the retained-copy-focus assertion.

- [ ] **Step 4: Migrate existing browser assertions without losing their eight cases.**

In `test/system/api_tokens_test.rb`, retain all widths/themes/long values/DB
revocation and geometry checks. Replace the confirmation/action block only:

```ruby
accept_confirm I18n.t("nosia.settings_tools.revoke_confirm", locale: :en, name: @token.name, account: @first.name) do
  find("form[action='#{api_token_path(@token)}']").click_button "Revoke token"
end
```

In its `token_card_layout` JavaScript, make these exact three selector replacements:

```javascript
const card = form.closest('[data-token-row]');
```

```javascript
noticeFits: textFits(card.querySelector('[data-token-security]')),
titleFits: textFits(card.querySelector('[data-token-title]')),
```

Its long account-name fit remains substantive: add `accountFits` to the returned
object and assert it in the long-name test beside `titleFits`:

```javascript
accountFits: textFits(card.querySelector('[data-token-title] + p')),
```

```ruby
assert layout.fetch("accountFits"), "The complete default account must wrap: #{layout}"
```

In `test/system/account_experience_test.rb`'s existing account/token workflow,
replace its two `Copy it now` text expectations and three clipboard selectors
with these exact expressions in their existing order:

```ruby
assert_text I18n.t("nosia.settings_tools.created_help")
assert_selector "#created_api_token[readonly][data-token-reveal-target=source]"
assert_selector "button[data-action='token-reveal#copy']"
```

```ruby
assert_no_text I18n.t("nosia.settings_tools.created_help")
assert_no_selector "#created_api_token[data-token-reveal-target=source]"
```

Also replace only its screenshot-redaction query selector
`[data-clipboard-target=source]` with `[data-token-reveal-target=source]`; keep the
existing redaction of both `.value` and its HTML attribute. Retain Generate, paths,
token identity, ownership, refresh/nonappearance and every unrelated assertion.

- [ ] **Step 5: Run browser GREEN/build/request regression and commit.**

```bash
record token-reveal-build rails_test tailwindcss:build
record token-reveal-green browser_test test/system/token_reveal_test.rb test/system/api_tokens_test.rb test/system/account_experience_test.rb
record token-reveal-request rails_test test test/controllers/api_tokens_workspace_test.rb test/controllers/api_tokens_controller_test.rb test/models/api_token_test.rb test/controllers/account_experience_test.rb test/integration/localized_pages_test.rb
record token-reveal-lint mise exec ruby@4.0.7 -- bundle exec rubocop test/system/token_reveal_test.rb test/system/api_tokens_test.rb test/system/account_experience_test.rb
git diff --check
git add app/javascript/controllers/token_reveal_controller.js test/system/token_reveal_test.rb test/system/api_tokens_test.rb test/system/account_experience_test.rb
git diff --cached --check
git commit -m "feat: Make one-time token copying truthful and snapshot safe"
```

Record actual tested tree/commit, counts/seeds/exits and review this full resource
slice for spec then quality. Full 128-state layout/contrast, submit busy feedback,
confirmation cancellation and workflow evidence remain the final plan's gates.
