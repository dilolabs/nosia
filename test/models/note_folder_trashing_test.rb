require "test_helper"

class NoteFolderTrashingTest < ActiveSupport::TestCase
  self.use_transactional_tests = false
  self.fixture_paths = [ Rails.root.join("test/support/fixtures/chat_accounts") ]
  fixtures :users, :accounts, :note_folders

  setup do
    @account = accounts(:picker_first)
    @folder = note_folders(:sessions)
  end

  teardown do
    if @folder
      accounts.each(&:destroy!)
      users.each(&:destroy!)
    end
  end

  test "direct marker creation holds the move's account lock until commit" do
    NoteFolderTrashing.transaction do
      NoteFolderTrashing.create!(note_folder: @folder)

      assert_account_lock_held
    end

    sibling = note_folders(:reading)
    assert_raises(ActiveRecord::RecordInvalid) { sibling.change_location!(parent: @folder) }
    assert_equal note_folders(:research), sibling.reload.parent
  end

  test "direct marker destruction holds the move's account lock until commit" do
    marker = @folder.create_trashing!

    NoteFolderTrashing.transaction do
      marker.destroy!

      assert_account_lock_held
    end

    assert NoteFolder.active_in(@account.id).exists?(@folder.id)
  end

  test "marker mutations also work under the caller's account lock" do
    @account.with_lock do
      @folder.create_trashing!.destroy!
    end

    assert NoteFolder.active_in(@account.id).exists?(@folder.id)
  end

  test "a marker cannot be reassigned to another folder in the same account" do
    marker = @folder.create_trashing!
    destination = note_folders(:reading)

    error = assert_raises(ActiveRecord::RecordInvalid) { marker.update!(note_folder: destination) }

    assert error.record.errors.added?(:note_folder_id, :invalid)
    assert_equal @folder, marker.reload.note_folder
    active = NoteFolder.active_in(@account.id)
    refute active.exists?(@folder.id)
    assert active.exists?(destination.id)
  end

  test "a marker cannot change accounts even when reassigned to a matching folder" do
    marker = @folder.create_trashing!
    destination = note_folders(:second_team)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      marker.update!(account_id: destination.account_id, note_folder_id: destination.id)
    end

    assert error.record.errors.added?(:account_id, :invalid)
    assert_equal @account, marker.reload.account
    assert_equal @folder, marker.note_folder
  end

  test "destroying a dirty marker locks its original account without touching the foreign folder" do
    marker = @folder.create_trashing!
    destination = note_folders(:private)
    timestamp = Time.utc(2020, 1, 1)
    destination.update!(updated_at: timestamp)
    assert_raises(ActiveRecord::RecordInvalid) do
      marker.update!(account: destination.account, note_folder: destination)
    end
    assert_equal destination, marker.note_folder

    NoteFolderTrashing.transaction do
      marker.destroy!

      assert_account_lock_held
    end

    refute NoteFolderTrashing.exists?(marker.id)
    assert_equal timestamp, destination.reload.updated_at
  end

  private
    def assert_account_lock_held
      pool = ApplicationRecord.connection_pool
      connection = pool.checkout
      # The primary connection still owns the transaction. NOWAIT tests contention
      # immediately on an independent session without sleeping or risking a hang.
      assert_raises ActiveRecord::LockWaitTimeout, "the marker did not hold the account row lock" do
        connection.select_value("SELECT id FROM accounts WHERE id = #{connection.quote(@account.id)} FOR UPDATE NOWAIT")
      end
    ensure
      pool.checkin(connection) if connection
    end
end
