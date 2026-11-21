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
      Account.where(id: accounts.map(&:id)).destroy_all
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
    marker = NoteFolderTrashing.create!(note_folder: @folder)

    NoteFolderTrashing.transaction do
      marker.destroy!

      assert_account_lock_held
    end

    assert NoteFolder.active_in(@account.id).exists?(@folder.id)
  end

  test "marker mutations also work under the caller's account lock" do
    @account.with_lock do
      NoteFolderTrashing.create!(note_folder: @folder).destroy!
    end

    assert NoteFolder.active_in(@account.id).exists?(@folder.id)
  end

  test "a same-account direct marker cannot hide General" do
    general = @account.general_note_folder

    assert_no_difference "NoteFolderTrashing.count" do
      assert_raises(ActiveRecord::RecordInvalid) do
        NoteFolderTrashing.create!(account: @account, note_folder: general)
      end
    end

    marker = NoteFolderTrashing.create!(account: @account, note_folder: @folder)
    active = NoteFolder.active_in(@account.id)
    assert active.exists?(general.id)
    refute active.exists?(@folder.id)

    @account.destroy!

    refute NoteFolder.exists?(general.id)
    refute NoteFolderTrashing.exists?(marker.id)
  end

  test "a dirty folder instance cannot disguise General from direct marker creation" do
    general = @account.general_note_folder
    general.system_key = nil
    refute general.general?

    error = assert_raises(ActiveRecord::RecordInvalid) { NoteFolderTrashing.create!(note_folder: general) }

    assert error.record.errors.added?(:note_folder, :invalid)
    assert general.reload.general?
    assert NoteFolder.active_in(@account.id).exists?(general.id)
  end

  test "direct creation rechecks persisted General identity even with stale cached reads and skipped validation" do
    root = note_folders(:research)
    marker = NoteFolderTrashing.new(account: @account, note_folder: root)
    worker = nil

    NoteFolder.cache do
      refute NoteFolder.find_by(id: root.id).general?
      assert marker.valid?

      worker = Thread.new do
        ApplicationRecord.with_connection do
          Account.find(@account.id).with_lock do
            # Simulate a persisted system identity unknown to the creating session.
            NoteFolder.find(root.id).update_columns(system_key: NoteFolder::GENERAL_SYSTEM_KEY)
          end
        end
      end
      assert worker.join(5), "the second database session did not finish"
      assert worker.value
      refute NoteFolder.find_by(id: root.id).general?, "the creating session still has the old identity cached"

      assert_raises(ActiveRecord::RecordInvalid) { marker.save!(validate: false) }
    end

    assert root.reload.general?
    assert NoteFolder.active_in(@account.id).exists?(root.id)
  ensure
    if worker&.alive?
      worker.kill
      worker.join(5)
    end
  end

  test "a persisted marker cannot be reassigned to General even if validation is skipped" do
    marker = NoteFolderTrashing.create!(note_folder: @folder)
    general = @account.general_note_folder
    marker.note_folder = general

    assert_raises(ActiveRecord::RecordInvalid) { marker.save!(validate: false) }

    assert_equal @folder, marker.reload.note_folder
    assert NoteFolder.active_in(@account.id).exists?(general.id)
  end

  test "a marker cannot be reassigned to another folder in the same account" do
    marker = NoteFolderTrashing.create!(note_folder: @folder)
    destination = note_folders(:reading)

    error = assert_raises(ActiveRecord::RecordInvalid) { marker.update!(note_folder: destination) }

    assert error.record.errors.added?(:note_folder_id, :invalid)
    assert_equal @folder, marker.reload.note_folder
    active = NoteFolder.active_in(@account.id)
    refute active.exists?(@folder.id)
    assert active.exists?(destination.id)
  end

  test "a marker cannot change accounts even when reassigned to a matching folder" do
    marker = NoteFolderTrashing.create!(note_folder: @folder)
    destination = note_folders(:second_team)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      marker.update!(account_id: destination.account_id, note_folder_id: destination.id)
    end

    assert error.record.errors.added?(:account_id, :invalid)
    assert_equal @account, marker.reload.account
    assert_equal @folder, marker.note_folder
  end

  test "destroying a dirty marker locks its original account without touching the foreign folder" do
    marker = NoteFolderTrashing.create!(note_folder: @folder)
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
