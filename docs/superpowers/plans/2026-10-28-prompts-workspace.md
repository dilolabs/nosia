# System Prompts Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve only the five prompt page variants, preserving prompt sets, permissions, precedence and explicit-only saving.

**Architecture:** Reuse the opt-in Settings-tool shell and share prompt read/editor partials between the existing global and account controllers. Add display/navigation helpers, not a new prompt service, editor dependency or authorization rule.

**Tech Stack:** Existing Rails/ERB, Turbo/Stimulus, scoped workspace CSS, Minitest/fixtures; no model/schema/API change.

---

Prerequisite: Tasks 0–1 of [shared preparation](2026-10-28-settings-tools-workspace.md)
are verified/reviewed, including user direction for any nonzero fresh baseline.
The [approved spec](../specs/2026-10-28-prompts-members-tokens-ui-ux-design.md) is authority.
Do not put member/token management on a prompt page.

## Task P1: Prompt presentation, navigation and invalid-save recovery

**Create:** `app/helpers/system_prompts_helper.rb`,
`app/views/system_prompts/_read.html.erb`, `_editor.html.erb`,
`test/controllers/prompts_workspace_test.rb`.
**Modify:** five existing prompt views and `app/controllers/system_prompts_controller.rb:19–24`.
Do not change `Prompt`, `Account#system_prompt`, global query/owner guards or account controller authorization.

- [ ] **Step 1: Add the complete request regression file before production changes.**

```ruby
require "test_helper"
require_relative "../support/settings_tool_fixtures"

class PromptsWorkspaceTest < ActionDispatch::IntegrationTest
  include SettingsToolFixtures
  setup { sign_in_overview }

  test "five variants own bilingual shells without other resource management" do
    %i[en fr].each do |locale|
      paths = [ system_prompts_path, system_prompt_path(@shared), edit_system_prompt_path(@shared),
        account_system_prompt_path(@second), edit_account_system_prompt_path(@second) ]
      paths.each do |path|
        assert_no_difference [ "Prompt.count", "Chat.count", "ApiToken.count", "AccountUser.count" ] do
          get path, headers: { "Accept-Language" => locale.to_s }
        end
        assert_response :success
        assert_select "main h1", count: 1
        assert_equal css_select("main h1").first.text, css_select("head title").first.text
        assert_select "main .n-workspace-header nav", count: 1
        assert_select "main nav [aria-current=page]", count: 1
        assert_select "#drawer-right, #accordion-right-actions", count: 0
        assert_select "[data-settings-tool] [data-token-row], [data-settings-tool] [data-member-row]", count: 0
        assert_select "[data-settings-tool] input[name^='api_token'], [data-settings-tool] input[name^='account_user']", count: 0
        refute_match(/translation missing|missing translation/i, response.body)
      end
    end
  end

  test "directory preserves both saved record kinds without listing personal identity data" do
    before = @user.accounts.flat_map { |account| account.prompts.where(name: "system_prompt").pluck(:id) }
    get system_prompts_path
    assert_select "[data-prompt-row]", count: before.size
    [ @shared, @personal ].each { |prompt| assert_select "[data-prompt-row] a[href=?]", system_prompt_path(prompt) }
    assert_select "[data-prompt-row]", text: /#{Regexp.escape(I18n.t('nosia.settings_tools.account_default'))}/
    assert_select "[data-prompt-row]", text: /#{Regexp.escape(I18n.t('nosia.settings_tools.user_specific'))}/
    refute_includes css_select("[data-prompt-row]").map(&:text).join, @member.email
  end

  test "read pages escape literal prompt text and preserve placeholders without writes" do
    content = "<script>Literal instructions</script>\n\nReference: %{documents}"
    @shared.update!(content: content)
    [ system_prompt_path(@shared), account_system_prompt_path(@second) ].each do |path|
      get path
      assert_select "main script", count: 0
      assert_select "[data-prompt-content]", text: content
      assert_equal content, @shared.reload.content
      assert_select "[data-settings-tool] a[href=?]", path == system_prompt_path(@shared) ? edit_system_prompt_path(@shared) : edit_account_system_prompt_path(@second), count: 1
    end
  end

  test "invalid global save stays on its editor with linked errors and unchanged stored data" do
    stored = @shared.content
    patch system_prompt_path(@shared), params: { prompt: { content: " \n ", account_id: @foreign.id } }
    assert_response :unprocessable_entity
    assert_select "[data-settings-screen=prompt-edit]"
    assert_select "[data-form-errors-target=summary][role=alert][tabindex='-1'] a[href='#prompt_content']"
    assert_select "#prompt_content[aria-invalid=true][aria-describedby='prompt_content_help prompt_content_error']"
    assert_equal " \n ", css_select("#prompt_content").first.content
    assert_select "a[href=?]", system_prompt_path(@shared), text: I18n.t("nosia.actions.cancel")
    assert_equal stored, @shared.reload.content
    assert_equal @second.id, @shared.account_id
  end

  test "missing account fallback is truthful and materializes only on valid explicit update" do
    [ account_system_prompt_path(@first), edit_account_system_prompt_path(@first) ].each do |path|
      assert_no_difference("Prompt.count") { get path }
      assert_response :success
      assert_select "[data-prompt-state]", text: I18n.t("nosia.settings_tools.prompt_builtin")
    end
    assert_no_difference("Prompt.count") do
      patch account_system_prompt_path(@first), params: { prompt: { content: "" } }
    end
    assert_response :unprocessable_entity
    assert_select "[data-settings-screen=account-prompt-edit] #prompt_content[aria-invalid=true]"
    content = "Saved exactly\n%{documents}"
    assert_difference("Prompt.count", 1) do
      patch account_system_prompt_path(@first), params: { prompt: { content: content, account_id: @foreign.id } }
    end
    assert_redirected_to account_system_prompt_path(@first)
    assert_equal content, @first.reload.system_prompt
    get account_system_prompt_path(@first)
    assert_select "[data-prompt-state]", text: I18n.t("nosia.settings_tools.prompt_saved")
    assert_equal "Personal research override", @second.system_prompt(user: @member)
    assert_equal @first, @user.reload.first_account
  end

  test "current mutation permissions are preserved rather than inferred from display labels" do
    sign_in_overview(@member)
    get account_system_prompt_path(@second)
    assert_response :success
    assert_select "a[href=?]", edit_account_system_prompt_path(@second), count: 0
    get edit_account_system_prompt_path(@second)
    assert_response :forbidden
    patch system_prompt_path(@shared), params: { prompt: { content: "forbidden" } }
    assert_response :forbidden
    patch system_prompt_path(@personal), params: { prompt: { content: "Existing permitted override" } }
    assert_redirected_to system_prompt_path(@personal)
    assert_equal "Existing permitted override", @personal.reload.content
    sign_in_overview(@outsider)
    get system_prompt_path(@shared)
    assert_response :not_found
    get account_system_prompt_path(@second), params: { account_id: @foreign.id }
    assert_response :not_found
  end

  test "global and account New chat keep their distinct context and legacy destroy remains" do
    get edit_system_prompt_path(@shared)
    assert_select ".n-workspace-header a[href=?]", new_chat_path
    assert_select ".lg\\:hidden a[href=?]", new_chat_path
    get edit_account_system_prompt_path(@second)
    assert_select ".n-workspace-header a[href=?]", new_chat_path(account_id: @second.id)
    assert_select ".lg\\:hidden a[href=?]", new_chat_path(account_id: @second.id)
    assert_select "[data-settings-tool] form input[name=_method][value=delete]", count: 0
    assert_difference("Prompt.count", -1) { delete system_prompt_path(@personal) }
    assert_redirected_to system_prompts_path
    assert_equal @first, @user.reload.first_account
  end
end
```

- [ ] **Step 2: Record RED for missing owned shells and editor recovery.**

```bash
source .superpowers/settings-tools-env.sh
record prompts-red rails_test test test/controllers/prompts_workspace_test.rb
```

Expected: missing shell/state/error associations and invalid global save returning
read markup. Fix only mistakes in new tests before calling this a genuine RED.

- [ ] **Step 3: Add the display-only helper.**

`app/helpers/system_prompts_helper.rb`:

```ruby
module SystemPromptsHelper
  # @param prompt [Prompt] Existing or unsaved authorized account fallback
  # @return [String] Existing context-preserving read URL
  def prompt_workspace_read_path(prompt)
    settings_tool_account_route? ? account_system_prompt_path(@account) : system_prompt_path(prompt)
  end

  # @param prompt [Prompt] Existing or unsaved authorized account fallback
  # @return [String] Existing edit URL
  def prompt_workspace_edit_path(prompt)
    settings_tool_account_route? ? edit_account_system_prompt_path(@account) : edit_system_prompt_path(prompt)
  end

  # @param prompt [Prompt] Already-authorized record
  # @return [Boolean] Mirrors existing controller/view permissions, not new ownership policy
  def prompt_workspace_editable?(prompt)
    prompt.user_id.present? || account_owner?(prompt.account)
  end

  # @param prompt [Prompt] Authorized saved prompt
  # @return [String] Kind without disclosing another user's personal identity
  def prompt_workspace_kind(prompt)
    t(prompt.user_id.nil? ? "nosia.settings_tools.account_default" : "nosia.settings_tools.user_specific")
  end

  # @param prompt [Prompt] Authorized record or fallback
  # @param editing [Boolean] Whether Edit is current
  # @return [Array<Hash>] One context-correct resource breadcrumb
  def prompt_workspace_trail(prompt, editing: false)
    if settings_tool_account_route?
      settings_tool_trail(resource: t("nosia.settings_tools.prompt_title"), path: account_system_prompt_path(@account), current: editing ? t("nosia.actions.edit") : nil)
    else
      record = { label: prompt.account.name, path: editing ? system_prompt_path(prompt) : nil }
      settings_tool_trail(resource: t("nosia.prompts.title"), path: system_prompts_path, record: record, current: editing ? t("nosia.actions.edit") : nil)
    end
  end
end
```

- [ ] **Step 4: Replace prompt views with these complete templates.**

`app/views/system_prompts/index.html.erb`:

```erb
<div class="n-workspace n-settings-tool" data-settings-tool data-settings-screen="prompts">
  <%= render "settings_tools/header", title: t("nosia.prompts.title"), description: t("nosia.settings_tools.prompts_description"), trail: settings_tool_trail(resource: t("nosia.prompts.title"), path: system_prompts_path) %>
  <%= render "settings_tools/feedback" %>
  <% if @system_prompts.any? %>
    <ul class="n-settings-tool-rows !list-none" role="list"><% @system_prompts.each do |prompt| %>
      <li class="n-settings-tool-row" data-prompt-row><div><h2 class="n-workspace-section-title"><%= link_to prompt.account.name, system_prompt_path(prompt), class: "n-workspace-link" %></h2><p class="n-workspace-help"><%= prompt_workspace_kind(prompt) %></p></div><%= link_to t("nosia.settings_tools.prompt_open"), system_prompt_path(prompt), class: "n-workspace-link" %></li>
    <% end %></ul>
  <% else %>
    <section class="n-workspace-panel"><h2 class="n-workspace-section-title"><%= t("nosia.settings_tools.prompts_empty") %></h2><p class="n-workspace-help"><%= t("nosia.settings_tools.prompts_empty_help") %></p><%= link_to t("nosia.settings_tools.open_accounts"), accounts_path, class: "n-workspace-link" %></section>
  <% end %>
</div>
```

`app/views/system_prompts/_read.html.erb`:

```erb
<%# locals: (prompt:) %>
<div class="n-workspace n-settings-tool" data-settings-tool data-settings-screen="<%= settings_tool_account_route? ? 'account-prompt' : 'prompt' %>">
  <% actions = link_to(t("nosia.settings_tools.prompt_edit_action"), prompt_workspace_edit_path(prompt), class: "n-workspace-button n-workspace-primary") if prompt_workspace_editable?(prompt) %>
  <%= render "settings_tools/header", title: t("nosia.settings_tools.prompt_title"), trail: prompt_workspace_trail(prompt), scope_label: t("nosia.workspace.account", name: prompt.account.name), actions: actions %>
  <%= render "settings_tools/feedback" %>
  <% if settings_tool_account_route? %>
    <p class="n-settings-tool-badge" data-prompt-state><%= t(prompt.persisted? ? "nosia.settings_tools.prompt_saved" : "nosia.settings_tools.prompt_builtin") %></p>
    <% unless prompt.persisted? %><p class="n-settings-tool-message"><%= t("nosia.settings_tools.prompt_fallback") %></p><% end %>
  <% else %><p class="n-settings-tool-badge"><%= prompt_workspace_kind(prompt) %></p><% end %>
  <% if prompt.user_id.nil? %><p class="n-workspace-help"><%= t("nosia.settings_tools.prompt_precedence") %></p><% end %>
  <section class="n-workspace-panel"><h2 class="n-workspace-section-title"><%= t("nosia.prompts.label") %></h2><div class="n-settings-tool-reading" data-prompt-content><%= prompt.content %></div></section>
</div>
```

Both `app/views/system_prompts/show.html.erb` and
`app/views/accounts/system_prompts/show.html.erb` become exactly:

```erb
<%= render "system_prompts/read", prompt: @system_prompt %>
```

`app/views/system_prompts/_editor.html.erb`:

```erb
<%# locals: (prompt:) %>
<div class="n-workspace n-settings-tool" data-settings-tool data-settings-screen="<%= settings_tool_account_route? ? 'account-prompt-edit' : 'prompt-edit' %>">
  <%= render "settings_tools/header", title: t("nosia.settings_tools.prompt_edit"), description: t("nosia.settings_tools.prompt_help"), trail: prompt_workspace_trail(prompt, editing: true), scope_label: t("nosia.workspace.account", name: prompt.account.name) %>
  <%= render "settings_tools/feedback" %>
  <% if settings_tool_account_route? %><p class="n-settings-tool-badge" data-prompt-state><%= t(prompt.persisted? ? "nosia.settings_tools.prompt_saved" : "nosia.settings_tools.prompt_builtin") %></p><% end %>
  <%= form_with model: prompt, url: prompt_workspace_read_path(prompt), method: :patch, class: "n-settings-tool-form", data: { controller: "form-errors html-form", action: "click->form-errors#focusField invalid->form-errors#revealInvalid:capture turbo:before-fetch-request->html-form#requestHTML" } do |form| %>
    <%= render "settings_tools/errors", items: settings_tool_errors(prompt, targets: { content: "prompt_content" }) %>
    <section class="n-workspace-panel space-y-4"><%= form.label :content, t("nosia.prompts.label"), class: "n-settings-tool-label" %>
      <%= form.text_area :content, id: "prompt_content", required: true, class: "n-settings-tool-input n-settings-tool-editor", aria: settings_tool_field_aria("prompt_content", invalid: prompt.errors[:content].any?) %>
      <p id="prompt_content_help" class="n-workspace-help"><%= t("nosia.settings_tools.required") %></p>
      <% if prompt.errors[:content].any? %><p id="prompt_content_error" class="n-settings-tool-error"><%= prompt.errors.full_messages_for(:content).join(" ") %></p><% end %>
    </section>
    <div class="n-workspace-actions"><%= form.submit t("nosia.actions.save"), class: "n-workspace-button n-workspace-primary", data: { turbo_submits_with: t("nosia.settings_tools.saving") } %><%= link_to t("nosia.actions.cancel"), prompt_workspace_read_path(prompt), class: "n-workspace-link" %></div>
  <% end %>
</div>
```

Both `app/views/system_prompts/edit.html.erb` and
`app/views/accounts/system_prompts/edit.html.erb` become exactly:

```erb
<%= render "system_prompts/editor", prompt: @system_prompt %>
```

Only the global controller's invalid-update branch changes:

```ruby
    else
      render :edit, status: :unprocessable_entity
    end
```

Retain its original query/order/strong parameters, owner guard, redirects/notices
and destroy method. The account controller already has correct fallback/422
orchestration and needs no changes.

- [ ] **Step 5: Make the precise legacy prompt assertion migrations.**

In `test/controllers/system_prompts_controller_test.rb`, replace both legacy
`p.n-card-title` assertions with the following respective expressions. Do not
change any record-count/account-move/read-only assertion:

```ruby
assert_select "[data-prompt-row] a[href=?]", system_prompt_path(@account.prompts.find_by!(name: "system_prompt", user: nil)), text: @account.name
```

```ruby
assert_select "[data-prompt-row] a[href=?]", system_prompt_path(prompt), text: @account.name
```

In `LocalizedPagesTest#test_French_prompt_read_pages_preserve_prompt_IDs_content_and_full_names`,
retain the whole existing loop, content/ID/DB/full_name assertions and label check;
replace only its final heading assertion with:

```ruby
assert_select "h1", text: I18n.t("nosia.settings_tools.prompt_edit", locale: :fr)
```

In `SettingsWorkspaceTest`, remove **only `system_prompts_path`** from the old
drawer-preservation loop (tokens remain legacy until their plan), and append:

```ruby
get system_prompts_path
assert_response :success
assert_select "#accordion-right-actions, #drawer-right", count: 0
assert_select "[data-settings-tool] .n-workspace-header a[href=?]", new_chat_path
assert_select ".lg\\:hidden a[href=?]", new_chat_path
```

Replace `AccountExperienceTest`'s test named `global tools retain navigation and
workspace reports omit conversation drawers` with this complete bounded version:

```ruby
test "global tools retain their own contextual navigation and drawer boundaries" do
  prompt_path = system_prompt_path(experience(:prompts, :overview_second_shared))
  [ sources_path, new_sources_text_path, api_tokens_path, token_usage_path, prompt_path ].each do |path|
    get path
    assert_response :success
    sources = [ sources_path, new_sources_text_path ].include?(path)
    report = path == token_usage_path
    prompts = path == prompt_path
    assert_select "nav[aria-label='Breadcrumb']", count: prompts ? 1 : 0
    assert_select "#accordion-right-actions, #drawer-right", count: sources || report || prompts ? 0 : 2
    if sources || report || prompts
      workspace = sources ? "[data-source-workspace]" : (report ? "[data-usage-workspace]" : "[data-settings-tool]")
      assert_select workspace, count: 1
      assert_select "#{workspace} a[href='#{new_chat_path}']", text: I18n.t("nosia.nav.new_chat")
    end
  end
end
```

These are approved changed presentation contracts, not dropped protected tests.
Unexpected unrelated failures still stop execution.

In `test/controllers/accounts/administration_test.rb`, retain all permission,
count, no-job, fallback and context tests. Make these exact presentation updates:

- Replace the old precedence paragraph assertion with:

```ruby
assert_select "p", text: I18n.t("nosia.settings_tools.prompt_precedence")
```

- In the test `legacy shared prompt read controls are hidden from members but personal controls remain`,
  change only both permitted Edit link counts from `2` to `1`:

```ruby
assert_select "a[href='#{edit_system_prompt_path(personal)}']", count: 1
```

```ruby
assert_select "a[href='#{edit_system_prompt_path(shared)}']", count: 1
```

- Replace the test `owner prompt page retains membership and both edit controls`
  with the complete navigation equivalent below. Membership stays reachable from
  the account hub, not a second management control on the prompt page:

```ruby
test "owner prompt page has one edit action and returns to the separate account hub" do
  sign_in_overview
  get account_system_prompt_path(@second)
  assert_response :success
  assert_select "a[href='#{edit_account_system_prompt_path(@second)}']", count: 1
  assert_select "a[href='#{account_path(@second)}']", minimum: 1
  assert_select "a[href='#{account_account_users_path(@second)}']", count: 0
  get edit_account_system_prompt_path(@second)
  assert_response :success
  assert_select "nav[aria-label='Breadcrumb'] [aria-current='page']", text: I18n.t("nosia.actions.edit")
  assert_select "form[action='#{account_system_prompt_path(@second)}'] input[name='_method'][value='patch']"
end
```

- [ ] **Step 6: Run GREEN/build/lint and review the staged scope.**

```bash
record prompts-build rails_test tailwindcss:build
record prompts-green rails_test test test/controllers/prompts_workspace_test.rb test/controllers/system_prompts_controller_test.rb test/controllers/accounts/system_prompts_controller_test.rb test/controllers/accounts/administration_test.rb test/integration/system_prompt_materialization_test.rb test/controllers/account_experience_test.rb test/controllers/settings_workspace_test.rb test/integration/localized_pages_test.rb test/internationalization/catalogs_test.rb
record prompts-lint mise exec ruby@4.0.7 -- bundle exec rubocop app/helpers/system_prompts_helper.rb app/controllers/system_prompts_controller.rb test/controllers/prompts_workspace_test.rb test/controllers/system_prompts_controller_test.rb test/controllers/accounts/administration_test.rb test/controllers/account_experience_test.rb test/controllers/settings_workspace_test.rb test/integration/localized_pages_test.rb
git diff --check
git add app/helpers/system_prompts_helper.rb app/controllers/system_prompts_controller.rb app/views/system_prompts app/views/accounts/system_prompts test/controllers/prompts_workspace_test.rb test/controllers/system_prompts_controller_test.rb test/controllers/accounts/administration_test.rb test/controllers/account_experience_test.rb test/controllers/settings_workspace_test.rb test/integration/localized_pages_test.rb
git diff --cached --check
git commit -m "feat: Align separate system prompt pages with the workspace"
```

Expect only original baseline exceptions explicitly accepted for this execution,
not new failures. Record actual tested tree, counts/seeds/exits and YARD checks.
Spec then quality review must approve this slice (independent agents only for the
selected subagent-driven method; otherwise inline). Prompt browser
workflows and all five variants are exercised in the final verification plan;
do not claim them verified from request assertions alone.
