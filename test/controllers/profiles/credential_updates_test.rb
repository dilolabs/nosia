require "test_helper"
require_relative "../../support/chat_account_fixtures"

class ProfileCredentialUpdatesTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures

  PASSWORD = ChatAccountFixtures::PASSWORD
  REPLACEMENT = "replacement-password-456".freeze

  setup do
    sign_in_picker_user
    if defined?(Profiles::BaseController::CREDENTIAL_RATE_LIMIT_STORE)
      Profiles::BaseController::CREDENTIAL_RATE_LIMIT_STORE.clear
    end
    @outsider = users(:picker_outsider)
    @original_attributes = @user.attributes
  end

  teardown do
    if defined?(Profiles::BaseController::CREDENTIAL_RATE_LIMIT_STORE)
      Profiles::BaseController::CREDENTIAL_RATE_LIMIT_STORE.clear
    end
  end

  test "email updates only the authenticated user's email and preserves all browser sessions" do
    @user.sessions.create!
    @outsider.sessions.create!
    original_sessions = session_attributes
    outsider_attributes = @outsider.attributes
    old_email = @user.email

    patch profile_email_path, params: {
      user_id: @outsider.id, account_id: @foreign.id,
      email_change: {
        email: "new-profile@example.com", current_password: PASSWORD,
        admin: true, password: REPLACEMENT
      }
    }

    assert_response :see_other
    assert_redirected_to profile_path(anchor: "email")
    assert_no_store
    assert_equal "Your email address has been updated.", flash[:notice]
    assert_equal "new-profile@example.com", @user.reload.email
    assert_equal @original_attributes.except("email", "updated_at"), @user.attributes.except("email", "updated_at")
    refute @user.admin?
    assert @user.authenticate(PASSWORD)
    assert_equal original_sessions, session_attributes
    assert_equal outsider_attributes, @outsider.reload.attributes

    delete logout_path
    post login_path, params: { email: old_email, password: PASSWORD }
    assert_response :unauthorized
    post login_path, params: { email: "new-profile@example.com", password: PASSWORD }
    assert_response :redirect
  end

  test "password updates retain this browser and revoke only this user's other browsers" do
    current_session_id = @user.sessions.sole.id
    other_browser = signed_in_browser(@user)
    other_session_id = @user.sessions.where.not(id: current_session_id).sole.id
    foreign_session = @outsider.sessions.create!
    outsider_attributes = @outsider.attributes

    patch profile_password_path, params: {
      user_id: @outsider.id, account_id: @foreign.id,
      password_change: {
        current_password: PASSWORD, password: REPLACEMENT, password_confirmation: REPLACEMENT,
        email: "forged@example.com", admin: true, session_id: foreign_session.id
      }
    }

    assert_response :see_other
    assert_redirected_to profile_path(anchor: "password")
    assert_no_store
    assert_equal "Your password has been updated. Other browsers have been signed out.", flash[:notice]
    assert_equal @original_attributes["email"], @user.reload.email
    refute @user.admin?
    assert_equal [ current_session_id ], @user.sessions.pluck(:id)
    refute Session.exists?(other_session_id)
    assert_equal @outsider, foreign_session.reload.user
    assert_equal outsider_attributes, @outsider.reload.attributes

    get profile_path
    assert_response :success
    other_browser.get profile_path
    assert_equal 404, other_browser.response.status

    delete logout_path
    post login_path, params: { email: @user.email, password: PASSWORD }
    assert_response :unauthorized
    post login_path, params: { email: @user.email, password: REPLACEMENT }
    assert_response :redirect
  end

  test "failed email updates retain only the attempted nonsecret address with accessible errors" do
    secret = "never-render-this-wrong-secret"

    patch profile_email_path, params: {
      email_change: { email: "attempted-profile@example.com", current_password: secret }
    }

    assert_response :unprocessable_entity
    assert_no_store
    assert_select "#profile_email_email[value='attempted-profile@example.com']"
    assert_select "#profile_email_errors[role=alert][tabindex='-1']" do
      assert_select "a[href='#profile_email_current_password']", text: "Current password is incorrect"
    end
    assert_select "#profile_email_current_password[aria-invalid=true][aria-describedby=profile_email_current_password_error]"
    assert_select "#profile_email_current_password_error", text: "is incorrect"
    assert_select "#profile_password_errors", count: 0
    assert_select "#profile-password-form [aria-invalid=true]", count: 0
    assert_secrets_absent(secret)
    assert_equal @original_attributes, @user.reload.attributes
  end

  test "failed password confirmation renders only password errors without leaking secrets or revoking sessions" do
    other_browser = signed_in_browser(@user)
    original_sessions = session_attributes
    confirmation = "mismatched-confirmation-789"

    patch profile_password_path, params: {
      password_change: { current_password: PASSWORD, password: REPLACEMENT, password_confirmation: confirmation }
    }

    assert_response :unprocessable_entity
    assert_no_store
    assert_select "#profile_password_errors[role=alert][tabindex='-1']" do
      assert_select "a[href='#profile_password_password_confirmation']"
    end
    assert_select "#profile_password_password_confirmation[aria-invalid=true]"
    assert_select "#profile_email_errors", count: 0
    assert_select "#profile-email-form [aria-invalid=true]", count: 0
    assert_secrets_absent(PASSWORD, REPLACEMENT, confirmation)
    assert_equal @original_attributes, @user.reload.attributes
    assert @user.authenticate(PASSWORD)
    assert_equal original_sessions, session_attributes
    other_browser.get profile_path
    assert_equal 200, other_browser.response.status
  end

  test "alternating endpoints share ten attempts while another user has a separate allowance" do
    exhaust_credential_attempts

    patch profile_email_path, params: {
      email_change: { email: "blocked-profile@example.com", current_password: PASSWORD }
    }

    assert_response :too_many_requests
    assert_no_store
    assert_select "#profile_email_errors a[href='#email']", text: "Too many attempts. Try again in a few minutes."
    assert_select "#profile_password_errors", count: 0
    assert_equal @original_attributes, @user.reload.attributes

    outsider_browser = signed_in_browser(@outsider)
    outsider_browser.patch profile_password_path, params: {
      password_change: { current_password: "wrong-password", password: REPLACEMENT, password_confirmation: REPLACEMENT }
    }
    assert_equal 422, outsider_browser.response.status
    outsider_browser.patch profile_email_path, params: {
      email_change: { email: @outsider.email, current_password: PASSWORD }
    }
    assert_equal 303, outsider_browser.response.status
  end

  test "signing into another browser does not reset the same user's allowance" do
    exhaust_credential_attempts
    other_browser = signed_in_browser(@user)
    original_sessions = session_attributes

    other_browser.patch profile_password_path, params: {
      password_change: { current_password: PASSWORD, password: REPLACEMENT, password_confirmation: REPLACEMENT }
    }

    assert_equal 429, other_browser.response.status
    assert_includes other_browser.response.body, "Too many attempts. Try again in a few minutes."
    assert_includes other_browser.response.headers["Cache-Control"], "no-store"
    assert_equal @original_attributes, @user.reload.attributes
    assert_equal original_sessions, session_attributes
  end

  test "credential allowance expires after three minutes and then permits an authorized no-op" do
    Profiles::BaseController::CREDENTIAL_RATE_LIMIT_STORE.write("profile-credentials:#{@user.id}", 10, expires_in: 3.minutes)

    patch profile_email_path, params: {
      email_change: { email: "blocked-profile@example.com", current_password: PASSWORD }
    }

    assert_response :too_many_requests
    assert_equal @original_attributes, @user.reload.attributes

    travel 3.minutes + 1.second do
      patch profile_email_path, params: { email_change: { email: @user.email, current_password: PASSWORD } }

      assert_response :see_other
      assert_redirected_to profile_path(anchor: "email")
      assert_no_store
      assert_equal @original_attributes, @user.reload.attributes
    end
  end

  test "French requests localize the full current password validation message" do
    patch profile_email_path, params: {
      email_change: { email: "attempted-profile@example.com", current_password: "wrong-password" }
    }, headers: { "Accept-Language" => "fr" }

    assert_response :unprocessable_entity
    assert_select "html[lang=fr]"
    assert_select "#profile_email_errors a[href='#profile_email_current_password']", text: "Mot de passe actuel est incorrect"
  end

  test "French requests localize rate limiting" do
    Profiles::BaseController::CREDENTIAL_RATE_LIMIT_STORE.write("profile-credentials:#{@user.id}", 10, expires_in: 3.minutes)

    patch profile_password_path, params: {
      password_change: { current_password: PASSWORD, password: REPLACEMENT, password_confirmation: REPLACEMENT }
    }, headers: { "Accept-Language" => "fr" }

    assert_response :too_many_requests
    assert_select "#profile_password_errors a[href='#password']", text: "Trop de tentatives. Réessayez dans quelques minutes."
    assert_select "#profile_email_errors", count: 0
    assert_equal @original_attributes, @user.reload.attributes
  end

  test "French requests localize successful email and password updates" do
    headers = { "Accept-Language" => "fr" }
    patch profile_email_path, params: {
      email_change: { email: @user.email, current_password: PASSWORD }
    }, headers: headers

    assert_response :see_other
    assert_equal "Votre adresse e-mail a été modifiée.", flash[:notice]

    patch profile_password_path, params: {
      password_change: { current_password: PASSWORD, password: REPLACEMENT, password_confirmation: REPLACEMENT }
    }, headers: headers

    assert_response :see_other
    assert_equal "Votre mot de passe a été modifié. Les autres navigateurs ont été déconnectés.", flash[:notice]
  end

  %i[email password].each do |section|
    test "#{section} updates reject missing or malformed parameter roots without mutation" do
      root = "#{section}_change"
      original_sessions = session_attributes

      [ {}, { root => "invalid" }, { root => [ "invalid" ] }, { root => true } ].each do |parameters|
        patch "/profile/#{section}", params: parameters

        assert_response :bad_request
        assert_no_store
        assert_empty response.body
        assert_equal @original_attributes, @user.reload.attributes
        assert_equal original_sessions, session_attributes
      end
    end

    test "#{section} updates require a valid CSRF token" do
      original_sessions = session_attributes
      previous = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true

      patch "/profile/#{section}", params: {
        "#{section}_change" => {
          email: "forged-profile@example.com", current_password: PASSWORD,
          password: REPLACEMENT, password_confirmation: REPLACEMENT
        }
      }

      assert_response :unprocessable_entity
      assert_no_store
      assert_empty response.body
      assert_equal @original_attributes, @user.reload.attributes
      assert_equal original_sessions, session_attributes
    ensure
      ActionController::Base.allow_forgery_protection = previous
    end
  end

  test "unauthenticated attempts cannot consume credential allowance" do
    delete logout_path

    patch profile_email_path, params: {
      email_change: { email: "forged-profile@example.com", current_password: PASSWORD }
    }

    assert_response :not_found
    assert_nil Profiles::BaseController::CREDENTIAL_RATE_LIMIT_STORE.read("profile-credentials:#{@user.id}")
    assert_equal @original_attributes, @user.reload.attributes
  end

  test "configured parameter filters cover every credential field including the hidden email context" do
    parameters = {
      "email_change" => { "email" => "filtered-profile@example.com", "current_password" => PASSWORD },
      "password_change" => {
        "email" => @user.email, "current_password" => PASSWORD,
        "password" => REPLACEMENT, "password_confirmation" => REPLACEMENT
      }
    }
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    assert_equal parameters.transform_values { "[FILTERED]" }, filter.filter(parameters)
    parameters.each_value do |credentials|
      assert_equal credentials.transform_values { "[FILTERED]" }, filter.filter(credentials)
    end

    get profile_path

    assert_response :success
    assert_select "#profile-password-form input[type=hidden][name='password_change[email]'][autocomplete=username]"
    assert_select ".n-profile input[name*='username']", count: 0
  end

  test "email and password changes preserve API token authentication and foreign user state" do
    token = @user.api_tokens.create!(account: @first, name: "Profile regression")
    plain_token = token.plain_token
    token_attributes = token.attributes
    foreign_attributes = @outsider.attributes
    foreign_session = @outsider.sessions.create!
    foreign_session_attributes = foreign_session.attributes

    patch profile_email_path, params: {
      email_change: { email: "token-profile@example.com", current_password: PASSWORD }
    }

    assert_response :see_other
    assert_equal token_attributes, token.reload.attributes
    assert_equal token, ApiToken.authenticate_token(plain_token)
    assert_equal foreign_attributes, @outsider.reload.attributes
    assert_equal foreign_session_attributes, foreign_session.reload.attributes

    patch profile_password_path, params: {
      password_change: { current_password: PASSWORD, password: REPLACEMENT, password_confirmation: REPLACEMENT }
    }

    assert_response :see_other
    assert_equal token_attributes, token.reload.attributes
    assert_equal token, ApiToken.authenticate_token(plain_token)
    assert_equal foreign_attributes, @outsider.reload.attributes
    assert_equal foreign_session_attributes, foreign_session.reload.attributes
  end

  test "script-like passwords with mismatched confirmation never appear in validation responses or flash" do
    secret = "<script>profile-secret</script>"
    confirmation = "different-confirmation-789"

    patch profile_password_path, params: {
      password_change: { current_password: PASSWORD, password: secret, password_confirmation: confirmation }
    }

    assert_response :unprocessable_entity
    assert_no_store
    assert_select "#profile_password_errors[role=alert][tabindex='-1']" do
      assert_select "a[href='#profile_password_password_confirmation']"
    end
    assert_select "#profile_password_password_confirmation[aria-invalid=true]"
    assert_select "#profile_email_errors", count: 0
    assert_select "#profile-email-form [aria-invalid=true]", count: 0
    assert_secrets_absent(PASSWORD, secret, ERB::Util.html_escape(secret), confirmation)
    assert_equal @original_attributes, @user.reload.attributes
  end

  private
    def signed_in_browser(user)
      open_session do |browser|
        browser.post login_path, params: { email: user.email, password: PASSWORD }
        assert_equal 302, browser.response.status
      end
    end

    def session_attributes
      Session.order(:id).map(&:attributes)
    end

    def assert_no_store
      assert_includes response.headers["Cache-Control"], "no-store"
    end

    def assert_secrets_absent(*secrets)
      secrets.each do |secret|
        refute_includes response.body, secret
        refute_includes flash.to_hash.to_s, secret
      end
      assert_select "input[data-credential-secret]", count: 4 do |inputs|
        inputs.each { |input| assert_empty input["value"].to_s }
      end
    end

    def exhaust_credential_attempts
      10.times do |attempt|
        if attempt.even?
          patch profile_email_path, params: {
            email_change: { email: "attempted-profile@example.com", current_password: "wrong-password" }
          }
        else
          patch profile_password_path, params: {
            password_change: { current_password: "wrong-password", password: REPLACEMENT, password_confirmation: REPLACEMENT }
          }
        end
        assert_response :unprocessable_entity
      end
    end
end
