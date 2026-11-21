# Account-scoped recursive relations for folder visibility and branch traversal.
module NoteFolder::Tree
  extend ActiveSupport::Concern

  class_methods do
    # Finds folders reachable from an active root without crossing a trash marker.
    # @param account_id [Integer] Account whose active tree should be searched.
    # @return [ActiveRecord::Relation] Active folders, composable as a subquery.
    def active_in(account_id)
      folders = unscoped.where(account_id:).where.missing(:trashing)
      roots = folders.where(parent_id: nil)
      descendants = folders.joins("INNER JOIN active_note_folders parent ON parent.id = note_folders.parent_id")

      unscoped.with_recursive(active_note_folders: [ roots, descendants ])
        .from("active_note_folders AS note_folders").where(account_id:)
    end

    # Finds a branch including its root and any trashed descendants.
    # @param account_id [Integer] Account to search.
    # @param root_id [Integer] Root folder of the branch.
    # @return [ActiveRecord::Relation] All folders in the branch.
    def branch_in(account_id, root_id:)
      folders = unscoped.where(account_id:)
      root = folders.where(id: root_id)
      descendants = folders.joins("INNER JOIN note_folder_branch parent ON parent.id = note_folders.parent_id")

      unscoped.with_recursive(note_folder_branch: [ root, descendants ])
        .from("note_folder_branch AS note_folders").where(account_id:)
    end
  end
end
