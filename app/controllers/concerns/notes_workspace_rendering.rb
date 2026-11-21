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
        options = {}
        if (search = query).present?
          options[:q] = search
        else
          options[:folder_id] = context_folder.id if params.key?(:folder_id)
          options[:tag] = selected_tag.key if params.key?(:tag)
        end
        options[:page] = page_number if page_number > 1
        options[:view] = params[:view] if LIST_VIEWS.include?(params[:view])
        options
      end
    end

    def context_folder
      if reading_workspace?
        active_folders.find(notes_id(params[:folder_id]))
      else
        folder_for_change(params[:folder_id])
      end
    end

    def selected_tag
      @selected_tag ||= begin
        key = normalized_tag_key
        active_tags.find_by(key:) || unavailable_tag(key)
      end
    end

    def normalized_tag_key
      key = params[:tag]
      unless key.is_a?(String) && key.bytesize <= NoteTag::MAX_KEY_BYTES + 1 && key.match?(/\A#?[\p{L}\p{N}][\p{L}\p{M}\p{N}_-]*\z/u)
        raise ActiveRecord::RecordNotFound
      end

      key.delete_prefix("#").unicode_normalize(:nfc).downcase(:fold).unicode_normalize(:nfc)
    end

    def unavailable_tag(key)
      raise ActiveRecord::RecordNotFound if reading_workspace? || !@account.note_tags.exists?(key:)

      raise Note::Unavailable
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
      options = list_options
      if options[:tag] && !active_tags.exists?(key: options[:tag])
        options = options.except(:tag, :page)
      end
      redirect_to account_note_path(@account, note, **options), status: :see_other
    end

    def render_workspace(screen: nil, status: :ok)
      @membership_accounts = Current.user.accounts.order(:name, :id)
      @active_folder_map = active_folders.order(:name, :id).index_by(&:id)
      @folder_groups = @active_folder_map.values.group_by(&:parent_id)
      @tags = active_tags.order(:key, :id)
      @screen = screen || workspace_screen
      @selected_folder = @active_folder_map[real_folder_id]

      if @screen == "trash"
        load_trash
      else
        load_note_list
      end

      render "notes/workspaces/show", formats: [ :html ], status:
    end

    def workspace_screen
      return "trash" if list_options[:view] == "trash"
      return "folders" if list_options[:view] == "folders" || list_options.empty?

      "list"
    end

    def load_note_list
      relation = list_for_context.order(content_updated_at: :desc, id: :desc).preload(:pin)
      rows = relation.offset((page_number - 1) * PAGE_SIZE).limit(PAGE_SIZE + 1).to_a
      @has_more_notes = rows.size > PAGE_SIZE && page_number < MAX_PAGE
      @notes = rows.first(PAGE_SIZE)
      @page = page_number
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
