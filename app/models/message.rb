class Message < ApplicationRecord
  include ActionView::RecordIdentifier

  acts_as_message
  broadcasts_to ->(message) { [ message.chat, "messages" ] }
  has_many_attached :attachments

  scope :for_user, -> { without_system_prompts.with_content.without_tool_calls }
  scope :without_system_prompts, -> { where.not(role: [ :system, :tool ]) }
  scope :with_content, -> { where("role != 10 OR (role = 10 AND content IS NOT NULL AND content != '')") }
  scope :without_tool_calls, -> {
    left_joins(:tool_calls)
      .where("messages.role != 30 OR tool_calls.id IS NULL")
      .distinct
  }

  enum :role, { system: 0, assistant: 10, user: 20, tool: 30 }

  belongs_to :chat
  belongs_to :model, optional: true
  has_many :tool_calls, dependent: :destroy
  has_many :token_usages, as: :source, dependent: :destroy

  before_create :set_default_role
  before_create :set_response_number
  before_save :normalize_content_to_markdown, if: -> { user? && content.to_s.match?(/<[a-z!]/i) }
  after_create_commit -> { broadcast_created }
  after_update_commit -> { broadcast_updated }

  # Convert composer-submitted HTML to markdown for user messages.
  # PDF action-text-attachment nodes become paperclip markers; URL anchors
  # pass through as markdown links.
  def self.html_to_markdown(html)
    doc = Nokogiri::HTML::DocumentFragment.parse(html)
    doc.css("action-text-attachment[content-type='application/pdf']").each do |node|
      filename = filename_for_attachment(node)
      node.replace(Nokogiri::HTML::DocumentFragment.parse("📎 #{filename}"))
    end
    HtmlToMarkdown.convert(doc.to_html, skip_images: true, autolinks: false).content
  end

  def self.filename_for_attachment(node)
    sgid = node["sgid"]
    return "attachment" unless sgid

    attachable = ActionText::Attachable.from_attachable_sgid(sgid)
    case attachable
    when ActiveStorage::Blob then attachable.filename.to_s
    when Document then attachable.file.filename.to_s
    else
      "attachment"
    end
  rescue
    "attachment"
  end

  # Re-render the full accumulated buffer to HTML and replace the content div.
  # One broadcast per flush (coalesced), formatted markdown instead of raw text.
  def broadcast_streamed_content(text)
    return unless assistant?
    html = self.class.render_markdown_content(text)
    return unless html

    broadcast_replace_to [ chat, "messages" ],
      target: dom_id(self, :content),
      partial: "messages/streaming_content",
      locals: { message: self, content_html: html }
  end

  def broadcast_created
    # Do not broadcast system and tool messages (internal)
    return unless assistant?

    # EN: If it's an assistant message with tool_calls, DO NOT broadcast
    # They are intermediate messages not meant for the user
    if assistant? && tool_calls.exists?
      Rails.logger.info "🚫 Skipping broadcast for intermediate assistant message ##{id} with tool_calls"
      return
    end

    # Prevent broadcasting consecutive duplicate user messages
    # If the last message (excluding this one) is a user message with the same content
    # and there was no assistant message in between, do not broadcast
    if user?
      previous_message = chat.messages.where.not(id: id).order(created_at: :desc).first
      if previous_message&.user? && previous_message.question == question
        # It's a duplicate, do not broadcast
        return
      end
    end

    # If it's an assistant message, remove the thinking animation
    if assistant?
      broadcast_remove_to chat, :messages, target: "thinking_animation"

      previous_message = chat.messages.where.not(id: id).order(created_at: :desc).first
      if previous_message&.assistant? && previous_message.content.blank?
        # Remove the previous empty assistant message
        broadcast_remove_to chat, :messages, target: dom_id(previous_message, :messages)
      end

      if previous_message&.tool?
        # Remove the previous tool message
        broadcast_remove_to chat, :messages, target: dom_id(previous_message, :messages)
      end
    end

    broadcast_append_to chat, :messages, target: dom_id(chat, :messages), locals: { message: self, scroll_to: true }
  end

  def broadcast_updated
    return unless assistant?

    broadcast_update_to chat, :messages, target: dom_id(self, :messages), locals: { message: self, scroll_to: true }
  end

  def content_without_context
    return unless content.present?
    doc = Nokogiri::HTML::DocumentFragment.parse(content)
    return unless doc.present?
    doc.at("context")&.remove
    Commonmarker.to_html(doc.to_html)
  end

  def context
    return unless content.present?
    doc = Nokogiri::HTML::DocumentFragment.parse(content)
    return unless doc.at("content").present?
    Commonmarker.to_html(doc.at("context").to_html)
  end

  def question
    return unless content.present?
    doc = Nokogiri::HTML::DocumentFragment.parse(content)
    return unless doc.present?
    doc.at("context")&.remove
    doc.to_html
  end

  def reasoning_content
    return unless content.present?
    doc = Nokogiri::HTML::DocumentFragment.parse(content)
    return unless doc.at("think").present?
    Commonmarker.to_html(doc.at("think").to_html)
  end

  # Shared markdown→HTML render used by both the streaming flush (which feeds
  # the in-memory buffer) and response_content (which reads persisted content).
  # Strips reasoning (think) tags so streaming output converges exactly to the
  # final render. Lenient on incomplete markdown — does not raise on an open
  # code fence or unclosed emphasis.
  def self.render_markdown_content(text)
    return if text.blank?
    doc = Nokogiri::HTML::DocumentFragment.parse(text)
    return unless doc.present?
    doc.at("think")&.remove
    Commonmarker.to_html(doc.to_html)
  end

  def response_content
    self.class.render_markdown_content(content)
  end

  def similar_authors
    Author.where(id: similar_documents.pluck(:author_id))
  end

  def similar_chunks
    Chunk.where(id: similar_chunk_ids.uniq)
  end

  def similar_documents
    Document.where(id: similar_document_ids.uniq)
  end

  def attached_websites
    Website.where(id: attached_website_ids)
  end

  def attached_documents
    Document.where(id: attached_document_ids)
  end

  # Lexxy emits lexxy:insert-link only when a URL is *pasted*, so a typed URL
  # (or a URL embedded in pasted text) never reaches /chat_sources and would
  # silently stay plain message text — never crawled, never used. Extract
  # http(s) URLs from this user message's content, find-or-create a Website
  # source for each (enqueueing the crawl), and merge their ids into
  # attached_website_ids so Chat#wait_for_attached_sources! waits on them.
  # Idempotent: an already-attached url (e.g. from the paste path) is neither
  # duplicated nor re-crawled. Called explicitly from the chat composer
  # controllers, not a callback — enqueuing a crawl is an external call.
  def attach_website_sources_from_content!(account)
    urls = extract_urls_from_content
    return if urls.empty?

    ids = (attached_website_ids || []).dup
    urls.each do |url|
      website = Website.find_or_create_by_url!(account, url)
      ids << website.id.to_s unless ids.include?(website.id.to_s)
    end

    ids.uniq!
    update!(attached_website_ids: ids) if ids != attached_website_ids
  end

  # Helper to check if it's an error message
  def error?
    false
  end

  # Helper to get the original message for retry
  def retryable?
    false
  end

  private
  def set_default_role
    self.role ||= "user"
  end

  def set_response_number
    self.response_number = Message.where(chat_id: chat_id).count if response_number.blank?
  end

  def normalize_content_to_markdown
    return if content.blank?
    self.content = self.class.html_to_markdown(content)
  end

  # content is markdown by the time this runs (normalize_content_to_markdown
  # fires before_save for user messages). Catch both bare typed URLs and the
  # href of markdown links: excluding ) and ] from the char class keeps the
  # surrounding link syntax out of the captured URL.
  def extract_urls_from_content
    return [] unless content.present?

    content.scan(%r{https?://[^\s<>)\]\}]+})
      .map { |url| url.gsub(/[.,;:!?]+$/, "") }
      .uniq
  end
end
