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

  test "footer renders token counts and gCO2e for a done assistant message" do
    msg = assistant_with_usage(model: "glm-5.2", input_tokens: 1240, output_tokens: 320, cache_read_tokens: 999, cache_write_tokens: 500)
    html = ApplicationController.render(partial: "messages/token_footer", locals: { message: msg })
    assert_includes html, "1,240"
    assert_includes html, "320"
    assert_includes html, "gCO2e"
    assert_not_includes html, "gCO2e*"
    assert_includes html, "0.006388 kWh" # 1,560 standard tokens, excluding cache buckets
  end

  test "footer shows the fallback asterisk for an unknown model" do
    msg = assistant_with_usage(model: "unknown-model", input_tokens: 1000, output_tokens: 0)
    msg.define_singleton_method(:model) { nil }
    html = ApplicationController.render(partial: "messages/token_footer", locals: { message: msg })
    assert_includes html, "gCO2e*"
    assert_includes html, "model absent from the Comparia benchmark"
  end

  test "French footer translates fallback tooltip and formats counts and impact" do
    msg = assistant_with_usage(model: "unknown-model", input_tokens: 1234, output_tokens: 2)
    msg.define_singleton_method(:model) { nil }
    html = I18n.with_locale(:fr) { ApplicationController.render(partial: "messages/token_footer", locals: { message: msg }) }
    fragment = Nokogiri::HTML.fragment(html)

    assert_select fragment, 'span[title="Jetons d’entrée et de sortie"]', text: /↑ 1[ \u00a0\u202f]234 ↓ 2/
    assert_select fragment, 'span[title="Estimation de l’énergie (kWh)"]', text: /0,\d{6} kWh/
    assert_select fragment, 'span[title="estimation — modèle absent du benchmark Comparia"]', text: /\d+,\d{2} gCO2e\*/
    refute_includes html, "1,234"
  end

  test "French known model footer keeps precision and has no fallback asterisk" do
    msg = assistant_with_usage(model: "glm-5.2", input_tokens: 1240, output_tokens: 320, cache_read_tokens: 999, cache_write_tokens: 500)
    html = I18n.with_locale(:fr) { ApplicationController.render(partial: "messages/token_footer", locals: { message: msg }) }
    fragment = Nokogiri::HTML.fragment(html)

    assert_includes html, "0,006388 kWh"
    assert_select fragment, 'span[title="Estimation du CO2e"]', text: /\d+,\d{2} gCO2e\z/
    refute_includes html, "gCO2e*"
  end

  test "footer uses zero for unreported buckets" do
    msg = assistant_with_usage(input_tokens: nil, output_tokens: 25)
    html = ApplicationController.render(partial: "messages/token_footer", locals: { message: msg })
    assert_includes html, "↑ 0 ↓ 25"
  end

  %w[assistant message].each do |partial|
    test "#{partial} footer guard uses reported normalized tokens only after completion" do
      msg = assistant_with_usage(input_tokens: nil, output_tokens: 0)
      msg.define_singleton_method(:input_tokens) { raise "legacy token reader used" }
      msg.define_singleton_method(:output_tokens) { raise "legacy token reader used" }
      html = ApplicationController.render(partial: "messages/#{partial}", locals: { message: msg })
      assert_includes html, "↑ 0 ↓ 0"

      msg.done = false
      html = ApplicationController.render(partial: "messages/#{partial}", locals: { message: msg })
      assert_not_includes html, "gCO2e"

      unreported = @chat.messages.create!(role: :assistant, content: "answer", done: true)
      html = ApplicationController.render(partial: "messages/#{partial}", locals: { message: unreported })
      assert_not_includes html, "gCO2e"
    end
  end

  test "chat totals partial shows cached counters and per-kind breakdown" do
    TokenUsage.create!(account: @account, chat: @chat, kind: :completion, input_tokens: 100, output_tokens: 40)
    TokenUsage.create!(account: @account, chat: @chat, kind: :embedding, input_tokens: 12, output_tokens: 0)
    html = ApplicationController.render(partial: "chats/token_totals", locals: { chat: @chat.reload })
    assert_includes html, "112"  # total input
    assert_includes html, "40"
    assert_includes html, "completion"
    assert_includes html, "embedding"
    assert_includes html, "kWh"
  end

  test "chat totals translate full conditional tooltips and kinds without changing counters" do
    [ :en, :fr ].each do |locale|
      html = I18n.with_locale(locale) { ApplicationController.render(partial: "chats/token_totals", locals: { chat: @chat.reload }) }
      fragment = Nokogiri::HTML.fragment(html)
      tooltip = locale == :fr ? "Énergie et CO₂e totaux — méthode Ecologits" : "Total energy & CO₂e — Ecologits methodology"
      assert_select fragment, "span[title=?]", tooltip
    end

    TokenUsage.create!(account: @account, chat: @chat, kind: :completion, model_id: "unknown-model", input_tokens: 1234, output_tokens: 2)
    TokenUsage.create!(account: @account, chat: @chat, kind: :agent_skill, input_tokens: 1, output_tokens: 0)
    html = I18n.with_locale(:fr) { ApplicationController.render(partial: "chats/token_totals", locals: { chat: @chat.reload }) }
    fragment = Nokogiri::HTML.fragment(html)

    assert_select fragment, "span.font-semibold", text: "⚡ Jetons"
    assert_select fragment, "span.capitalize", text: /génération/
    assert_select fragment, "span.capitalize", text: /compétence d’agent/
    assert_select fragment, 'span[title="Énergie et CO₂e totaux — méthode Ecologits (avec estimation de repli)"]', text: /0,\d{6} kWh · \d+,\d{2} gCO₂e\*/
    assert_match(/1[ \u00a0\u202f]235/, html)
    assert_equal [ 1235, 2 ], [ @chat.reload.input_tokens_count, @chat.output_tokens_count ]
    assert_equal %w[agent_skill completion], @chat.token_totals_by_kind.keys.sort

    html = I18n.with_locale(:en) { ApplicationController.render(partial: "chats/token_totals", locals: { chat: @chat }) }
    assert_select Nokogiri::HTML.fragment(html), 'span[title="Total energy & CO₂e — Ecologits methodology (incl. fallback estimate)"]'
  end

  private
    def assistant_with_usage(model: "glm-5.2", **tokens)
      msg = @chat.messages.create!(role: :assistant, content: "answer", done: true)
      msg.ruby_llm_usages.create!(chat: @chat, operation: "chat", provider: "openai", model: model, status: "succeeded", **tokens)
      msg.reload
    end
end
