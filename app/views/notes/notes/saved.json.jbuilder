location = account_note_path(@account, @note, **@list_options)
json.id @note.id
json.revision @note.content_revision
json.update_url location
json.location location
json.index_status render(partial: "notes/workspaces/index_status", formats: [ :html ], locals: { account: @account, note: @note })
json.workspace do
  json.set! "notes-list", render(partial: "notes/workspaces/list", formats: [ :html ], locals: {
    account: @account, notes: @notes, options: @list_options, folder: @selected_folder, folders: @active_folder_map,
    selected_note: @note, page: @page, more: @has_more_notes
  })
  json.set! "notes-sidebar", render(partial: "notes/workspaces/sidebar", formats: [ :html ], locals: {
    account: @account, folders: @active_folder_map, groups: @folder_groups, tags: @tags,
    options: @list_options, selected_folder: @selected_folder
  })
  json.set! "notes-editor-heading", render(partial: "notes/workspaces/editor_heading", formats: [ :html ], locals: {
    account: @account, note: @note, options: @list_options, folders: @active_folder_map
  })
  json.set! "notes-header-actions", render(partial: "notes/workspaces/header_actions", formats: [ :html ], locals: {
    account: @account, options: @list_options, screen: @screen
  })
end
