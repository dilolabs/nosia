require "test_helper"
require "active_job/test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def setup
    @user = User.create!(email: "mc@example.com", password: "testpassword123")
    @account = Account.create!(name: "MC Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    post login_url, params: { email: @user.email, password: "testpassword123" }
  end

  def teardown
    ActsAsTenant.current_tenant = nil
    ActiveJob::Base.queue_adapter = @original_queue_adapter
  end

  test "create stamps attached document ids and passes markdown to the job" do
    chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
    d = @account.documents.new
    d.file.attach(io: StringIO.new("x"), filename: "d.pdf", content_type: "application/pdf")
    d.save!
    assert_enqueued_with(job: ChatResponseJob) do
      post chat_messages_url(chat), params: { message: { content: "<p>hi <em>there</em></p>", attached_document_ids: [d.id] } }
    end
    message = chat.messages.where(role: :user).last
    assert_equal [d.id.to_s], message.attached_document_ids
    assert_equal "hi *there*", message.content.strip
  end
end
