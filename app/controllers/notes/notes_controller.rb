# Renders the Notes editor and handles explicit revisioned saves.
class Notes::NotesController < ApplicationController
  include NotesWorkspaceRendering

  def new
    list_options
    @note = @account.notes.build(draft_key: SecureRandom.uuid)
    @form_body_html = view_context.tag.p("##{list_options[:tag]}") if list_options[:tag] && !list_options[:q]
    render_workspace(screen: "editor")
  end

  def create
    note = with_notes_write do
      list_options
      @form_seed_tag = draft_seed_tag
      reject_untouched_tag_seed
      folder = real_folder_id ? folder_for_change(real_folder_id.to_s) : @account.general_note_folder
      Note.save_draft!(account: @account, folder:, draft_key: note_params[:draft_key], **content_params)
    end
    redirect_to_note(note)
  rescue ActiveRecord::RecordInvalid => error
    render_note_errors(error.record)
  end

  def show
    @note = active_notes.find(notes_id(request.path_parameters.fetch(:id)))
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
    redirect_to_note(@note)
  rescue ActiveRecord::RecordInvalid => error
    if active_notes.exists?(id: @note.id)
      render_note_errors(error.record)
    else
      render_unavailable
    end
  end

  private
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
        draft.errors.add(:base, I18n.t("nosia.notes.edit_tag_seed"))
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
      @note = record.is_a?(Note) ? record : note_for_validation_error(record)
      @form_title = note_params[:title].to_s
      @form_body_html = submitted_body&.html
      render_workspace(screen: "editor", status: :unprocessable_entity)
    end

    def note_for_validation_error(record)
      note = @note || @account.notes.build(draft_key: note_params[:draft_key])
      message = if record.is_a?(NoteTag) && record.errors.of_kind?(:key, :too_long)
        "hashtag_too_long"
      else
        "invalid_note"
      end
      note.errors.add(:base, I18n.t("nosia.notes.#{message}"))
      note
    end
end
