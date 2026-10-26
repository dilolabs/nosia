require "test_helper"
require_relative "../support/account_experience_fixtures"

class AccountsWorkspaceShellTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures

  setup { sign_in_overview }

  test "directory has one localized trail heading and primary creation action" do
    %i[en fr].each do |locale|
      get accounts_path, headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      assert_select "head title", count: 1 do |titles|
        assert_equal I18n.t("nosia.nav.accounts", locale: locale), titles.first.text
      end
      assert_select "main h1", text: I18n.t("nosia.nav.accounts", locale: locale), count: 1
      assert_select "main nav[aria-label='#{I18n.t('nosia.account_experience.breadcrumb', locale: locale)}']", count: 1
      assert_select "nav[aria-label='#{I18n.t('nosia.account_experience.breadcrumb', locale: locale)}']" do
        assert_select "a[href='#{user_root_path}']", text: I18n.t("nosia.nav.home", locale: locale)
        assert_select "[aria-current='page']", text: I18n.t("nosia.nav.accounts", locale: locale), count: 1
        assert_select "a[href='#{accounts_path}']", count: 0
        assert_select "li[aria-hidden='true']", count: 1
      end
      assert_select ".n-workspace-header .n-workspace-primary[href='#{new_account_path}']" do
        assert_select "span", text: I18n.t("nosia.accounts.add", locale: locale)
        assert_select "svg[aria-hidden='true']", count: 1
      end
      assert_select ".n-workspace-help", text: I18n.t("nosia.accounts_workspace.description", locale: locale)
      assert_select "[data-account-id]", count: 3
      assert_select "#accordion-right-actions, #drawer-right", count: 0
      refute_match(/translation missing|missing translation/i, response.body)
    end
  end

  test "overview has a complete escaped trail and authorized account actions" do
    @second.update_columns(name: "<script>Research account</script>", uid: "<img src=x onerror=alert(1)>")
    %i[en fr].each do |locale|
      get account_path(@second), headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      assert_select "head title", count: 1 do |titles|
        assert_equal @second.name, titles.first.text
      end
      assert_select "main h1", text: @second.name, count: 1
      assert_select "main nav", count: 1
      assert_select "main nav" do
        assert_select "a[href='#{user_root_path}']"
        assert_select "a[href='#{accounts_path}']"
        assert_select "[aria-current='page']", text: @second.name, count: 1
        assert_select "a[href='#{account_path(@second)}']", count: 0
      end
      assert_select ".n-workspace-header .n-workspace-help", text: /#{Regexp.escape(@second.uid)}/
      assert_select ".n-workspace-header a.n-workspace-button[href='#{edit_account_path(@second)}']:not(.n-workspace-primary)"
      assert_select ".n-workspace-header a.n-workspace-primary[href='#{new_chat_path(account_id: @second.id)}']" do
        assert_select "span", text: I18n.t("nosia.account_experience.new_conversation", locale: locale)
        assert_select "svg[aria-hidden='true']", count: 1
      end
      assert_select "main script, main img[onerror]", count: 0
      assert_select "[data-conversation-id]", count: 5
    end
    assert_equal @first, @user.reload.first_account
  end

  test "member retains contextual conversation action without owner editing" do
    sign_in_overview(@member)
    get account_path(@second)
    assert_response :success
    assert_select ".n-workspace-header a[href='#{edit_account_path(@second)}']", count: 0
    assert_select ".n-workspace-header a[href='#{new_chat_path(account_id: @second.id)}']"
    get edit_account_path(@second)
    assert_response :forbidden
    get account_path(@foreign)
    assert_response :not_found
  end

  test "revocation does not fall back to another account" do
    experience(:account_users, :overview_owner_second).destroy!
    get account_path(@second), params: { id: @first.id }
    assert_response :not_found
  end

  test "new and edit forms retain their existing breadcrumb contracts" do
    get new_account_path
    assert_select "nav[aria-label='Breadcrumb'] a", count: 1
    assert_select "nav a[href='#{accounts_path}']"
    get edit_account_path(@second)
    assert_select "nav[aria-label='Breadcrumb'] a", count: 2
    assert_select "nav a[href='#{account_path(@second)}']"
    assert_select "main nav a[href='#{user_root_path}']", count: 0
  end
end
