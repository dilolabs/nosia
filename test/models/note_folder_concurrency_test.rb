require "test_helper"

class NoteFolderConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false
  self.fixture_paths = [ Rails.root.join("test/support/fixtures/chat_accounts") ]
  fixtures :users, :accounts, :note_folders

  setup do
    @account = accounts(:picker_first)
    @source = note_folders(:reading)
    @destination = note_folders(:sessions)
  end

  teardown do
    if @account
      Account.where(id: accounts.map(&:id)).destroy_all
      User.where(id: users.map(&:id)).destroy_all
    end
  end

  test "save checks committed ancestry even after validation cached the old branch" do
    @source.parent = @destination

    NoteFolder.cache do
      assert @source.valid?
      branch = NoteFolder.branch_in(@account.id, root_id: @source.id)
      refute branch.exists?(id: @destination.id)

      in_another_session do
        NoteFolder.find(@destination.id).update!(parent_id: @source.id)
      end

      refute branch.exists?(id: @destination.id), "the primary connection still has the old branch cached"
      assert_raises(ActiveRecord::RecordInvalid) { @source.save! }
    end

    assert_equal note_folders(:research), @source.reload.parent
    assert_equal @source, @destination.reload.parent
  end

  test "save checks committed trash markers even after validation cached the active tree" do
    @source.parent = @destination

    NoteFolder.cache do
      assert @source.valid?
      active = NoteFolder.active_in(@account.id)
      assert active.exists?(id: @destination.id)

      in_another_session do
        NoteFolderTrashing.create!(note_folder: NoteFolder.find(@destination.id))
      end

      assert active.exists?(id: @destination.id), "the primary connection still has the old tree cached"
      assert_raises(ActiveRecord::RecordInvalid) { @source.save! }
    end

    assert_equal note_folders(:research), @source.reload.parent
  end

  test "account destruction cleans up folders added after its collection was loaded" do
    marker = nil

    NoteFolder.cache do
      @account.note_folders.load
      marker = in_another_session do
        folder = NoteFolder.create!(account_id: @account.id, name: "Committed later")
        folder.create_trashing!
      end

      @account.destroy!
    end

    refute NoteFolder.exists?(marker.note_folder_id)
    refute NoteFolderTrashing.exists?(marker.id)
  ensure
    if marker
      NoteFolderTrashing.where(id: marker.id).delete_all
      NoteFolder.where(id: marker.note_folder_id).delete_all
    end
  end

  private
    def in_another_session(&block)
      worker = Thread.new { ApplicationRecord.with_connection { block.call } }
      assert worker.join(5), "the second database session did not finish"
      worker.value
    ensure
      if worker&.alive?
        worker.kill
        worker.join(5)
      end
    end
end
