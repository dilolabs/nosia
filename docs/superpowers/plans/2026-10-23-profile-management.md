# Profile Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (recommended) or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let signed-in users securely change their login email and password at `/profile` through two accessible, independently saved cards.

**Architecture:** Keep `Current.user` as the only identity authority. User-model methods authorize and persist credential changes; password saving and other-browser revocation share one transaction. Dedicated REST update controllers share profile rendering/privacy/rate-limiting behavior, while small Stimulus controllers enhance native forms.

**Tech Stack:** Actual repository stack: Ruby 4.0.7, Rails 8.0.5.1, PostgreSQL, encrypted Active Record email, bcrypt, ERB, Turbo, Stimulus/importmap, Tailwind 4, Minitest/fixtures, Selenium/Chrome. Do not change dependencies, IDs, authentication mechanisms, or the database schema.

---

## Approved scope and workspace

Read `docs/superpowers/specs/2026-10-23-profile-management-design.md` first. The user approved the written spec with “Go”. This document is the implementation plan, not permission to bypass the execution handoff.

- Branch: `feature/profile-management`.
- Worktree: `/home/cbldev/gitd/dilolabs/nosia/.worktrees/profile-management`.
- Base includes approved spec commit `f29eee5` and unrelated documentation commits through `3c3b14a`.
- `bundle check` passed during planning. No database preparation, baseline tests, or application implementation ran during documentation-only planning. Task 0 establishes the execution baseline.
- The original worktree contains unrelated concurrent work. Never reset it, copy its modified application files, or stage it. Commit explicit feature paths only.
- Reuse opt-in `ChatAccountFixtures`; global fixtures are intentionally sparse. Do not replace this with factories or add application-wide default fixture data.
- The user identity spans account memberships. Do not add `account_id` filtering/columns to users or sessions and do not introduce services, policies, or form objects.

### Public contracts

- `User#change_email(email:, current_password:) -> true/false`; failed validation errors live on that user.
- `User#change_password(password:, password_confirmation:, current_password:, session:) -> true/false`; `session` is the authenticated `Current.session`, never client-supplied.
- Email request: `PATCH /profile/email`, root `email_change`, allowed `email`, `current_password`.
- Password request: `PATCH /profile/password`, root `password_change`, allowed `password`, `password_confirmation`, `current_password`.
- Success: HTTP 303 to `/profile#email` or `/profile#password`, localized notice. Validation: HTTP 422. Exhausted shared update allowance: HTTP 429. Anonymous requests remain denied by existing authenticated route constraints (normally HTTP 404); do not redesign the broken/unrelated `new_session_url` fallback.
- Email changes leave sessions/API tokens untouched. Password changes keep the submitting session and revoke only that user's other browser sessions. API tokens remain valid.
- Valid identical-password replacements are allowed and still revoke other browsers. No password reuse/history policy is added.

## File map

| Path | Responsibility |
| --- | --- |
| `app/models/user.rb` | Credential authorization, scoped password validation context, atomic session revocation. |
| `app/controllers/profiles/base_controller.rb` | Authenticated profile state, no-store responses, shared credential attempt counter. |
| `app/controllers/profiles_controller.rb` | Existing profile GET through shared rendering setup. |
| `app/controllers/profiles/emails_controller.rb` | Email-only allowlisted update. |
| `app/controllers/profiles/passwords_controller.rb` | Password-only allowlisted update. |
| `config/routes.rb` | Nested singular email/password update resources. |
| `app/views/profiles/show.html.erb` | Heading, breadcrumb, two-card composition, Turbo cache opt-out. |
| `app/views/profiles/_email.html.erb`, `_password.html.erb` | Independent native forms. |
| `app/views/profiles/_field.html.erb`, `_errors.html.erb` | Explicitly supplied labels, safe values, localized visibility controls, associated errors. |
| `app/assets/stylesheets/nosia/profile.css`, `app/assets/tailwind/application.css` | Profile-scoped layout, readable states and focus; stylesheet import. |
| `app/javascript/controllers/password_visibility_controller.js` | One-field reveal/mask and navigation cleanup. |
| `app/javascript/controllers/credential_form_controller.js` | Focus the failed card's error summary. |
| `config/locales/en.nosia_profile.yml`, `fr.nosia_profile.yml` | Feature copy and credential model error translations. |
| `test/models/user_credentials_test.rb` | Credential validation, isolation, encryption and atomicity. |
| `test/controllers/profiles_controller_test.rb` | Page access, rendering, error/secret semantics and localization. |
| `test/controllers/profiles/credential_updates_test.rb` | Updates, login/session effects, forged input, CSRF and shared rate limit. |
| `test/system/profile_management_test.rb` | Real form submissions, focus, reveal/privacy, responsiveness and themes. |
| `docs/profile-management.md`, `docs/README.md` | User behavior, developer contracts and operational limits. |

## Task 0: Establish the execution baseline

- [ ] Run `git status --short` in this worktree. Expected: only the planning/spec documentation if not yet committed; no application changes. Re-read local `AGENTS.md`.
- [ ] Run `bundle check`. Expected: satisfied. If missing, stop and resolve the environment with the user rather than updating the lockfile.
- [ ] Prepare a dedicated **test-only** PostgreSQL database. The following commands load the original ignored `.env` without copying or displaying it; an explicit test URL takes precedence. If this installation needs a host/user, substitute its approved test-only URL, never a development/production database.

```bash
RAILS_ENV=test DATABASE_URL=postgresql:///nosia_profile_management_test bundle exec dotenv -f ../../.env -- bin/rails db:prepare
DATABASE_URL=postgresql:///nosia_profile_management_test PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails test test/integration/authentication_lifecycle_test.rb test/controllers/language_preferences_controller_test.rb
```

Expected: schema preparation succeeds and existing tests pass. If either command fails, capture the exact failure and get a decision before application work. Do not silently substitute a shared active test database or run `db:reset`.

- [ ] Run `command -v chromium` and, if absent, `command -v google-chrome`. Confirm one usable local Chrome installation. The remote Selenium URL in `test/application_system_test_case.rb` is incomplete; do not enable that path without a supplied working service.
- [ ] For all later commands, retain the explicit dedicated `DATABASE_URL`; use `bundle exec dotenv -f ../../.env --` before `bin/rails`/`bin/rubocop` if the required environment is not already exported. Never print encryption keys.

## Task 1: Model-owned credential changes

**Files:** Modify `app/models/user.rb`; create `test/models/user_credentials_test.rb`.

- [ ] **Step 1: Write the failing behavioral tests.** Reuse the existing opt-in fixtures and its singleton replacement helper; do not assume `Object#stub` exists.

```ruby
require "test_helper"
require_relative "../support/chat_account_fixtures"

class UserCredentialsTest < ActiveSupport::TestCase
  include ChatAccountFixtures

  PASSWORD = ChatAccountFixtures::PASSWORD
  REPLACEMENT = "replacement-password-456"

  setup do
    @current = @user.sessions.create!(user_agent: "Current", ip_address: "127.0.0.1")
    @other = @user.sessions.create!(user_agent: "Other", ip_address: "127.0.0.2")
    @outsider = users(:picker_outsider)
    @foreign_session = @outsider.sessions.create!(user_agent: "Foreign")
  end

  test "email change preserves the password and every session" do
    digest = @user.password_digest
    session_ids = Session.order(:id).pluck(:id)
    assert @user.change_email(email: "new-profile@example.com", current_password: PASSWORD)
    assert_equal "new-profile@example.com", @user.reload.email
    assert_equal digest, @user.password_digest
    assert_equal session_ids, Session.order(:id).pluck(:id)
    refute_equal @user.email, @user.read_attribute_before_type_cast(:email)
    assert @user.authenticate(PASSWORD)
  end

  test "invalid email or authorization cannot alter persisted credentials" do
    original = @user.attributes
    [
      [ "new-profile@example.com", nil, :current_password ],
      [ "new-profile@example.com", "wrong", :current_password ],
      [ nil, PASSWORD, :email ],
      [ "not-an-email", PASSWORD, :email ],
      [ @outsider.email, PASSWORD, :email ]
    ].each do |email, challenge, field|
      @user.reload
      refute @user.change_email(email: email, current_password: challenge)
      assert @user.errors[field].any?
      assert_equal original, @user.reload.attributes
    end
  end

  test "same email is a harmless authorized no-op" do
    assert_no_changes -> { @user.reload.updated_at } do
      assert @user.change_email(email: @user.email, current_password: PASSWORD)
    end
    assert @user.sessions.exists?(@other.id)
  end

  test "password change retains only the submitting browser for this user" do
    assert @user.change_password(password: REPLACEMENT,
      password_confirmation: REPLACEMENT, current_password: PASSWORD, session: @current)
    refute @user.reload.authenticate(PASSWORD)
    assert @user.authenticate(REPLACEMENT)
    assert Session.exists?(@current.id)
    refute Session.exists?(@other.id)
    assert Session.exists?(@foreign_session.id)
    assert_equal "picker@example.com", @user.email
  end

  test "blank short oversized unconfirmed or unauthorized passwords do not revoke sessions" do
    digest = @user.password_digest
    [
      [ nil, nil, PASSWORD ], [ "", "", PASSWORD ],
      [ "x" * 11, "x" * 11, PASSWORD ],
      [ "x" * 73, "x" * 73, PASSWORD ],
      [ "é" * 37, "é" * 37, PASSWORD ],
      [ REPLACEMENT, nil, PASSWORD ], [ REPLACEMENT, "different", PASSWORD ],
      [ REPLACEMENT, REPLACEMENT, nil ], [ REPLACEMENT, REPLACEMENT, "wrong" ]
    ].each do |password, confirmation, challenge|
      @user.reload
      refute @user.change_password(password: password, password_confirmation: confirmation,
        current_password: challenge, session: @current)
      assert @user.errors.any?
      assert_equal digest, @user.reload.password_digest
      assert @user.sessions.exists?(@other.id)
      assert Session.exists?(@foreign_session.id)
    end
  end

  test "identical valid replacement is accepted and still revokes other browsers" do
    assert @user.change_password(password: PASSWORD, password_confirmation: PASSWORD,
      current_password: PASSWORD, session: @current)
    assert @user.reload.authenticate(PASSWORD)
    assert Session.exists?(@current.id)
    refute Session.exists?(@other.id)
  end

  test "password boundaries accept twelve characters and seventy-two UTF-8 bytes" do
    assert @user.change_password(password: "x" * 12, password_confirmation: "x" * 12,
      current_password: PASSWORD, session: @current)
    @user.reload
    assert @user.change_password(password: "é" * 36, password_confirmation: "é" * 36,
      current_password: "x" * 12, session: @current)
    assert @user.reload.authenticate("é" * 36)
  end

  test "another user's session cannot be used as the preserved browser" do
    digest = @user.password_digest
    assert_raises(ActiveRecord::RecordNotFound) do
      @user.change_password(password: REPLACEMENT, password_confirmation: REPLACEMENT,
        current_password: PASSWORD, session: @foreign_session)
    end
    assert_equal digest, @user.reload.password_digest
    assert Session.exists?(@other.id)
  end

  test "storage uniqueness conflicts become email errors outside the savepoint" do
    original = @user.email
    with_singleton_replacement(@user, :save, ->(*, **) { raise ActiveRecord::RecordNotUnique }) do
      refute @user.change_email(email: "raced@example.com", current_password: PASSWORD)
      assert @user.errors.added?(:email, :taken)
    end
    assert_equal original, @user.reload.email
  end

  test "session deletion failure rolls back the saved password" do
    digest = @user.password_digest
    connection = Session.connection
    original = connection.method(:exec_delete)
    replacement = ->(sql, *args, **options) do
      raise ActiveRecord::StatementInvalid, "simulated session deletion failure" if sql.include?('DELETE FROM "sessions"')
      original.call(sql, *args, **options)
    end
    with_singleton_replacement(connection, :exec_delete, replacement) do
      assert_raises(ActiveRecord::StatementInvalid) do
        @user.change_password(password: REPLACEMENT, password_confirmation: REPLACEMENT,
          current_password: PASSWORD, session: @current)
      end
    end
    assert_equal digest, @user.reload.password_digest
    assert Session.exists?(@current.id)
    assert Session.exists?(@other.id)
  end
end
```

- [ ] **Step 2: Run RED.** Run `bin/rails test test/models/user_credentials_test.rb` with Task 0's environment prefix. Expected: undefined `change_email` / `change_password`, not an encryption/connection/fixture failure. Fix test setup rather than implementing around an environmental failure.
- [ ] **Step 3: Implement the model contract.** Keep the existing associations/encryption/class methods. Change the existing password validation's `on:` to `[ :create, :password_change ]`, add confirmation presence for that context, and add these instance/private methods in project ordering:

```ruby
validates :password,
  presence: true,
  length: { minimum: 12 },
  on: [ :create, :password_change ]

validates :password_confirmation, presence: true, on: :password_change

# Changes the login email after verifying the persisted password.
# @param email [String, nil] requested login email
# @param current_password [String, nil] existing password, never persisted
# @return [Boolean] whether the change passed authorization and validation
def change_email(email:, current_password:)
  with_lock(requires_new: true) do
    self.email = email
    if credential_password_valid?(current_password)
      save
    else
      false
    end
  end
rescue ActiveRecord::RecordNotUnique
  errors.add(:email, :taken)
  false
end

# Changes the password and revokes other browser sessions atomically.
# @param password [String, nil] replacement password
# @param password_confirmation [String, nil] matching replacement
# @param current_password [String, nil] existing password
# @param session [Session] authenticated browser session belonging to this user
# @return [Boolean] whether the change passed authorization and validation
# @raise [ActiveRecord::RecordNotFound] if the retained session is not owned
def change_password(password:, password_confirmation:, current_password:, session:)
  with_lock(requires_new: true) do
    retained_session = sessions.find(session.id)
    if credential_password_valid?(current_password)
      assign_attributes(password: password, password_confirmation: password_confirmation)
      if save(context: :password_change)
        sessions.where.not(id: retained_session.id).delete_all
        true
      else
        false
      end
    else
      false
    end
  end
end

private
  def credential_password_valid?(current_password)
    errors.clear
    if authenticate(current_password.to_s)
      true
    else
      errors.add(:current_password, :invalid)
      false
    end
  end
```

`with_lock` reloads under a row lock before checking the old digest. `requires_new: true` gives uniqueness rescue a savepoint boundary even inside transactional tests. Assign the replacement only after authorization. Session deletion exceptions must escape the transaction, not be swallowed inside it. bcrypt's existing 72-byte validation remains authoritative.

- [ ] **Step 4: Run GREEN.** Run the model test and `test/integration/authentication_lifecycle_test.rb`. Expected: passing model behavior and unchanged registration/login/logout behavior. A failure saving a password before revocation must also leave every session unchanged because both operations are transactional.
- [ ] **Step 5: Commit.** `git add app/models/user.rb test/models/user_credentials_test.rb`; `git commit -m "feat(profile): Add authorized credential changes"` (run as separate commands).

## Task 2: Render the two accessible cards and translations

**Files:** Create the four profile partials, profile CSS, and two locale files from the file map; modify profile show/controller and Tailwind imports; create `test/controllers/profiles_controller_test.rb`.

- [ ] **Step 1: Write RED rendering/access tests.**

```ruby
require "test_helper"
require_relative "../support/chat_account_fixtures"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures

  test "anonymous profile reads and credential writes are denied" do
    get "/profile"
    assert_response :not_found
    patch "/profile/email", params: { email_change: { email: "attack@example.com" } }
    assert_response :not_found
    patch "/profile/password", params: { password_change: { password: "attack-password" } }
    assert_response :not_found
    assert @user.reload.authenticate(ChatAccountFixtures::PASSWORD)
  end

  test "profile renders independent labeled forms without caching" do
    sign_in_picker_user
    get "/profile"
    assert_response :success
    assert_includes response.headers.fetch("Cache-Control"), "no-store"
    assert_select "meta[name=turbo-cache-control][content=no-cache]"
    assert_select "h1", text: "Your profile"
    assert_select "form#profile-email-form[action='/profile/email']"
    assert_select "form#profile-password-form[action='/profile/password']"
    assert_select "form form", count: 0
    assert_select "#profile_email_email[value=?]", @user.email
    assert_select "#profile_password_email[autocomplete=username][value=?]", @user.email
    assert_select "input[data-credential-secret]", count: 4
    assert_select "input[data-credential-secret][value]:not([value=''])", count: 0
    assert_select "input[autocomplete=current-password]", count: 2
    assert_select "input[autocomplete=new-password]", count: 2
    assert_select "button[type=button][aria-pressed=false]", count: 4
    assert_select "[role=alert][data-credential-form-target=errors]", count: 0
    ids = css_select(".n-profile [id]").map { |element| element["id"] }
    assert_equal ids.uniq, ids
  end

  test "French profile strings and credential errors exist without fallback" do
    sign_in_picker_user
    get "/profile", headers: { "Accept-Language" => "fr" }
    assert_select "html[lang=fr]"
    assert_select "h1", text: "Votre profil"
    assert_select "button", text: "Modifier l’e-mail"
    assert_select "button", text: "Modifier le mot de passe"
    %i[en fr].each do |locale|
      assert I18n.exists?("activerecord.errors.models.user.attributes.current_password.invalid", locale, fallback: false)
      assert I18n.exists?("activerecord.errors.models.user.attributes.password.password_too_long", locale, fallback: false)
    end
  end
end
```

- [ ] **Step 2: Run RED.** Run `bin/rails test test/controllers/profiles_controller_test.rb`. Expect missing page/form/privacy assertions, not a missing fixture or login failure. Anonymous denial may already pass.
- [ ] **Step 3: Add translations.** Create these files, avoiding shared shell locale files under concurrent work.

```yaml
# config/locales/en.nosia_profile.yml
en:
  activerecord:
    attributes:
      user:
        current_password: "Current password"
    errors:
      models:
        user:
          attributes:
            current_password:
              invalid: "is incorrect"
            password:
              password_too_long: "must be 72 bytes or fewer"
            base:
              profile_rate_limited: "Too many attempts. Try again in a few minutes."
  nosia:
    profile:
      title: "Your profile"
      introduction: "Manage your sign-in details securely."
      email_title: "Email address"
      email_description: "Use this address to sign in to Nosia."
      email_hint: "Your new email works immediately after saving. No confirmation email is sent."
      email_submit: "Update email"
      email_pending: "Updating email…"
      email_success: "Your email address has been updated."
      password_title: "Password"
      password_description: "Choose a strong password you don’t use elsewhere."
      password_hint: "At least 12 characters."
      sessions_hint: "Other browsers will be signed out. You’ll stay signed in here. API tokens stay active."
      password_submit: "Update password"
      password_pending: "Updating password…"
      password_success: "Your password has been updated. Other browsers have been signed out."
      errors_title: "There is a problem"
      show: "Show"
      hide: "Hide"
      show_label: "Show %{field}"
      hide_label: "Hide %{field}"
      fields:
        email: "Email address"
        current_password: "Current password"
        password: "New password"
        password_confirmation: "Confirm new password"
```

```yaml
# config/locales/fr.nosia_profile.yml
fr:
  activerecord:
    attributes:
      user:
        current_password: "Mot de passe actuel"
    errors:
      models:
        user:
          attributes:
            current_password:
              invalid: "est incorrect"
            password:
              password_too_long: "doit contenir au maximum 72 octets"
            base:
              profile_rate_limited: "Trop de tentatives. Réessayez dans quelques minutes."
  nosia:
    profile:
      title: "Votre profil"
      introduction: "Gérez vos identifiants de connexion en toute sécurité."
      email_title: "Adresse e-mail"
      email_description: "Utilisez cette adresse pour vous connecter à Nosia."
      email_hint: "Votre nouvelle adresse fonctionne dès l’enregistrement. Aucun e-mail de confirmation n’est envoyé."
      email_submit: "Modifier l’e-mail"
      email_pending: "Modification de l’e-mail…"
      email_success: "Votre adresse e-mail a été modifiée."
      password_title: "Mot de passe"
      password_description: "Choisissez un mot de passe robuste que vous n’utilisez pas ailleurs."
      password_hint: "Au moins 12 caractères."
      sessions_hint: "Les autres navigateurs seront déconnectés. Vous resterez connecté ici. Les jetons API resteront actifs."
      password_submit: "Modifier le mot de passe"
      password_pending: "Modification du mot de passe…"
      password_success: "Votre mot de passe a été modifié. Les autres navigateurs ont été déconnectés."
      errors_title: "Un problème est survenu"
      show: "Afficher"
      hide: "Masquer"
      show_label: "Afficher : %{field}"
      hide_label: "Masquer : %{field}"
      fields:
        email: "Adresse e-mail"
        current_password: "Mot de passe actuel"
        password: "Nouveau mot de passe"
        password_confirmation: "Confirmer le nouveau mot de passe"
```

- [ ] **Step 4: Add nested routes and initial profile state.** Replace the existing singular profile route with this block. Both new controllers are implemented in Task 3; rendering named helpers needs the routes now.

```ruby
resource :profile, only: :show do
  scope module: :profiles do
    resource :email, only: :update
    resource :password, only: :update
  end
end
```

Initially use the controller below. Task 3 moves this shared setup to the base controller without changing behavior.

```ruby
class ProfilesController < ApplicationController
  before_action -> { response.headers["Cache-Control"] = "no-store" }

  def show
    @user = Current.user
  end
end
```

- [ ] **Step 5: Write the page and partials.** The field partial owns explicit values/IDs and can never accidentally use the model's in-memory password. Error objects are passed only to the failed card.

```erb
<%# app/views/profiles/show.html.erb %>
<% content_for :title, t("nosia.profile.title") %>
<% content_for :head do %>
  <meta name="turbo-cache-control" content="no-cache">
<% end %>
<% content_for :navbar do %>
  <li><%= link_to t("nosia.nav.settings"), settings_path, class: "n-ariane n-main-focus" %></li>
  <li aria-current="page"><%= t("nosia.profile.title") %></li>
<% end %>
<div class="n-profile">
  <header>
    <h1 class="n-main-title"><%= t("nosia.profile.title") %></h1>
    <p class="n-profile-help mt-2"><%= t("nosia.profile.introduction") %></p>
  </header>
  <%= render "profiles/email", user: @user, errors: (@failed_section == :email ? @user.errors : nil) %>
  <%= render "profiles/password", user: @user, errors: (@failed_section == :password ? @user.errors : nil) %>
</div>
```

```erb
<%# app/views/profiles/_email.html.erb %>
<section class="n-profile-card" aria-labelledby="email">
  <h2 id="email" tabindex="-1" class="n-card-title"><%= t("nosia.profile.email_title") %></h2>
  <p class="n-profile-help"><%= t("nosia.profile.email_description") %></p>
  <%= form_with scope: :email_change, url: profile_email_path, method: :patch,
      id: "profile-email-form", data: { controller: "credential-form" } do |form| %>
    <%= render "profiles/errors", errors: errors, section: :email %>
    <%= render "profiles/field", form: form, section: :email, field: :email,
        value: user.email, errors: errors, autocomplete: "username", hint: nil %>
    <%= render "profiles/field", form: form, section: :email, field: :current_password,
        value: nil, errors: errors, autocomplete: "current-password", hint: nil %>
    <p class="n-profile-help mt-3"><%= t("nosia.profile.email_hint") %></p>
    <div class="n-profile-actions">
      <%= form.button t("nosia.profile.email_submit"), class: "n-profile-submit",
          data: { turbo_submits_with: t("nosia.profile.email_pending") } %>
    </div>
  <% end %>
</section>
```

```erb
<%# app/views/profiles/_password.html.erb %>
<section class="n-profile-card" aria-labelledby="password">
  <h2 id="password" tabindex="-1" class="n-card-title"><%= t("nosia.profile.password_title") %></h2>
  <p class="n-profile-help"><%= t("nosia.profile.password_description") %></p>
  <%= form_with scope: :password_change, url: profile_password_path, method: :patch,
      id: "profile-password-form", data: { controller: "credential-form" } do |form| %>
    <%= form.hidden_field :email, id: "profile_password_email", value: user.email_in_database, autocomplete: "username" %>
    <%= render "profiles/errors", errors: errors, section: :password %>
    <%= render "profiles/field", form: form, section: :password, field: :current_password,
        value: nil, errors: errors, autocomplete: "current-password", hint: nil %>
    <%= render "profiles/field", form: form, section: :password, field: :password,
        value: nil, errors: errors, autocomplete: "new-password", hint: t("nosia.profile.password_hint") %>
    <%= render "profiles/field", form: form, section: :password, field: :password_confirmation,
        value: nil, errors: errors, autocomplete: "new-password", hint: nil %>
    <p class="n-profile-note"><%= t("nosia.profile.sessions_hint") %></p>
    <div class="n-profile-actions">
      <%= form.button t("nosia.profile.password_submit"), class: "n-profile-submit",
          data: { turbo_submits_with: t("nosia.profile.password_pending") } %>
    </div>
  <% end %>
</section>
```

```erb
<%# app/views/profiles/_errors.html.erb %>
<% if errors&.any? %>
  <div id="profile_<%= section %>_errors" class="n-profile-errors" role="alert"
       tabindex="-1" aria-labelledby="profile_<%= section %>_errors_title" data-credential-form-target="errors">
    <h3 id="profile_<%= section %>_errors_title" class="font-semibold"><%= t("nosia.profile.errors_title") %></h3>
    <ul>
      <% errors.each do |error| %>
        <% destination = error.attribute == :base ? section : "profile_#{section}_#{error.attribute}" %>
        <li><%= link_to error.full_message, "##{destination}", class: "underline" %></li>
      <% end %>
    </ul>
  </div>
<% end %>
```

```erb
<%# app/views/profiles/_field.html.erb %>
<% field_id = "profile_#{section}_#{field}" %>
<% label = t("nosia.profile.fields.#{field}") %>
<% messages = errors ? errors.where(field).map(&:message) : [] %>
<% description_ids = [ ("#{field_id}_hint" if hint), ("#{field_id}_error" if messages.any?) ].compact.join(" ") %>
<% options = { id: field_id, class: "n-field", autocomplete: autocomplete, required: true,
    aria: { invalid: messages.any?, describedby: description_ids.presence } } %>
<div class="mt-4">
  <%= form.label field, label, for: field_id, class: "n-label block font-medium" %>
  <% if field == :email %>
    <%= form.email_field field, **options, value: value %>
  <% else %>
    <div class="n-profile-secret" data-controller="password-visibility"
         data-password-visibility-show-value="<%= t('nosia.profile.show') %>"
         data-password-visibility-hide-value="<%= t('nosia.profile.hide') %>"
         data-password-visibility-show-label-value="<%= t('nosia.profile.show_label', field: label) %>"
         data-password-visibility-hide-label-value="<%= t('nosia.profile.hide_label', field: label) %>"
         data-action="turbo:before-cache@document->password-visibility#reset turbo:before-visit@document->password-visibility#reset pagehide@window->password-visibility#reset">
      <%= form.password_field field, **options, value: nil,
          data: { credential_secret: true, password_visibility_target: "input" } %>
      <button type="button" class="n-profile-visibility" aria-controls="<%= field_id %>" aria-pressed="false"
              aria-label="<%= t('nosia.profile.show_label', field: label) %>"
              data-password-visibility-target="button" data-action="password-visibility#toggle">
        <%= t("nosia.profile.show") %>
      </button>
    </div>
  <% end %>
  <% if hint %><p id="<%= field_id %>_hint" class="n-profile-help mt-1"><%= hint %></p><% end %>
  <% if messages.any? %><p id="<%= field_id %>_error" class="n-profile-error mt-1"><%= messages.to_sentence %></p><% end %>
</div>
```

The hidden username context is named `email` so existing `:email` log filtering still applies. It is not permitted as a password-change attribute. Password inputs have explicit `value: nil`, even when the user object contains a rejected replacement.

- [ ] **Step 6: Add scoped styling and import it.** Add `@import "../stylesheets/nosia/profile.css" layer(utilities);` to `app/assets/tailwind/application.css` after the existing form import. Create:

```css
/* app/assets/stylesheets/nosia/profile.css */
.n-profile { @apply mx-auto w-full min-w-0 max-w-2xl space-y-6 pb-8; }
.n-profile-card { @apply min-w-0 rounded-xl border border-neutral-300 bg-white p-5 dark:border-neutral-600 dark:bg-neutral-800 sm:p-6; }
.n-profile-help { @apply break-words text-sm leading-relaxed text-neutral-600 dark:text-neutral-300; }
.n-profile .n-field { @apply min-h-11 min-w-0 border-neutral-500 text-neutral-900 focus:outline-green-700 dark:text-neutral-100 dark:focus:outline-green-400; }
.n-profile-secret { @apply grid min-w-0 grid-cols-[minmax(0,1fr)_auto] items-center gap-2; }
.n-profile-visibility { @apply min-h-11 min-w-11 cursor-pointer rounded-lg px-2 text-sm font-medium text-green-800 hover:bg-green-50 focus:outline-2 focus:outline-offset-2 focus:outline-green-700 dark:text-green-200 dark:hover:bg-green-900 dark:focus:outline-green-400; }
.n-profile-actions { @apply mt-5 flex justify-end; }
.n-profile-submit { @apply min-h-11 cursor-pointer rounded-lg bg-green-700 px-4 py-2 text-sm font-semibold text-white hover:bg-green-800 focus:outline-2 focus:outline-offset-2 focus:outline-green-700 disabled:cursor-wait dark:focus:outline-green-400; }
.n-profile-note { @apply mt-4 rounded-lg bg-green-50 p-3 text-sm leading-relaxed text-green-900 dark:bg-green-950 dark:text-green-100; }
.n-profile-errors { @apply my-4 break-words rounded-lg border border-red-700 p-3 text-sm text-red-800 focus:outline-2 focus:outline-offset-2 focus:outline-red-700 dark:border-red-400 dark:text-red-200 dark:focus:outline-red-300; }
.n-profile-error { @apply text-sm text-red-700 dark:text-red-300; }
```

No new motion is needed, so reduced-motion users receive the same static layout. Existing green-300 buttons are not used here with white text; the scoped green-700 action provides sufficient contrast. Do not globally restyle existing forms/buttons or change the application viewport meta tag in this task.

- [ ] **Step 7: Run GREEN.** Run `bin/rails tailwindcss:build` and `bin/rails test test/controllers/profiles_controller_test.rb`. Expected: stylesheet compilation and all page assertions pass. The new form endpoints are wired but are not advertised as functional until Task 3 is green.
- [ ] **Step 8: Commit.** Stage only the exact profile view/style/localization/controller/routes/test paths above; commit `feat(profile): Add accessible credential settings cards`.

## Task 3: Wire authenticated independent updates and shared attempt limiting

**Files:** Create `app/controllers/profiles/base_controller.rb`, `emails_controller.rb`, `passwords_controller.rb`, `test/controllers/profiles/credential_updates_test.rb`; modify `app/controllers/profiles_controller.rb`.

- [ ] **Step 1: Write RED request tests.**

```ruby
require "test_helper"
require_relative "../../support/chat_account_fixtures"

class ProfileCredentialUpdatesTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures

  PASSWORD = ChatAccountFixtures::PASSWORD
  REPLACEMENT = "replacement-password-456"

  setup do
    sign_in_picker_user
    Profiles::BaseController::CREDENTIAL_RATE_LIMIT_STORE.clear if defined?(Profiles::BaseController)
  end

  test "email update only changes the current identity and accepts the new login" do
    original = @user.email
    outsider = users(:picker_outsider)
    foreign_digest = outsider.password_digest
    sessions = @user.sessions.pluck(:id)
    patch "/profile/email", params: { user_id: outsider.id, account_id: @foreign.id,
      email_change: { email: "new-profile@example.com", current_password: PASSWORD,
        admin: true, password: REPLACEMENT } }
    assert_response :see_other
    assert_redirected_to "/profile#email"
    assert_equal "new-profile@example.com", @user.reload.email
    refute @user.admin?
    assert @user.authenticate(PASSWORD)
    assert_equal sessions, @user.sessions.pluck(:id)
    assert_equal foreign_digest, outsider.reload.password_digest
    delete logout_url
    post login_url, params: { email: original, password: PASSWORD }
    assert_response :unauthorized
    post login_url, params: { email: @user.email, password: PASSWORD }
    assert_response :redirect
  end

  test "password update preserves this browser and rejects a revoked browser cookie" do
    other_browser = open_session
    other_browser.post login_url, params: { email: @user.email, password: PASSWORD }
    other_id = @user.sessions.order(:id).last.id
    patch "/profile/password", params: { password_change: { current_password: PASSWORD,
      password: REPLACEMENT, password_confirmation: REPLACEMENT, email: "ignored@example.com" } }
    assert_response :see_other
    assert_redirected_to "/profile#password"
    get "/profile"
    assert_response :success
    refute Session.exists?(other_id)
    other_browser.get "/profile"
    assert_equal 404, other_browser.response.status
    assert_equal "picker@example.com", @user.reload.email
    delete logout_url
    post login_url, params: { email: @user.email, password: PASSWORD }
    assert_response :unauthorized
    post login_url, params: { email: @user.email, password: REPLACEMENT }
    assert_response :redirect
  end

  test "failed email keeps attempted input and associates only its own errors" do
    patch "/profile/email", params: { email_change: { email: "attempt@example.com", current_password: "wrong-secret-123" } }
    assert_response :unprocessable_entity
    assert_includes response.headers.fetch("Cache-Control"), "no-store"
    assert_select "#profile_email_email[value='attempt@example.com']"
    assert_select "#profile_email_errors[tabindex='-1'][role=alert]"
    assert_select "#profile_email_current_password[aria-invalid=true][aria-describedby=profile_email_current_password_error]"
    assert_select "a[href='#profile_email_current_password']"
    assert_select "#profile_password_errors", count: 0
    refute_includes response.body, "wrong-secret-123"
    assert_equal "picker@example.com", @user.reload.email
  end

  test "failed password renders no secrets and keeps other sessions" do
    other = @user.sessions.create!(user_agent: "Other")
    patch "/profile/password", params: { password_change: { current_password: PASSWORD,
      password: REPLACEMENT, password_confirmation: "mismatch-secret-456" } }
    assert_response :unprocessable_entity
    assert_select "#profile_password_errors"
    assert_select "#profile_email_errors", count: 0
    [ PASSWORD, REPLACEMENT, "mismatch-secret-456" ].each { |secret| refute_includes response.body, secret }
    [ PASSWORD, REPLACEMENT, "mismatch-secret-456" ].each { |secret| refute_includes flash.to_hash.inspect, secret }
    assert @user.reload.authenticate(PASSWORD)
    assert Session.exists?(other.id)
  end

  test "both endpoints share ten attempts and a different user has a separate allowance" do
    10.times do |index|
      if index.even?
        patch "/profile/email", params: { email_change: { email: @user.email, current_password: "wrong" } }
      else
        patch "/profile/password", params: { password_change: { current_password: "wrong" } }
      end
      assert_response :unprocessable_entity
    end
    patch "/profile/email", params: { email_change: { email: @user.email, current_password: PASSWORD } }
    assert_response :too_many_requests
    assert_select "#profile_email_errors", text: /Too many attempts/
    sign_in_picker_user(users(:picker_outsider))
    patch "/profile/email", params: { email_change: { email: "separate@example.com", current_password: PASSWORD } }
    assert_response :see_other
  end

  test "limiter expires after three minutes and failure cannot mutate credentials" do
    store = Profiles::BaseController::CREDENTIAL_RATE_LIMIT_STORE
    store.write("profile-credentials:#{@user.id}", 10, expires_in: 3.minutes)
    patch "/profile/password", params: { password_change: { current_password: PASSWORD,
      password: REPLACEMENT, password_confirmation: REPLACEMENT } }
    assert_response :too_many_requests
    assert @user.reload.authenticate(PASSWORD)
    travel 3.minutes + 1.second do
      patch "/profile/email", params: { email_change: { email: @user.email, current_password: PASSWORD } }
      assert_response :see_other
    end
  end

  test "French credential errors stay localized" do
    patch "/profile/email", params: { email_change: { email: @user.email, current_password: "wrong" } },
      headers: { "Accept-Language" => "fr" }
    assert_response :unprocessable_entity
    assert_select "#profile_email_errors", text: /Mot de passe actuel est incorrect/
  end

  test "credential updates remain CSRF protected" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    patch "/profile/email", params: { email_change: { email: "forged@example.com", current_password: PASSWORD } }
    assert_response :unprocessable_entity
    assert_equal "picker@example.com", @user.reload.email
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end
end
```

- [ ] **Step 2: Run RED.** Run the request test. Expected: missing update controllers, then missing shared counter until implemented. Ensure anonymous/profile rendering tests still run separately.
- [ ] **Step 3: Add shared setup and controllers.** Rails 8.0's `rate_limit` includes `controller_path` and has no shared `scope:` option. Use one explicit counter in the shared controller; do not pretend two independent declarations share an allowance.

```ruby
# app/controllers/profiles/base_controller.rb
class Profiles::BaseController < ApplicationController
  CREDENTIAL_RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new

  before_action :prepare_profile
  before_action :limit_credential_changes, if: -> { action_name == "update" }

  private
    def prepare_profile
      @user = Current.user
      response.headers["Cache-Control"] = "no-store"
    end

    def limit_credential_changes
      count = CREDENTIAL_RATE_LIMIT_STORE.increment("profile-credentials:#{@user.id}", 1, expires_in: 3.minutes)
      if count > 10
        @failed_section = controller_name.singularize.to_sym
        @user.errors.add(:base, :profile_rate_limited)
        render "profiles/show", status: :too_many_requests
      end
    end
end

# app/controllers/profiles_controller.rb
class ProfilesController < Profiles::BaseController
  def show
  end
end

# app/controllers/profiles/emails_controller.rb
class Profiles::EmailsController < Profiles::BaseController
  def update
    attributes = params.expect(email_change: [ :email, :current_password ])
    if @user.change_email(email: attributes[:email], current_password: attributes[:current_password])
      redirect_to profile_path(anchor: "email"), status: :see_other, notice: t("nosia.profile.email_success")
    else
      @failed_section = :email
      render "profiles/show", status: :unprocessable_entity
    end
  end
end

# app/controllers/profiles/passwords_controller.rb
class Profiles::PasswordsController < Profiles::BaseController
  def update
    attributes = params.expect(password_change: [ :password, :password_confirmation, :current_password ])
    if @user.change_password(password: attributes[:password], password_confirmation: attributes[:password_confirmation],
        current_password: attributes[:current_password], session: Current.session)
      redirect_to profile_path(anchor: "password"), status: :see_other, notice: t("nosia.profile.password_success")
    else
      @failed_section = :password
      render "profiles/show", status: :unprocessable_entity
    end
  end
end
```

The inherited authentication callback precedes the counter. Use a callable condition instead of `only: :update` in the shared controller: this project raises for callbacks naming actions absent from a subclass (the show controller has no update).

The explicit MemoryStore follows the existing registration limiter, works when the test cache is NullStore, and is shared across both controllers in a process. It is not a distributed limiter across workers/hosts; document this deployment limitation rather than adding Redis or quietly promising cluster-wide enforcement.

- [ ] **Step 4: Run GREEN.** Run both new controller test files, the model test, and existing authentication lifecycle test. Expected: all feature tests pass, including combined endpoint allowance and revocation-cookie denial. Verify success notices exist in both locales.
- [ ] **Step 5: Commit.** Stage only these shared/update controllers, profile show controller, and update tests; commit `feat(profile): Connect isolated credential update endpoints`.

## Task 4: Browser enhancement, feedback and secret cleanup

**Files:** Create both Stimulus controllers and `test/system/profile_management_test.rb`.

- [ ] **Step 1: Write failing system tests.** Tests deliberately use a correct-length wrong current password so native `required` does not prevent the server error response.

```ruby
require "application_system_test_case"
require_relative "../support/chat_account_fixtures"

class ProfileManagementSystemTest < ApplicationSystemTestCase
  include ChatAccountFixtures

  setup do
    Profiles::BaseController::CREDENTIAL_RATE_LIMIT_STORE.clear
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_button "Sign in"
    visit "/profile"
    assert_selector "#profile-email-form"
  end

  teardown { Capybara.reset_sessions! }

  test "visibility changes one field and keyboard errors receive focus" do
    fill_in "profile_email_current_password", with: "wrong-password-123"
    within "#profile-email-form" do
      click_button "Show Current password", enable_aria_label: true
      assert_selector "#profile_email_current_password[type=text]"
      assert_selector "button[aria-pressed=true]"
    end
    assert_selector "#profile_password_current_password[type=password]"
    find("#profile-email-form button[type=submit]").send_keys(:enter)
    assert_selector "#profile_email_errors:focus"
    assert_selector "#profile_email_current_password_error", text: "is incorrect"
    assert_equal "", find("#profile_email_current_password").value
    assert_selector "#profile_email_current_password[type=password]"
    find("#profile_email_errors a[href='#profile_email_current_password']").click
    assert_selector "#profile_email_current_password:focus"
  end

  test "each form saves independently and successful navigation clears both cards" do
    fill_in "profile_email_email", with: "browser-profile@example.com"
    fill_in "profile_email_current_password", with: ChatAccountFixtures::PASSWORD
    fill_in "profile_password_password", with: "unsaved-secret-789"
    click_button "Update email"
    assert_text "Your email address has been updated."
    assert_equal "browser-profile@example.com", find("#profile_email_email").value
    assert_equal "", find("#profile_password_password").value
    fill_in "profile_password_current_password", with: ChatAccountFixtures::PASSWORD
    fill_in "profile_password_password", with: "browser-replacement-456"
    fill_in "profile_password_password_confirmation", with: "browser-replacement-456"
    click_button "Update password"
    assert_text "Your password has been updated."
    assert @user.reload.authenticate("browser-replacement-456")
    assert_selector "#profile-password-form"
  end

  test "navigation and back do not restore a revealed secret" do
    fill_in "profile_email_current_password", with: "temporary-secret-456"
    within("#profile-email-form") { click_button "Show Current password", enable_aria_label: true }
    page.execute_script("document.dispatchEvent(new Event('turbo:before-cache'))")
    assert_equal "", find("#profile_email_current_password").value
    assert_selector "#profile_email_current_password[type=password]"
    fill_in "profile_password_password", with: "second-secret-456"
    page.execute_script("window.dispatchEvent(new Event('pagehide'))")
    assert_equal "", find("#profile_password_password").value
    fill_in "profile_email_current_password", with: "temporary-secret-456"
    page.execute_script("Turbo.visit('/settings')")
    assert_current_path "/settings"
    page.go_back
    assert_selector "#profile-email-form"
    assert_equal "", find("#profile_email_current_password").value
    assert_selector "#profile_email_current_password[type=password]"
  end

  test "375px controls fit in English and French in both themes" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 900, deviceScaleFactor: 1, mobile: false)
    %w[en fr].each do |locale|
      find("#language_preference_locale option[value='#{locale}']", visible: :all).select_option
      find("form[action='/language_preference'] button[type=submit]").click
      assert_selector "html[lang=#{locale}]"
      visit "/profile"
      assert_selector "html[lang=#{locale}]"
      [ false, true ].each do |dark|
        page.execute_script("document.documentElement.classList.toggle('dark', arguments[0])", dark)
        overflow = page.evaluate_script("document.documentElement.scrollWidth - innerWidth")
        assert_operator overflow, :<=, 1
        %w[profile_email_email profile_email_current_password profile_password_password].each do |id|
          height = find("##{id}").evaluate_script("this.getBoundingClientRect().height")
          assert_operator height, :>=, 44
        end
        find("#profile_email_email").send_keys(:tab)
        assert_selector "#profile_email_current_password:focus-visible"
      end
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
```

The actual signed language-preference form is the locale authority. Use its native option values (`en`/`fr`) and submit button rather than manually changing `html[lang]` or assuming the target locale's label is already displayed.

- [ ] **Step 2: Run RED.** Build Tailwind and run `bin/rails test test/system/profile_management_test.rb`. Expect visibility/focus/cleanup assertions to fail before the controllers exist. Record any unavailable Chrome/environment failure distinctly; do not report it as a behavior failure.
- [ ] **Step 3: Implement focused Stimulus behavior.** Importmap eagerly discovers both controller files; do not add a dependency or manually duplicate registration.

```javascript
// app/javascript/controllers/password_visibility_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "button"]
  static values = { show: String, hide: String, showLabel: String, hideLabel: String }

  connect() {
    this.setVisibility(false)
  }

  toggle() {
    this.setVisibility(this.inputTarget.type === "password")
  }

  reset() {
    this.inputTarget.value = ""
    this.setVisibility(false)
  }

  setVisibility(visible) {
    this.inputTarget.type = visible ? "text" : "password"
    this.buttonTarget.textContent = visible ? this.hideValue : this.showValue
    this.buttonTarget.setAttribute("aria-label", visible ? this.hideLabelValue : this.showLabelValue)
    this.buttonTarget.setAttribute("aria-pressed", String(visible))
  }
}
```

```javascript
// app/javascript/controllers/credential_form_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["errors"]

  connect() {
    if (this.hasErrorsTarget) this.errorsTarget.focus()
  }
}
```

Do not clear inputs in `connect()`; that can fight legitimate password-manager autofill. Clear on Turbo cache/visit and native pagehide, mask after every reconnect, and never store values in Stimulus values, browser storage, or DOM data attributes. Native Turbo disables the submitting button; `data-turbo-submits-with` supplies localized pending copy. No optimistic credential update is allowed.

- [ ] **Step 4: Run GREEN and the visual checks.** Run the system test. Then inspect both themes/locales at 375px and desktop, 200% browser zoom, and reduced-motion emulation. Check normal/help/primary-button text at 4.5:1 and meaningful control/focus boundaries at 3:1 against actual computed backgrounds; verify long emails/French errors wrap and the summary/focused input remains visible inside the application's scrolling main region. Exercise a password-manager fill and paste manually; automation checks autocomplete and no paste blockers, not a third-party password manager. With JavaScript disabled in Chrome's site settings, reload `/profile`, submit each card with valid values, and confirm native submission/redirect still works. Re-enable JavaScript afterwards. Refresh a successful result and confirm it does not resubmit or revoke sessions again.
- [ ] **Step 5: Commit.** Stage the two controllers and system test; commit `feat(profile): Add password visibility and safe browser feedback`.

## Task 5: Complete security regressions and docs

**Files:** Append to `test/controllers/profiles/credential_updates_test.rb`; create `docs/profile-management.md`; modify `docs/README.md`.

- [ ] **Step 1: Add explicit no-regression/privacy assertions before any fixes.** Append these tests to the existing request test class:

```ruby
test "request filtering covers every password field and hidden username context" do
  filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
  filtered = filter.filter("email_change" => { "email" => @user.email, "current_password" => PASSWORD },
    "password_change" => { "email" => @user.email, "current_password" => PASSWORD,
      "password" => REPLACEMENT, "password_confirmation" => REPLACEMENT })
  assert_equal "[FILTERED]", filtered.dig("email_change", "email")
  assert_equal "[FILTERED]", filtered.dig("email_change", "current_password")
  %w[email current_password password password_confirmation].each do |field|
    assert_equal "[FILTERED]", filtered.dig("password_change", field)
  end
end

test "email and password changes do not revoke API tokens or other identities" do
  token = @user.api_tokens.create!(account: @first, name: "Profile regression")
  outsider = users(:picker_outsider)
  foreign_session = outsider.sessions.create!(user_agent: "Unrelated")
  foreign_attributes = outsider.attributes
  patch "/profile/email", params: { email_change: { email: "tokens@example.com", current_password: PASSWORD } }
  assert_response :see_other
  patch "/profile/password", params: { password_change: { current_password: PASSWORD,
    password: REPLACEMENT, password_confirmation: REPLACEMENT } }
  assert_response :see_other
  assert @user.api_tokens.exists?(token.id)
  assert_equal foreign_attributes, outsider.reload.attributes
  assert Session.exists?(foreign_session.id)
end

test "password errors are bounded to their fields and cannot echo HTML or secrets" do
  payload = "<script>profile-secret</script>"
  patch "/profile/password", params: { password_change: { current_password: PASSWORD,
    password: payload, password_confirmation: "different" } }
  assert_response :unprocessable_entity
  assert_select "#profile_password_password_confirmation[aria-invalid=true]"
  assert_select "#profile_email_errors", count: 0
  refute_includes response.body, payload
  refute_includes response.body, "&lt;script&gt;profile-secret"
  refute_includes response.body, PASSWORD
end
```

- [ ] **Step 2: Run the new assertions.** They should pass if prior tasks honored the contract. If one fails, treat it as the RED gate for a narrowly scoped correction; make no speculative application changes first.
- [ ] **Step 3: Write the behavior/operations document.** Create `docs/profile-management.md` with this content and add `- [Profile management](profile-management.md) — credential changes, browser sessions, and privacy guarantees.` under Development in `docs/README.md`.

```markdown
# Profile management

Open User info from the header menu to visit `/profile`. Email and password
have separate save actions; both require your current password.

Email changes take effect immediately without a verification email. Existing
browser sessions and API tokens remain active. A typo can prevent a later
login, so check the new address before saving; email recovery is not included.

Passwords require at least 12 characters, at most 72 UTF-8 bytes, and matching
confirmation. Successful password updates keep the submitting browser signed
in and sign out your other browsers. API tokens remain active. Reusing the
current password is permitted and applies the same browser-session policy.

## Developer contract

`PATCH /profile/email` accepts `email_change[email]` and
`email_change[current_password]`. `PATCH /profile/password` accepts
`password_change[password]`, `[password_confirmation]`, and `[current_password]`.
Controllers act only on `Current.user`; the retained session comes only from
`Current.session`. User-model methods own authorization, validation, and saving.

Password updates and other-session deletion share a transaction. A failed
change cannot partially save credentials or revoke browsers. Email storage
continues to use Active Record encryption. No schema migration is required.

Successful forms redirect with HTTP 303. Invalid values render HTTP 422 with
field errors and a linked, focusable summary. Credentials are filtered from
logs and are never returned as password input values or persisted in drafts.
Profile HTML uses no-store and opts out of Turbo snapshots. Visibility controls
clear and mask secrets when leaving/caching; browser/password-manager autofill
is still supported and is distinct from restoring an application draft.

The two update endpoints share 10 attempts per signed-in user per three minutes.
Exhaustion returns HTTP 429 without saving. Like the existing registration
limiter, the shared MemoryStore is process-local, not distributed across
workers or hosts. Deployments requiring a global ceiling need a shared backing
store as a separately reviewed infrastructure change.

English/French copy, light/dark styling, keyboard focus, password-manager
autocomplete, and 375px layouts are covered by focused profile tests. No mail
delivery, reset/recovery, passkeys, account administration, or token revocation
flow is introduced by this feature.
```

- [ ] **Step 4: Run final verification with the isolated test environment.**

```bash
bin/rails tailwindcss:build
bin/rails zeitwerk:check
PARALLEL_WORKERS=1 bin/rails test test/models/user_credentials_test.rb test/controllers/profiles_controller_test.rb test/controllers/profiles/credential_updates_test.rb test/integration/authentication_lifecycle_test.rb test/controllers/language_preferences_controller_test.rb
PARALLEL_WORKERS=1 bin/rails test test/system/profile_management_test.rb
bundle exec rubocop app/models/user.rb app/controllers/profiles_controller.rb app/controllers/profiles test/models/user_credentials_test.rb test/controllers/profiles_controller_test.rb test/controllers/profiles test/system/profile_management_test.rb
bundle exec brakeman --no-pager
git diff --check
```

Use the Task 0 database/environment prefix on every Rails command. Expected: passing targeted tests, successful asset/autoload checks, no new lint/security warnings, and clean whitespace. Also run `PARALLEL_WORKERS=1 bin/rails test` and `bin/rails test:system` when the baseline environment supports them; report exact unrelated failures instead of broad fixes. Do not claim visual/contrast/password-manager checks passed unless actually performed.

- [ ] **Step 5: Review against the approved spec.** Use `rails-code-review` and `rails-security-review`; confirm no submitted ID chooses a user/session, failed writes are atomic, form secrets never re-render, unrelated cards do not inherit errors, both endpoints share the limiter, and no new migration/dependency/auth flow was introduced. Keep public model YARD comments accurate. Resolve findings only after a failing regression test exists.
- [ ] **Step 6: Commit and hand off without automatically merging.** Stage only the feature regression/doc paths; commit `docs(profile): Document credential and browser-session behavior`. Use `verification-before-completion` before success claims and `finishing-a-development-branch` for the eventual integration choice. Do not push, merge, or delete the worktree without the user's integration decision.

## Spec-to-task coverage

| Approved requirement | Task |
| --- | --- |
| Current-user identity, allowlisted independent REST updates | 1, 3, 5 |
| Immediate encrypted email update; unchanged password/sessions/tokens | 1, 3, 5 |
| Password challenge, 12 characters, 72 bytes, required matching confirmation | 1, 2, 3 |
| Atomic other-browser revocation, current/foreign sessions safe | 1, 3 |
| Duplicate-email conflict recovery and failed-save rollback | 1 |
| Shared per-user rate limit, HTTP 429, expiry and user isolation | 3, 5 |
| Neutral/green stacked cards, independent actions and native fallback | 2, 3 |
| Inline linked errors, summary focus, safe pending/success states | 2, 3, 4 |
| Password visibility, paste/managers, no-store/cache/navigation privacy | 2, 4, 5 |
| English/French, 375px/zoom, both themes/contrast/reduced motion | 2, 4 |
| No dependency/schema/authentication/API-token-policy changes | 0, 1, 5 |
| Public API documentation, regression/lint/security review | 1, 5 |

## Execution handoff

Choose `subagent-driven-development` for fresh task agents with reviews, or
`executing-plans` for inline batches with checkpoints. No application files
have been changed while writing this plan.
