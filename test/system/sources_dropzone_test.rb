require "application_system_test_case"

class SourcesDropzoneTest < ApplicationSystemTestCase
  def setup
    @user = User.create!(email: "dz@example.com", password: "testpassword123")
    @account = Account.create!(name: "DZ Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    visit login_url
    fill_in "Email", with: @user.email
    fill_in "Password", with: "testpassword123"
    click_on "Sign in"
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "the sources list exposes a dropzone drop target" do
    visit sources_path
    assert_selector "[data-controller~='dropzone'] [data-dropzone-target='input']", visible: :all
  end
end
