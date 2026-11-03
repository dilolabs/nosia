require "test_helper"
require "turbo/broadcastable/test_helper"
require_relative "../support/chat_workspace_fixtures"

class PremiumChatHeaderTest < ActionDispatch::IntegrationTest
  include ChatWorkspaceFixtures
  include ActionView::RecordIdentifier
  include Turbo::Broadcastable::TestHelper

  setup { sign_in_picker_user }

  %i[en fr].each do |locale|
    test "premium header retains all information without a table in #{locale}" do
      get chat_path(@chat), headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      assert_select ".n-chat-toolbar h1.n-chat-title", count: 1
      assert_select ".n-chat-toolbar [data-chat-account-label]", count: 0
      assert_select ".n-chat-header [data-chat-account-label]", text: @second.name, count: 1
      assert_select "section#chat-usage-details[aria-labelledby=chat-usage-summary]", count: 1
      assert_select "#chat-usage-details > h2#chat-usage-summary:not([tabindex])", count: 1
      assert_select ".n-chat-header a[href='#{new_chat_path}'], .n-chat-header .n-workspace-actions", count: 0
      assert_select "#chat-history > .n-orbite-navigation-actions > a.n-workspace-button[href='#{new_chat_path}']",
        text: I18n.t("nosia.chat_workspace.new_chat", locale: locale), count: 1
      assert_select "#chat-history > .n-orbite-navigation-actions > #workspace-navigation-close[type=button][data-chat-dialog-initial-focus][data-action='workspace-navigation#close']", count: 1 do |buttons|
        assert_equal I18n.t("nosia.chat_workspace.close", locale: locale), buttons.first["aria-label"]
      end
      assert_select "#chat-history .n-orbite-panel-content .n-orbite-navigation-actions", count: 0
      assert_select ".n-chat-header #workspace-history-trigger, .n-chat-header a[href='#{user_root_path}']", count: 0
      fragment = Nokogiri::HTML.fragment(response.body)
      assert_distribution(fragment, chat: @chat, input: 125, output: 24, locale: locale)
      @chat.token_totals_by_kind.each do |kind, values|
        assert_select fragment, "li[data-usage-kind='#{kind}']" do
          assert_select ".n-chat-token-kind-name", text: I18n.t("nosia.usage.kinds.#{kind}", locale: locale)
          assert_select "[data-usage-input]", text: formatted(values.first, locale)
          assert_select "[data-usage-output]", text: formatted(values.last, locale)
          assert_select "dt", text: I18n.t("nosia.usage.input", locale: locale)
          assert_select "dt", text: I18n.t("nosia.usage.output", locale: locale)
        end
      end
      assert_select "#chat-usage-details [data-estimate-note]", text: I18n.t("nosia.usage.total_fallback_tooltip", locale: locale)
      assert_select "#chat-usage-details [data-chat-impact-estimates]", text: /kWh.*gCO₂e/m
      assert_no_enqueued_jobs only: ChatResponseJob
    end

    test "History top action remains saved chat only in #{locale}" do
      [ new_chat_path(account_id: @second.id), new_chat_path, accounts_path,
        account_path(@second), settings_path ].each do |path|
        get path, headers: { "Accept-Language" => locale.to_s }
        assert_response :success
        assert_select "#chat-history > .n-orbite-navigation-actions", count: 1 do
          assert_select "a", count: 0
          assert_select "#workspace-navigation-close[data-chat-dialog-initial-focus][data-action='workspace-navigation#close']", count: 1
        end
      end
      assert_no_enqueued_jobs only: ChatResponseJob
    end

    { zero: [ 0, 0 ], input_only: [ 17, 0 ], output_only: [ 0, 19 ], large: [ 1_234_567_890, 987_654_321 ] }.each do |state, values|
      test "#{locale} premium #{state} summary uses exact cached counts" do
        chat = workspace(:chats, :workspace_first_chat)
        assert_empty chat.token_usages
        chat.update_columns(input_tokens_count: 0, output_tokens_count: 0)
        input, output = values
        if input.positive? || output.positive?
          TokenUsage.create!(account: @first, chat: chat, kind: :completion,
            model_id: "picker-test-model", input_tokens: input, output_tokens: output)
        end
        chat.reload
        before = [ chat.input_tokens_count, chat.output_tokens_count, chat.token_usages.count ]
        fragment = I18n.with_locale(locale) do
          Nokogiri::HTML.fragment(ApplicationController.render(partial: "chats/token_totals", locals: { chat: chat }))
        end
        assert_distribution(fragment, chat: chat, input: input, output: output, locale: locale)
        assert_equal before, [ chat.reload.input_tokens_count, chat.output_tokens_count, chat.token_usages.count ]
        if state == :zero
          assert_select fragment, ".n-chat-token-caption", text: I18n.t("nosia.usage.none", locale: locale)
          assert_select fragment, "li[data-usage-kind]", count: 0
          assert_select fragment, "[data-estimate-note]", text: I18n.t("nosia.usage.total_tooltip", locale: locale)
        end
        assert_no_enqueued_jobs only: ChatResponseJob
      end
    end

    test "#{locale} actual totals replacement updates counts and distribution together" do
      Current.reset
      streams = nil
      foreign = capture_turbo_stream_broadcasts([ chats(:picker_foreign_chat), :token_totals, locale ]) do
        streams = capture_turbo_stream_broadcasts([ @chat, :token_totals, locale ]) do
          TokenUsage.create!(account: @second, chat_id: @chat.id, kind: :agent_skill,
            model_id: "picker-test-model", input_tokens: 2, output_tokens: 3)
        end
      end
      assert_empty foreign
      replacement = streams.find { |stream| stream["target"] == dom_id(@chat, :token_totals) }
      assert replacement
      assert_equal "replace", replacement["action"]
      assert_distribution(replacement.at_css("template"), chat: @chat, input: 127, output: 27, locale: locale)
      assert_select replacement.at_css("template"), "li[data-usage-kind=agent_skill] [data-usage-input]", text: "2"
      assert_select replacement.at_css("template"), "li[data-usage-kind=agent_skill] [data-usage-output]", text: "3"
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  private
    def formatted(value, locale)
      I18n.with_locale(locale) { ApplicationController.helpers.number_with_delimiter(value) }
    end

    def assert_distribution(fragment, chat:, input:, output:, locale:)
      root = "##{dom_id(chat, :token_totals)}"
      assert_select fragment, root, count: 1
      assert_select fragment, "#{root} [data-chat-total-input]", text: formatted(input, locale)
      assert_select fragment, "#{root} [data-chat-total-output]", text: formatted(output, locale)
      assert_select fragment, "#{root} [data-chat-total-tokens]", text: formatted(input + output, locale)
      assert_select fragment, "#{root} [data-chat-token-bar][aria-hidden=true][data-empty='#{(input + output).zero?}']", count: 1
      { input: input, output: output }.each do |part, count|
        selector = "#{root} [data-chat-token-part='#{part}']"
        assert_select fragment, selector, count: count.positive? ? 1 : 0
        if count.positive?
          assert_equal "flex-grow: #{count}", fragment.at_css(selector)["style"]
        end
      end
      assert_select fragment, "#{root} table, #{root} details, #{root} summary, #{root} [hidden], #{root} [role=progressbar], #{root} canvas", count: 0
      assert_select fragment, "#{root} [data-chat-token-bar] [tabindex], #{root} [data-chat-token-bar] a, #{root} [data-chat-token-bar] button", count: 0
      assert_select fragment, "#{root} [data-estimate-note]", count: 1
    end
end
