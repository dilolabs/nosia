require "test_helper"

class TokenFooterTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(email: "tf@example.com", password: "testpassword123")
    @account = Account.create!(name: "TF Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "footer discloses token counts and gCO₂e for a done assistant message" do
    msg = assistant_with_usage(model: "glm-5.2", input_tokens: 1240, output_tokens: 320, cache_read_tokens: 999, cache_write_tokens: 500)
    html = ApplicationController.render(partial: "messages/token_footer", locals: { message: msg })
    fragment = Nokogiri::HTML.fragment(html)

    assert_response_details fragment
    assert_token_values fragment, input: "1,240", output: "320"
    assert_select fragment, "p.n-workspace-help", text: /\d+\.\d{2} gCO₂e/
    assert_select fragment, "[data-estimate-note]", count: 0
    assert_includes html, "0.006388 kWh" # 1,560 standard tokens, excluding cache buckets
  end

  test "footer explains the fallback estimate for an unknown model" do
    msg = assistant_with_usage(model: "unknown-model", input_tokens: 1000, output_tokens: 0)
    msg.define_singleton_method(:model) { nil }
    html = ApplicationController.render(partial: "messages/token_footer", locals: { message: msg })
    fragment = Nokogiri::HTML.fragment(html)

    assert_response_details fragment
    assert_token_values fragment, input: "1,000", output: "0"
    assert_select fragment, "p.n-workspace-help", text: /0\.\d{6} kWh.*\d+\.\d{2} gCO₂e/m
    assert_select fragment, "p[data-estimate-note]:not([hidden])", text: I18n.t("nosia.usage.fallback_note")
  end

  test "French footer translates fallback note and formats counts and impact" do
    msg = assistant_with_usage(model: "unknown-model", input_tokens: 1234, output_tokens: 2)
    msg.define_singleton_method(:model) { nil }
    html = I18n.with_locale(:fr) { ApplicationController.render(partial: "messages/token_footer", locals: { message: msg }) }
    fragment = Nokogiri::HTML.fragment(html)

    assert_response_details fragment, locale: :fr
    assert_token_values fragment, input: /1[ \u00a0\u202f]234/, output: "2", locale: :fr
    assert_select fragment, "p.n-workspace-help", text: /0,\d{6} kWh.*\d+,\d{2} gCO₂e/m
    assert_select fragment, "p[data-estimate-note]:not([hidden])", text: I18n.t("nosia.usage.fallback_note", locale: :fr)
    refute_includes html, "1,234"
  end

  test "French known model footer keeps precision and has no fallback note" do
    msg = assistant_with_usage(model: "glm-5.2", input_tokens: 1240, output_tokens: 320, cache_read_tokens: 999, cache_write_tokens: 500)
    html = I18n.with_locale(:fr) { ApplicationController.render(partial: "messages/token_footer", locals: { message: msg }) }
    fragment = Nokogiri::HTML.fragment(html)

    assert_response_details fragment, locale: :fr
    assert_token_values fragment, input: /1[ \u00a0\u202f]240/, output: "320", locale: :fr
    assert_includes html, "0,006388 kWh"
    assert_select fragment, "p.n-workspace-help", text: /\d+,\d{2} gCO₂e\s*\z/
    assert_select fragment, "[data-estimate-note]", count: 0
  end

  test "footer uses zero for unreported buckets" do
    msg = assistant_with_usage(input_tokens: nil, output_tokens: 25)
    html = ApplicationController.render(partial: "messages/token_footer", locals: { message: msg })
    fragment = Nokogiri::HTML.fragment(html)

    assert_response_details fragment
    assert_token_values fragment, input: "0", output: "25"
  end

  %w[assistant message].each do |partial|
    test "#{partial} footer guard uses reported normalized tokens only after completion" do
      msg = assistant_with_usage(input_tokens: nil, output_tokens: 0)
      msg.define_singleton_method(:input_tokens) { raise "legacy token reader used" }
      msg.define_singleton_method(:output_tokens) { raise "legacy token reader used" }
      html = ApplicationController.render(partial: "messages/#{partial}", locals: { message: msg })
      fragment = Nokogiri::HTML.fragment(html)
      assert_response_details fragment
      assert_token_values fragment, input: "0", output: "0"

      msg.done = false
      html = ApplicationController.render(partial: "messages/#{partial}", locals: { message: msg })
      assert_select Nokogiri::HTML.fragment(html), "details[data-response-details]", count: 0
      assert_not_includes html, "gCO₂e"

      unreported = @chat.messages.create!(role: :assistant, content: "answer", done: true)
      html = ApplicationController.render(partial: "messages/#{partial}", locals: { message: unreported })
      assert_select Nokogiri::HTML.fragment(html), "details[data-response-details]", count: 0
      assert_not_includes html, "gCO₂e"
    end
  end

  test "chat totals partial shows cached counters and per-kind breakdown" do
    TokenUsage.create!(account: @account, chat: @chat, kind: :completion, input_tokens: 100, output_tokens: 40)
    TokenUsage.create!(account: @account, chat: @chat, kind: :embedding, input_tokens: 12, output_tokens: 0)
    html = ApplicationController.render(partial: "chats/token_totals", locals: { chat: @chat.reload })
    fragment = Nokogiri::HTML.fragment(html)

    assert_token_values fragment, input: "112", output: "40"
    assert_select fragment, "dd[data-chat-total-input]", text: "112"
    assert_select fragment, "dd[data-chat-total-output]", text: "40"
    assert_select fragment, ".n-chat-token-kind-heading", text: I18n.t("nosia.usage.per_kind")
    assert_select fragment, "ul.n-chat-token-kinds", count: 1
    assert_select fragment, "table", count: 0
    assert_usage_row fragment, kind: :completion, input: "100", output: "40"
    assert_usage_row fragment, kind: :embedding, input: "12", output: "0"
    assert_includes html, "kWh"
  end

  test "chat totals translate readable conditional notes and kinds without changing counters" do
    [ :en, :fr ].each do |locale|
      html = I18n.with_locale(locale) { ApplicationController.render(partial: "chats/token_totals", locals: { chat: @chat.reload }) }
      fragment = Nokogiri::HTML.fragment(html)
      note = locale == :fr ? "Énergie et CO₂e totaux — méthode Ecologits" : "Total energy & CO₂e — Ecologits methodology"
      assert_select fragment, "p[data-estimate-note]:not([hidden])", text: note
      assert_token_values fragment, input: "0", output: "0", locale: locale
    end

    TokenUsage.create!(account: @account, chat: @chat, kind: :completion, model_id: "unknown-model", input_tokens: 1234, output_tokens: 2)
    TokenUsage.create!(account: @account, chat: @chat, kind: :agent_skill, input_tokens: 1, output_tokens: 0)
    html = I18n.with_locale(:fr) { ApplicationController.render(partial: "chats/token_totals", locals: { chat: @chat.reload }) }
    fragment = Nokogiri::HTML.fragment(html)

    assert_token_values fragment, input: /1[ \u00a0\u202f]235/, output: "2", locale: :fr
    assert_select fragment, ".n-chat-token-kind-heading", text: "Par type"
    assert_usage_row fragment, kind: :completion, input: /1[ \u00a0\u202f]234/, output: "2", locale: :fr
    assert_usage_row fragment, kind: :agent_skill, input: "1", output: "0", locale: :fr
    assert_select fragment, "p.n-workspace-help", text: /0,\d{6} kWh.*\d+,\d{2} gCO₂e/m
    assert_select fragment, "p[data-estimate-note]:not([hidden])", text: "Énergie et CO₂e totaux — méthode Ecologits (avec estimation de repli)"
    assert_match(/1[ \u00a0\u202f]235/, html)
    assert_equal [ 1235, 2 ], [ @chat.reload.input_tokens_count, @chat.output_tokens_count ]
    assert_equal %w[agent_skill completion], @chat.token_totals_by_kind.keys.sort

    html = I18n.with_locale(:en) { ApplicationController.render(partial: "chats/token_totals", locals: { chat: @chat }) }
    assert_select Nokogiri::HTML.fragment(html), "p[data-estimate-note]:not([hidden])", text: "Total energy & CO₂e — Ecologits methodology (incl. fallback estimate)"
  end

  private
    def assert_response_details(fragment, locale: :en)
      assert_select fragment, "details[data-response-details][data-chat-detail]:not([open])", count: 1 do
        assert_select "summary", text: I18n.t("nosia.chat_workspace.response_details", locale: locale)
      end
    end

    def assert_token_values(fragment, input:, output:, locale: :en)
      assert_select fragment, "dl.n-chat-values > div", count: 2 do |values|
        assert_select values.first, "dt", text: I18n.t("nosia.usage.input", locale: locale)
        assert_select values.first, "dd", text: input
        assert_select values.last, "dt", text: I18n.t("nosia.usage.output", locale: locale)
        assert_select values.last, "dd", text: output
      end
    end

    def assert_usage_row(fragment, kind:, input:, output:, locale: :en)
      assert_select fragment, "li[data-usage-kind='#{kind}']", count: 1 do
        assert_select ".n-chat-token-kind-name", text: I18n.t("nosia.usage.kinds.#{kind}", locale: locale)
        assert_select "dt", text: I18n.t("nosia.usage.input", locale: locale)
        assert_select "dt", text: I18n.t("nosia.usage.output", locale: locale)
        assert_select "[data-usage-input]", text: input
        assert_select "[data-usage-output]", text: output
      end
    end

    def assistant_with_usage(model: "glm-5.2", **tokens)
      msg = @chat.messages.create!(role: :assistant, content: "answer", done: true)
      msg.ruby_llm_usages.create!(chat: @chat, operation: "chat", provider: "openai", model: model, status: "succeeded", **tokens)
      msg.reload
    end
end
