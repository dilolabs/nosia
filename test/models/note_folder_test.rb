require "test_helper"
require_relative "../support/chat_account_fixtures"

class NoteFolderTest < ActiveSupport::TestCase
  include ChatAccountFixtures

  setup do
    @folder_fixtures = ActiveRecord::FixtureSet.create_fixtures(
      Rails.root.join("test/support/fixtures/chat_accounts").to_s, %w[note_folders]
    ).first.fixtures
  end

  test "a descendant cannot become its ancestor's new parent" do
    root = folder(:research)
    child = folder(:sessions)
    leaf = folder(:interviews)

    error = assert_raises(ActiveRecord::RecordInvalid) { root.change_location!(parent: leaf) }
    assert error.record.errors.added?(:parent, :invalid)
    assert_nil root.reload.parent_id
    assert_equal [ root.id, child.id, leaf.id ].sort, NoteFolder.active_in(@first.id).where(id: [ root, child, leaf ]).ids.sort
  end

  test "a folder cannot become its own parent" do
    root = @first.note_folders.create!(name: "Research")

    assert_raises(ActiveRecord::RecordInvalid) { root.change_location!(parent: root) }
    assert_nil root.reload.parent_id
  end

  test "a regular update cannot bypass the cycle check" do
    root = folder(:research)

    assert_raises(ActiveRecord::RecordInvalid) { root.update!(parent_id: folder(:interviews).id) }
    assert_nil root.reload.parent_id
  end

  test "a foreign folder cannot become the parent by association or ID" do
    root = folder(:research)
    foreign = folder(:private)

    assert_raises(ActiveRecord::RecordInvalid) { @first.note_folders.create!(name: "Foreign child", parent: foreign) }
    assert_raises(ActiveRecord::RecordInvalid) { root.update!(parent_id: foreign.id) }
    assert_raises(ActiveRecord::RecordInvalid) { root.change_location!(parent: foreign) }
    assert_nil root.reload.parent_id
  end

  test "a folder cannot change accounts" do
    root = folder(:research)

    assert_raises(ActiveRecord::RecordInvalid) { root.update!(account: @second) }
    assert_equal @first, root.reload.account
  end

  test "active trees are scoped to each account and selectable in a subquery" do
    root = folder(:research)
    child = folder(:sessions)
    leaf = folder(:interviews)
    sibling = folder(:reading)
    second = folder(:second_team)
    foreign = folder(:private)
    active = NoteFolder.active_in(@first.id)

    assert_equal [ root.id, child.id, leaf.id, sibling.id ].sort, NoteFolder.where(id: active.select(:id)).ids.sort
    assert_equal [ child.id, sibling.id ].sort, active.where(parent: root).ids.sort
    assert_equal [ second.id ], NoteFolder.active_in(@second.id).ids
    assert_equal [ foreign.id ], NoteFolder.active_in(@foreign.id).ids
  end

  test "a trash marker hides a branch but leaves its sibling active" do
    root = folder(:research)
    child = folder(:sessions)
    child.create_trashing!

    assert_equal [ root.id, folder(:reading).id ].sort, NoteFolder.active_in(@first.id).ids.sort
    assert_equal [ child.id, folder(:interviews).id ].sort, NoteFolder.branch_in(@first.id, root_id: child.id).ids.sort
    assert_empty NoteFolder.branch_in(@second.id, root_id: child.id)
  end

  test "a folder trash marker belongs to its folder's account" do
    child = folder(:sessions)

    assert_raises(ActiveRecord::RecordInvalid) { child.create_trashing!(account: @foreign) }
    assert_equal @first, child.create_trashing!.account
  end

  test "a move checks that its source and destination are still active" do
    child = folder(:sessions)
    leaf = folder(:interviews)
    sibling = folder(:reading)
    child.create_trashing!

    assert_raises(ActiveRecord::RecordInvalid) { leaf.change_location!(parent: nil) }
    assert_raises(ActiveRecord::RecordInvalid) { sibling.change_location!(parent: leaf) }
    assert_equal child, leaf.reload.parent
    assert_equal folder(:research), sibling.reload.parent
  end

  test "a new folder cannot be created under a hidden parent" do
    folder(:sessions).create_trashing!

    assert_raises(ActiveRecord::RecordInvalid) { @first.note_folders.create!(name: "New", parent: folder(:interviews)) }
  end

  test "a hidden folder cannot be renamed" do
    folder(:sessions).create_trashing!
    leaf = folder(:interviews)

    assert_raises(ActiveRecord::RecordInvalid) { leaf.update!(name: "Calls") }
    assert_equal "Interviews", leaf.reload.name
  end

  test "an active folder can move under another active folder or back to the root" do
    child = folder(:sessions)
    sibling = folder(:reading)

    child.change_location!(parent: sibling)
    assert_equal sibling, child.reload.parent
    child.change_location!(parent: nil)
    assert_nil child.reload.parent_id
    assert_includes NoteFolder.active_in(@first.id), folder(:interviews)
  end

  test "folder names cannot be blank on create or rename" do
    assert_raises(ActiveRecord::RecordInvalid) { @first.note_folders.create!(name: "") }

    root = folder(:research)
    assert_raises(ActiveRecord::RecordInvalid) { root.update!(name: "  ") }
    assert_equal "Research", root.reload.name
  end

  test "an active folder can be renamed" do
    root = folder(:research)
    root.update!(name: "Fieldwork")

    assert_equal "Fieldwork", root.reload.name
  end

  test "General is provisioned lazily once per account" do
    account = Account.create!(name: "New team", owner: @user)
    assert_empty account.note_folders

    assert_difference -> { @first.note_folders.count }, 1 do
      general = @first.general_note_folder
      assert_equal general, @first.general_note_folder
      assert_equal "general", general.system_key
      assert_nil general.parent_id
      assert_includes NoteFolder.active_in(@first.id), general
      assert_not_equal general, @second.general_note_folder
    end
  end

  test "General cannot move or be renamed" do
    general = @first.general_note_folder
    root = folder(:research)

    assert_raises(ActiveRecord::RecordInvalid) { general.change_location!(parent: root) }
    assert_raises(ActiveRecord::RecordInvalid) { general.update!(parent: root) }
    assert_raises(ActiveRecord::RecordInvalid) { general.update!(name: "Other") }
    assert_raises(ActiveRecord::RecordInvalid) { general.update!(system_key: nil) }
    assert_equal general, @first.general_note_folder
  end

  private
    def folder(name)
      @folder_fixtures.fetch(name.to_s).find
    end
end
