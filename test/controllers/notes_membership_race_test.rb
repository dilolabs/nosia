require "test_helper"
require "timeout"

class NotesMembershipRaceTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false
  self.fixture_paths = [ Rails.root.join("test/support/fixtures/chat_accounts") ]
  fixtures :users, :accounts, :account_users, :note_folders, :notes

  setup do
    @account = accounts(:picker_first)
    @member = users(:picker_outsider)
    @note = notes(:field_notes)
    @account.account_users.grant_to(@member)
    @membership = @account.account_users.find_by!(user: @member)
    post login_path, params: { email: @member.email, password: "picker-password-123" }
    assert_response :redirect
  end

  teardown do
    Account.where(id: accounts.map(&:id)).destroy_all
    User.where(id: users.map(&:id)).destroy_all
    ActiveRecord::FixtureSet.reset_cache
  end

  test "an edit queued behind membership revocation cannot change the note" do
    revoke_ahead_of_write do
      patch account_note_path(@account, @note), params: {
        note: { title: "Forbidden edit", body_html: "", expected_revision: 1 }
      }
    end

    assert_response :not_found
    assert_equal [ "Field notes", 1 ], @note.reload.values_at(:title, :content_revision)
  end

  test "a JSON autosave queued behind membership revocation cannot change the note" do
    revoke_ahead_of_write do
      patch account_note_path(@account, @note), params: {
        note: { title: "Forbidden autosave", body_html: "<p>#forbidden</p>", expected_revision: 1 }
      }, headers: { "Accept" => "application/json" }
    end

    assert_response :not_found
    assert_empty response.body
    assert_equal [ "Field notes", 1 ], @note.reload.values_at(:title, :content_revision)
    assert_empty @note.note_tags
  end

  test "trashing queued behind membership revocation cannot hide the note" do
    revoke_ahead_of_write { post account_note_trashing_path(@account, @note) }

    assert_response :not_found
    assert Note.active_in(@account.id).exists?(@note.id)
    refute NoteTrashing.exists?(note_id: @note.id)
  end

  private
    def revoke_ahead_of_write
      Account.with_connection do |connection|
        queue_request_behind_revocation(connection.raw_connection.backend_pid) { yield }
      end
    end

    def queue_request_behind_revocation(request_pid)
      request_thread = Thread.current
      passed_membership_read, membership_deleted = Array.new(2) { Queue.new }
      remover = Thread.new do
        AccountUser.with_connection do |connection|
          next unless passed_membership_read.pop(timeout: 10)

          AccountUser.transaction do
            AccountUser.find(@membership.id).destroy!
            membership_deleted << connection.raw_connection.backend_pid
            # Don't commit until PostgreSQL confirms the HTTP write is blocked
            # behind our account row lock.
            Timeout.timeout(10) do
              until connection.select_value("SELECT pg_backend_pid() = ANY(pg_blocking_pids(#{request_pid}))")
                Thread.pass
              end
            end
          end
        end
      end

      observed = false
      observer = ->(event) do
        next if observed || Thread.current != request_thread
        next unless event.payload[:sql].include?('FROM "accounts" INNER JOIN "account_users"')

        observed = true
        # Also warm the request's membership query cache before revocation.
        assert @account.account_users.exists?(user_id: @member.id)
        passed_membership_read << true
        removal_pid = membership_deleted.pop(timeout: 10)
        assert removal_pid, "membership removal did not reach its uncommitted delete"
        refute_equal request_pid, removal_pid
      end

      ActiveSupport::Notifications.subscribed(observer, "sql.active_record") { yield }
      assert observed, "request never passed its initial account membership lookup"
      assert remover.join(10), "membership removal did not commit"
      refute AccountUser.exists?(@membership.id)
    ensure
      passed_membership_read&.push(false)
      remover&.kill&.join if remover&.alive?
    end
end
