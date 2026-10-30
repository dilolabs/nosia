require "test_helper"
require_relative "../support/chat_workspace_fixtures"

class OrbiteShellTest < ActionDispatch::IntegrationTest
  include ChatWorkspaceFixtures
  include ActionView::RecordIdentifier

  setup { sign_in_picker_user }

  test "history keeps personal roots current item and existing delete confirmation" do
    get chat_path(@chat)
    assert_response :success
    assert_select "[data-history-chat='#{@chat.id}']", count: 1 do
      assert_select "a[href='#{chat_path(@chat)}'][aria-current=page]", count: 1
      assert_select "form[action='#{chat_path(@chat)}'] [name=_method][value=delete]", count: 1
      assert_select "[data-turbo-confirm]", count: 1 do |controls|
        assert_equal I18n.t("nosia.actions.confirm_delete"), controls.first["data-turbo-confirm"]
      end
    end
    [ workspace(:chats, :workspace_peer_chat), workspace(:chats, :workspace_child_chat), chats(:picker_foreign_chat) ].each do |excluded|
      assert_select "[data-history-chat='#{excluded.id}']", count: 0
    end
    assert_select "##{dom_id(@chat, :token_totals)}", count: 1
  end

  test "native utility identities and logout method remain unique" do
    get chat_path(@chat)
    %w[theme-toggle theme-toggle-dark-icon theme-toggle-light-icon language_preference_locale dropdownUser dropdown].each do |id|
      assert_select "[id='#{id}']", count: 1
    end
    assert_select "form[action='#{language_preference_path}'] [name=_method][value=patch]", count: 1
    assert_select "a[href='#{logout_path}'][data-turbo-method=delete]", count: 1
    assert_select "a[href='#{profile_path}']", minimum: 1
  end
end
