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
    assert_includes html, "absent du benchmark Comparia"
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

  private
    def assistant_with_usage(model: "glm-5.2", **tokens)
      msg = @chat.messages.create!(role: :assistant, content: "answer", done: true)
      msg.ruby_llm_usages.create!(chat: @chat, operation: "chat", provider: "openai", model: model, status: "succeeded", **tokens)
      msg.reload
    end
end
