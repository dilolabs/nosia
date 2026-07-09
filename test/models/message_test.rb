require "test_helper"

class MessageTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "mt@example.com", password: "testpassword123")
    @account = Account.create!(name: "MT Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
  end

  def teardown
    ActsAsTenant.current_tenant = nil
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
end
