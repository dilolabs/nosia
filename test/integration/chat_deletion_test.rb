require "test_helper"
require_relative "../support/chat_workspace_fixtures"

class ChatDeletionTest < ActionDispatch::IntegrationTest
  include ChatWorkspaceFixtures

  setup { sign_in_picker_user }

  %i[en fr].each do |locale|
    test "saved chat offers an accessible localized deletion dialog in #{locale}" do
      get chat_path(@chat), headers: { "Accept-Language" => locale.to_s }

      assert_response :success
      assert_select ".n-chat-toolbar #chat-delete-trigger[type=button][aria-controls=chat-delete-dialog][aria-haspopup=dialog][data-action='chat-dialog#open']", count: 1 do |buttons|
        assert_equal I18n.t("nosia.nav.delete_chat", locale: locale), buttons.first["aria-label"]
        assert_select "svg[aria-hidden=true]", count: 1
      end
      assert_select "dialog#chat-delete-dialog:not([open])[aria-labelledby=chat-delete-title][aria-describedby=chat-delete-description]", count: 1 do
        assert_select "#chat-delete-title", text: I18n.t("nosia.chat_workspace.delete_title", locale: locale)
        assert_select ".n-chat-delete-name", text: workspace(:messages, :workspace_question).content
        assert_select "#chat-delete-description", text: I18n.t("nosia.chat_workspace.delete_description", locale: locale)
        assert_select "button[type=button][data-chat-dialog-initial-focus][data-action='chat-dialog#close']", text: I18n.t("nosia.chat_workspace.cancel", locale: locale)
        assert_select "form[action='#{chat_path(@chat)}'][method=post]", count: 1 do
          assert_select "input[name=_method][value=delete]", count: 1
          assert_select "button[type=submit][data-turbo-submits-with='#{I18n.t('nosia.chat_workspace.deleting', locale: locale)}']", text: I18n.t("nosia.nav.delete_chat", locale: locale)
        end
      end
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  test "new conversation has no deletion action" do
    get new_chat_path

    assert_response :success
    assert_select "#chat-delete-trigger, #chat-delete-dialog", count: 0
  end

  test "deletion removes the owned conversation and its messages with a safe redirect" do
    message_ids = @chat.messages.ids
    assert_not_empty message_ids

    delete chat_path(@chat), headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }

    assert_response :see_other
    assert_redirected_to root_path
    refute Chat.exists?(@chat.id)
    assert_empty Message.where(id: message_ids)
    follow_redirect!
    assert_response :success
    assert_select "a[href='#{chat_path(@chat)}']", count: 0
  end

  test "another user's conversation cannot be deleted even in a shared account" do
    [ workspace(:chats, :workspace_peer_chat), chats(:picker_foreign_chat) ].each do |chat|
      counts = [ Chat.count, Message.count ]

      delete chat_path(chat)

      assert_response :not_found
      assert_equal counts, [ Chat.count, Message.count ]
      assert Chat.exists?(chat.id)
    end
  end

  test "revoked membership prevents deletion of an owned conversation" do
    @user.account_users.find_by!(account: @second).destroy!

    assert_no_difference [ "Chat.count", "Message.count" ] do
      delete chat_path(@chat)
    end

    assert_response :not_found
    assert Chat.exists?(@chat.id)
  end
end
