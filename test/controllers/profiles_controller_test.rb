require "test_helper"
require_relative "../support/chat_account_fixtures"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures

  test "anonymous requests cannot read or change profile credentials" do
    original_email = @user.email
    original_digest = @user.password_digest

    get "/profile"
    assert_response :not_found

    patch "/profile/email", params: {
      email_change: { email: "replacement@example.com", current_password: ChatAccountFixtures::PASSWORD }
    }
    assert_response :not_found

    patch "/profile/password", params: {
      password_change: {
        current_password: ChatAccountFixtures::PASSWORD,
        password: "replacement-password-456", password_confirmation: "replacement-password-456"
      }
    }
    assert_response :not_found
    assert_equal original_email, @user.reload.email
    assert_equal original_digest, @user.password_digest
    assert @user.authenticate(ChatAccountFixtures::PASSWORD)
  end

  test "profile disables caching and presents two independent credential forms" do
    sign_in_picker_user
    get profile_path

    assert_response :success
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_select "meta[name=turbo-cache-control][content=no-cache]", count: 1
    assert_select "title", text: "Your profile"
    assert_select ".n-profile h1.n-workspace-title", text: "Your profile"
    assert_select ".n-profile .n-profile-card", count: 2
    assert_select ".n-profile form", count: 2
    assert_select "form form", count: 0

    assert_select "form#profile-email-form[action='/profile/email'][data-controller=credential-form]" do
      assert_select "input[name=_method][value=patch]"
      assert_select "input#profile_email_email[type=email][name='email_change[email]'][autocomplete=username][value=?]", @user.email
      assert_select "button[type=submit][data-turbo-submits-with='Updating email…']", text: "Update email"
    end
    assert_select "form#profile-password-form[action='/profile/password'][data-controller=credential-form]" do
      assert_select "input[name=_method][value=patch]"
      assert_select "input#profile_password_email[type=hidden][name='password_change[email]'][autocomplete=username][value=?]", @user.email
      assert_select "button[type=submit][data-turbo-submits-with='Updating password…']", text: "Update password"
    end
  end

  test "profile uses the accounts workspace breadcrumb design in both languages" do
    sign_in_picker_user

    %i[en fr].each do |locale|
      get profile_path, headers: { "Accept-Language" => locale.to_s }

      assert_response :success
      assert_select "main nav", count: 1
      assert_select ".n-profile .n-workspace-header nav.n-workspace-help[aria-label=?]", I18n.t("nosia.workspace.breadcrumb", locale: locale) do
        assert_select "ol.n-workspace-trail" do
          assert_select "a.n-workspace-link[href=?]", user_root_path, text: I18n.t("nosia.nav.home", locale: locale)
          assert_select "a", count: 1
          assert_select "a[href=?]", settings_path, count: 0
          assert_select "li[aria-current=page]", text: I18n.t("nosia.profile.title", locale: locale), count: 1
          assert_select "li[aria-hidden=true]", text: "/", count: 1
        end
      end
      assert_select "main h1", text: I18n.t("nosia.profile.title", locale: locale), count: 1
      assert_select "main .n-ariane", count: 0
    end
  end

  test "profile uses shared primary update buttons and secondary visibility buttons" do
    sign_in_picker_user
    get profile_path

    assert_select ".n-profile button.n-workspace-button[type=submit].n-workspace-primary", count: 2
    assert_select ".n-profile button.n-workspace-button[type=button]:not(.n-workspace-primary)[aria-pressed=false]", count: 4
  end

  test "profile secret fields start empty with accessible visibility controls and unique ids" do
    sign_in_picker_user
    get profile_path

    assert_select ".n-profile input[data-credential-secret]", count: 4
    css_select(".n-profile input[data-credential-secret]").each do |input|
      assert_equal "password", input["type"]
      assert_empty input["value"].to_s
      assert_equal "required", input["required"]
      assert_equal "false", input["aria-invalid"]
      assert_select ".n-profile label[for=?]", input["id"], count: 1
      assert_select ".n-profile button[type=button][aria-controls=?][aria-pressed=false]", input["id"], count: 1
    end
    assert_select ".n-profile input[autocomplete=current-password]", count: 2
    assert_select ".n-profile input[autocomplete=new-password]", count: 2
    assert_select ".n-profile button[type=button][aria-pressed=false]", count: 4
    assert_select ".n-profile [role=alert]", count: 0
    assert_select ".n-profile .n-profile-error", count: 0
    assert_select ".n-profile [id]" do |elements|
      ids = elements.map { |element| element["id"] }
      assert_equal ids.uniq, ids
    end
    css_select(".n-profile input[aria-describedby]").each do |input|
      input["aria-describedby"].split.each do |id|
        assert_select ".n-profile [id=?]", id, count: 1
      end
    end
  end

  test "French browser preference localizes the profile and its actions" do
    sign_in_picker_user
    get profile_path, headers: { "Accept-Language" => "fr" }

    assert_response :success
    assert_select "html[lang=fr]"
    assert_select ".n-profile h1", text: "Votre profil"
    assert_select "#profile-email-form button[type=submit]", text: "Modifier l’e-mail"
    assert_select "#profile-password-form button[type=submit]", text: "Modifier le mot de passe"
  end

  test "credential validation messages have direct English and French translations" do
    translations = {
      current_password: { en: "is incorrect", fr: "est incorrect" },
      password: { en: "must be 72 bytes or fewer", fr: "doit contenir au maximum 72 octets" }
    }

    translations.each do |attribute, locales|
      type = attribute == :current_password ? :invalid : :password_too_long
      key = "activerecord.errors.models.user.attributes.#{attribute}.#{type}"
      locales.each do |locale, expected|
        assert I18n.exists?(key, locale, fallback: false), "Missing #{locale} translation: #{key}"
        assert_equal expected, I18n.t(key, locale: locale, fallback: false)
      end
    end
  end

  test "profile page renders its cards and validation errors from another controller prefix" do
    @user.errors.add(:current_password, :invalid)

    html = ApplicationController.renderer.render(template: "profiles/show",
      assigns: { user: @user, failed_section: :email }, layout: false)
    page = Nokogiri::HTML.fragment(html)

    assert_select page, "form#profile-email-form", count: 1
    assert_select page, "form#profile-password-form", count: 1
    assert_select page, "#profile_email_errors a[href='#profile_email_current_password']", text: "Current password is incorrect"
    assert_select page, "#profile_email_current_password[aria-invalid=true]"
    assert_select page, "#profile_password_errors", count: 0
  end

  { email: 2, password: 3 }.each do |section, field_count|
    test "#{section} card renders fields and validation errors directly from another controller prefix" do
      @user.errors.add(:current_password, :invalid)

      html = ApplicationController.renderer.render(partial: "profiles/#{section}",
        locals: { user: @user, errors: @user.errors }, layout: false)
      page = Nokogiri::HTML.fragment(html)

      assert_select page, "form#profile-#{section}-form", count: 1
      assert_select page, ".n-field", count: field_count
      assert_select page, "#profile_#{section}_errors a[href='#profile_#{section}_current_password']", text: "Current password is incorrect"
      assert_select page, "#profile_#{section}_current_password[aria-invalid=true]"
      assert_select page, "#profile_#{section}_current_password_error", text: "is incorrect"
    end
  end

  test "failed password rendering links summary and inline errors without retaining any secrets" do
    secret = "never-render-this-password"
    @user.password = secret
    @user.password_confirmation = secret
    @user.errors.add(:current_password, :invalid)
    @user.errors.add(:password, :password_too_long)
    @user.errors.add(:base, :profile_rate_limited)

    html = ProfilesController.render(:show, assigns: { user: @user, failed_section: :password }, layout: false)
    page = Nokogiri::HTML.fragment(html)

    refute_includes html, secret
    assert_select page, "#profile_email_errors", count: 0
    assert_select page, "#profile_password_errors[role=alert][tabindex='-1'][data-credential-form-target=errors][aria-labelledby=profile_password_errors_title]" do
      assert_select "h3#profile_password_errors_title", text: "There is a problem"
      assert_select "a[href='#profile_password_current_password']", text: "Current password is incorrect"
      assert_select "a[href='#profile_password_password']", text: /must be 72 bytes or fewer/
      assert_select "a[href='#password']", text: "Too many attempts. Try again in a few minutes."
    end
    assert_select page, "#profile_password_current_password[aria-invalid=true][aria-describedby=profile_password_current_password_error]"
    assert_select page, "#profile_password_current_password_error", text: "is incorrect"
    assert_select page, "#profile_password_password[aria-invalid=true][aria-describedby='profile_password_password_hint profile_password_password_error']"
    assert_select page, "#profile_password_password_error", text: "must be 72 bytes or fewer"
    assert_select page, "#profile-email-form [aria-invalid=true]", count: 0
    assert_select page, ".n-profile input[data-credential-secret]", count: 4 do |inputs|
      inputs.each { |input| assert_empty input["value"].to_s }
    end
  end
end
