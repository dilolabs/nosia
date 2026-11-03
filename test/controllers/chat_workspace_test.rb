require "test_helper"
require_relative "../support/chat_workspace_fixtures"

class ChatWorkspaceTest < ActionDispatch::IntegrationTest
  include ChatWorkspaceFixtures
  include ActionView::RecordIdentifier

  setup { sign_in_picker_user }

  test "new chat has a focused shell with initially closed history" do
    get new_chat_url

    assert_workspace_shell
    assert_select "#new-chat-workspace.n-chat-workspace--new", count: 1
    assert_select ".n-chat-start h1", text: "What would you like to explore?"
    assert_select ".n-chat-header .n-chat-toolbar, .n-chat-header .n-workspace-actions", count: 0
  end

  test "saved chat has a focused shell with initially closed history" do
    get chat_url(@chat)

    assert_workspace_shell
    assert_select "#chat-workspace-#{@chat.id}.n-chat-workspace--saved", count: 1
    assert_select ".n-chat-header h1", text: "What are the key findings in this report?"
    assert_select "section#chat-usage-details > h2#chat-usage-summary", text: "Usage details", count: 1
    assert_select "#chat-usage-details summary, .n-header-details", count: 0
  end

  test "history includes only personal root chats in accessible accounts" do
    [ new_chat_url, chat_url(@chat) ].each do |url|
      get url

      assert_response :success
      assert_select "#chat-history [data-history-chat='#{@chat.id}']", count: 1
      assert_select "#chat-history [data-history-chat='#{workspace(:chats, :workspace_first_chat).id}']", count: 1
      [ workspace(:chats, :workspace_peer_chat), workspace(:chats, :workspace_child_chat), chats(:picker_foreign_chat) ].each do |excluded|
        assert_select "[data-history-chat='#{excluded.id}']", count: 0
      end
    end
  end

  test "revoked membership removes history and saved chat access" do
    @user.account_users.find_by!(account: @second).destroy!

    get new_chat_url

    assert_response :success
    assert_select "#chat-history [data-history-chat='#{@chat.id}']", count: 0
    assert_select "#chat-history [data-history-chat='#{workspace(:chats, :workspace_first_chat).id}']", count: 1

    get chat_url(@chat)

    assert_response :not_found
  end

  test "saved title is plain text and bounded without truncating the transcript" do
    question = workspace(:messages, :workspace_question)
    content = "<b>#{'A' * 240}</b>"
    question.update_columns(content: content)

    get chat_url(@chat)

    assert_response :success
    assert_select ".n-chat-header h1", text: "#{'A' * 119}…" do |headings|
      assert_equal 120, headings.first.text.length
      assert_select "b", count: 0
    end
    assert_select "##{dom_id(question, :messages)}", text: "A" * 240
    assert_select "[data-history-chat='#{@chat.id}'] a[aria-current=page] > .n-chat-history-title", text: "#{'A' * 119}…", count: 1
    assert_equal content, question.reload.content
  end

  test "authorized child chat keeps its own title without joining root history" do
    child = workspace(:chats, :workspace_child_chat)
    workspace(:messages, :workspace_first_question).update_columns(chat_id: child.id)

    get chat_url(child)

    assert_response :success
    assert_select ".n-chat-header h1", text: "First account question"
    assert_select "[data-history-chat='#{child.id}']", count: 0
  end

  test "saved shell preserves account and unique streaming and composer targets" do
    get chat_url(@chat), params: { account_id: @first.id }

    assert_response :success
    assert_select "[data-chat-account-readonly]", text: /#{Regexp.escape(@second.name)}/, count: 1
    assert_select "select[name='chat[account_id]']", count: 0
    assert_select ".n-chat-header .n-workspace-help", text: @second.name
    assert_select "##{dom_id(@chat)}_messages", count: 1
    assert_select "##{dom_id(@chat, :messages)}", count: 1
    assert_select "##{dom_id(@chat, :token_totals)}", count: 1
    assert_select "##{dom_id(@chat, :messages)} ##{dom_id(@chat, :token_totals)}", count: 0
    assert_select "turbo-frame[id='#{dom_id(@chat)}_message_form']", count: 1
    assert_select "turbo-cable-stream-source", minimum: 2
  end

  test "French no-account shell provides setup and empty history without a composer" do
    @user.account_users.destroy_all

    get new_chat_url, headers: { "Accept-Language" => "fr" }

    assert_response :success
    assert_select "html[lang=fr]", count: 1
    assert_select "[data-chat-no-account][role=status]", count: 1
    assert_select "a[href='#{accounts_path}']", text: "Configurer un compte", count: 1
    assert_select ".n-chat-composer", count: 0
    assert_select "#chat-history[data-history-empty]", count: 1
    assert_select ".n-chat-header a, .n-chat-header button, [data-orbite-composer-navigation]", count: 0
    assert_select "#workspace-mobile-trigger[aria-controls=chat-history]", text: I18n.t("nosia.orbite.navigation", locale: :fr), count: 1
  end

  private
    def assert_workspace_shell
      assert_response :success
      assert_select ".n-chat-workspace h1", count: 1
      assert_select "main.n-chat-main", count: 1
      assert_select ".n-chat-header #workspace-history-trigger, .n-chat-header [aria-controls=chat-history], .n-chat-header a[href='#{user_root_path}']", count: 0
      assert_select "#workspace-history-rail-trigger[aria-controls=chat-history], [data-orbite-composer-navigation][aria-controls=chat-history]", count: 2
      assert_select "#workspace-mobile-trigger", count: 0
      assert_select "dialog#chat-history:not([open])", count: 1
      assert_select "#accordion-right-actions, #drawer-right", count: 0
      assert_select ".n-chat-composer", count: 1
      assert_select "form form", count: 0
    end
end
