require "test_helper"

class TokenFooterTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(email: "tf@example.com", password: "testpassword123")
    @account = Account.create!(name: "TF Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
  end

  test "footer renders token counts and gCO2e for a done assistant message" do
    model = Model.create!(model_id: "glm-5.2", name: "GLM 5.2", provider: "openai")
    msg = @chat.messages.create!(role: :assistant, content: "answer", done: true,
                                 input_tokens: 1240, output_tokens: 320, model: model)
    html = ApplicationController.render(partial: "messages/token_footer", locals: { message: msg })
    assert_includes html, "1,240"
    assert_includes html, "320"
    assert_includes html, "gCO2e"
  end

  test "footer shows the fallback asterisk for an unknown model" do
    msg = @chat.messages.create!(role: :assistant, content: "answer", done: true,
                                 input_tokens: 1000, output_tokens: 0, model: nil)
    html = ApplicationController.render(partial: "messages/token_footer", locals: { message: msg })
    assert_includes html, "gCO2e*"
    assert_includes html, "absent du benchmark Comparia"
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
end
