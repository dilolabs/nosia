require "test_helper"
require "timeout"

class NotesTrashTest < ActiveSupport::TestCase
  self.fixture_paths = [ Rails.root.join("test/support/fixtures/chat_accounts") ]
  fixtures :users, :accounts, :note_folders, :notes

  setup do
    @account = accounts(:picker_first)
    @owner = users(:picker_owner)
    @root = note_folders(:research)
    @child = note_folders(:sessions)
    @leaf = note_folders(:interviews)
    @destination = note_folders(:reading)
    @note = notes(:field_notes)
  end

  test "restoring a branch does not restore independently trashed descendants" do
    retained = draft_in(@child)
    withheld = draft_in(@child)

    withheld.trash
    @leaf.trash
    assert_difference "NoteFolderTrashing.count", 1 do
      assert_no_difference "NoteTrashing.count" do
        @root.trash
      end
    end
    visible = Note.active_in(@account.id).where(id: [ retained.id, withheld.id, @note.id ])
    assert_empty visible
    assert_raises(Note::Unavailable) { withheld.restore }
    assert_raises(ActiveRecord::RecordInvalid) { @leaf.restore }
    assert_no_difference [ "NoteTrashing.count", "NoteFolderTrashing.count" ] do
      withheld.trash
      @leaf.trash
      @root.trash
    end

    @root.restore

    assert_equal [ retained.id ], visible.ids
    assert_equal @root, @child.reload.parent
    assert_equal @child, @leaf.reload.parent
    assert_equal @child, withheld.reload.note_folder
    assert_not NoteFolder.active_in(@account.id).exists?(@leaf.id)
    withheld.restore
    @leaf.restore
    assert_equal [ retained.id, withheld.id, @note.id ].sort, visible.ids.sort
  end

  test "direct note trash is idempotent and restoration keeps its original pin" do
    @note.pin_in_folder
    pin = @note.pin
    @note.trash
    assert_no_difference "NoteTrashing.count" do
      @note.trash
    end
    assert_not Note.active_in(@account.id).exists?(@note.id)
    assert_raises(Note::Unavailable) { @note.unpin }
    assert_raises(Note::Unavailable) { @note.pin_in_folder }
    assert_raises(Note::Unavailable) { @note.move_to(@destination) }

    @note.restore

    assert Note.active_in(@account.id).exists?(@note.id)
    assert_equal @leaf, @note.note_folder
    assert_equal pin, @note.pin
    assert_raises(Note::Unavailable) { @note.restore }
  end

  test "inherited trash is read-only until the branch is restored" do
    @note.pin_in_folder
    pin = @note.pin
    @child.trash

    assert_raises(Note::Unavailable) { @note.trash }
    assert_raises(Note::Unavailable) { @note.restore }
    assert_raises(Note::Unavailable) { @note.purge(by: @owner) }
    assert_raises(Note::Unavailable) { @note.pin_in_folder }
    assert_raises(Note::Unavailable) { @note.unpin }
    assert_raises(Note::Unavailable) { @note.move_to(@destination) }
    assert_raises(Note::Unavailable) { @note.edit_content!(expected_revision: 1, title: "Not saved", body_html: "") }
    assert_raises(ActiveRecord::RecordInvalid) { @note.update!(note_folder: @destination) }
    assert_raises(ActiveRecord::RecordInvalid) { @leaf.trash }
    assert_raises(ActiveRecord::RecordInvalid) { @leaf.restore }
    assert_raises(ActiveRecord::RecordInvalid) { @leaf.purge(by: @owner) }
    assert_raises(ActiveRecord::RecordInvalid) { @leaf.update!(name: "Not renamed") }
    assert_raises(ActiveRecord::RecordInvalid) { @leaf.change_location!(parent: @destination) }

    @child.restore

    assert_equal pin, @note.reload.pin
    assert_equal @leaf, @note.note_folder
    assert_equal @root, @child.reload.parent
  end

  test "the owner can purge a directly trashed note under a trashed ancestor without deleting its sibling" do
    sibling = draft_in(@leaf)
    member = users(:picker_outsider)
    @account.account_users.grant_to(member)
    @note.trash
    @child.trash

    assert_raises(Note::Unavailable) { @note.restore }
    assert_raises(Note::Unavailable) { sibling.purge(by: @owner) }
    assert_raises(Note::PurgeForbidden) { @note.purge(by: member) }

    assert @note.purge(by: @owner).destroyed?
    refute Note.exists?(@note.id)
    assert Note.exists?(sibling.id)
    assert NoteFolderTrashing.exists?(note_folder_id: @child.id)
    @child.restore
    assert Note.active_in(@account.id).exists?(sibling.id)
  end

  test "the owner can purge a directly trashed branch under a trashed ancestor without deleting its sibling" do
    sibling = @account.note_folders.create!(parent: @child, name: "Keep")
    member = users(:picker_outsider)
    @account.account_users.grant_to(member)
    @leaf.trash
    @root.trash

    assert_raises(ActiveRecord::RecordInvalid) { @leaf.restore }
    assert_raises(ActiveRecord::RecordInvalid) { sibling.purge(by: @owner) }
    assert_raises(Note::PurgeForbidden) { @leaf.purge(by: member) }

    assert @leaf.purge(by: @owner).destroyed?
    refute NoteFolder.exists?(@leaf.id)
    refute Note.exists?(@note.id)
    assert NoteFolder.exists?(sibling.id)
    assert NoteFolderTrashing.exists?(note_folder_id: @root.id)
    @root.restore
    assert NoteFolder.active_in(@account.id).exists?(sibling.id)
  end

  test "purge rejects a dirty note ID without deleting either record" do
    outside = draft_in(note_folders(:private))
    sibling = draft_in(@leaf)
    [ @note, outside, sibling ].each(&:trash)

    [ outside, sibling ].each do |other|
      receiver = Note.find(@note.id)
      receiver.id = other.id
      assert_raises(Note::Unavailable) { receiver.purge(by: @owner) }
    end

    assert_equal [ @note.id, outside.id, sibling.id ].sort,
      NoteTrashing.where(note_id: [ @note.id, outside.id, sibling.id ]).pluck(:note_id).sort
    assert_equal 3, Note.where(id: [ @note.id, outside.id, sibling.id ]).count
  end

  test "purge rejects a dirty folder ID without deleting either branch" do
    outside = note_folders(:private)
    [ @leaf, outside, @destination ].each(&:trash)

    [ outside, @destination ].each do |other|
      receiver = NoteFolder.find(@leaf.id)
      receiver.id = other.id
      assert_raises(ActiveRecord::RecordInvalid) { receiver.purge(by: @owner) }
    end

    assert_equal [ @leaf.id, outside.id, @destination.id ].sort,
      NoteFolderTrashing.where(note_folder_id: [ @leaf.id, outside.id, @destination.id ]).pluck(:note_folder_id).sort
    assert_equal 3, NoteFolder.where(id: [ @leaf.id, outside.id, @destination.id ]).count
    assert Note.exists?(@note.id)
  end

  test "a dirty note ID cannot redirect an edit or an ordinary move" do
    outside = notes(:second_team_note)
    receiver = Note.find(@note.id)
    receiver.id = outside.id

    assert_raises(Note::Unavailable) do
      receiver.edit_content!(expected_revision: outside.content_revision, title: "Not saved", body_html: "")
    end
    assert_equal "Research 100%", outside.reload.title

    pinned = draft_in(@leaf).pin_in_folder
    receiver = Note.find(@note.id)
    receiver.id = pinned.id
    assert_raises(ActiveRecord::RecordInvalid) { receiver.update!(note_folder: @destination) }
    assert pinned.reload.pin
    assert_equal @leaf, pinned.note_folder
  end

  test "a dirty folder ID cannot redirect a move" do
    other = note_folders(:private)
    @leaf.id = other.id

    assert_raises(ActiveRecord::RecordInvalid) { @leaf.change_location!(parent: other.account.general_note_folder) }
    assert_nil other.reload.parent_id
  end

  test "purge rejects a persisted row that no longer belongs to the locked account" do
    receiver = @note.trash
    folder = @leaf.trash
    other_account = accounts(:picker_foreign)
    # Model writes reject changing accounts; simulate an out-of-band change.
    Note.where(id: receiver.id).update_all(account_id: other_account.id)
    NoteFolder.where(id: folder.id).update_all(account_id: other_account.id)

    assert_raises(Note::Unavailable) { receiver.purge(by: @owner) }
    assert_raises(ActiveRecord::RecordInvalid) { folder.purge(by: @owner) }
    assert Note.exists?(receiver.id)
    assert NoteFolder.exists?(folder.id)
  end

  test "ordinary destruction does not clean up dependents through a dirty target ID" do
    pinned = draft_in(note_folders(:second_team)).pin_in_folder.trash
    outside = note_folders(:private).trash
    @note.id = pinned.id
    @leaf.id = outside.id

    assert_raises(ActiveRecord::RecordInvalid) { @note.destroy! }
    assert_raises(ActiveRecord::RecordInvalid) { @leaf.destroy! }
    assert pinned.reload.trashing
    assert pinned.pin
    assert outside.reload.trashing
  end

  test "restore does not destroy a marker from a different persisted account" do
    other_account = accounts(:picker_foreign)
    note_marker = @note.trash.trashing
    note_marker.update_columns(account_id: other_account.id)
    assert_raises(Note::Unavailable) { @note.restore }
    assert NoteTrashing.exists?(note_marker.id)

    folder_marker = @leaf.trash.trashing
    folder_marker.update_columns(account_id: other_account.id)
    assert_raises(ActiveRecord::RecordInvalid) { @leaf.restore }
    assert NoteFolderTrashing.exists?(folder_marker.id)
  end

  test "notes and folders expose the trash marker for reading but not for replacement" do
    @note.trash
    @leaf.trash
    @child.trash

    [ @note, @leaf ].each do |target|
      marker = target.trashing
      %i[build_trashing create_trashing create_trashing! trashing=].each do |mutation|
        refute_respond_to target, mutation
      end
      assert_raises(NoMethodError) { target.build_trashing }
      assert_equal marker, target.reload.trashing
    end
  end

  test "association replacement is not dependent cleanup under a trashed ancestor" do
    @note.trash
    @leaf.trash
    @child.trash

    [ @note, @leaf ].each do |target|
      marker = target.trashing
      assert_raises(ActiveRecord::RecordInvalid) { target.association(:trashing).build }
      marker.mark_for_destruction
      assert_raises(ActiveRecord::RecordInvalid) { target.association(:trashing).build }
      assert_equal marker, target.reload.trashing
    end
  end

  test "direct removal cannot restore markers under a trashed ancestor, even with dirty associations" do
    @note.trash
    note_marker = @note.trashing
    @leaf.trash
    folder_marker = @leaf.trashing
    @child.trash

    note_marker.note = draft_in(@destination)
    folder_marker.note_folder = @destination
    assert_raises(ActiveRecord::RecordInvalid) { note_marker.destroy! }
    assert_raises(ActiveRecord::RecordInvalid) { folder_marker.destroy! }

    @child.restore
    assert_equal folder_marker, @leaf.reload.trashing
    assert_equal note_marker, @note.reload.trashing
    @leaf.restore
    refute Note.active_in(@account.id).exists?(@note.id)
    @note.restore
    assert Note.active_in(@account.id).exists?(@note.id)
  end

  test "General remains a permanent root and may contain notes and folders" do
    general = @account.general_note_folder
    general.update!(name: general.name)
    assert_raises(ActiveRecord::RecordInvalid) { general.update!(name: "Renamed") }
    assert_raises(ActiveRecord::RecordInvalid) { general.change_location!(parent: @root) }
    assert_raises(ActiveRecord::RecordInvalid) { general.trash }
    assert_raises(ActiveRecord::RecordInvalid) { general.purge(by: @owner) }

    folder = @account.note_folders.create!(parent: general, name: "Projects")
    note = draft_in(general)

    assert NoteFolder.active_in(@account.id).exists?(folder.id)
    assert Note.active_in(@account.id).exists?(note.id)
    assert_nil general.reload.parent_id
  end

  test "only the owner can purge even if another user is a member" do
    member = users(:picker_outsider)
    @account.account_users.grant_to(member)

    assert_raises(Note::Unavailable) { @note.purge(by: @owner) }
    assert_raises(ActiveRecord::RecordInvalid) { @root.purge(by: @owner) }
    @note.trash
    @root.trash

    assert_raises(Note::PurgeForbidden) { @note.purge(by: member) }
    assert_raises(Note::PurgeForbidden) { @root.purge(by: member) }
    assert_raises(Note::PurgeForbidden) { @note.purge(by: User.new(id: @owner.id)) }
    assert Note.exists?(@note.id)
    assert NoteFolder.exists?(@root.id)
  end

  test "owner purges a direct note and its state records" do
    note = draft_in(@destination, body_html: "<p>#planning</p>")
    note.pin_in_folder
    note.trash

    assert_difference({ "Note.count" => -1, "NotePin.count" => -1, "NoteTrashing.count" => -1, "NoteTagging.count" => -1 }) do
      note.purge(by: @owner)
    end
    assert_not Note.exists?(note.id)
    assert NoteFolder.exists?(@destination.id)
  end

  test "purging a branch destroys direct and inherited descendants without changing other branches" do
    @root.children.load
    covered = draft_in(@leaf, body_html: "<p>#planning</p>")
    direct = draft_in(@child, body_html: "<p>#planning</p>")
    outside = draft_in(@account.general_note_folder)
    [ covered, direct, outside ].each(&:pin_in_folder)
    pins = [ covered.pin.id, direct.pin.id ]
    taggings = NoteTagging.where(note_id: [ covered.id, direct.id ]).ids
    direct.trash
    new_branch = @account.note_folders.create!(parent: @root, name: "Created after preload")
    new_branch.trash
    @child.trash
    @root.trash
    folders = [ @root, @child, @leaf, @destination, new_branch ].map(&:id)

    @root.purge(by: @owner)

    assert_empty NoteFolder.where(id: folders)
    assert_empty NoteFolderTrashing.where(note_folder_id: folders)
    assert_empty Note.where(id: [ covered.id, direct.id, @note.id ])
    assert_empty NoteTrashing.where(note_id: [ covered.id, direct.id ])
    assert_empty NotePin.where(id: pins)
    assert_empty NoteTagging.where(id: taggings)
    assert Note.active_in(@account.id).exists?(outside.id)
    assert outside.reload.pin
    assert NoteFolder.exists?(note_folders(:second_team).id)
  end

  test "pinning and unpinning are idempotent and do not change content recency" do
    assert_difference "NotePin.count", 1 do
      @note.pin_in_folder
      pin = @note.pin
      @note.pin_in_folder
      assert_equal pin, @note.pin
      assert_equal @account, pin.account
    end
    assert_no_changes -> { @note.reload.content_updated_at } do
      assert_difference "NotePin.count", -1 do
        @note.unpin
        @note.unpin
        assert_nil @note.pin
      end
    end
  end

  test "moving to a different folder clears the pin and preserves the revisioned content and tags" do
    note = draft_in(@child, body_html: "<p>#planning</p>")
    saved = note.slice(:id, :title, :body_html, :body_text, :draft_key, :content_revision, :content_updated_at)
    tagging_ids = note.note_taggings.ids
    note.pin_in_folder
    assert_equal note, note.move_to(@child)
    assert note.pin

    assert_difference "NotePin.count", -1 do
      assert_equal note, note.move_to(@destination)
    end

    assert_equal @destination, note.reload.note_folder
    assert_nil note.pin
    assert_equal saved, note.slice(*saved.keys)
    assert_equal tagging_ids, note.note_taggings.ids
    note.pin_in_folder
    assert note.pin
  end

  test "invalid moves leave the existing pin alone" do
    @note.pin_in_folder
    pin = @note.pin
    @destination.trash

    assert_raises(ActiveRecord::RecordNotFound) { @note.move_to(@destination) }
    assert_raises(ActiveRecord::RecordNotFound) { @note.move_to(note_folders(:second_team)) }
    assert_raises(ActiveRecord::RecordNotFound) { @note.move_to(NoteFolder.new(id: @child.id)) }
    assert_raises(ActiveRecord::RecordInvalid) { @note.update!(note_folder: @destination) }
    assert_raises(ActiveRecord::RecordInvalid) { @note.reload.update_attribute!(:note_folder_id, @destination.id) }
    assert_equal pin, @note.reload.pin
    assert_equal @leaf, @note.note_folder
  end

  test "an ordinary reassignment clears a pin even if the pin association was already loaded" do
    assert_nil @note.pin
    pin = Note.find(@note.id).pin_in_folder.pin

    @note.update!(note_folder: @leaf)
    assert NotePin.exists?(pin.id)
    @note.update!(note_folder: @destination)

    assert_not NotePin.exists?(pin.id)
    assert_nil @note.pin
  end

  test "a stale ordinary save to the currently persisted folder keeps its pin" do
    current = Note.find(@note.id).move_to(@destination).pin_in_folder

    @note.update!(note_folder: @destination)

    assert_equal current.pin, @note.reload.pin
  end

  test "a validation-skipping move cannot reassign the note's account" do
    pin = @note.pin_in_folder.pin
    @note.account = accounts(:picker_foreign)

    assert_raises(ActiveRecord::RecordInvalid) { @note.update_attribute!(:note_folder_id, @destination.id) }
    assert_equal @account, @note.reload.account
    assert_equal pin, @note.pin
  end

  test "direct pin writes verify the stored account and cannot reassign a persisted pin" do
    foreign = notes(:second_team_note)
    foreign.account = @account
    assert_raises(ActiveRecord::RecordInvalid) { NotePin.create!(account: @account, note: foreign) }
    pin = NotePin.create!(note: @note)
    assert_raises(ActiveRecord::RecordNotUnique) do
      NotePin.transaction(requires_new: true) { NotePin.create!(note: @note) }
    end
    assert_raises(ActiveRecord::RecordInvalid) { pin.update!(note: draft_in(@leaf)) }
    assert_raises(ActiveRecord::RecordInvalid) do
      pin.update!(account_id: foreign.account_id_in_database, note_id: foreign.id)
    end
    assert_raises(ActiveRecord::RecordInvalid) { pin.save!(validate: false) }
    assert_equal @note, pin.reload.note
  end

  test "direct pin creation cannot pin an inactive note" do
    @child.trash

    assert_raises(ActiveRecord::RecordInvalid) { NotePin.create!(note: @note) }
    assert_raises(ActiveRecord::RecordInvalid) { NotePin.new(note: @note).save!(validate: false) }
  end

  test "direct pin destruction cannot unpin an inactive note" do
    pin = @note.pin_in_folder.pin
    @child.trash

    assert_raises(ActiveRecord::RecordInvalid) { pin.destroy! }
    assert NotePin.exists?(pin.id)
  end

  test "ordinary note destruction cleans up a pin committed after its association was loaded" do
    assert_nil @note.pin
    pin = Note.find(@note.id).pin_in_folder.pin

    @note.destroy!

    assert_not NotePin.exists?(pin.id)
  end

  private
    def draft_in(folder, body_html: "")
      Note.save_draft!(account: folder.account, folder:, draft_key: SecureRandom.uuid, title: "Draft", body_html:)
    end
end

class NotesLifecycleConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false
  self.fixture_paths = [ Rails.root.join("test/support/fixtures/chat_accounts") ]
  fixtures :users, :accounts, :note_folders, :notes

  setup do
    @account = accounts(:picker_first)
    @folder = note_folders(:sessions)
    @note = notes(:field_notes)
  end

  teardown do
    if @account
      Account.where(id: accounts.map(&:id)).destroy_all
      User.where(id: users.map(&:id)).destroy_all
    end
  end

  test "simultaneous opposite folder moves cannot create a cycle" do
    sibling = note_folders(:reading)
    ready = Queue.new
    go = Queue.new
    workers = [ [ @folder.id, sibling.id ], [ sibling.id, @folder.id ] ].map do |source, destination|
      Thread.new do
        ApplicationRecord.with_connection do |connection|
          folder = NoteFolder.find(source)
          parent = NoteFolder.find(destination)
          ready << connection
          go.pop
          folder.change_location!(parent:)
          :moved
        rescue ActiveRecord::RecordInvalid
          :rejected
        end
      end
    end

    connections = Timeout.timeout(5) { [ ready.pop, ready.pop ] }
    refute_same(*connections)
    2.times { go << true }
    workers.each { |worker| assert worker.join(5), "folder move did not finish" }

    assert_equal [ :moved, :rejected ], workers.map(&:value).sort
    assert_equal 1, [ @folder.reload.parent_id == sibling.id, sibling.reload.parent_id == @folder.id ].count(true)
    assert_equal [ @folder.id, sibling.id ].sort, NoteFolder.active_in(@account.id).where(id: [ @folder.id, sibling.id ]).ids.sort
  ensure
    workers&.each do |worker|
      if worker.alive?
        worker.kill
        worker.join(5)
      end
    end
  end

  test "moves ignore cached eligibility and a dirty destination association" do
    destination = note_folders(:reading)
    @note.pin_in_folder
    pin_id = @note.pin.id
    destination.account = accounts(:picker_second)

    Note.cache do
      active = NoteFolder.active_in(@account.id)
      assert active.exists?(destination.id)
      in_another_session { NoteFolder.find(destination.id).trash }
      assert active.exists?(destination.id), "the moving session still has the old visibility cached"
      assert_raises(ActiveRecord::RecordNotFound) { @note.move_to(destination) }
    end

    assert_equal pin_id, @note.reload.pin.id
    assert_equal note_folders(:interviews), @note.note_folder
    assert_equal @account, destination.reload.account
  end

  test "direct marker removal ignores cached parent visibility from before the account lock" do
    @note.trash
    note_marker = @note.trashing
    sibling = note_folders(:reading).trash
    folder_marker = sibling.trashing

    NoteFolder.cache do
      active = NoteFolder.active_in(@account.id)
      assert active.exists?(@note.note_folder_id)
      assert active.exists?(sibling.parent_id)
      in_another_session { NoteFolder.find(sibling.parent_id).trash }
      assert active.exists?(@note.note_folder_id)
      assert active.exists?(sibling.parent_id)

      assert_raises(ActiveRecord::RecordInvalid) { note_marker.destroy! }
      assert_raises(ActiveRecord::RecordInvalid) { folder_marker.destroy! }
    end

    assert NoteTrashing.exists?(note_marker.id)
    assert NoteFolderTrashing.exists?(folder_marker.id)
  end

  test "direct pin creation and dirty removal lock the original account without touching a replacement" do
    pin = nil
    NotePin.transaction do
      pin = NotePin.create!(note: @note)
      assert_account_lock_held
    end

    replacement = notes(:second_team_note)
    timestamp = replacement.updated_at
    pin.assign_attributes(note: replacement, account: replacement.account)

    NotePin.transaction do
      pin.destroy!
      assert_account_lock_held
    end

    assert_not NotePin.exists?(pin.id)
    assert_equal timestamp, replacement.reload.updated_at
  end

  test "purge ignores a cached branch and a previously loaded account still cleans up General and pins" do
    general = @account.general_note_folder
    account_notes = @account.notes.load
    @folder.trash
    ids = nil

    NoteFolder.cache do
      branch = NoteFolder.branch_in(@account.id, root_id: @folder.id)
      expected = branch.ids
      ids = in_another_session do
        account = Account.find(@account.id)
        root = NoteFolder.find(@folder.id)
        root.restore
        child = account.note_folders.create!(parent: root, name: "New descendant")
        note = Note.save_draft!(account:, folder: general, draft_key: SecureRandom.uuid, title: "General note", body_html: "")
        note.pin_in_folder
        root.trash
        { child: child.id, note: note.id, pin: note.pin.id }
      end
      assert_equal expected, branch.ids
      refute_includes account_notes.map(&:id), ids.fetch(:note)
      @folder.purge(by: users(:picker_owner))
    end

    assert_not NoteFolder.exists?(ids.fetch(:child))
    assert NotePin.exists?(ids.fetch(:pin))
    @account.destroy!
    assert_not NoteFolder.exists?(general.id)
    assert_not Note.exists?(ids.fetch(:note))
    assert_not NotePin.exists?(ids.fetch(:pin))
  end

  private
    def assert_account_lock_held
      pool = ApplicationRecord.connection_pool
      connection = pool.checkout
      assert_raises ActiveRecord::LockWaitTimeout do
        connection.select_value("SELECT id FROM accounts WHERE id = #{connection.quote(@account.id)} FOR UPDATE NOWAIT")
      end
    ensure
      pool.checkin(connection) if connection
    end

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
