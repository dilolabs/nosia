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

  # One row replace + one replace per sidebar count badge
  # (all + 4 types + failed + pending = 7) = 8 broadcasts.
  EXPECTED_BROADCASTS = 8

  test "mark_indexed! broadcasts the row and every count badge" do
    text = @account.texts.create!(data: "# Hi")

    streams = capture_turbo_stream_broadcasts([ @account, "sources" ]) do
      text.mark_indexed!
    end

    assert_equal EXPECTED_BROADCASTS, streams.size
    assert streams.any? { |s| s["target"] == ActionView::RecordIdentifier.dom_id(text, :source_row) }
    assert streams.any? { |s| s["target"] == "source_count_all" }
  end

  test "mark_indexing_failed! also broadcasts (update_columns bypasses callbacks)" do
    text = @account.texts.create!(data: "# Hi")

    streams = capture_turbo_stream_broadcasts([ @account, "sources" ]) do
      text.mark_indexing_failed!
    end

    assert_equal EXPECTED_BROADCASTS, streams.size
    assert streams.any? { |s| s["target"] == "source_count_status-failed" }
  end

  test "creating a source prepends its row to the 'all' list stream" do
    streams = capture_turbo_stream_broadcasts([ @account, "sources", "list:all:all" ]) do
      @account.texts.create!(data: "freshly added")
    end

    assert streams.any? { |s| s["action"] == "prepend" && s["target"] == "sources_list" },
      "a new source should be prepended live to the All view"
  end

  test "creating a source prepends its row to the type-scoped list stream" do
    streams = capture_turbo_stream_broadcasts([ @account, "sources", "list:text:all" ]) do
      @account.texts.create!(data: "freshly added")
    end

    assert streams.any? { |s| s["action"] == "prepend" && s["target"] == "sources_list" },
      "a new source should be prepended live to its own type view"
  end
end
