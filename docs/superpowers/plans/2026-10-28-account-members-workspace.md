# Account Members Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve the dedicated owner-only member page with readable rows and recoverable existing-user addition.

**Architecture:** Keep the existing AccountScoped/owner guards and membership model. The controller retains submitted email and presents known lookup/validation outcomes as field errors; shared display partials do not become a user directory or invitation system.

**Tech Stack:** Existing Rails/ERB, Turbo, form-errors/html-form Stimulus, Minitest and account-experience fixtures.

---

Prerequisite: [shared preparation](2026-10-28-settings-tools-workspace.md) is verified.
This slice works without token or prompt UI changes. Do not add member management
to any other screen, change member permissions or delete User records.

## Task M1: Existing-user recovery and owner-protected rows

**Modify:** `app/controllers/accounts/account_users_controller.rb`,
`app/views/accounts/account_users/index.html.erb`, the two precise French tests below.
**Create:** `_form.html.erb`, `_member.html.erb` in that view directory;
`test/controllers/account_members_workspace_test.rb`.

- [ ] **Step 1: Write request tests before changing controller/template behavior.**

```ruby
require "test_helper"
require_relative "../support/settings_tool_fixtures"

class AccountMembersWorkspaceTest < ActionDispatch::IntegrationTest
  include SettingsToolFixtures
  setup { sign_in_overview }

  test "dedicated bilingual page identifies owner and keeps other resources out" do
    %i[en fr].each do |locale|
      get account_account_users_path(@second), headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      assert_select "main h1", text: I18n.t("nosia.settings_tools.members_title", locale: locale), count: 1
      assert_equal css_select("main h1").first.text, css_select("head title").first.text
      assert_select "main .n-workspace-header nav", count: 1
      assert_select "[data-workspace-scope]", text: /#{Regexp.escape(@second.name)}/
      assert_select "[data-member-row]", count: 2
      assert_select "[data-member-owner=true] form", count: 0
      assert_select "[data-member-owner=true]", text: /#{Regexp.escape(I18n.t('nosia.settings_tools.owner_protected', locale: locale))}/
      assert_select "[data-settings-tool] input[name^='api_token'], [data-settings-tool] textarea[name='prompt[content]']", count: 0
      assert_select "#drawer-right, #accordion-right-actions", count: 0
      refute_match(/translation missing|missing translation/i, response.body)
    end
  end

  test "unknown and duplicate users retain email with linked 422 recovery and no side effects" do
    %i[en fr].each do |locale|
      { "not-registered@example.invalid" => :member_unknown, @member.email => :member_duplicate }.each do |email, key|
        assert_no_enqueued_jobs do
          assert_no_difference [ "User.count", "AccountUser.count", "Prompt.count", "ApiToken.count", "Chat.count" ] do
            post account_account_users_path(@second), params: { account_user: { email: email } }, headers: { "Accept-Language" => locale.to_s }
          end
        end
        assert_response :unprocessable_entity
        assert_select "#account_user_email[value=?][aria-invalid=true]", email
        assert_select "[data-form-errors-target=summary][role=alert][tabindex='-1'] a[href='#account_user_email']", text: I18n.t("nosia.settings_tools.#{key}", locale: locale)
        assert_select "#account_user_email_error", text: I18n.t("nosia.settings_tools.#{key}", locale: locale)
        assert_select "form[action=?]", account_account_users_path(@second)
      end
    end
  end

  test "owner adds existing user and removes only that membership with contextual confirmation" do
    assert_no_enqueued_jobs do
      assert_no_difference [ "User.count", "ApiToken.count", "Chat.count", "Prompt.count" ] do
        assert_difference("AccountUser.count", 1) do
          post account_account_users_path(@second), params: { account_user: { email: @outsider.email, account_id: @foreign.id } }
        end
      end
    end
    assert_redirected_to account_account_users_path(@second)
    follow_redirect!
    membership = @second.account_users.find_by!(user: @outsider)
    assert_select "form[action=?] button[data-turbo-confirm=?]", account_account_user_path(@second, membership), I18n.t("nosia.settings_tools.member_confirm", email: @outsider.email, account: @second.name)
    assert_no_difference [ "User.count", "ApiToken.count", "Chat.count" ] do
      assert_difference("AccountUser.count", -1) { delete account_account_user_path(@second, membership) }
    end
    assert_redirected_to account_account_users_path(@second)
    assert User.exists?(@outsider.id)
    assert @foreign.account_users.exists?(user: @outsider)
    assert_equal @first, @user.reload.first_account
  end

  test "owner protection and existing owner member foreign revoked context rules stay authoritative" do
    owner_membership = @second.account_users.find_by!(user: @user)
    assert_no_difference("AccountUser.count") { delete account_account_user_path(@second, owner_membership) }
    assert_redirected_to account_account_users_path(@second)
    assert_equal I18n.t("nosia.accounts.owner_cannot_remove"), flash[:alert]
    foreign_membership = @foreign.account_users.first
    assert_no_difference("AccountUser.count") { delete account_account_user_path(@second, foreign_membership) }
    assert_response :not_found
    sign_in_overview(@member)
    get account_account_users_path(@second)
    assert_response :forbidden
    assert_no_difference("AccountUser.count") do
      post account_account_users_path(@second), params: { account_user: { email: @outsider.email } }
    end
    assert_response :forbidden
    get account_account_users_path(@foreign), params: { account_id: @second.id }
    assert_response :not_found
    sign_in_overview
    owner_membership.destroy!
    get account_account_users_path(@second)
    assert_response :not_found
  end

  test "owner-only list is not mislabeled empty and malformed form containers fail closed" do
    get account_account_users_path(@empty)
    assert_select "[data-member-row]", count: 1
    assert_select "[data-members-only-owner]", text: I18n.t("nosia.settings_tools.no_additional_members")
    [ nil, "bad", [], { email: [] } ].each do |payload|
      assert_no_difference [ "User.count", "AccountUser.count" ] do
        post account_account_users_path(@second), params: { account_user: payload }, as: :json
      end
      assert_response :bad_request
    end
  end
end
```

- [ ] **Step 2: Run RED, then replace the existing controller with this bounded version.**

```bash
source .superpowers/settings-tools-env.sh
record members-red rails_test test test/controllers/account_members_workspace_test.rb
```

Expected: old redirect/markup, not an authorization prerequisite mistake.

```ruby
# frozen_string_literal: true

module Accounts
  class AccountUsersController < ApplicationController
    include AccountScoped

    before_action :set_account
    before_action :require_account_owner
    before_action :set_account_user, only: :destroy

    def index
      @account_users = @account.account_users.includes(:user)
      @member_email = ""
    end

    def create
      @member_email = member_params.fetch(:email)
      user = User.find_by(email: @member_email)
      @account_user = @account.account_users.new(user: user)

      if user.nil?
        @member_error = t("nosia.settings_tools.member_unknown")
      elsif @account_user.save
        redirect_to account_account_users_path(@account), notice: t("nosia.accounts.user_added")
      else
        @member_error = t(@account_user.errors.of_kind?(:user, :taken) ? "nosia.settings_tools.member_duplicate" : "nosia.settings_tools.member_failed")
      end

      if @member_error
        @account_users = @account.account_users.includes(:user)
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      if @account_user.user_id == @account.owner_id
        redirect_to account_account_users_path(@account), alert: t("nosia.accounts.owner_cannot_remove")
      else
        @account_user.destroy!
        redirect_to account_account_users_path(@account), notice: t("nosia.accounts.user_removed")
      end
    end

    private
      def set_account
        @account = member_account(request.path_parameters.fetch(:account_id))
      end

      def member_params
        input = params[:account_user]
        raise ActionController::ParameterMissing, :account_user unless input.is_a?(ActionController::Parameters)
        permitted = input.permit(:email)
        raise ActionController::ParameterMissing, :email unless permitted[:email].is_a?(String)
        permitted
      end

      def set_account_user
        @account_user = @account.account_users.find(params[:id])
      end
  end
end
```

No new lookup semantics, email normalization, User creation or model validation
rules. The virtual email stays a controller/view value; no form/service object or
database column is needed. Owner guard executes before lookup, as before.

- [ ] **Step 3: Replace the dedicated page and add its two partials.**

`app/views/accounts/account_users/index.html.erb`:

```erb
<div class="n-workspace n-settings-tool" data-settings-tool data-settings-screen="members">
  <%= render "settings_tools/header", title: t("nosia.settings_tools.members_title"), description: t("nosia.settings_tools.members_description"), scope_label: t("nosia.workspace.account", name: @account.name), trail: settings_tool_trail(resource: t("nosia.settings_tools.members_title"), path: account_account_users_path(@account)) %>
  <%= render "settings_tools/feedback" %>
  <%= render "form" %>
  <ul class="n-settings-tool-rows !list-none" role="list"><%= render partial: "member", collection: @account_users, as: :membership %></ul>
  <% if @account_users.all? { |membership| membership.user_id == @account.owner_id } %><p class="n-settings-tool-message" data-members-only-owner><%= t("nosia.settings_tools.no_additional_members") %></p><% end %>
</div>
```

`app/views/accounts/account_users/_form.html.erb`:

```erb
<%= form_with scope: :account_user, url: account_account_users_path(@account), method: :post, class: "n-settings-tool-form", data: { controller: "form-errors html-form", action: "click->form-errors#focusField invalid->form-errors#revealInvalid:capture turbo:before-fetch-request->html-form#requestHTML" } do |form| %>
  <%= render "settings_tools/errors", items: @member_error ? [ { message: @member_error, target: "account_user_email" } ] : [] %>
  <section class="n-workspace-panel space-y-4"><h2 class="n-workspace-section-title"><%= t("nosia.settings_tools.add_existing") %></h2><p id="account_user_email_help" class="n-workspace-help"><%= t("nosia.settings_tools.existing_user_help") %></p>
    <%= form.label :email, t("nosia.settings_tools.email"), class: "n-settings-tool-label" %>
    <%= form.email_field :email, id: "account_user_email", value: @member_email, required: true, class: "n-settings-tool-input", aria: settings_tool_field_aria("account_user_email", invalid: @member_error.present?) %>
    <% if @member_error %><p id="account_user_email_error" class="n-settings-tool-error"><%= @member_error %></p><% end %>
    <%= form.submit t("nosia.settings_tools.add_member"), class: "n-workspace-button n-workspace-primary", data: { turbo_submits_with: t("nosia.settings_tools.adding_member") } %>
  </section>
<% end %>
```

`app/views/accounts/account_users/_member.html.erb`:

```erb
<%# locals: (membership:) %>
<% owner = membership.user_id == @account.owner_id %>
<li class="n-settings-tool-row" data-member-row data-member-owner="<%= owner %>">
  <div><h2 class="n-workspace-section-title"><%= membership.user.email %></h2>
    <p><span class="n-settings-tool-badge"><%= t(owner ? "nosia.settings_tools.owner" : "nosia.settings_tools.member") %></span>
      <% if membership.user_id == Current.user.id %><span class="n-settings-tool-badge"><%= t("nosia.settings_tools.you") %></span><% end %></p>
  </div>
  <% if owner %><p class="n-workspace-help"><%= t("nosia.settings_tools.owner_protected") %></p>
  <% else %><%= button_to t("nosia.settings_tools.remove_member"), account_account_user_path(@account, membership), method: :delete, class: "n-workspace-button n-workspace-danger", data: { turbo_confirm: t("nosia.settings_tools.member_confirm", email: membership.user.email, account: @account.name), turbo_submits_with: t("nosia.settings_tools.removing_member") } %><% end %>
</li>
```

- [ ] **Step 4: Update only the corresponding French presentation/recovery assertions.**

In `LocalizedPagesTest#test_French_account_members_translate_actions_without_changing_form_paths_or_email`,
use this complete body; the path, method, email and current-user information remain checked:

```ruby
sign_in_picker_user
get account_account_users_url(@second), headers: { "Accept-Language" => "fr" }
assert_response :success
assert_select "h1", text: I18n.t("nosia.settings_tools.members_title", locale: :fr)
assert_select "[data-workspace-scope]", text: /Research team/
assert_select "form[action=?][method=post]", account_account_users_path(@second) do
  assert_select 'input[type="submit"][value=?]', I18n.t("nosia.settings_tools.add_member", locale: :fr)
  assert_select 'input[type="email"][name="account_user[email]"]'
end
assert_select "[data-member-row] h2", text: @user.email
assert_select "[data-member-row] span", text: I18n.t("nosia.settings_tools.you", locale: :fr)
```

In the French membership lifecycle test, replace the unknown-user flash assertion
immediately after its original POST with:

```ruby
assert_response :unprocessable_entity
assert_select "#account_user_email[value='missing@example.invalid'][aria-invalid=true]"
assert_select "#account_user_email_error", text: I18n.t("nosia.settings_tools.member_unknown", locale: :fr)
```

Keep the successful addition notice, membership lookup and all later lifecycle/
owner/forbidden assertions. After that successful addition notice, add
`follow_redirect!(headers: headers)` to consume the notice as a real browser does.
Replace only the duplicate-member flash assertion after the original duplicate
POST with:

```ruby
assert_response :unprocessable_entity
assert_select "#account_user_email_error", text: I18n.t("nosia.settings_tools.member_duplicate", locale: :fr)
assert_select "#account_user_email[value=?]", outsider.email
```

The owner's removal error and successful removal still use their original
`nosia.accounts` notices, so do not rewrite those assertions.

- [ ] **Step 5: Verify and commit this independent slice.**

```bash
record members-build rails_test tailwindcss:build
record members-green rails_test test test/controllers/account_members_workspace_test.rb test/controllers/accounts/account_users_authorization_test.rb test/controllers/account_experience_test.rb test/integration/localized_pages_test.rb test/internationalization/catalogs_test.rb
record members-lint mise exec ruby@4.0.7 -- bundle exec rubocop app/controllers/accounts/account_users_controller.rb test/controllers/account_members_workspace_test.rb test/integration/localized_pages_test.rb
git diff --check
git add app/controllers/accounts/account_users_controller.rb app/views/accounts/account_users test/controllers/account_members_workspace_test.rb test/integration/localized_pages_test.rb
git diff --cached --check
git commit -m "feat: Improve dedicated account member management and recovery"
```

Record actual tested tree/commit and raw counts/seeds/exits. Require spec then
quality approval, using independent agents only if subagent-driven execution was
selected; otherwise review inline. Real confirmation cancel/accept, native validation and
summary focus remain browser obligations in the final verification plan; no
browser or permissions-success claim may be inferred just from the template.
