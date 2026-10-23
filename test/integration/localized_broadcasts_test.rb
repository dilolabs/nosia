require "test_helper"
require "turbo/broadcastable/test_helper"
require_relative "../support/localization_fixtures"

class LocalizedBroadcastsTest < ActiveSupport::TestCase
  include LocalizationFixtures
  include Turbo::Broadcastable::TestHelper
  include ActionView::RecordIdentifier

  setup do
    @prior_locale = I18n.locale
    I18n.locale = :en
  end

  teardown { I18n.locale = @prior_locale }

  test "one background finish unlocks and refreshes both languages without Current" do
    chat = chats(:picker_second_chat)
    chat.start_generation!
    Current.reset

    streams = capture_languages([ chat, :messages ]) { chat.finish_generation! }

    { en: "Send", fr: "Envoyer" }.each do |locale, label|
      assert_equal %w[replace remove refresh], streams[locale].map { |stream| stream["action"] }
      form = streams[locale].first
      assert_equal "#{dom_id(chat)}_message_form", form["target"]
      assert_equal 1, form.css("button[aria-label='#{label}']:not([disabled])").size
      assert_equal "thinking_animation", streams[locale][1]["target"]
    end
    refute_predicate chat.reload, :generating?
    assert_equal :en, I18n.locale
  end

  test "one English worker phase event renders each subscriber language" do
    streams = capture_languages([ chats(:picker_second_chat), :messages ]) do
      I18n.with_locale(:en) { chats(:picker_second_chat).broadcast_thinking_phase("indexing") }
    end

    { en: "Indexing your attachments", fr: "Indexation de vos pièces jointes" }.each do |locale, text|
      assert_equal 1, streams[locale].size
      assert_equal "update", streams[locale].first["action"]
      assert_equal "thinking_animation_content", streams[locale].first["target"]
      assert_includes streams[locale].first.text, text
    end
    assert_equal :en, I18n.locale
  end

  test "one indexed source event updates its row and all seven badges in both languages" do
    source = texts(:picker_second_text)
    source.update_columns(index_status: :pending, indexed_at: nil)
    Current.reset

    streams = capture_languages([ @second, "sources" ]) { source.mark_indexed! }

    { en: "Indexed", fr: "Indexé" }.each do |locale, label|
      assert_equal 8, streams[locale].size
      assert streams[locale].all? { |stream| stream["action"] == "replace" }
      assert_equal dom_id(source, :source_row), streams[locale].first["target"]
      assert_includes streams[locale].first.text, label
      assert_equal %w[all type-document type-text type-qna type-website status-failed status-pending].map { |key| "source_count_#{key}" }.sort,
        streams[locale].drop(1).map { |stream| stream["target"] }.sort
    end
  end

  test "one source creation fans out to the same four filtered list identities" do
    source = texts(:picker_second_text)
    source.update_columns(index_status: :pending)
    captures = {}
    operation = -> { source.broadcast_source_created }
    %w[all:all all:pending text:all text:pending].reverse_each do |scope|
      inner = operation
      operation = -> { captures[scope] = capture_languages([ @second, "sources", "list:#{scope}" ], &inner) }
    end
    operation.call

    captures.each_value do |streams|
      streams.each_value do |localized|
        assert_equal 1, localized.size
        assert_equal "prepend", localized.first["action"]
        assert_equal "sources_list", localized.first["target"]
        assert_includes localized.first.inner_html, dom_id(source, :source_row)
      end
    end
  end

  test "real operations never publish to the old unqualified streams" do
    chat = chats(:picker_second_chat)
    source = texts(:picker_second_text)
    old_sources = nil
    old_messages = capture_turbo_stream_broadcasts([ chat, :messages ]) do
      old_sources = capture_turbo_stream_broadcasts([ @second, "sources" ]) do
        perform_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) do
          chat.finish_generation!
          chat.touch
          messages(:localized_assistant).broadcast_streamed_content("Shared")
          source.mark_indexed!
        end
      end
    end

    assert_empty old_messages
    assert_empty old_sources
  end

  test "streamed markdown is computed once and shared without changing stored content" do
    message = messages(:localized_assistant)
    original_content = message.content
    render = Message.method(:render_markdown_content)
    renders = 0
    replacement = ->(text) { renders += 1; render.call(text) }
    streams = with_singleton_replacement(Message, :render_markdown_content, replacement) do
      capture_languages([ message.chat, :messages ]) do
        message.broadcast_streamed_content("# Shared\n\n**answer**")
      end
    end

    streams.each_value do |localized|
      assert_equal 1, localized.size
      assert_equal "replace", localized.first["action"]
      assert_equal dom_id(message, :content), localized.first["target"]
      assert_equal "Shared", localized.first.at_css("h1").text
      assert_equal "answer", localized.first.at_css("strong").text
    end
    assert_equal streams[:en].first.inner_html, streams[:fr].first.inner_html
    assert_equal 1, renders
    assert_equal original_content, message.reload.content
  end

  test "automatic chat update jobs render both locales and restore the worker locale" do
    chat = chats(:picker_second_chat)
    Current.reset

    streams = capture_languages([ chat, :messages ]) do
      perform_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) { chat.touch }
    end

    { en: "Created", fr: "Création" }.each do |locale, label|
      assert_equal 1, streams[locale].size
      assert_equal "replace", streams[locale].first["action"]
      assert_equal dom_id(chat), streams[locale].first["target"]
      assert_includes streams[locale].first.text, label
    end
    assert_equal :en, I18n.locale
  end

  test "automatic chat create and destroy preserve their default targets in both locales" do
    chat = chats(:picker_second_chat).dup
    # The stream identity must be known before the create callbacks run.
    chat.id = Chat.maximum(:id) + 1
    streams = capture_languages([ chat, :messages ]) do
      perform_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) { chat.save! }
    end
    streams.each_value do |localized|
      assert_equal 1, localized.size
      assert_equal "append", localized.first["action"]
      assert_equal "chats", localized.first["target"]
    end

    streams = capture_languages([ chat, :messages ]) { chat.destroy! }
    streams.each_value do |localized|
      assert_equal 1, localized.size
      assert_equal "remove", localized.first["action"]
      assert_equal dom_id(chat), localized.first["target"]
    end
  end

  test "deferred lifecycle jobs retain each publishing locale inside a French worker" do
    chat = chats(:picker_second_chat)
    Current.reset
    assert_enqueued_jobs 2, only: Turbo::Streams::ActionBroadcastJob do
      I18n.with_locale(:en) { chat.touch }
    end

    streams = I18n.with_locale(:fr) do
      captured = capture_languages([ chat, :messages ]) do
        perform_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob)
      end
      assert_equal :fr, I18n.locale
      captured
    end

    { en: "Created", fr: "Création" }.each do |locale, label|
      assert_equal 1, streams[locale].size
      assert_equal "replace", streams[locale].first["action"]
      assert_equal dom_id(chat), streams[locale].first["target"]
      assert_includes streams[locale].first.text, label
    end
    assert_equal :en, I18n.locale
  end

  test "a deferred render exception restores the French worker and outer English locale" do
    chat = chats(:picker_second_chat)
    I18n.with_locale(:en) do
      chat.broadcast_localized_to(:replace_later, chat, :messages, partial: "localization_missing_partial")
    end

    I18n.with_locale(:fr) do
      assert_raises ActionView::MissingTemplate do
        perform_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob)
      end
      assert_equal :fr, I18n.locale
    end
    assert_equal :en, I18n.locale
  end

  test "a synchronous render exception restores the public helper caller locale" do
    chat = chats(:picker_second_chat)

    I18n.with_locale(:fr) do
      assert_raises ActionView::MissingTemplate do
        chat.broadcast_localized_to(:replace, chat, :messages,
          target: "synchronous_locale_probe", partial: "messages/nonexistent_locale_probe", locals: { chat: chat })
      end
      assert_equal :fr, I18n.locale
    end
    assert_equal :en, I18n.locale
  end

  test "automatic message lifecycle jobs render both languages with unchanged targets" do
    message = messages(:localized_assistant).dup
    message.content = ""
    chat = message.chat
    streams = capture_languages([ chat, :messages ]) do
      perform_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) { message.save! }
    end
    { en: "Generating", fr: "Génération" }.each do |locale, label|
      automatic = streams[locale].select { |stream| stream["action"] == "append" && stream["target"] == "messages" }
      assert_equal 1, automatic.size
      assert_includes automatic.first.text, label
    end

    streams = capture_languages([ chat, :messages ]) do
      perform_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) { message.touch }
    end
    { en: "Generating", fr: "Génération" }.each do |locale, label|
      automatic = streams[locale].select { |stream| stream["action"] == "replace" }
      assert_equal 1, automatic.size
      assert_equal dom_id(message), automatic.first["target"]
      assert_includes automatic.first.text, label
    end

    streams = capture_languages([ chat, :messages ]) { message.destroy! }
    streams.each_value do |localized|
      assert_equal 1, localized.size
      assert_equal "remove", localized.first["action"]
      assert_equal dom_id(message), localized.first["target"]
    end
    assert_equal :en, I18n.locale
  end

  test "source deletion reaches both languages but not a foreign account" do
    source = texts(:picker_second_text)
    streams = nil
    foreign = capture_languages([ @foreign, "sources" ]) do
      streams = capture_languages([ @second, "sources" ]) { source.destroy! }
    end

    streams.each_value do |localized|
      assert_equal 8, localized.size
      assert_equal "remove", localized.first["action"]
      assert_equal dom_id(source, :source_row), localized.first["target"]
      assert_equal 7, localized.count { |stream| stream["action"] == "replace" }
    end
    foreign.each_value { |localized| assert_empty localized }
  end

  test "a new ledger event updates localized token totals without Current or foreign chat delivery" do
    chat = chats(:picker_second_chat)
    usage = token_usages(:localized_chat_usage).dup
    Current.reset
    streams = nil
    foreign = capture_languages([ chats(:picker_foreign_chat), :token_totals ]) do
      streams = capture_languages([ chat, :token_totals ]) { usage.save! }
    end

    { en: "Tokens", fr: "Jetons" }.each do |locale, label|
      assert_equal 1, streams[locale].size
      assert_equal "replace", streams[locale].first["action"]
      assert_equal dom_id(chat, :token_totals), streams[locale].first["target"]
      assert_includes streams[locale].first.text, label
    end
    assert_includes streams[:en].first.text, "1,234"
    assert_match(/1[\s\u00a0\u202f]234/, streams[:fr].first.text)
    assert_not_includes streams[:fr].first.text, "1,234"
    assert_equal [ 1234, 12 ], chat.reload.attributes.values_at("input_tokens_count", "output_tokens_count")
    foreign.each_value { |localized| assert_empty localized }
    assert_equal :en, I18n.locale
  end

  test "stream coalescing preserves one and four content flushes per locale" do
    chat = chats(:picker_second_chat)
    message = messages(:localized_assistant)
    message.define_singleton_method(:update) { |*| true }
    chat.messages.define_singleton_method(:last) { message }
    stub_chat_for_streaming(chat, chunks: %w[a b c].map { |text| StreamChunk.new(text) })

    { 1000 => 1, 0 => 4 }.each do |interval, count|
      streams = capture_languages([ chat, :messages ]) do
        chat.complete_with_nosia("hi", stream_buffer: Message::StreamBuffer.new(interval: interval))
      end
      streams.each_value do |localized|
        assert_equal count, localized.size
        assert localized.all? { |stream| stream["action"] == "replace" && stream["target"] == dom_id(message, :content) }
      end
    end

    received = []
    streams = capture_languages([ chat, :messages ]) do
      chat.complete_with_nosia("hi") { |chunk| received << chunk.content }
    end
    streams.each_value { |localized| assert_empty localized }
    assert_equal %w[a b c], received
  end

  test "indexing searching retrieving and generating keep their order in both languages" do
    chat = chats(:picker_second_chat)
    message = messages(:localized_assistant)
    message.define_singleton_method(:update) { |*| true }
    chat.messages.define_singleton_method(:last) { message }
    stub_chat_for_streaming(chat, chunks: [])
    chat.singleton_class.remove_method(:similarity_search)
    chat.singleton_class.remove_method(:broadcast_thinking_phase)
    chat.account.chunks.define_singleton_method(:search_by_similarity) { |*| [] }
    source = texts(:picker_second_text)
    source.update_columns(index_status: :indexed)
    attachments = Struct.new(:attached_websites, :attached_documents).new([], [ source ])

    streams = capture_languages([ chat, :messages ]) do
      chat.wait_for_attached_sources!(attachments)
      chat.complete_with_nosia("hi")
    end

    { en: %w[Indexing Searching Retrieving Generating], fr: %w[Indexation Recherche Récupération Génération] }.each do |locale, titles|
      assert_equal 4, streams[locale].size
      assert streams[locale].all? { |stream| stream["action"] == "update" && stream["target"] == "thinking_animation_content" }
      titles.zip(streams[locale]).each { |title, stream| assert_includes stream.text, title }
    end
  end

  test "localized fanout flattens stream parts and preserves Turbo suppression and caller locale" do
    chat = chats(:picker_second_chat)
    streams = capture_languages([ chat, :messages ]) do
      I18n.with_locale(:fr) do
        chat.broadcast_localized_to(:remove, [ [ chat ], :messages ], target: "thinking_animation")
        assert_equal :fr, I18n.locale
      end
    end
    streams.each_value do |localized|
      assert_equal 1, localized.size
      assert_equal "remove", localized.first["action"]
      assert_equal "thinking_animation", localized.first["target"]
    end

    streams = capture_languages([ chat, :messages ]) do
      perform_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) do
        Chat.suppressing_turbo_broadcasts do
          chat.touch
          chat.finish_generation!
        end
      end
    end
    streams.each_value { |localized| assert_empty localized }
    assert_equal :en, I18n.locale
  end

  test "message visibility guards and consecutive duplicates apply to both locales" do
    message = messages(:localized_assistant)
    [ :system, :tool ].each do |role|
      message.role = role
      streams = capture_languages([ message.chat, :messages ]) { message.broadcast_created }
      streams.each_value { |localized| assert_empty localized }
    end
    message.role = :assistant
    message.ruby_llm_tool_calls.create!(tool_call_id: "localized_internal", name: "search", arguments: {})
    streams = capture_languages([ message.chat, :messages ]) { message.broadcast_created }
    streams.each_value { |localized| assert_empty localized }

    chat = chats(:picker_foreign_chat)
    streams = capture_languages([ chat, :messages ]) { chat.messages.create!(role: :user, content: "One prompt") }
    { en: "Preparing", fr: "Préparation" }.each do |locale, label|
      assert_equal 2, streams[locale].size
      assert streams[locale].all? { |stream| stream["action"] == "append" && stream["target"] == dom_id(chat, :messages) }
      assert_includes streams[locale].last.text, label
    end
    streams = capture_languages([ chat, :messages ]) { chat.messages.create!(role: :user, content: "One prompt") }
    streams.each_value { |localized| assert_empty localized }
  end

  test "subscriptions are locale qualified and searched sources omit live prepends" do
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.post "/login", params: { email: @user.email, password: ChatAccountFixtures::PASSWORD }
    assert_equal 302, session.response.status

    %i[en fr].each do |locale|
      session.get "/chats/#{chats(:picker_second_chat).id}", headers: { "Accept-Language" => locale.to_s }
      assert_equal 200, session.response.status
      assert_equal signed_streams([ chats(:picker_second_chat), :messages, locale ], [ chats(:picker_second_chat), :token_totals, locale ]), subscription_names(session.response.body)

      session.get "/sources", params: { type: "text", status: "pending" }, headers: { "Accept-Language" => locale.to_s }
      assert_equal 200, session.response.status
      assert_equal signed_streams([ @first, "sources", locale ], [ @first, "sources", "list:text:pending", locale ]), subscription_names(session.response.body)

      session.get "/sources", params: { type: "text", status: "pending", q: "evidence" }, headers: { "Accept-Language" => locale.to_s }
      assert_equal 200, session.response.status
      assert_equal signed_streams([ @first, "sources", locale ]), subscription_names(session.response.body)
    end
  end

  private
    def capture_languages(parts, &operation)
      french = nil
      english = capture_turbo_stream_broadcasts([ *parts, :en ]) do
        french = capture_turbo_stream_broadcasts([ *parts, :fr ], &operation)
      end
      { en: english, fr: french }
    end

    def signed_streams(*streams)
      streams.map { |parts| Turbo::StreamsChannel.signed_stream_name(parts) }.sort
    end

    def subscription_names(html)
      Nokogiri::HTML.fragment(html).css("turbo-cable-stream-source").map { |node| node["signed-stream-name"] }.sort
    end
end
