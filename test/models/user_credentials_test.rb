require "test_helper"
require_relative "../support/chat_account_fixtures"

class UserCredentialsTest < ActiveSupport::TestCase
  include ChatAccountFixtures

  PASSWORD = ChatAccountFixtures::PASSWORD
  REPLACEMENT = "replacement-password-456".freeze

  setup do
    @current_session = @user.sessions.create!
    @other_session = @user.sessions.create!
    @outsider = users(:picker_outsider)
    @foreign_session = @outsider.sessions.create!
    @original_attributes = @user.attributes
    @original_sessions = Session.order(:id).pluck(:id, :user_id, :created_at, :updated_at)
  end

  test "changing email encrypts the new address without changing passwords or browser sessions" do
    assert @user.change_email(email: "replacement@example.com", current_password: PASSWORD)
    assert_nil @user.current_password

    @user.reload
    assert_equal "replacement@example.com", @user.email
    ciphertext = @user.read_attribute_before_type_cast(:email)
    assert JSON.parse(ciphertext).key?("p")
    refute_includes ciphertext, "replacement@example.com"
    assert_equal @original_attributes["password_digest"], @user.password_digest
    assert_equal @user, @user.authenticate(PASSWORD)
    assert_sessions_unchanged
  end

  { missing: nil, incorrect: "incorrect-password" }.each do |description, current_password|
    test "changing email rejects #{description} current password without saving" do
      refute @user.change_email(email: "replacement@example.com", current_password: current_password)

      assert @user.errors.of_kind?(:current_password, :invalid)
      assert_credentials_unchanged
    end
  end

  { missing: nil, blank: "", malformed: "not-an-email" }.each do |description, email|
    test "changing email rejects a #{description} address without saving" do
      refute @user.change_email(email: email, current_password: PASSWORD)

      assert @user.errors.of_kind?(:email, description == :malformed ? :invalid : :blank)
      assert_credentials_unchanged
    end
  end

  test "changing email rejects another user's address without saving" do
    refute @user.change_email(email: @outsider.email, current_password: PASSWORD)

    assert @user.errors.of_kind?(:email, :taken)
    assert_credentials_unchanged
  end

  test "changing to the same email is a successful no-op" do
    travel_to 1.minute.from_now do
      assert @user.change_email(email: @user.email, current_password: PASSWORD)
    end

    assert_credentials_unchanged
  end

  test "changing email converts a storage uniqueness race into a validation error after rollback" do
    replacement = ->(*) { raise ActiveRecord::RecordNotUnique, "email already taken" }

    with_singleton_replacement(@user, :save, replacement) do
      refute @user.change_email(email: "replacement@example.com", current_password: PASSWORD)
    end

    assert @user.errors.of_kind?(:email, :taken)
    assert_credentials_unchanged
  end

  test "a PostgreSQL email uniqueness violation rolls back its savepoint without poisoning the transaction" do
    original_save = @user.method(:save)
    uniqueness_error = nil
    replacement = ->(*) do
      original_save.call(validate: false)
    rescue ActiveRecord::RecordNotUnique => error
      uniqueness_error = error
      raise
    end

    with_singleton_replacement(@user, :save, replacement) do
      refute @user.change_email(email: @outsider.email, current_password: PASSWORD)
    end

    assert_kind_of ActiveRecord::RecordNotUnique, uniqueness_error
    assert_kind_of PG::UniqueViolation, uniqueness_error.cause
    assert_match(/UPDATE "users"/, uniqueness_error.sql)
    assert @user.errors.of_kind?(:email, :taken)
    assert User.connection.transaction_open?
    assert_equal 1, User.connection.select_value("SELECT 1")
    assert_credentials_unchanged
  end

  test "changing password retains only the submitting browser and other users' sessions" do
    @user.sessions.create!

    assert @user.change_password(password: REPLACEMENT, password_confirmation: REPLACEMENT,
      current_password: PASSWORD, session: @current_session)
    assert_nil @user.current_password

    @user.reload
    refute_equal @original_attributes["password_digest"], @user.password_digest
    refute @user.authenticate(PASSWORD)
    assert_equal @user, @user.authenticate(REPLACEMENT)
    assert_equal @original_attributes["email"], @user.email
    assert_equal [ @current_session.id ], @user.sessions.pluck(:id)
    assert_equal [ @current_session.id, @foreign_session.id ].sort, Session.order(:id).pluck(:id)
    assert_equal @outsider, @foreign_session.reload.user
    refute Session.exists?(@other_session.id)
  end

  { missing: nil, empty: "", blank: " " * 12, short: "x" * 11,
    over_72_bytes: "x" * 73, over_72_utf8_bytes: "é" * 37 }.each do |description, password|
    test "changing password rejects #{description} replacements without saving or revoking sessions" do
      refute @user.change_password(password: password, password_confirmation: password,
        current_password: PASSWORD, session: @current_session)

      assert @user.errors[:password].any?
      assert_credentials_unchanged
    end
  end

  { missing: nil, blank: "", mismatched: "different-password-789" }.each do |description, confirmation|
    test "changing password rejects #{description} confirmation without saving or revoking sessions" do
      refute @user.change_password(password: REPLACEMENT, password_confirmation: confirmation,
        current_password: PASSWORD, session: @current_session)

      assert @user.errors[:password_confirmation].any?
      assert_credentials_unchanged
    end
  end

  { missing: nil, incorrect: "incorrect-password" }.each do |description, current_password|
    test "changing password rejects #{description} current password without saving or revoking sessions" do
      refute @user.change_password(password: REPLACEMENT, password_confirmation: REPLACEMENT,
        current_password: current_password, session: @current_session)

      assert @user.errors.of_kind?(:current_password, :invalid)
      assert_credentials_unchanged
    end
  end

  %i[en fr].each do |locale|
    test "current password errors render safely in #{locale} without retaining the secret" do
      submitted_secret = "never-retain-this-current-password"

      I18n.with_locale(locale) do
        refute @user.change_password(password: REPLACEMENT, password_confirmation: REPLACEMENT,
          current_password: submitted_secret, session: @current_session)

        error = @user.errors.where(:current_password, :invalid).first
        assert_kind_of String, error.message
        refute_empty error.message
        assert_equal [ error.full_message ], @user.errors.full_messages
        refute_includes @user.errors.full_messages.join, submitted_secret
        assert_nil @user.current_password
        refute @user.respond_to?(:current_password=)
      end
    end
  end

  test "changing to the same valid password still revokes other browser sessions" do
    assert @user.change_password(password: PASSWORD, password_confirmation: PASSWORD,
      current_password: PASSWORD, session: @current_session)

    assert_equal @user, @user.reload.authenticate(PASSWORD)
    assert_equal @original_attributes["email"], @user.email
    assert_equal [ @current_session.id ], @user.sessions.pluck(:id)
    assert_equal [ @current_session.id, @foreign_session.id ].sort, Session.order(:id).pluck(:id)
  end

  { empty: [ "", REPLACEMENT ], missing: [ nil, REPLACEMENT ],
    whitespace: [ " " * 12, " " * 12 ] }.each do |description, (password, confirmation)|
    test "changing password rejects #{description} replacements on a reused instance" do
      assert @user.change_password(password: REPLACEMENT, password_confirmation: REPLACEMENT,
        current_password: PASSWORD, session: @current_session)
      @user.sessions.create!
      saved_attributes = @user.attributes
      saved_sessions = Session.order(:id).pluck(:id, :user_id, :created_at, :updated_at)

      refute @user.change_password(password: password, password_confirmation: confirmation,
        current_password: REPLACEMENT, session: @current_session)

      assert @user.errors.of_kind?(:password, :blank)
      assert_equal saved_attributes, @user.reload.attributes
      assert_equal @user, @user.authenticate(REPLACEMENT)
      assert_equal saved_sessions, Session.order(:id).pluck(:id, :user_id, :created_at, :updated_at)
    end
  end

  { missing: nil, blank: "", mismatched: "different-password-789" }.each do |description, confirmation|
    test "changing password rejects #{description} confirmation on a reused instance" do
      assert @user.change_password(password: REPLACEMENT, password_confirmation: REPLACEMENT,
        current_password: PASSWORD, session: @current_session)
      @user.sessions.create!
      saved_attributes = @user.attributes
      saved_sessions = Session.order(:id).pluck(:id, :user_id, :created_at, :updated_at)

      refute @user.change_password(password: REPLACEMENT, password_confirmation: confirmation,
        current_password: REPLACEMENT, session: @current_session)

      assert @user.errors[:password_confirmation].any?
      assert_equal saved_attributes, @user.reload.attributes
      assert_equal @user, @user.authenticate(REPLACEMENT)
      assert_equal saved_sessions, Session.order(:id).pluck(:id, :user_id, :created_at, :updated_at)
    end
  end

  test "changing password accepts the 12 character and 72 UTF-8 byte boundaries" do
    minimum = "x" * 12
    maximum = "é" * 36

    assert @user.change_password(password: minimum, password_confirmation: minimum,
      current_password: PASSWORD, session: @current_session)
    assert_equal @user, @user.reload.authenticate(minimum)

    assert @user.change_password(password: maximum, password_confirmation: maximum,
      current_password: minimum, session: @current_session)
    assert_equal @user, @user.reload.authenticate(maximum)
    refute @user.authenticate(minimum)
  end

  test "changing password rejects another user's retained session before mutation" do
    assert_raises ActiveRecord::RecordNotFound do
      @user.change_password(password: REPLACEMENT, password_confirmation: REPLACEMENT,
        current_password: PASSWORD, session: @foreign_session)
    end

    assert_credentials_unchanged
  end

  test "a database session deletion failure rolls back the saved password" do
    connection = Session.connection
    original_exec_delete = connection.method(:exec_delete)
    user_id = @user.id
    saved_digest = nil
    replacement = ->(sql, *args, **kwargs, &block) do
      if sql.include?('DELETE FROM "sessions"')
        saved_digest = User.find(user_id).password_digest
        raise ActiveRecord::StatementInvalid, "session deletion failed"
      else
        original_exec_delete.call(sql, *args, **kwargs, &block)
      end
    end

    error = assert_raises ActiveRecord::StatementInvalid do
      with_singleton_replacement(connection, :exec_delete, replacement) do
        @user.change_password(password: REPLACEMENT, password_confirmation: REPLACEMENT,
          current_password: PASSWORD, session: @current_session)
      end
    end

    assert_equal "session deletion failed", error.message
    assert_not_nil saved_digest
    refute_equal @original_attributes["password_digest"], saved_digest
    assert_credentials_unchanged
    refute @user.authenticate(REPLACEMENT)
  end

  private
    def assert_credentials_unchanged
      assert_equal @original_attributes, @user.reload.attributes
      assert_equal @user, @user.authenticate(PASSWORD)
      assert_sessions_unchanged
    end

    def assert_sessions_unchanged
      assert_equal @original_sessions, Session.order(:id).pluck(:id, :user_id, :created_at, :updated_at)
    end
end
