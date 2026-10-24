require "test_helper"

module Accounts
  # Membership management is owner-only: any member could previously add or
  # remove anyone — including the account owner.
  class AccountUsersAuthorizationTest < ActionDispatch::IntegrationTest
    def setup
      @owner = User.create!(email: "auo@example.com", password: "testpassword123")
      @account = Account.create!(name: "AU Account", owner: @owner)
      AccountUser.create!(account: @account, user: @owner)

      @member = User.create!(email: "aum@example.com", password: "testpassword123")
      AccountUser.create!(account: @account, user: @member)

      @stranger = User.create!(email: "aus@example.com", password: "testpassword123")
    end

    test "owner can add and remove members" do
      sign_in_as(@owner)

      post account_account_users_path(@account), params: { account_user: { email: @stranger.email } }
      assert_redirected_to account_account_users_path(@account)
      assert @account.account_users.exists?(user: @stranger)

      membership = @account.account_users.find_by!(user: @stranger)
      delete account_account_user_path(@account, membership)
      assert_redirected_to account_account_users_path(@account)
      assert_not @account.account_users.exists?(user: @stranger)
    end

    test "member cannot add users" do
      sign_in_as(@member)

      assert_no_difference -> { @account.account_users.count } do
        post account_account_users_path(@account), params: { account_user: { email: @stranger.email } }
      end

      assert_response :forbidden
    end

    test "member cannot remove other members" do
      sign_in_as(@member)

      owner_membership = @account.account_users.find_by!(user: @owner)
      assert_no_difference -> { @account.account_users.count } do
        delete account_account_user_path(@account, owner_membership)
      end

      assert_response :forbidden
    end

    test "the owner cannot be removed" do
      sign_in_as(@owner)

      owner_membership = @account.account_users.find_by!(user: @owner)
      assert_no_difference -> { @account.account_users.count } do
        delete account_account_user_path(@account, owner_membership)
      end

      assert_redirected_to account_account_users_path(@account)
      assert_not flash[:alert].nil?
    end

    private

    def sign_in_as(user)
      delete logout_url if cookies[:session_id]
      post login_url, params: { email: user.email, password: "testpassword123" }
    end
  end
end
