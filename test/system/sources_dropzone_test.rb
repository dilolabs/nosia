require "application_system_test_case"

class SourcesDropzoneTest < ApplicationSystemTestCase
  def setup
    @user = User.create!(email: "dz@example.com", password: "testpassword123")
    @account = Account.create!(name: "DZ Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: "testpassword123"
    click_on "Sign in"
    assert_selector "select[name='chat[account_id]']"
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "the sources list exposes a dropzone drop target" do
    visit sources_path
    assert_selector "[data-controller~='dropzone'] [data-dropzone-target='input']", visible: :all
  end
end
