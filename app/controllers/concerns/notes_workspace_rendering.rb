# Builds workspace panes and carries authorized list filters across HTML requests.
module NotesWorkspaceRendering
  extend ActiveSupport::Concern
  include NotesAccountScoped

  PAGE_SIZE = 30
  MAX_PAGE = 1_000
  MAX_QUERY_LENGTH = 200
  LIST_VIEWS = %w[ folders list trash ].freeze

  private
    def list_options
      @list_options ||= begin
        options = list_filters
        # A page number belongs to the list that produced it.
        filter_went_stale = options.empty? && (params.key?(:folder_id) || params.key?(:tag))
        options[:page] = page_number if page_number > 1 && !filter_went_stale
        options[:view] = params[:view] if LIST_VIEWS.include?(params[:view])
        options
      end
    end

    def list_filters
      search = query
      return { q: search } if search.present?

      folder = context_folder if params.key?(:folder_id)
      if params.key?(:tag)
        tag = selected_tag
        tag ? { tag: tag.key } : {}
      elsif folder
        { folder_id: folder.id }
      else
        {}
      end
    end

    def context_folder
      id = notes_id(params[:folder_id])
      if reading_workspace?
        active_for_read(active_folders, @account.note_folders, id)
      elsif filing_note?
        folder_for_change(id)
      else
        # Keep a missing or foreign ID a 404, but drop a known inactive
        # folder when it was only carrying the return path.
        active_folders.find_by(id:).tap { |folder| @account.note_folders.find(id) unless folder }
      end
    end

    def filing_note?
      false
    end

    def selected_tag
      @selected_tag ||= begin
        key = normalized_tag_key
        active_tags.find_by(key:).tap do |tag|
          unless tag
            known_tag = @account.note_tags.exists?(key:)
            raise_inactive_destination(known_tag) if reading_workspace? || !known_tag
          end
        end
      end
    end

    def normalized_tag_key
      key = params[:tag]
      unless key.is_a?(String) && key.bytesize <= NoteTag::MAX_KEY_BYTES + 1 && key.match?(/\A#?[\p{L}\p{N}][\p{L}\p{M}\p{N}_-]*\z/u)
        raise ActiveRecord::RecordNotFound
      end

      key.delete_prefix("#").unicode_normalize(:nfc).downcase(:fold).unicode_normalize(:nfc)
    end

    def reading_workspace?
      request.get? || request.head?
    end

    def active_tags
      links = NoteTagging.where(account_id: @account.id, note_id: active_notes.select(:id))
      @account.note_tags.where(id: links.select(:note_tag_id))
    end

    def query
      value = params[:q]
      value.first(MAX_QUERY_LENGTH).delete("\0").strip if value.is_a?(String)
    end

    def page_number
      value = params[:page]
      value.is_a?(String) ? value.to_i.clamp(1, MAX_PAGE) : 1
    end

    def real_folder_id
      list_options[:folder_id] unless list_options[:q] || list_options[:tag]
    end

    def redirect_to_note(note)
      discard_stale_list_filters
      redirect_to account_note_path(@account, note, **list_options), status: :see_other
    end

    def discard_stale_list_filters
      if (list_options[:tag] && !active_tags.exists?(key: list_options[:tag])) ||
          (list_options[:folder_id] && !filing_note? && !active_folders.exists?(id: list_options[:folder_id]))
        @list_options = list_options.except(:tag, :folder_id, :page)
      end
    end

    def render_workspace(screen: nil, status: :ok, import_id: nil)
      discard_stale_list_filters unless reading_workspace?
      @membership_accounts = Current.user.accounts.order(:name, :id)
      load_workspace(screen || workspace_screen)
      load_import_report(import_id) if import_id && @selected_folder && @screen != "trash"
      render "notes/workspaces/show", formats: [ :html ], status:
    end

    def load_import_report(import_id)
      id = notes_id(import_id)
      @reported_import = @account.note_imports.select(:id, :report).find_by(
        id:, initiator_id: Current.user.id, status: :succeeded, root_note_folder_id: @selected_folder.id
      )
      no_store if @reported_import
    rescue ActiveRecord::RecordNotFound
      # An optional receipt id does not change access to the shared folder.
    end

    def load_workspace(screen)
      @active_folder_map = active_folders.order(:name, :id).index_by(&:id)
      @folder_groups = @active_folder_map.values.group_by(&:parent_id)
      @tags = active_tags.order(:key, :id)
      @screen = screen
      @selected_folder = @active_folder_map[real_folder_id]

      if @screen == "trash"
        load_trash
      else
        load_note_list
      end
    end

    def workspace_screen
      return "trash" if list_options[:view] == "trash"
      return "folders" if list_options[:view] == "folders" || list_options.empty?

      "list"
    end

    def load_note_list
      @page = list_options.fetch(:page, 1)
      relation = list_for_context.order(content_updated_at: :desc, id: :desc).preload(:pin)
      rows = relation.offset((@page - 1) * PAGE_SIZE).limit(PAGE_SIZE + 1).to_a
      @has_more_notes = rows.size > PAGE_SIZE && @page < MAX_PAGE
      @notes = rows.first(PAGE_SIZE)
    end

    def list_for_context
      if list_options[:q]
        active_notes.search_literal(list_options[:q])
      elsif list_options[:tag]
        links = NoteTagging.where(account_id: @account.id, note_tag_id: selected_tag.id)
        active_notes.where(id: links.select(:note_id))
      elsif real_folder_id
        active_notes.where(note_folder_id: real_folder_id).left_joins(:pin).order(Arel.sql("note_pins.id IS NULL"))
      else
        active_notes
      end
    end

    def load_trash
      @trash_folder_map = @account.note_folders.order(:name, :id).index_by(&:id)
      @trash_folders = @trash_folder_map.except(*@active_folder_map.keys).values.group_by(&:parent_id)
      @direct_folder_ids = NoteFolderTrashing.where(account_id: @account.id).pluck(:note_folder_id).to_set
      @direct_note_ids = NoteTrashing.where(account_id: @account.id).pluck(:note_id).to_set
      trashed = @account.notes.where(note_folder_id: @trash_folders.values.flatten.map(&:id))
        .or(@account.notes.where(id: @direct_note_ids.to_a))
      @trash_notes = trashed.order(content_updated_at: :desc, id: :desc).group_by(&:note_folder_id)
    end
end
