require "application_system_test_case"
require "tmpdir"
require_relative "../support/settings_tool_fixtures"

class TokenRevealTest < ApplicationSystemTestCase
  include SettingsToolFixtures

  setup do
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: AccountExperienceFixtures::PASSWORD
    click_button "Sign in"
    assert_selector "[data-dashboard]"
  end

  test "copy waits for completion and retains button focus without announcing the token" do
    create_token
    assert_selector "[data-token-reveal]:focus"
    plain = find("#created_api_token").value
    page.execute_script(<<~JS)
      window.testClipboardWrites = [];
      Object.defineProperty(navigator, 'clipboard', {
        configurable: true,
        value: {
          writeText(value) {
            window.testClipboardWrites.push(value);
            return new Promise(resolve => window.finishTestCopy = resolve);
          }
        }
      });
    JS

    find("button[data-action='token-reveal#copy']").click

    assert_selector "button[data-action='token-reveal#copy'][aria-disabled='true']", exact_text: "Copying…"
    assert_selector "#created_api_token_status", exact_text: "", visible: :all
    refute find("#created_api_token_status", visible: :all).text(:all).include?(plain), "The live status must not disclose the token"
    find("button[data-action='token-reveal#copy']").click
    assert page.evaluate_script("window.testClipboardWrites").eql?([ plain ]), "Copy must write the exact field value only once while pending"

    page.execute_script("window.finishTestCopy()")

    assert_selector "#created_api_token_status", exact_text: "Copied."
    assert_selector "button[data-action='token-reveal#copy'][aria-disabled='false']:focus", exact_text: "Copy token"
    assert find("#created_api_token").value == plain, "Copy must preserve the exact field value"
    refute find("#created_api_token_status").text.include?(plain), "The live status must not disclose the token"
  end

  test "rejected and unavailable clipboard writes preserve readonly manual copying" do
    [ "{ writeText() { return Promise.reject(new Error('denied')); } }", "undefined" ].each do |clipboard|
      create_token
      plain = find("#created_api_token").value
      page.execute_script("Object.defineProperty(navigator, 'clipboard', { configurable: true, value: #{clipboard} })")
      click_button "Copy token"

      assert_selector "#created_api_token_status", exact_text: I18n.t("nosia.settings_tools.copy_failed")
      assert_no_text "Copied."
      field = find("#created_api_token[readonly]")
      assert field.value == plain, "A failed copy must preserve the exact field value"
      field.click
      field.send_keys([ :control, "a" ])
      assert_equal plain.length, page.evaluate_script("arguments[0].selectionEnd - arguments[0].selectionStart", field)
      refute find("#created_api_token_status").text.include?(plain), "The live status must not disclose the token"
    end
  end

  test "refresh and application navigation back never restore the one-time token" do
    create_token
    plain = find("#created_api_token").value

    page.refresh

    assert_no_selector "[data-token-reveal]", visible: :all
    refute page.html.include?(plain), "Refresh must not retain the one-time token in HTML"

    create_token
    second_plain = find("#created_api_token").value
    find(".n-workspace-header nav a[href='#{account_path(@second)}']").click
    assert_current_path account_path(@second)

    page.go_back

    assert_current_path account_api_tokens_path(@second)
    assert_no_selector "[data-token-reveal]", visible: :all
    refute page.html.include?(second_plain), "Back navigation must not restore the one-time token in HTML"
    refute page.evaluate_script(<<~JS, second_plain), "Browser storage must not contain the one-time token"
      [localStorage, sessionStorage].some(storage =>
        Object.entries(storage).some(([key, value]) => key.includes(arguments[0]) || value.includes(arguments[0]))
      )
    JS
  end

  test "application navigation ignores a pending copy's late completion" do
    create_token
    page.execute_script(<<~JS)
      window.testTokenPanel = document.querySelector('[data-token-reveal]');
      window.testTokenStatus = document.querySelector('#created_api_token_status');
      window.testTokenButton = document.querySelector('button[data-action="token-reveal#copy"]');
      Object.defineProperty(navigator, 'clipboard', {
        configurable: true,
        value: {
          writeText() {
            window.testCopyPromise = new Promise(resolve => window.finishTestCopy = resolve);
            return window.testCopyPromise;
          }
        }
      });
    JS
    click_button "Copy token"
    assert_selector "button[data-action='token-reveal#copy'][aria-disabled='true']", exact_text: "Copying…"

    find(".n-workspace-header nav a[href='#{account_path(@second)}']").click

    assert_current_path account_path(@second)
    refute page.evaluate_script("window.testTokenPanel.isConnected"), "Navigation must remove the one-time panel"
    page.driver.browser.execute_async_script(<<~JS)
      const done = arguments[0];
      window.finishTestCopy();
      window.testCopyPromise.then(() => queueMicrotask(done));
    JS
    assert_equal "", page.evaluate_script("window.testTokenStatus.textContent")
    assert_equal "true", page.evaluate_script("window.testTokenButton.getAttribute('aria-disabled')")
    assert_equal "Copying…", page.evaluate_script("window.testTokenButton.textContent")
    assert_no_selector "[data-token-reveal]", visible: :all
    assert_no_text "Copied."
  end

  %w[before after].each do |timing|
    %w[resolve reject].each do |outcome|
      test "same-instance reconnect ignores #{outcome} settling #{timing} reattachment" do
        create_token
        assert_selector "[data-token-reveal]:focus"
        plain = find("#created_api_token").value
        prepare_reconnect_copy
        click_button "Copy token"
        assert_selector "button[data-action='token-reveal#copy'][aria-disabled='true']", exact_text: "Copying…"

        page.driver.browser.execute_async_script(<<~JS)
          const done = arguments[0];
          window.testReconnect.element.remove();
          queueMicrotask(done);
        JS
        assert page.evaluate_script(<<~JS), "The real MutationObserver lifecycle must disconnect the controller"
          !window.testReconnect.element.isConnected &&
            window.Stimulus.getControllerForElementAndIdentifier(window.testReconnect.element, 'token-reveal') === null
        JS
        settle_reconnect_copy(0, outcome) if timing == "before"

        page.driver.browser.execute_async_script(<<~JS)
          const done = arguments[0], state = window.testReconnect;
          state.parent.insertBefore(state.element, state.nextSibling);
          queueMicrotask(done);
        JS
        assert page.evaluate_script(<<~JS), "Reattachment must reconnect the same controller instance"
          window.Stimulus.getControllerForElementAndIdentifier(window.testReconnect.element, 'token-reveal') ===
            window.testReconnect.controller
        JS
        recovered_on_connect = page.evaluate_script(<<~JS)
          (() => {
            const state = window.testReconnect;
            return state.button.innerHTML === state.originalHTML &&
              state.button.textContent === state.originalLabel &&
              state.button.getAttribute('aria-disabled') === 'false' && state.status.textContent === '';
          })()
        JS
        settle_reconnect_copy(0, outcome) if timing == "after"

        assert page.evaluate_script("window.testReconnect.status.textContent === ''"), "A cancelled copy must not announce stale success or failure"
        assert recovered_on_connect, "Reconnect must immediately restore the exact original button HTML, label, enabled aria state, and empty status"
        assert page.evaluate_script("window.testReconnect.button.innerHTML === window.testReconnect.originalHTML"), "A cancelled completion must preserve the original button HTML"
        assert_selector "button[data-action='token-reveal#copy'][aria-disabled='false']", exact_text: "Copy token"
        assert_no_selector "button[data-action='token-reveal#copy'][disabled]"
        field = find("#created_api_token[readonly]")
        assert field.value == plain, "Reconnect must preserve the exact readonly token value"
        field.click
        field.send_keys([ :control, "a" ])
        assert_equal plain.length, page.evaluate_script("arguments[0].selectionEnd - arguments[0].selectionStart", field)

        click_button "Copy token"
        assert_selector "button[data-action='token-reveal#copy'][aria-disabled='true']:focus", exact_text: "Copying…"
        assert page.evaluate_script("window.testReconnect.writes").eql?([ plain, plain ]), "Only explicit copies must write the exact field value"
        settle_reconnect_copy(1, "resolve")

        assert_selector "#created_api_token_status", exact_text: "Copied."
        assert_selector "button[data-action='token-reveal#copy'][aria-disabled='false']:focus", exact_text: "Copy token"
        assert page.evaluate_script("window.testReconnect.button.innerHTML === window.testReconnect.originalHTML"), "The new copy must restore the exact original button HTML"
        assert find("#created_api_token[readonly]").value == plain, "The new copy must preserve the exact readonly token value"
        refute find("#created_api_token_status").text.include?(plain), "The live status must not disclose the token"
      end
    end
  end

  %w[global account].product(%w[before while], %w[resolve reject]).each do |route, timing, outcome|
    test "consecutive results isolate #{route} #{outcome} before or while copying #{timing}" do
      @consecutive_case = "#{route}-#{timing}-#{outcome}"
      path = route == "global" ? api_tokens_path : account_api_tokens_path(@second)
      visit path
      prepare_consecutive_copies(path)
      generate_consecutive_token("Consecutive A", route)
      assert_current_path path
      assert_selector "[data-token-reveal]:focus"
      first = @user.api_tokens.find_by!(name: "Consecutive A", account: @second)
      first_plain = find("#created_api_token[readonly]").value
      assert ApiToken.authenticate_token(first_plain) == first, "The first result must authenticate its authorized token"
      page.execute_script(<<~JS)
        const state = window.testConsecutive;
        state.firstRoot = document.querySelector('[data-token-reveal]');
        state.firstController = window.Stimulus.getControllerForElementAndIdentifier(state.firstRoot, 'token-reveal');
        state.firstGeneration = state.firstController.generation;
        state.morphs = 0;
      JS
      find("button[data-action='token-reveal#copy']").send_keys(:enter)
      assert_selector "button[data-action='token-reveal#copy'][aria-disabled='true']:focus", exact_text: "Copying…"

      # Submit the still-present form: no visit or navigation between these results.
      generate_consecutive_token("Consecutive B", route)
      assert_current_path path
      second = @user.api_tokens.find_by!(name: "Consecutive B", account: @second)
      assert_equal [ @user.id, @second.id ], [ second.user_id, second.account_id ]
      refute_equal first.id, second.id
      second_plain = find("#created_api_token[readonly]").value
      assert second_plain != first_plain, "Each generation must reveal a distinct token"
      assert ApiToken.authenticate_token(second_plain) == second, "The second result must authenticate exactly its authorized token"
      refute page.html.include?(first_plain), "The old plaintext must not remain anywhere in the current DOM"
      diagnostics = page.evaluate_script(<<~JS)
        (() => {
          const state = window.testConsecutive, root = document.querySelector('[data-token-reveal]');
          state.secondOriginalHTML = root.querySelector('button').innerHTML;
          return {
            morphed: state.morphs > 0, sameRoot: root === state.firstRoot,
            sameController: window.Stimulus.getControllerForElementAndIdentifier(root, 'token-reveal') === state.firstController,
            oldRootConnected: state.firstRoot.isConnected,
            oldControllerConnected: window.Stimulus.getControllerForElementAndIdentifier(state.firstRoot, 'token-reveal') === state.firstController,
            oldGenerationUnchanged: state.firstController.generation === state.firstGeneration,
            resultFocused: document.activeElement === root,
            samePathRedirects: state.submissions.length === 2 && state.submissions.every(submission => submission)
          };
        })()
      JS
      settle_consecutive_copy(0, outcome) if timing == "before"
      diagnostics["staleStatusIgnored"] = page.evaluate_script("document.querySelector('#created_api_token_status').textContent === ''")

      click_button "Copy token"
      assert_selector "button[data-action='token-reveal#copy'][aria-disabled='true']:focus", exact_text: "Copying…"
      find("button[data-action='token-reveal#copy']").click
      assert page.evaluate_script("window.testConsecutive.writes").eql?([ first_plain, second_plain ]), "Pending duplicates must not write either token again"
      settle_consecutive_copy(0, outcome) if timing == "while"
      diagnostics["staleStatusIgnored"] &&= page.evaluate_script("document.querySelector('#created_api_token_status').textContent === ''")
      diagnostics["secondStillPending"] = page.evaluate_script(<<~JS)
        (() => {
          const button = document.querySelector('button[data-action="token-reveal#copy"]');
          return button.getAttribute('aria-disabled') === 'true' && button.textContent === 'Copying…';
        })()
      JS
      find("button[data-action='token-reveal#copy']").click
      diagnostics["duplicateProtected"] = page.evaluate_script("window.testConsecutive.writes").eql?([ first_plain, second_plain ])
      puts "Consecutive result lifecycle #{@consecutive_case}: #{diagnostics.to_json}"
      assert diagnostics.values_at("morphed", "samePathRedirects", "resultFocused", "staleStatusIgnored", "secondStillPending", "duplicateProtected").all?,
        "Each new result must focus and isolate pending copy feedback: #{diagnostics}"

      settle_consecutive_copy(1, "resolve")
      assert_selector "#created_api_token_status", exact_text: "Copied."
      assert_selector "button[data-action='token-reveal#copy'][aria-disabled='false']:focus", exact_text: "Copy token"
      assert page.evaluate_script("document.querySelector('button[data-action=\"token-reveal#copy\"]').innerHTML === window.testConsecutive.secondOriginalHTML"), "Completion must restore the second result's exact button HTML"
      assert find("#created_api_token[readonly]").value == second_plain, "Completion must preserve the exact second token"

      click_button "Copy token"
      settle_consecutive_copy(2, "reject")
      assert_selector "#created_api_token_status", exact_text: I18n.t("nosia.settings_tools.copy_failed")
      assert_no_text "Copied."
      field = find("#created_api_token[readonly]")
      assert field.value == second_plain, "Manual fallback must preserve the exact second token"
      field.click
      field.send_keys([ :control, "a" ])
      assert_equal second_plain.length, page.evaluate_script("arguments[0].selectionEnd - arguments[0].selectionStart", field)
      assert page.evaluate_script("window.testConsecutive.writes").eql?([ first_plain, second_plain, second_plain ]), "Only explicit copies may write the current result"
      refute [ first_plain, second_plain ].any? { |plain| find("#created_api_token_status").text.include?(plain) }, "The live status must not disclose either token"
      assert_equal @first, @user.reload.first_account
    end
  end

  private
    def create_token
      visit account_api_tokens_path(@second)
      fill_in "api_token_name", with: "Browser deploy"
      click_button "Generate"
      assert_selector "[data-token-reveal]"
    end

    def prepare_reconnect_copy
      page.execute_script(<<~JS)
        const element = document.querySelector('[data-token-reveal]');
        const button = element.querySelector('button[data-action="token-reveal#copy"]');
        window.testReconnect = {
          element, button, parent: element.parentNode, nextSibling: element.nextSibling,
          controller: window.Stimulus.getControllerForElementAndIdentifier(element, 'token-reveal'),
          status: element.querySelector('#created_api_token_status'),
          originalHTML: button.innerHTML, originalLabel: button.textContent, writes: [], pending: []
        };
        Object.defineProperty(navigator, 'clipboard', {
          configurable: true,
          value: {
            writeText(value) {
              const state = window.testReconnect, pending = {};
              state.writes.push(value);
              pending.promise = new Promise((resolve, reject) => Object.assign(pending, { resolve, reject }));
              state.pending.push(pending);
              return pending.promise;
            }
          }
        });
      JS
    end

    def settle_reconnect_copy(index, outcome)
      page.driver.browser.execute_async_script(<<~JS, index, outcome)
        const pending = window.testReconnect.pending[arguments[0]], outcome = arguments[1], done = arguments[2];
        pending.promise.then(() => queueMicrotask(done), () => queueMicrotask(done));
        if (outcome === 'resolve') pending.resolve();
        else pending.reject(new Error('denied'));
      JS
    end

    def prepare_consecutive_copies(path)
      page.execute_script(<<~JS, path)
        const path = arguments[0];
        window.testConsecutive = { writes: [], pending: [], submissions: [], morphs: 0 };
        document.addEventListener('turbo:morph', () => window.testConsecutive.morphs++);
        document.addEventListener('turbo:submit-end', event => {
          const response = event.detail.fetchResponse;
          window.testConsecutive.submissions.push(event.detail.success && response.redirected && response.location.pathname === path);
        });
        Object.defineProperty(navigator, 'clipboard', {
          configurable: true,
          value: {
            writeText(value) {
              const state = window.testConsecutive, pending = {};
              state.writes.push(value);
              pending.promise = new Promise((resolve, reject) => Object.assign(pending, { resolve, reject }));
              state.pending.push(pending);
              return pending.promise;
            }
          }
        });
      JS
    end

    def generate_consecutive_token(name, route)
      fill_in "api_token_name", with: name
      select @second.name, from: "api_token_account_id" if route == "global"
      click_button "Generate"
      assert_selector "[data-token-reveal] > p:first-of-type", exact_text: "#{name} · #{I18n.t('nosia.settings_tools.default_account')}: #{@second.name}"
    end

    def settle_consecutive_copy(index, outcome)
      page.driver.browser.execute_async_script(<<~JS, index, outcome)
        const pending = window.testConsecutive.pending[arguments[0]], outcome = arguments[1], done = arguments[2];
        pending.promise.then(() => queueMicrotask(done), () => queueMicrotask(done));
        if (outcome === 'resolve') pending.resolve();
        else pending.reject(new Error('denied'));
      JS
    end

    def take_failed_screenshot
      # Redact both the displayed value and serialized HTML before failure artifacts.
      page.execute_script(<<~JS)
        document.querySelectorAll('[data-token-reveal-target=source]').forEach(field => {
          field.value = '[REDACTED]';
          field.setAttribute('value', '[REDACTED]');
        });
        const status = document.querySelector('#created_api_token_status');
        if (status) status.textContent = '[REDACTED]';
      JS
      if @consecutive_case && failed?
        directory = Dir.mktmpdir("failure-#{@consecutive_case}-", ENV.fetch("EVIDENCE", Rails.root.join("tmp/screenshots").to_s))
        page.save_screenshot(File.join(directory, "redacted.png"))
      end
      super
    end
end
