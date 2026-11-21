# Serializes first saves and edits with the account's other Notes writes.
module Note::Editable
  extend ActiveSupport::Concern

  UUID_SHAPE = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
  CONTENT_ATTRIBUTES = %w[title body_html body_text content_revision content_updated_at].freeze

  included do
    validate :content_written_through_revision
    validate :meaningful_initial_content, if: :new_record?
  end

  class_methods do
    # Saves a new draft or returns its unchanged initial revision on a matching retry.
    # @param account [Account] Owner of the note.
    # @param folder [NoteFolder] Active destination in that account.
    # @param draft_key [String] Client-generated UUID.
    # @param title [String] Submitted title.
    # @param body_html [String] Submitted Lexxy HTML.
    # @return [Note] The saved or previously saved note.
    # @raise [Note::EditConflict] If the key already represents different or newer content.
    # @raise [Note::Unavailable] If the saved draft is no longer active.
    # @raise [ActiveRecord::RecordInvalid] If the draft inputs are invalid.
    def save_draft!(account:, folder:, draft_key:, title:, body_html:)
      draft = new
      draft.account_id = account.id if account.is_a?(Account) && account.persisted?
      draft.note_folder_id = folder.id if folder.is_a?(NoteFolder) && folder.persisted?
      draft.draft_key = draft_key if draft_key.is_a?(String) && draft_key.ascii_only? && UUID_SHAPE.match?(draft_key)
      %i[account_id note_folder_id draft_key].each { |field| draft.errors.add(field, :invalid) unless draft[field] }
      title, body = Note::Editable.canonical_content(draft, title:, body_html:)

      transaction(requires_new: true) do
        if Account.lock.exists?(id: draft.account_id)
          uncached { save_or_replay(draft, title:, body:) }
        else
          draft.errors.add(:account, :invalid)
          raise ActiveRecord::RecordInvalid, draft
        end
      end
    end

    private
      def save_or_replay(draft, title:, body:)
        account_id = draft.account_id
        existing = find_by(account_id:, draft_key: draft.draft_key)
        raise Note::Unavailable if existing && !active_in(account_id).exists?(id: existing.id)

        unless NoteFolder.active_in(account_id).exists?(id: draft.note_folder_id)
          draft.errors.add(:note_folder, :invalid)
          raise ActiveRecord::RecordInvalid, draft
        end

        if existing
          raise Note::EditConflict unless existing.content_revision == 1 && existing.title == title && existing.body_html == body.html

          existing
        else
          Note::Editable.persist_content(draft, title:, body:)
        end
      end
  end

  # Applies a content change only if the caller still holds the current revision.
  # @param expected_revision [Integer] Last revision seen by the caller.
  # @param title [String] Submitted title.
  # @param body_html [String] Submitted Lexxy HTML.
  # @return [Note] The current note, unchanged for a canonical no-op.
  # @raise [Note::EditConflict] If the revision does not match exactly.
  # @raise [Note::Unavailable] If the note or its folder is no longer active.
  # @raise [ActiveRecord::RecordInvalid] If the supplied content is invalid.
  def edit_content!(expected_revision:, title:, body_html:)
    errors.clear
    title, body = Note::Editable.canonical_content(self, title:, body_html:)

    self.class.transaction(requires_new: true) do
      raise Note::Unavailable unless Account.lock.exists?(id: account_id_in_database)

      self.class.uncached do
        reload
        raise Note::Unavailable unless self.class.active_in(account_id).exists?(id:)
        raise Note::EditConflict unless content_revision.eql?(expected_revision)

        Note::Editable.persist_content(self, title:, body:)
      end
    end
  rescue ActiveRecord::RecordNotFound
    raise Note::Unavailable
  end

  # @api private
  def self.canonical_content(note, title:, body_html:)
    { title:, body_html: }.each do |field, value|
      unless value.is_a?(String) && value.valid_encoding? &&
          (value.encoding == Encoding::UTF_8 || value.ascii_only?) && !value.include?("\0")
        note.errors.add(field, :invalid)
      end
    end
    raise ActiveRecord::RecordInvalid, note if note.errors.any?

    [ title.strip, parse_body(note, body_html) ]
  end

  # @api private
  def self.persist_content(note, title:, body:)
    return note if note.persisted? && note.title == title && note.body_html == body.html

    note.assign_attributes(title:, body_html: body.html, body_text: body.text,
      content_revision: note.content_revision.to_i + 1, content_updated_at: Time.current)
    note.save!(context: :revisioned_content)
    Note::Taggable.sync(note, body.tag_keys)
    note
  end

  def self.parse_body(note, html)
    Note::Body.new(html)
  rescue ArgumentError
    note.errors.add(:body_html, :invalid)
    raise ActiveRecord::RecordInvalid, note
  end
  private_class_method :parse_body

  private
    def content_written_through_revision
      if validation_context != :revisioned_content && (new_record? || (changes_to_save.keys & CONTENT_ATTRIBUTES).any?)
        errors.add(:base, :invalid)
      end
    end

    def meaningful_initial_content
      unless [ title, body_text ].any? { |text| text&.match?(/[^\p{Space}\p{Cc}\p{Cf}]/u) }
        errors.add(:base, :blank)
      end
    end
end
