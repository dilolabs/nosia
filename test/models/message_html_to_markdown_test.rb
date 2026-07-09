require "test_helper"

class MessageHtmlToMarkdownTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "mh@example.com", password: "testpassword123")
    @account = Account.create!(name: "MH Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "user message HTML content is converted to markdown on save" do
    message = @chat.messages.create!(role: "user", content: "<p>Hello <strong>world</strong></p>")
    assert_equal "Hello **world**", message.content.strip
  end

  test "anchors pass through as markdown links" do
    message = @chat.messages.create!(role: "user",
      content: '<p>See <a href="https://x.example">https://x.example</a></p>')
    assert_includes message.content, "https://x.example"
    assert_includes message.content, "[https://x.example](https://x.example)"
  end

  test "action-text-attachment PDF nodes become a paperclip marker" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4"), filename: "report.pdf", content_type: "application/pdf"
    )
    sgid = blob.attachable_sgid
    html = %(<p>Here is the doc</p><action-text-attachment sgid="#{sgid}" content-type="application/pdf"></action-text-attachment>)
    message = @chat.messages.create!(role: "user", content: html)
    assert_includes message.content, "📎 report.pdf"
    refute_includes message.content, "action-text-attachment"
  end

  test "assistant markdown content is not converted" do
    message = @chat.messages.create!(role: "assistant", content: "Already **markdown** here")
    assert_equal "Already **markdown** here", message.content
  end

  test "plain text user content without HTML tags is unchanged" do
    message = @chat.messages.create!(role: "user", content: "Just plain text, no tags.")
    assert_equal "Just plain text, no tags.", message.content
  end
end
