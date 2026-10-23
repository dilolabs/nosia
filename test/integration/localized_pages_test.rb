require "test_helper"
require_relative "../support/chat_account_fixtures"

class LocalizedPagesTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures

  test "French visitors see translated sign in fields" do
    get root_url, headers: { "Accept-Language" => "fr" }

    assert_response :success
    assert_select 'input[type="email"][placeholder=?]', "Saisissez votre adresse e-mail"
    assert_select 'input[type="password"][placeholder=?]', "Saisissez votre mot de passe"
    assert_select 'input[type="submit"][value=?]', "Se connecter"
  end

  test "French visitors see a translated unauthorized error" do
    post login_url, params: { email: @user.email, password: "wrong-password" }, headers: { "Accept-Language" => "fr" }

    assert_response :unauthorized
    assert_includes response.body, "Trop de demandes ou accès non autorisé."
  end

  test "English visitors still see sign in" do
    get root_url, headers: { "Accept-Language" => "en" }

    assert_response :success
    assert_select 'input[type="submit"][value=?]', "Sign in"
  end
end
