# Presentation helpers for the account-scoped Notes workspace.
module NotesHelper
  # @return [Boolean] Whether the current page supplies its own Notes header.
  def notes_workspace_page?
    controller_path.start_with?("notes/")
  end

  # @param folder [NoteFolder] An authorized folder.
  # @return [String] The name displayed in the current locale.
  def notes_folder_name(folder)
    folder.general? ? t("nosia.notes.general") : folder.name
  end

  # @param folder [NoteFolder, nil] The folder at the end of the path.
  # @param folders [Hash{Integer => NoteFolder}] Authorized folders indexed by ID.
  # @return [String] The root-to-folder path without loading associations.
  def notes_folder_path(folder, folders)
    names = []
    while folder
      names << notes_folder_name(folder)
      folder = folders[folder.parent_id]
    end
    names.reverse.join(" / ")
  end

  # @param folders [Hash{Integer => NoteFolder}] Authorized destination folders.
  # @param except [NoteFolder, nil] Exclude this folder and its descendants.
  # @return [Array<Array>] Full paths and IDs for a select input.
  def notes_folder_choices(folders, except: nil)
    folders.values.filter_map do |folder|
      next if except && notes_folder_ancestors(folder.id, folders).include?(except.id)

      [ notes_folder_path(folder, folders), folder.id ]
    end.sort_by(&:first)
  end

  # @param id [Integer, nil] The folder to start with.
  # @param folders [Hash{Integer => NoteFolder}] Authorized folders indexed by ID.
  # @return [Array<Integer>] Folder IDs from the selected folder up to its root.
  def notes_folder_ancestors(id, folders)
    ids = []
    while (folder = folders[id])
      ids << id
      id = folder.parent_id
    end
    ids
  end

  # @param note [Note] An authorized note.
  # @return [String] The saved title or a localized Untitled label.
  def notes_title(note)
    note.title.presence || t("nosia.notes.untitled")
  end

  # @param options [Hash] Authorized workspace filters.
  # @param folder [NoteFolder, nil] The actual folder when the list is not virtual.
  # @param folders [Hash{Integer => NoteFolder}] Authorized folders indexed by ID.
  # @return [String] A heading for the current list.
  def notes_list_heading(options, folder, folders)
    if options[:q]
      t("nosia.notes.search_results")
    elsif options[:tag]
      "##{options[:tag]}"
    elsif folder
      notes_folder_path(folder, folders)
    else
      t("nosia.notes.all_notes")
    end
  end
end
