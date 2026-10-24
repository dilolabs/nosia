require "test_helper"
require_relative "../support/account_experience_fixtures"

class DashboardRecentsTest < ActiveSupport::TestCase
  include AccountExperienceFixtures

  test "recents select only personal root chats in current memberships in stable activity order" do
    first = experience(:chats, :overview_first_chat)
    first.update_columns(updated_at: Time.utc(2026, 1, 10))
    expected = [ first ] + 4.times.map { |index| experience(:chats, "overview_second_chat_#{27 - index}") }
    rows = @user.recent_conversations.limit(5).to_a
    assert_equal expected.map(&:id), rows.map(&:id)
    assert rows.all? { |chat| chat.association(:account).loaded? }
    refute_includes rows, experience(:chats, :overview_member_chat)
    refute_includes rows, experience(:chats, :overview_child_chat)
    experience(:account_users, :overview_owner_second).destroy!
    assert_equal [ first.id ], @user.recent_conversations.limit(5).pluck(:id)
  end

  test "equal activity timestamps use descending IDs and no-account users have no recents" do
    first = experience(:chats, :overview_first_chat)
    second = experience(:chats, :overview_second_chat_27)
    [ first, second ].each { |chat| chat.update_columns(updated_at: Time.utc(2026, 2, 1)) }
    assert_equal [ first.id, second.id ].sort.reverse, @user.recent_conversations.limit(2).pluck(:id)
    assert_empty experience(:users, :overview_no_account).recent_conversations
  end
end
