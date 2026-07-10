require "test_helper"
require "active_job/test_helper"
require "turbo/broadcastable/test_helper"

class MessageTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper  # pulls in ActionCable::TestHelper + Turbo::Streams::StreamName
  include ActionView::RecordIdentifier      # for dom_id in the target assertion

  def setup
    @user = User.create!(email: "mt@example.com", password: "testpassword123")
    @account = Account.create!(name: "MT Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    @chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
  end

  def teardown
    ActsAsTenant.current_tenant = nil
    ActiveJob::Base.queue_adapter = @original_queue_adapter
  end

  test "attached_websites and attached_documents resolve ids to records" do
    w = @account.websites.create!(url: "https://a.example")
    d = @account.documents.new
    d.file.attach(io: StringIO.new("x"), filename: "d.pdf", content_type: "application/pdf")
    d.save!

    message = @chat.messages.create!(role: "user", content: "hi",
      attached_website_ids: [ w.id ], attached_document_ids: [ d.id ])

    assert_equal [ w ], message.attached_websites
    assert_equal [ d ], message.attached_documents
  end

  test "attached ids default to empty arrays" do
    message = @chat.messages.create!(role: "user", content: "hi")
    assert_equal [], message.attached_website_ids
    assert_equal [], message.attached_document_ids
  end

  # Lexxy emits lexxy:insert-link only on paste, so a TYPED url never goes
  # through /chat_sources. attach_website_sources_from_content! is the
  # server-side path that turns http(s) urls in the message body into crawled
  # Website sources so the indexing gate waits on them.
  test "attach_website_sources_from_content! creates a Website for a typed url and enqueues the crawl" do
    message = @chat.messages.create!(role: "user", content: "see https://typed.example/page")

    assert_enqueued_with(job: CrawlWebsiteUrlJob) do
      message.attach_website_sources_from_content!(@account)
    end

    website = @account.websites.find_by!(url: "https://typed.example/page")
    assert website.pending?
    assert_includes message.reload.attached_website_ids, website.id.to_s
  end

  test "attach_website_sources_from_content! dedupes urls and ids within one message" do
    message = @chat.messages.create!(role: "user",
      content: "https://dup.example and https://dup.example plus https://other.example")

    assert_enqueued_jobs(2, only: CrawlWebsiteUrlJob) do
      message.attach_website_sources_from_content!(@account)
    end

    urls = @account.websites.pluck(:url).sort
    assert_equal [ "https://dup.example", "https://other.example" ], urls
    assert_equal 2, message.reload.attached_website_ids.uniq.size
  end

  test "attach_website_sources_from_content! strips trailing sentence punctuation from a url" do
    message = @chat.messages.create!(role: "user", content: "look at https://punct.example/path.")

    message.attach_website_sources_from_content!(@account)

    assert @account.websites.exists?(url: "https://punct.example/path")
    refute @account.websites.exists?(url: "https://punct.example/path.")
  end

  test "attach_website_sources_from_content! does not duplicate or re-crawl an already-attached url" do
    existing = @account.websites.create!(url: "https://already.example", index_status: :indexed)
    message = @chat.messages.create!(role: "user", content: "https://already.example",
      attached_website_ids: [ existing.id ])

    assert_no_enqueued_jobs(only: CrawlWebsiteUrlJob) do
      message.attach_website_sources_from_content!(@account)
    end

    assert_equal [ existing.id.to_s ], message.reload.attached_website_ids
  end

  test "attach_website_sources_from_content! is a no-op when the message has no url" do
    message = @chat.messages.create!(role: "user", content: "just a plain question")

    assert_no_enqueued_jobs(only: CrawlWebsiteUrlJob) do
      message.attach_website_sources_from_content!(@account)
    end

    assert_empty message.reload.attached_website_ids
    assert_equal 0, @account.websites.count
  end

  test "render_markdown_content renders markdown to HTML" do
    html = Message.render_markdown_content("# Title\n\n**bold**")
    assert_includes html, "<h1"
    assert_includes html, "<strong>"
  end

  test "render_markdown_content strips think tags" do
    # Build the think tag in pieces so the literal survives in this plan file
    # uncorrupted. Without Nokogiri's think-tag removal, Commonmarker keeps
    # "secret" as text (raw-HTML-omitted comments around it), so the
    # assert_not_includes "secret" genuinely tests the removal path -- not
    # Commonmarker's raw-HTML omission.
    think = "<th" + "ink>secret</th" + "ink>"   # => a think element wrapping "secret"
    html = Message.render_markdown_content("#{think} visible **text**")
    assert_not_includes html, "secret"
    assert_includes html, "visible"
    assert_includes html, "<strong>"
  end

  test "render_markdown_content returns nil for blank input" do
    assert_nil Message.render_markdown_content(nil)
    assert_nil Message.render_markdown_content("")
    assert_nil Message.render_markdown_content("   ")
  end

  test "render_markdown_content does not raise on incomplete markdown" do
    assert_nothing_raised do
      Message.render_markdown_content("``` unfinished code fence")
      Message.render_markdown_content("**unclosed bold")
      Message.render_markdown_content("| a | b |\n| --- |")
    end
  end

  test "response_content delegates to render_markdown_content" do
    message = @chat.messages.create!(role: "assistant", content: "# Hi\n\n**x**")
    assert_includes message.response_content, "<h1"
    assert_includes message.response_content, "<strong>"
  end

  test "broadcast_streamed_content broadcasts a replace of the content div with rendered HTML" do
    message = @chat.messages.create!(role: "assistant", content: "")
    streams = capture_turbo_stream_broadcasts([ @chat, "messages" ]) do
      message.broadcast_streamed_content("# Title\n\n**bold**")
    end
    assert_equal 1, streams.size
    replace = streams.first
    assert_equal "replace", replace["action"]
    assert_equal dom_id(message, :content), replace["target"]
    assert_includes replace.inner_html, "<h1"
    assert_includes replace.inner_html, "<strong>"
  end

  test "broadcast_streamed_content is a no-op for non-assistant messages" do
    message = @chat.messages.create!(role: "user", content: "hi")
    # Creating the user message legitimately broadcasts the bubble + thinking
    # animation, so assert specifically that broadcast_streamed_content emits no
    # content-div replace (its only possible broadcast) for a non-assistant message.
    streams = capture_turbo_stream_broadcasts([ @chat, "messages" ]) do
      message.broadcast_streamed_content("anything")
    end
    assert streams.none? { |s| s["target"] == dom_id(message, :content) },
      "broadcast_streamed_content must not emit a content replace for a user message"
  end

  # A prompt sent from one tab must reach every tab open on the same chat. The
  # user bubble is appended to the submitting tab via the create.turbo_stream
  # response, but other tabs only receive it through the [chat, "messages"]
  # broadcast — so creating a user message must broadcast-append it.
  test "creating a user message broadcasts it to the chat stream for other tabs" do
    streams = capture_turbo_stream_broadcasts([ @chat, "messages" ]) do
      @chat.messages.create!(role: "user", content: "hello from tab A")
    end

    append = streams.find { |s| s["action"] == "append" && s["target"] == dom_id(@chat, :messages) }
    assert append, "user message should be broadcast-appended so other tabs receive it"
    assert_includes append.inner_html, "hello from tab A"
  end

  # Other tabs also need the waiting animation so the phase updates (which target
  # thinking_animation_content) have somewhere to land.
  test "creating a user message broadcasts the thinking animation to all tabs" do
    streams = capture_turbo_stream_broadcasts([ @chat, "messages" ]) do
      @chat.messages.create!(role: "user", content: "hi")
    end

    assert streams.any? { |s| s["action"] == "append" && s.inner_html.include?("thinking_animation") },
      "the waiting animation should be broadcast to every subscribed tab"
  end

  # Guards the double-submit / retry dedup: a consecutive duplicate user message
  # (no assistant reply in between) must not be broadcast again.
  test "a consecutive duplicate user message is not broadcast" do
    @chat.messages.create!(role: "user", content: "same question")

    streams = capture_turbo_stream_broadcasts([ @chat, "messages" ]) do
      @chat.messages.create!(role: "user", content: "same question")
    end

    assert streams.none? { |s| s["action"] == "append" && s.inner_html.include?("same question") },
      "a consecutive duplicate user message should not be re-broadcast"
  end
end
