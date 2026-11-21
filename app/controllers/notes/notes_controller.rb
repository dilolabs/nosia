# Renders the Notes editor and handles revisioned form submissions and autosaves.
class Notes::NotesController < ApplicationController
  include NotesWorkspaceRendering
  rescue_from ActiveRecord::RecordNotFound, with: :render_missing_note

  def new
    @note = @account.notes.build(draft_key: SecureRandom.uuid, note_folder_id: real_folder_id)
    @form_seed_tag = list_options[:tag]
    @form_body_html = view_context.tag.p("##{@form_seed_tag}") if @form_seed_tag
    render_workspace(screen: "editor")
  end

  def create
    @note = with_notes_write do
      list_options
      @form_seed_tag = draft_seed_tag
      reject_untouched_tag_seed
      folder = real_folder_id ? folder_for_change(real_folder_id.to_s) : @account.general_note_folder
      save_draft(folder)
    end
    respond_to_save(status: @note.previously_new_record? ? :created : :ok)
  rescue ActiveRecord::RecordInvalid => error
    render_note_errors(error.record)
  end

  def show
    @note = active_for_read(active_notes, @account.notes, notes_id(request.path_parameters.fetch(:id)))
    @form_revision = @note.content_revision
    set_note_context
    render_workspace(screen: "editor")
  end

  def update
    with_notes_write do
      @note = @account.notes.find(notes_id(request.path_parameters.fetch(:id)))
      set_note_context
      @form_revision = expected_revision
      @note.edit_content!(expected_revision: @form_revision, **content_params)
    end
    respond_to_save
  rescue ActiveRecord::RecordInvalid => error
    if active_notes.exists?(id: @note.id)
      render_note_errors(error.record)
    else
      render_unavailable
    end
  end

  private
    def save_draft(folder)
      Note.save_draft!(account: @account, folder:, draft_key: note_params[:draft_key], **content_params)
    rescue Note::EditConflict
      @note = active_notes.find_by(draft_key: note_params[:draft_key]) if request.format.json?
      raise
    end

    def respond_to_save(status: :ok)
      respond_to do |format|
        format.html { redirect_to_note(@note) }
        format.json do
          discard_stale_list_filters
          set_note_context
          load_workspace("editor")
          render :saved, status:
        end
      end
    end

    def render_notes_conflict(code)
      if request.format.json?
        with_request_locale do
          if code == "edit_conflict" && @note && active_notes.exists?(id: @note.id)
            discard_stale_list_filters
            set_note_context
            location = account_note_path(@account, @note, **list_options)
          end
          render :save_error, status: :conflict, locals: { code:, message: I18n.t("nosia.notes.#{code}"), location: }
        end
      else
        super
      end
    end

    def render_missing_note(error)
      if request.format.json?
        head :not_found
      else
        raise error
      end
    end

    def filing_note?
      action_name == "create" && !params.key?(:tag)
    end

    def note_params
      @note_params ||= params.expect(note: %i[ title body_html draft_key expected_revision seed_tag ])
    end

    def content_params
      { title: note_params[:title], body_html: note_params[:body_html] }
    end

    def expected_revision
      revision = note_params[:expected_revision].to_s
      revision.to_i if /\A[0-9]{1,19}\z/.match?(revision)
    end

    def set_note_context
      list_options
      # A deep link has no list options. Follow the note's actual folder
      # without treating an inactive parent as a requested filter.
      if @list_options.empty? && active_folders.exists?(id: @note.note_folder_id)
        @list_options = { folder_id: @note.note_folder_id }
      end
    end

    def reject_untouched_tag_seed
      return unless @form_seed_tag && note_params[:title].to_s.blank?

      if submitted_body&.text == "##{@form_seed_tag}"
        draft = @account.notes.build(draft_key: note_params[:draft_key])
        draft.errors.add(:base, :edit_tag_seed, message: I18n.t("nosia.notes.edit_tag_seed"))
        raise ActiveRecord::RecordInvalid, draft
      end
    end

    def draft_seed_tag
      if params.key?(:tag) && !list_options[:q]
        normalized_tag_key
      else
        # A 422 may drop the old tag filter; retain its seed only for comparison
        # with the draft text, never as a filing or navigational parameter.
        key = note_params[:seed_tag]
        key if key.is_a?(String) && key.bytesize <= NoteTag::MAX_KEY_BYTES
      end
    end

    def submitted_body
      value = note_params[:body_html]
      Note::Body.new(value) if value.is_a?(String) && value.valid_encoding?
    rescue ArgumentError
      nil
    end

    def render_note_errors(record)
      respond_to do |format|
        format.html do
          @note = record.is_a?(Note) ? record : note_for_validation_error(record)
          @form_title = note_params[:title].to_s
          @form_body_html = submitted_body&.html
          render_workspace(screen: "editor", status: :unprocessable_entity)
        end
        format.json do
          render :save_error, status: :unprocessable_entity,
            locals: { code: "invalid", message: validation_message_for(record), location: nil }
        end
      end
    end

    def note_for_validation_error(record)
      note = @note || @account.notes.build(draft_key: note_params[:draft_key])
      note.errors.add(:base, validation_message_for(record))
      note
    end

    def validation_message_for(record)
      key = if record.is_a?(NoteTag) && record.errors.of_kind?(:key, :too_long)
        "hashtag_too_long"
      elsif record.errors.of_kind?(:base, :edit_tag_seed)
        "edit_tag_seed"
      else
        "invalid_note"
      end
      I18n.t("nosia.notes.#{key}")
    end
end
