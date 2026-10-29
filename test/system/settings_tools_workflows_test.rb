require "application_system_test_case"
require_relative "../support/settings_tool_fixtures"
require_relative "../support/settings_tool_browser_checks"

# Exercises real recovery workflows and bounded generated-result interaction states.
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

  %w[global account].product(%w[light dark], [ [ 375, 812 ], [ 1440, 1000 ] ]).each do |route, theme, (width, height)|
    test "generated token result controls #{route} #{theme} #{width}x#{height}" do
      @tools_result_case = "#{route}-en-#{theme}-#{width}x#{height}"
      path = route == "global" ? api_tokens_path : account_api_tokens_path(@second)
      before = [ Prompt.count, Chat.count, ApiToken.count ]
      defaults = @user.api_tokens.order(:id).pluck(:id, :account_id)
      visit path
      tools_size(width, height)
      tools_theme(theme)
      fill_in "api_token_name", with: "Result measurement"
      select @second.name, from: "api_token_account_id" if route == "global"
      click_button "Generate"
      assert_current_path path
      assert_selector "[data-token-reveal]:focus"
      assert_selector "html[lang=en]", visible: :all
      assert_equal theme == "dark", page.evaluate_script("document.documentElement.classList.contains('dark')")
      token = @user.api_tokens.order(:created_at, :id).last
      plain = find("#created_api_token[readonly]").value
      assert ApiToken.authenticate_token(plain) == token, "The generated local result must authenticate exactly"
      assert_equal [ @user.id, @second.id ], [ token.user_id, token.account_id ]
      assert_selector "[data-token-reveal] > p:first-of-type", text: @second.name
      tools_record("result-cases", { case_key: @tools_result_case, stage: "generated", authorized_context: true,
        exact_authentication: true, reveal_focused: true })
      tools_result_measure("normal")
      tools_result_keyboard
      tools_result_hover
      find("#theme-toggle").hover
      tools_wait
      tools_result_feedback(plain)

      assert_equal [ before[0], before[1], before[2] + 1 ], [ Prompt.count, Chat.count, ApiToken.count ]
      assert_equal defaults, @user.api_tokens.where.not(id: token.id).order(:id).pluck(:id, :account_id)
      assert_equal @first, @user.reload.first_account
      assert_no_enqueued_jobs
      tools_record("result-cases", { case_key: @tools_result_case, stage: "complete", token_delta: 1,
        prompt_chat_counts_unchanged: true, defaults_unchanged: true, no_jobs: true, no_screenshots: true })
    ensure
      page.execute_script("window.toolsResultPending?.resolve()")
    end
  end

  private
    def tools_result_identify
      # Tag otherwise anonymous result samples; no styles, values or focus change.
      page.execute_script(<<~JS)
        const result = document.querySelector('[data-token-reveal]');
        result.querySelector('p:first-of-type').id = 'tools_result_context';
        result.querySelector('label[for=created_api_token]').id = 'tools_result_label';
        const copy = result.querySelector('button[data-action="token-reveal#copy"]');
        copy.id = 'tools_result_copy';
        copy.querySelector('svg').id = 'tools_result_icon';
      JS
    end

    def tools_result_measure(phase, feedback: false)
      tools_result_identify
      ids = %w[created_api_token_title tools_result_context created_api_token_help tools_result_label created_api_token tools_result_copy tools_result_icon]
      ids << "created_api_token_status" if feedback
      tools_layout
      layout = tools_probe("layout").fetch("rows").select { |row| ids.include?(row.fetch("id")) }
      # The shared text-layout probe intentionally omits text inputs and SVGs.
      # Supplement their actual outer bounds, allowing readonly input content scrolling.
      bounds = page.evaluate_script(<<~JS)
        (() => {
          const result = document.querySelector('[data-token-reveal]'), panel = result.getBoundingClientRect();
          const main = document.querySelector('main').getBoundingClientRect();
          return ['created_api_token', 'tools_result_icon'].map(id => {
            const element = document.getElementById(id), r = element.getBoundingClientRect();
            const parent = element.parentElement.getBoundingClientRect();
            return {id, tag: element.tagName, kind: 'outer-bounds', width: r.width, height: r.height,
              left: r.left, right: r.right, parentLeft: parent.left, parentRight: parent.right,
              fits: r.width > 0 && r.height > 0 && r.left >= Math.max(panel.left, main.left, parent.left) &&
                r.right <= Math.min(panel.right, main.right, parent.right, innerWidth)};
          });
        })()
      JS
      layout.concat(bounds)
      ids.each { |id| assert_equal 1, layout.count { |row| row.fetch("id") == id }, "Missing result layout sample: #{id}" }
      bounds.each { |row| assert row.fetch("fits"), row.to_json }

      tools_contrast("result-#{phase}")
      contrast = tools_probe("contrast").select { |row| ids.include?(row.fetch("id")) }
      ids.each do |id|
        text = contrast.select { |row| row.fetch("id") == id && row.fetch("property") == "color" }
        assert_equal 1, text.size, "Missing result contrast sample: #{id}"
        assert_equal id == "tools_result_icon" ? 3 : 4.5, text.first.fetch("minimum")
      end
      %w[created_api_token tools_result_copy].each do |id|
        borders = contrast.select { |row| row.fetch("id") == id && row.fetch("property") == "borderTopColor" }
        assert_equal [ false, true ], borders.map { |row| row.fetch("outside") }.sort_by { |outside| outside ? 1 : 0 }
        borders.each { |row| assert_equal 3, row.fetch("minimum") }
      end
      tools_record("result-measurements", { case_key: @tools_result_case, phase: phase, feedback_nonempty: feedback,
        layout: layout, contrast: contrast, required_ids: ids })
    end

    def tools_result_hover
      copy = find("#tools_result_copy[data-action='token-reveal#copy']")
      assert_selector "[data-token-reveal] button[data-action='token-reveal#copy']", count: 1
      page.execute_script("document.querySelectorAll('[data-tools-hover]').forEach(e=>e.removeAttribute('data-tools-hover'));arguments[0].setAttribute('data-tools-hover','');", copy)
      find("main").scroll_to(copy, align: :center)
      find("#theme-toggle").hover
      tools_wait
      before = tools_probe("hover")
      refute before.fetch("hovered"), before.to_json
      copy.hover
      tools_wait
      after = tools_probe("hover")
      tools_record("result-copy-hover", { case_key: @tools_result_case, selector: "button[data-action='token-reveal#copy']", before: before, after: after })
      assert_equal "tools_result_copy", before.fetch("id")
      assert_equal "tools_result_copy", after.fetch("id")
      assert before.fetch("capable"), before.to_json
      assert after.fetch("capable"), after.to_json
      assert after.fetch("hovered"), after.to_json
      assert_equal before.fetch("bounds"), after.fetch("bounds"), after.to_json
      refute_equal before.fetch("backgroundCSS"), after.fetch("backgroundCSS"), after.to_json
      refute_equal before.fetch("rgba"), after.fetch("rgba"), after.to_json
      tools_result_measure("copy-hover")
    end

    def tools_result_keyboard
      tools_probe("walk")
      find("#theme-toggle").hover
      tools_tab_to("#created_api_token[readonly]")
      tools_result_focus("#created_api_token", "forward-field")
      page.send_keys(:tab)
      tools_wait
      tools_result_focus("#tools_result_copy", "forward-copy")
      page.send_keys(:tab)
      page.send_keys([ :shift, :tab ])
      tools_wait
      tools_result_focus("#tools_result_copy", "reverse-copy")
      page.send_keys([ :shift, :tab ])
      tools_wait
      tools_result_focus("#created_api_token", "reverse-field")
    end

    def tools_result_focus(selector, direction)
      assert_selector "#{selector}:focus"
      tools_assert_keyboard(Integer(find(selector)["data-tools-walk"]), "result-#{direction}")
      tools_record("result-keyboard", { case_key: @tools_result_case, selector: selector, direction: direction, sample: tools_probe("focus") })
      tools_result_measure("keyboard-#{direction}")
    end

    def tools_result_feedback(plain)
      %w[copied rejected unavailable].each do |outcome|
        page.execute_script(<<~JS, outcome)
          window.toolsResultWrites = [];
          Object.defineProperty(navigator, 'clipboard', {configurable: true, value: arguments[0] === 'unavailable' ? undefined : {
            writeText(value) {
              window.toolsResultWrites.push(value);
              return new Promise((resolve, reject) => window.toolsResultPending = {resolve, reject});
            }
          }});
        JS
        page.send_keys(:tab)
        assert_selector "#tools_result_copy:focus"
        page.send_keys(:enter)
        unless outcome == "unavailable"
          assert_selector "#tools_result_copy[aria-disabled=true]:focus", exact_text: I18n.t("nosia.settings_tools.copying", locale: :en)
          assert_selector "#created_api_token_status", exact_text: "", visible: :all
          assert page.evaluate_script("window.toolsResultWrites").eql?([ plain ]), "Only the exact revealed value must be copied"
          tools_record("result-feedback", { case_key: @tools_result_case, outcome: outcome, stage: "pending",
            exact_write: true, status_empty: true, copy_focused: true })
          page.execute_script(outcome == "copied" ? "window.toolsResultPending.resolve()" : "window.toolsResultPending.reject(new Error('denied'))")
        end
        key = outcome == "copied" ? "copied" : "copy_failed"
        assert_selector "#created_api_token_status", exact_text: I18n.t("nosia.settings_tools.#{key}", locale: :en)
        assert_selector "#tools_result_copy[aria-disabled=false]:focus", exact_text: I18n.t("nosia.settings_tools.copy", locale: :en)
        assert find("#created_api_token[readonly]").value == plain, "Copy feedback must preserve the exact readonly value"
        refute find("#created_api_token_status").text.include?(plain), "Live feedback must not announce the token"
        tools_result_measure(outcome, feedback: true)
        # Native Shift+Tab and Select All retain a manual fallback without an OS clipboard claim.
        page.send_keys([ :shift, :tab ])
        tools_wait
        assert_selector "#created_api_token[readonly]:focus"
        page.send_keys([ :control, "a" ])
        assert_equal plain.length, page.evaluate_script("((e)=>e.selectionEnd-e.selectionStart)(document.querySelector('#created_api_token'))")
        tools_assert_keyboard(Integer(find("#created_api_token")["data-tools-walk"]), "result-manual-#{outcome}")
        tools_result_measure("selected-#{outcome}", feedback: true)
        tools_record("result-feedback", { case_key: @tools_result_case, outcome: outcome, stage: "complete",
          copy_focus_retained: true, readonly_exact: true, no_secret_announcement: true, native_manual_selection: true })
      end
    end

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
