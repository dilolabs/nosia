require "test_helper"

class Sources::TextsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(email: "st@example.com", password: "testpassword123")
    @account = Account.create!(name: "ST Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    post login_url, params: { email: @user.email, password: "testpassword123" }
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  # new builds a Text with nil data; Commonmarker.to_html rejects the
  # US-ASCII empty string that nil.to_s yields unless we force UTF-8.
  test "new renders without an encoding error for a blank text" do
    get new_sources_text_url

    assert_response :success
  end
end