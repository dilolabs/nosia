require "application_system_test_case"
require_relative "../support/chat_workspace_fixtures"
require_relative "../support/orbite_browser_checks"

class ChatDeletionSystemTest < ApplicationSystemTestCase
  include ChatWorkspaceFixtures
  include OrbiteBrowserChecks

  setup do
    @original_size = page.current_window.size
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    page.current_window.resize_to(*@original_size)
  end

  test "cancellation preserves the draft and restores keyboard focus in both themes and languages" do
    %w[en fr].product([ [ 375, 812 ], [ 1400, 1000 ] ], [ false, true ]).each do |locale, (width, height), dark|
      open_chat(locale, width: width, height: height, dark: dark)
      find("lexxy-editor .lexxy-editor__content").send_keys("Keep this conversation draft")
      orbite_read_start
      orbite_tab_to("#chat-delete-trigger")
      page.driver.browser.action.send_keys(:enter).perform

      assert_selector "#chat-delete-dialog:modal"
      assert_selector "#chat-delete-dialog [data-chat-dialog-initial-focus]:focus"
      assert_selector "#chat-delete-title", text: I18n.t("nosia.chat_workspace.delete_title", locale: locale)
      assert_selector ".n-chat-delete-name", text: workspace(:messages, :workspace_question).content
      assert_dialog_bounds
      orbite_record("chat-deletion-#{locale}-#{width}-#{dark}", {}, screenshot: true)

      within "#chat-delete-dialog" do
        click_on I18n.t("nosia.chat_workspace.cancel", locale: locale)
      end
      assert_no_selector "#chat-delete-dialog[open]", visible: :all
      assert_selector "#chat-delete-trigger:focus"

      page.driver.browser.action.send_keys(:enter).perform
      assert_selector "#chat-delete-dialog:modal"
      page.driver.browser.action.send_keys(:escape).perform
      assert_no_selector "#chat-delete-dialog[open]", visible: :all
      assert_selector "#chat-delete-trigger:focus"
      assert_selector "lexxy-editor .lexxy-editor__content", text: "Keep this conversation draft"
      assert Chat.exists?(@chat.id)
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  test "long titles fit a short landscape viewport with reduced motion" do
    workspace(:messages, :workspace_question).update_columns(content: "ConversationSansEspace" * 20)
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    open_chat("fr", width: 812, height: 375, dark: true)
    orbite_read_start
    find("#chat-delete-trigger").click

    assert_selector "#chat-delete-dialog:modal"
    assert_selector "#chat-delete-dialog [data-chat-dialog-initial-focus]:focus"
    assert_dialog_bounds
    orbite_assert_reachable("#chat-delete-dialog [data-chat-dialog-initial-focus]")
    assert page.evaluate_script("getComputedStyle(document.querySelector('#chat-delete-trigger')).transitionDuration.split(',').every(value => parseFloat(value) === 0)")
    orbite_record("chat-deletion-long-title-landscape", {}, screenshot: true)
  end

  %w[en fr].each do |locale|
    test "confirmed deletion returns home and removes the conversation in #{locale}" do
      open_chat(locale, width: locale == "fr" ? 375 : 1400, height: 900, dark: locale == "fr")
      message_ids = @chat.messages.ids
      orbite_read_start
      find("#chat-delete-trigger").click
      assert_selector "#chat-delete-dialog:modal"

      within "#chat-delete-dialog" do
        click_on I18n.t("nosia.nav.delete_chat", locale: locale)
      end

      assert_selector "[data-dashboard]"
      refute Chat.exists?(@chat.id)
      assert_empty Message.where(id: message_ids)
      assert_no_selector "a[href='#{chat_path(@chat)}']"
      assert_no_selector "#chat-delete-dialog", visible: :all
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  private
    def open_chat(locale, width:, height:, dark:)
      orbite_viewport(width, height)
      orbite_select_language(locale.upcase)
      visit chat_path(@chat)
      assert_selector "lexxy-editor[connected]"
      orbite_theme(dark)
      find("#workspace-navigation-close").click if page.has_selector?("#chat-history[open]", wait: 0)
    end

    def assert_dialog_bounds
      geometry = page.evaluate_script(<<~JS)
        (() => {
          const dialog = document.querySelector('#chat-delete-dialog'), trigger = document.querySelector('#chat-delete-trigger')
          return { dialog: dialog.getBoundingClientRect().toJSON(), trigger: trigger.getBoundingClientRect().toJSON(),
            overflow: dialog.scrollWidth > dialog.clientWidth, viewport: [innerWidth, innerHeight] }
        })()
      JS
      assert_operator geometry.fetch("dialog").fetch("left"), :>=, 0
      assert_operator geometry.fetch("dialog").fetch("right"), :<=, geometry.fetch("viewport").first
      assert_operator geometry.fetch("dialog").fetch("top"), :>=, 0
      assert_operator geometry.fetch("dialog").fetch("bottom"), :<=, geometry.fetch("viewport").last
      refute geometry.fetch("overflow")
      %w[width height].each { |axis| assert_operator geometry.fetch("trigger").fetch(axis), :>=, 44 }
    end
end
