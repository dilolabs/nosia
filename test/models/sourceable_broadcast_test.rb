require "test_helper"
require "turbo/broadcastable/test_helper"

class SourceableBroadcastTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  def setup
    @user = User.create!(email: "bc@example.com", password: "testpassword123")
    @account = Account.create!(name: "BC Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "mark_indexed! broadcasts a row replace and a counts replace" do
    text = @account.texts.create!(data: "# Hi")

    streams = capture_turbo_stream_broadcasts([ @account, "sources" ]) do
      text.mark_indexed!
    end

    assert_equal 2, streams.size
  end

  test "mark_indexing_failed! also broadcasts (update_columns bypasses callbacks)" do
    text = @account.texts.create!(data: "# Hi")

    streams = capture_turbo_stream_broadcasts([ @account, "sources" ]) do
      text.mark_indexing_failed!
    end

    assert_equal 2, streams.size
  end
end
