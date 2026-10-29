require "application_system_test_case"
require_relative "../support/settings_tool_fixtures"
require_relative "../support/settings_tool_browser_checks"

# Exercises real recovery and destructive workflows at a representative desktop state.
class SettingsToolsWorkflowsTest < ApplicationSystemTestCase
  include SettingsToolFixtures
  include SettingsToolBrowserChecks

  setup do
    tools_sign_in
    tools_locale("en")
    tools_size(1440, 1000)
    tools_theme("light")
  end

  test "global and account editors retain rejected text focus native errors and save explicitly" do
    first_account = @user.first_account.id
    cases = [
      [ edit_system_prompt_path(@shared), system_prompt_path(@shared), 0 ],
      [ edit_account_system_prompt_path(@first), account_system_prompt_path(@first), 1 ]
    ]
    cases.each do |edit_path, read_path, materialized|
      visit edit_path
      before = Prompt.count
      fill_in "prompt_content", with: ""
      click_button "Save"
      assert_selector "#prompt_content:invalid:focus"
      assert_no_selector "[data-form-errors-target=summary]", visible: :all
      assert_equal before, Prompt.count
      tools_record("prompt-workflow", { stage: "native-rejected", count_unchanged: true, invalid_focused: true })

      rejected = " \n "
      fill_in "prompt_content", with: rejected
      # Only this whitespace submission bypasses native validation to exercise the 422.
      page.execute_script("document.querySelector('form[data-controller~=\"html-form\"]').noValidate = true")
      click_button "Save"
      assert_selector "[data-form-errors-target=summary]:focus"
      assert_equal rejected, page.evaluate_script("document.querySelector('#prompt_content').value")
      assert_equal before, Prompt.count
      tools_record("prompt-workflow", { stage: "server-rejected", retained_exact: true, summary_focused: true, count_unchanged: true })
      tools_error_field("prompt_content", "prompt-error-focus")

      content = "Literal instructions\n%{documents}"
      fill_in "prompt_content", with: content
      click_button "Save"
      assert_current_path read_path
      tools_status("nosia.prompts.updated")
      assert_equal content, page.evaluate_script("document.querySelector('[data-prompt-content]').textContent")
      assert_equal before + materialized, Prompt.count
      saved = materialized.zero? ? @shared.reload : @first.prompts.find_by!(name: "system_prompt", user: nil)
      assert_equal content, saved.content
      tools_record("prompt-workflow", { stage: "saved", literal_body: true, count_delta: materialized, correct_context: true })

      visit edit_path
      fill_in "prompt_content", with: "Unsaved cancellation"
      click_link "Cancel"
      assert_current_path read_path
      assert_no_text "Unsaved cancellation"
      assert_equal content, saved.reload.content
      assert_equal before + materialized, Prompt.count
      tools_record("prompt-workflow", { stage: "cancelled", saved_content_unchanged: true, correct_context: true })
    end
    assert_equal "Personal research override", @second.system_prompt(user: @member)
    assert_equal first_account, @user.reload.first_account.id
    assert_no_enqueued_jobs
    tools_record("prompt-workflow", { stage: "invariants", personal_precedence: true, default_unchanged: true, no_jobs: true })
  end

  test "members retain unknown and duplicate emails and distinguish cancel from removal" do
    visit account_account_users_path(@second)
    before = [ User.count, AccountUser.count ]
    click_button "Add member"
    assert_selector "#account_user_email:invalid:focus"
    fill_in "account_user_email", with: "not-an-email"
    click_button "Add member"
    assert_selector "#account_user_email:invalid:focus"
    assert_no_selector "[data-form-errors-target=summary]", visible: :all
    assert_equal before, [ User.count, AccountUser.count ]
    tools_record("member-workflow", { stage: "native-rejected", invalid_focused: true, counts_unchanged: true })

    [ [ "unknown@example.invalid", "member_unknown" ], [ @member.email, "member_duplicate" ] ].each do |email, error|
      fill_in "account_user_email", with: email
      click_button "Add member"
      assert_selector "[data-form-errors-target=summary]:focus", text: I18n.t("nosia.settings_tools.#{error}", locale: :en)
      assert_equal email, find("#account_user_email").value
      assert_equal before, [ User.count, AccountUser.count ]
      tools_record("member-workflow", { stage: error, summary_focused: true, retained_exact: true, counts_unchanged: true })
      tools_error_field("account_user_email", "member-error-focus")
    end

    fill_in "account_user_email", with: @outsider.email
    click_button "Add member"
    assert_current_path account_account_users_path(@second)
    tools_status("nosia.accounts.user_added")
    membership = @second.account_users.find_by!(user: @outsider)
    foreign_membership = experience(:account_users, :overview_outsider_foreign)
    path = account_account_user_path(@second, membership)
    confirmation = I18n.t("nosia.settings_tools.member_confirm", locale: :en, email: @outsider.email, account: @second.name)
    assert_equal [ before.first, before.last + 1 ], [ User.count, AccountUser.count ]
    tools_record("member-workflow", { stage: "added", membership_delta: 1, user_delta: 0, correct_context: true })

    dismiss_confirm confirmation do
      find("form[action='#{path}']").click_button "Remove member"
    end
    assert AccountUser.exists?(membership.id)
    assert_selector "form[action='#{path}']"
    tools_record("member-workflow", { stage: "dismissed", membership_present: true })

    tools_tab_to("form[action='#{path}'] button")
    assert_selector "form[action='#{path}'] button:focus"
    accept_confirm(confirmation) { page.send_keys(:enter) }
    assert_no_selector "form[action='#{path}']", visible: :all
    tools_status("nosia.accounts.user_removed")
    refute AccountUser.exists?(membership.id)
    assert User.exists?(@outsider.id)
    assert AccountUser.exists?(foreign_membership.id)
    assert_equal before, [ User.count, AccountUser.count ]
    within "[data-member-owner=true]" do
      assert_text I18n.t("nosia.settings_tools.owner_protected", locale: :en)
      assert_no_selector "form", visible: :all
    end
    assert_no_enqueued_jobs
    tools_record("member-workflow", { stage: "confirmed-native-enter", membership_removed: true, user_preserved: true,
      foreign_membership_preserved: true, owner_static: true, counts_restored: true })
  end

  test "repeated member rejection refocuses the morphed error summary" do
    visit account_account_users_path(@second)
    fill_in "account_user_email", with: "unknown@example.invalid"
    click_button "Add member"
    assert_selector "[data-form-errors-target=summary]:focus"
    tools_error_field("account_user_email", "member-first-error-focus")
    page.execute_script(<<~JS)
      window.toolsPreviousSummary = document.querySelector('[data-form-errors-target=summary]');
      window.toolsMorphs = 0;
      document.addEventListener('turbo:morph', () => window.toolsMorphs++);
    JS

    fill_in "account_user_email", with: @member.email
    click_button "Add member"
    assert_selector "[data-form-errors-target=summary]", text: I18n.t("nosia.settings_tools.member_duplicate", locale: :en)
    tools_record("repeat-error-regression", {
      summary_preserved: page.evaluate_script("window.toolsPreviousSummary === document.querySelector('[data-form-errors-target=summary]')"),
      morph_events: page.evaluate_script("window.toolsMorphs"),
      summary_focused: page.has_css?("[data-form-errors-target=summary]:focus", wait: 0), focus: tools_probe("focus")
    })
    assert_selector "[data-form-errors-target=summary]:focus"
  end

  test "global and scoped token errors are recoverable and revocation requires confirmation" do
    first_account = @user.first_account.id
    defaults = ApiToken.order(:id).pluck(:id, :account_id)
    [ api_tokens_path, account_api_tokens_path(@second) ].each do |index_path|
      visit index_path
      before = ApiToken.count
      click_button "Generate"
      assert_selector "#api_token_name:invalid:focus"
      fill_in "api_token_name", with: "Browser token"
      if index_path == api_tokens_path
        click_button "Generate"
        assert_selector "#api_token_account_id:invalid:focus"
        assert_no_selector "#api_token_account_id option[value='#{@foreign.id}']", visible: :all
        select @second.name, from: "api_token_account_id"
      end
      assert_equal before, ApiToken.count
      tools_record("token-workflow", { stage: "native-rejected", invalid_focused: true, count_unchanged: true })

      fill_in "api_token_name", with: " "
      click_button "Generate"
      assert_selector "[data-form-errors-target=summary]:focus"
      assert_equal " ", find("#api_token_name").value
      assert_equal before, ApiToken.count
      assert_no_selector "[data-token-reveal]", visible: :all
      tools_record("token-workflow", { stage: "server-rejected", summary_focused: true, count_unchanged: true, no_reveal: true })
      tools_error_field("api_token_name", "token-error-focus")

      fill_in "api_token_name", with: "Browser token"
      click_button "Generate"
      assert_current_path index_path
      assert_selector "[data-token-reveal]:focus"
      token = @user.api_tokens.order(:created_at, :id).last
      plain = find("#created_api_token[readonly]").value
      assert ApiToken.authenticate_token(plain) == token, "The exact revealed value must authenticate the newly created token"
      assert_equal [ @user.id, @second.id ], [ token.user_id, token.account_id ]
      assert_equal before + 1, ApiToken.count
      tools_record("token-workflow", { stage: "generated", reveal_focused: true, exact_authentication: true,
        count_delta: 1, correct_account: true, correct_context: true })

      path = index_path == api_tokens_path ? api_token_path(token) : account_api_token_path(@second, token)
      confirmation = I18n.t("nosia.settings_tools.revoke_confirm", locale: :en, name: token.name, account: @second.name)
      dismiss_confirm confirmation do
        find("form[action='#{path}']").click_button "Revoke token"
      end
      assert ApiToken.exists?(token.id)
      assert_selector "form[action='#{path}']"
      assert ApiToken.authenticate_token(plain) == token, "Dismissing confirmation must leave the exact token usable"
      tools_record("token-workflow", { stage: "dismissed", token_present: true, authentication_preserved: true })

      accept_confirm confirmation do
        find("form[action='#{path}']").click_button "Revoke token"
      end
      assert_current_path index_path
      tools_status("nosia.settings_tools.token_removed")
      assert_no_selector "form[action='#{path}']", visible: :all
      refute ApiToken.exists?(token.id)
      assert ApiToken.authenticate_token(plain).nil?, "The revoked token must no longer authenticate"
      assert_no_selector "[data-token-reveal]", visible: :all
      refute page.html.include?(plain), "Revocation must not retain the revealed value in hidden HTML"
      assert ApiToken.exists?(@other_token.id)
      assert_equal before, ApiToken.count
      tools_record("token-workflow", { stage: "confirmed", token_removed: true, authentication_rejected: true,
        no_hidden_reveal: true, other_member_token_preserved: true, count_restored: true, correct_context: true })
    end
    assert_equal defaults, ApiToken.order(:id).pluck(:id, :account_id)
    assert_equal first_account, @user.reload.first_account.id
    assert_no_enqueued_jobs
    tools_record("token-workflow", { stage: "invariants", default_accounts_unchanged: true, no_jobs: true })
  end

  test "empty fallback and no-account pages remain truthful without read side effects" do
    Prompt.where(account: @user.accounts).delete_all
    @user.api_tokens.delete_all
    before = [ Prompt.count, Chat.count, ApiToken.count, AccountUser.count ]
    visit system_prompts_path
    assert_text I18n.t("nosia.settings_tools.prompts_empty", locale: :en)
    assert_no_selector "[data-prompt-row]", visible: :all
    tools_record("empty-workflows", { stage: "prompts", empty: true })

    visit account_system_prompt_path(@first)
    assert_selector "[data-prompt-state]", exact_text: I18n.t("nosia.settings_tools.prompt_builtin", locale: :en)
    assert_text I18n.t("nosia.settings_tools.prompt_fallback", locale: :en)
    assert_equal Prompts.system_prompt, page.evaluate_script("document.querySelector('[data-prompt-content]').textContent")
    visit edit_account_system_prompt_path(@first)
    assert_selector "[data-prompt-state]", exact_text: I18n.t("nosia.settings_tools.prompt_builtin", locale: :en)
    assert_equal Prompts.system_prompt, find("#prompt_content").value
    tools_record("empty-workflows", { stage: "fallback-read-edit", builtin_content: true, not_materialized: true })

    visit account_account_users_path(@empty)
    assert_selector "[data-members-only-owner]", exact_text: I18n.t("nosia.settings_tools.no_additional_members", locale: :en)
    assert_selector "[data-member-row]", count: 1
    assert_selector "[data-member-owner=true]"
    tools_record("empty-workflows", { stage: "members", owner_only: true })
    [ [ api_tokens_path, "tokens_empty" ], [ account_api_tokens_path(@second), "tokens_empty_account" ] ].each do |path, key|
      visit path
      assert_selector "[data-token-empty]", exact_text: I18n.t("nosia.settings_tools.#{key}", locale: :en)
      assert_no_selector "[data-token-row], [data-token-reveal]", visible: :all
      tools_record("empty-workflows", { stage: key, empty: true })
    end
    assert_equal before, [ Prompt.count, Chat.count, ApiToken.count, AccountUser.count ]

    @user.account_users.destroy_all
    after_removal = [ Prompt.count, Chat.count, ApiToken.count, AccountUser.count ]
    visit api_tokens_path
    assert_selector "[data-token-setup] a[href='#{new_account_path}']", exact_text: I18n.t("nosia.settings_tools.setup_account", locale: :en)
    assert_no_selector "#api_token_name", visible: :all
    assert_equal after_removal, [ Prompt.count, Chat.count, ApiToken.count, AccountUser.count ]
    assert_equal before.first(3), after_removal.first(3)
    assert ApiToken.exists?(@other_token.id)
    assert_no_enqueued_jobs
    tools_record("empty-workflows", { verified: true, reads_without_side_effects: true, no_default_materialization: true,
      no_jobs: true, no_account_setup: true, other_member_token_preserved: true })
  end

  test "submissions expose distinct busy text prevent duplicate submit and recover" do
    before = [ Prompt.count, User.count, AccountUser.count, ApiToken.count ]
    cases = [
      [ edit_system_prompt_path(@shared), system_prompt_path(@shared), "Save", "Saving…", "patch", "prompt_content", "Busy instructions" ],
      [ account_account_users_path(@second), account_account_users_path(@second), "Add member", "Adding member…", "post", "account_user_email", @outsider.email ],
      [ account_api_tokens_path(@second), account_api_tokens_path(@second), "Generate", "Generating…", "post", "api_token_name", "Busy token" ]
    ]
    cases.each do |edit_path, request_path, label, busy, method, field, value|
      visit edit_path
      fill_in field, with: value
      begin
        tools_hold_request(request_path, method)
        click_button label
        tools_assert_busy("input[type=submit][disabled][value='#{busy}']", label)
        page.execute_script("window.toolsRelease()")
        assert_current_path request_path
        if label == "Generate"
          assert_selector "[data-token-reveal]:focus"
        else
          tools_status(label == "Save" ? "nosia.prompts.updated" : "nosia.accounts.user_added")
        end
        tools_assert_recovered
        tools_record("busy-workflow", { stage: "completed", action: label, correct_context: true,
          reveal_focused: label == "Generate", status_present: label != "Generate", recovered: true })
      ensure
        tools_release_request
      end
    end
    assert_equal "Busy instructions", @shared.reload.content
    assert_equal [ before[0], before[1], before[2] + 1, before[3] + 1 ], [ Prompt.count, User.count, AccountUser.count, ApiToken.count ]
    token = @user.api_tokens.find_by!(name: "Busy token", account: @second)
    membership = @second.account_users.find_by!(user: @outsider)

    visit account_api_tokens_path(@second)
    tools_busy_removal(account_api_token_path(@second, token), "Revoke token", "Revoking…",
      I18n.t("nosia.settings_tools.revoke_confirm", locale: :en, name: token.name, account: @second.name), "nosia.settings_tools.token_removed")
    refute ApiToken.exists?(token.id)
    assert ApiToken.exists?(@other_token.id)

    visit account_account_users_path(@second)
    tools_busy_removal(account_account_user_path(@second, membership), "Remove member", "Removing member…",
      I18n.t("nosia.settings_tools.member_confirm", locale: :en, email: @outsider.email, account: @second.name), "nosia.accounts.user_removed")
    refute AccountUser.exists?(membership.id)
    assert User.exists?(@outsider.id)
    assert AccountUser.exists?(experience(:account_users, :overview_outsider_foreign).id)
    assert_equal before, [ Prompt.count, User.count, AccountUser.count, ApiToken.count ]
    assert_equal @first, @user.reload.first_account
    assert_no_enqueued_jobs
    tools_record("busy-workflow", { stage: "invariants", counts_restored: true, other_member_token_preserved: true,
      foreign_membership_preserved: true, default_unchanged: true, no_jobs: true })
  end

  private
    def tools_status(key)
      assert_selector "[data-settings-tool] [role=status]", exact_text: I18n.t(key, locale: :en)
    end

    def tools_error_field(field, phase)
      tools_tab_to("[data-error-field='#{field}']")
      page.send_keys(:enter)
      assert_selector "##{field}:focus"
      tools_record("error-focus", { phase: phase, native_tab_enter: true, focus: tools_probe("focus") })
      tools_contrast(phase)
    end

    def tools_hold_request(path, method)
      page.execute_script(<<~JS, path, method)
        const path = arguments[0], method = arguments[1], original = window.fetch.bind(window);
        window.toolsHeldCount = 0;
        window.fetch = (...args) => {
          const url = new URL(args[0].url || args[0], location.href), options = args[1] || {}, body = options.body;
          const verb = (body?.get?.('_method') || options.method || 'get').toLowerCase();
          if (url.pathname === path && verb === method) {
            window.toolsHeldCount++;
            return new Promise(resolve => window.toolsRelease = () => {
              window.fetch = original;
              delete window.toolsRelease;
              resolve(original(...args));
            });
          }
          return original(...args);
        };
      JS
    end

    def tools_assert_busy(selector, label)
      control = find(selector)
      assert control.disabled?
      assert_equal 1, page.evaluate_script("window.toolsHeldCount")
      # A real pointer click on a native disabled control must not submit again.
      control.click
      tools_wait
      assert_equal 1, page.evaluate_script("window.toolsHeldCount")
      tools_record("busy-workflow", { stage: "held", action: label, disabled: true, held_requests: 1,
        disabled_pointer_click: true, additional_held_requests: 0 })
      tools_contrast("busy-#{label}")
    end

    def tools_assert_recovered
      assert_no_selector "[data-settings-tool] input[type=submit][disabled], [data-settings-tool] button[disabled], [data-settings-tool] [aria-busy=true]", visible: :all
    end

    def tools_busy_removal(path, label, busy, confirmation, status)
      tools_hold_request(path, "delete")
      accept_confirm(confirmation) { find("form[action='#{path}']").click_button(label) }
      selector = "form[action='#{path}'] button[disabled]"
      assert_selector selector, exact_text: busy
      tools_assert_busy(selector, label)
      page.execute_script("window.toolsRelease()")
      assert_no_selector "form[action='#{path}']", visible: :all
      tools_status(status)
      tools_assert_recovered
      tools_record("busy-workflow", { stage: "confirmed-removal", action: label, row_removed: true, status_present: true, recovered: true })
    ensure
      tools_release_request
    end

    def tools_release_request
      page.execute_script("window.toolsRelease?.()")
      assert_no_selector "[data-settings-tool] [aria-busy=true]", visible: :all
    end

    def take_failed_screenshot
      return unless failed?

      # Redact only after behavioral assertions, before any framework artifact capture.
      page.execute_script(<<~JS)
        document.querySelectorAll('[data-token-reveal-target=source]').forEach(field => {
          field.value = '[REDACTED]';
          field.setAttribute('value', '[REDACTED]');
        });
        const status = document.querySelector('#created_api_token_status');
        if (status) status.textContent = '[REDACTED]';
      JS
      page.save_screenshot(File.join(@tools_evidence, "failure-redacted.png"))
      super
      FileUtils.cp(absolute_html_path, File.join(@tools_evidence, "failure-redacted.html")) if File.exist?(absolute_html_path)
    end
end
