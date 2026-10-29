require "test_helper"
require "turbo/broadcastable/test_helper"
require_relative "../support/chat_workspace_fixtures"

class ChatMessageRenderingTest < ActionDispatch::IntegrationTest
  include ChatWorkspaceFixtures
  include ActionView::RecordIdentifier
  include Turbo::Broadcastable::TestHelper

  test "shared workspace usage fixture supplies normalized response tokens without changing counters" do
    message = workspace(:messages, :workspace_answer)

    assert_equal [ 120, 24 ], [ message.tokens.input, message.tokens.output ]
    usage = workspace(:ruby_llm_usages, :workspace_answer_usage)
    assert_instance_of RubyLLM::ActiveRecord::Usage, usage
    assert_equal message, usage.message
    assert_equal @chat, usage.chat
    assert_equal 1, message.ruby_llm_usages.count
    assert_equal "picker-test-model", message.model
    assert_equal [ 125, 24 ], [ @chat.reload.input_tokens_count, @chat.output_tokens_count ]
    assert_equal 2, @chat.token_usages.count
    assert_equal({ "completion" => [ 120, 24 ], "embedding" => [ 5, 0 ] }, @chat.token_totals_by_kind)
  end

  test "message entry point keeps one role wrapper and streaming content target" do
    [ workspace(:messages, :workspace_question), workspace(:messages, :workspace_answer) ].each do |message|
      html = ApplicationController.render(partial: "messages/message", locals: { message: message })
      fragment = Nokogiri::HTML.fragment(html)
      assert_select fragment, "##{dom_id(message, :messages)}", count: 1
      assert_select fragment, ".message-container.n-chat-message[data-created-at='#{message.created_at.iso8601}']", count: 1
      if message.assistant?
        assert_select fragment, "##{dom_id(message, :content)}", count: 1
        assert_select fragment, "h2", text: "Three findings"
        assert_select fragment, "details", minimum: 1
      else
        assert_select fragment, ".n-chat-message--user .n-chat-user-body", count: 1
        assert_includes fragment.text, "What are the key findings"
      end
    end
  end

  test "saved request and streamed render use the same message identities" do
    sign_in_picker_user
    get chat_url(@chat)
    assert_response :success
    assert_select "##{dom_id(@chat, :messages)}", count: 1
    assert_select "##{dom_id(workspace(:messages, :workspace_answer), :content)}", count: 1
    assert_select "turbo-frame[id='#{dom_id(@chat)}_message_form']", count: 1
    assert_select "#chat-usage-details > #chat-usage-summary", text: I18n.t("nosia.chat_workspace.usage_details")
    assert_select "#chat-usage-details > ##{dom_id(@chat, :token_totals)}", count: 1
    assert_select "##{dom_id(@chat, :token_totals)} summary", count: 0
  end

  test "finalized assistant discloses reasoning separately from readable response estimates" do
    message = workspace(:messages, :workspace_answer)
    assert message.done?
    assert_equal 120, message.tokens.input
    assert_equal 24, message.tokens.output
    fragment = render_message(message)

    assert_select fragment, ".n-chat-assistant-name", text: I18n.t("nosia.chat.assistant")
    assert_select fragment, ".n-chat-assistant-body", count: 1
    assert_select fragment, "details##{dom_id(message, :reasoning_details)}[data-chat-detail]:not([open])" do
      assert_select "summary##{dom_id(message, :reasoning_summary)}", text: I18n.t("nosia.chat.reasoning")
      assert_select "##{dom_id(message, :reasoning_content)}", text: /Evidence was compared carefully/
      assert_select "details details", count: 0
    end
    assert_select fragment, "details[data-response-details]", count: 1
    assert_select fragment, "details##{dom_id(message, :response_details)}[data-chat-detail]:not([open])" do
      assert_select "summary##{dom_id(message, :response_summary)}", text: I18n.t("nosia.chat_workspace.response_details")
      assert_select ".n-chat-values > div" do |values|
        assert_equal [ "Input 120", "Output 24" ], values.map { |value| value.text.squish }
      end
      energy = GreenIt.energy_kwh(tokens: message.tokens.input + message.tokens.output, model_id: message.model, kind: :completion)
      assert_select "p.n-workspace-help", text: /Environmental impact estimates.*#{Regexp.escape(number_with_precision(energy[:kwh], precision: 6))} kWh.*#{Regexp.escape(number_with_precision(GreenIt.co2e_g(kwh: energy[:kwh]), precision: 2))} gCO₂e/m
      assert energy[:fallback], "The fixture model must exercise the existing fallback estimate"
      assert_select "p[data-estimate-note]:not([hidden])", text: I18n.t("nosia.usage.fallback_note")
    end
  end

  test "pending assistant omits finalized response details even with token counts" do
    message = workspace(:messages, :workspace_answer)
    message.update_columns(done: false)

    fragment = render_message(message)

    assert_select fragment, "details[data-response-details]", count: 0
    assert_select fragment, "##{dom_id(message, :content)}", count: 1
  end

  test "background totals expose counters kind breakdown and qualified estimates without Current" do
    Current.reset
    usages = @chat.token_usages.to_a
    fragment = Nokogiri::HTML.fragment(ApplicationController.render(partial: "chats/token_totals", locals: { chat: @chat }))

    assert_select fragment, "##{dom_id(@chat, :token_totals)}", count: 1
    assert_select fragment, ".n-chat-values dt", text: "Input"
    assert_select fragment, "dd[data-chat-total-input]", text: "125"
    assert_select fragment, ".n-chat-values dt", text: "Output"
    assert_select fragment, "dd[data-chat-total-output]", text: "24"
    assert_select fragment, ".n-chat-table-scroll > table.n-chat-usage-table" do
      assert_select "caption", text: I18n.t("nosia.usage.per_kind")
      assert_select "thead th[scope=col]", count: 3
      @chat.token_totals_by_kind.each do |kind, sums|
        assert_select "tbody tr[data-usage-kind='#{kind}']" do
          assert_select "th[scope=row]", text: I18n.t("nosia.usage.kinds.#{kind}")
          assert_select "td" do |cells|
            assert_equal sums.map { |sum| ApplicationController.helpers.number_with_delimiter(sum) }, cells.map(&:text)
          end
        end
      end
      assert_select "tr[data-usage-kind=completion]", text: /completion\s+120\s+24/
      assert_select "tr[data-usage-kind=embedding]", text: /embedding\s+5\s+0/
    end
    assert_select fragment, "p.n-workspace-help", text: /Environmental impact estimates.*#{Regexp.escape(number_with_precision(usages.sum(&:energy_kwh), precision: 6))} kWh.*#{Regexp.escape(number_with_precision(usages.sum(&:co2e_g), precision: 2))} gCO₂e/m
    assert usages.any?(&:used_fallback?), "The fixture usages must exercise the existing fallback estimate"
    assert_select fragment, "p[data-estimate-note]:not([hidden])", text: I18n.t("nosia.usage.total_fallback_tooltip")
  end

  test "existing error presentation hook keeps a plain retry action outside disclosures" do
    message = workspace(:messages, :workspace_answer)
    message.metadata = message.metadata.merge("original_question" => "Original question")
    refute message.error?
    refute message.retryable?
    fragment = with_singleton_replacement(message, :error?, -> { true }) do
      with_singleton_replacement(message, :retryable?, -> { true }) { render_message(message) }
    end

    assert_select fragment, ".n-chat-assistant-body[role=alert][data-chat-error=true]", count: 1
    assert_select fragment, "[role=alert]", count: 1
    assert_select fragment, "form[action='#{chat_messages_path(message.chat)}'][method=post][data-turbo-frame=_top]" do
      assert_select "button.n-workspace-button.n-workspace-primary", text: I18n.t("nosia.chat_workspace.retry")
      assert_select "input[type=hidden][name='message[content]'][value='Original question']", count: 1
    end
    assert_select fragment, "details form", count: 0
    refute message.error?
    refute message.retryable?
  end

  test "sources only disclose saved account evidence independently of reasoning" do
    width = Chunk.columns_hash.fetch("embedding").limit
    vector = [ 1.0 ] + Array.new(width - 1, 0.0)
    local = insert_picker_chunk(@second, texts(:picker_second_text), "Local <script>alert('unsafe')</script> evidence", vector)
    foreign = insert_picker_chunk(@first, texts(:picker_first_text), "Foreign evidence", vector)
    message = workspace(:messages, :workspace_answer)
    message.update_columns(similar_chunk_ids: [ local.id.to_s, foreign.id.to_s ])

    fragment = render_message(message)

    assert_select fragment, "details##{dom_id(message, :sources)}[data-chat-detail]:not([open])" do
      assert_select "summary##{dom_id(message, :sources_summary)}", text: I18n.t("nosia.chat.sources", count: 1, formatted_count: "1")
      assert_select "##{dom_id(message, :search_content)} a.n-chat-source[href='#{chunk_path(local, chat_id: message.chat_id)}'][target=_blank][rel=noopener]", count: 1 do
        assert_select "span[aria-hidden=true]", text: "1"
        assert_select "p.font-medium", text: local.title
        assert_select "script", count: 0
      end
      assert_select "details details", count: 0
    end
    assert_select fragment, "a[href='#{chunk_path(foreign, chat_id: message.chat_id)}']", count: 0
    refute_includes fragment.text, "Foreign evidence"
    assert_select fragment, "details##{dom_id(message, :reasoning_details)} > summary##{dom_id(message, :reasoning_summary)}", count: 1
    assert_select fragment, "##{dom_id(message, :reasoning_content)}", count: 1
  end

  test "actual update payload does not nest a second message wrapper" do
    message = workspace(:messages, :workspace_answer)
    current = Nokogiri::HTML.fragment(ApplicationController.render(partial: "messages/message", locals: { message: message }))
    message.content = "The updated answer confirms three key findings."
    streams = capture_turbo_stream_broadcasts([ @chat, :messages, :en ]) { message.broadcast_updated }
    update = streams.find { |stream| stream["action"] == "update" && stream["target"] == dom_id(message, :messages) }
    assert update
    current.at_css("##{dom_id(message, :messages)}").inner_html = update.at_css("template").inner_html
    assert_select current, "##{dom_id(message, :messages)}", count: 1
    assert_select current, "##{dom_id(message, :content)}", count: 1
    assert_select current, ".ai-response-content", text: "The updated answer confirms three key findings."
    assert_select current, "h2", text: "Three findings", count: 0
  end

  test "actual role-based creation payload retains its future update target" do
    [ workspace(:messages, :workspace_question), workspace(:messages, :workspace_answer) ].each do |message|
      streams = capture_turbo_stream_broadcasts([ @chat, :messages, :en ]) { message.broadcast_created }
      append = streams.find { |stream| stream["action"] == "append" && stream["target"] == dom_id(@chat, :messages) }
      assert append, "Expected the actual role-based message creation broadcast"
      assert_select append.at_css("template"), "##{dom_id(message, :messages)}.message-container", count: 1
    end
  end

  %i[en fr].each do |locale|
    test "actual #{locale} totals replacement stays inside the stable Usage disclosure" do
      sign_in_picker_user
      get chat_url(@chat), headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      current = Nokogiri::HTML.fragment(response.body)
      Current.reset

      streams = capture_turbo_stream_broadcasts([ @chat, :token_totals, locale ]) do
        TokenUsage.create!(account: @second, chat_id: @chat.id, kind: :completion, input_tokens: 2, output_tokens: 3)
      end
      replacement = streams.find { |stream| stream["target"] == dom_id(@chat, :token_totals) }
      assert replacement
      assert_equal "replace", replacement["action"]
      payload = replacement.at_css("template")
      assert_select payload, "##{dom_id(@chat, :token_totals)}", count: 1
      assert_select payload, "details, summary", count: 0
      assert_select payload, "[data-chat-total-input]", text: "127"
      assert_select payload, "[data-chat-total-output]", text: "27"
      current.at_css("##{dom_id(@chat, :token_totals)}").replace(replacement.at_css("template").inner_html)

      assert_select current, "#chat-usage-details > summary#chat-usage-summary", count: 1, text: I18n.t("nosia.chat_workspace.usage_details", locale: locale)
      assert_select current, "#chat-usage-details > ##{dom_id(@chat, :token_totals)}", count: 1
      assert_select current, "#chat-usage-details [data-chat-total-input]", text: "127"
      assert_select current, "#chat-usage-details [data-chat-total-output]", text: "27"
      assert_select current, "#chat-usage-details caption", text: I18n.t("nosia.usage.per_kind", locale: locale)
    end

    test "#{locale} phase rendering uses known phases with a restrained fallback" do
      %w[preparing indexing searching retrieving generating using_tool thinking unknown].each do |phase|
        expected = phase == "unknown" ? "thinking" : phase
        html = I18n.with_locale(locale) { ApplicationController.render(partial: "messages/thinking_animation", locals: { phase: phase }) }
        fragment = Nokogiri::HTML.fragment(html)
        assert_select fragment, ".n-chat-phase[data-phase='#{expected}']", count: 1 do
          assert_select "span.n-chat-phase-indicator[aria-hidden=true]", count: 1
          assert_select "p.n-chat-phase-title", text: I18n.t("nosia.chat.phases.#{expected}.title", locale: locale)
          assert_select "p.n-workspace-help", text: I18n.t("nosia.chat.phases.#{expected}.subtitle", locale: locale)
        end
        assert_select fragment, "[role=status], [aria-live], svg, .animate-spin", count: 0
      end
    end
  end

  private
    def render_message(message)
      Nokogiri::HTML.fragment(ApplicationController.render(partial: "messages/message", locals: { message: message }))
    end

    def number_with_precision(number, **options)
      ApplicationController.helpers.number_with_precision(number, **options)
    end
end
