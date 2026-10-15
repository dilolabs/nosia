require "test_helper"
require_relative "../support/chat_account_fixtures"

class ChatAccountFixtureTest < ActiveSupport::TestCase
  include ChatAccountFixtures

  test "fixture owner has two ordered accounts and a second-account chat" do
    assert_equal "picker@example.com", @user.email
    assert_equal @first, @user.first_account
    assert_equal [ @first.id, @second.id ].sort, @user.accounts.pluck(:id).sort
    assert_equal @second, chats(:picker_second_chat).account
    assert_empty users(:picker_no_account).accounts
  end
end
