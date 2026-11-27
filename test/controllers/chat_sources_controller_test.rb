require "test_helper"
require "active_job/test_helper"

class ChatSourcesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def setup
    @user = User.create!(email: "cs@example.com", password: "testpassword123")
    @account = Account.create!(name: "CS Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    post login_url, params: { email: @user.email, password: "testpassword123" }
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  def teardown
    ActsAsTenant.current_tenant = nil
    ActiveJob::Base.queue_adapter = @original_queue_adapter
  end

  test "url branch creates a website and returns its id/url/status as JSON" do
    assert_enqueued_with(job: CrawlWebsiteUrlJob) do
      post chat_sources_url, params: { url: "https://x.example/page" }, as: :json
    end
    assert_response :success
    json = JSON.parse(response.body)
    assert json["id"].present?
    assert_equal "https://x.example/page", json["url"]
    assert_equal "pending", json["index_status"]
    assert @account.websites.exists?(id: json["id"])
  end

  test "attachable_sgid branch creates a document and returns its id/filename/status as JSON" do
    blob = create_document_upload(account: @account, user: @user)
    assert_enqueued_with(job: AddDocumentJob) do
      post chat_sources_url, params: { attachable_sgid: blob.attachable_sgid }, as: :json
    end
    assert_response :success
    json = JSON.parse(response.body)
    assert json["id"].present?
    assert_equal "report.pdf", json["filename"]
    assert_equal "pending", json["index_status"]
  end

  test "the composer receives an upload capability bound to its current workspace" do
    bytes = "%PDF-1.4\n%%EOF"
    post rails_direct_uploads_path(account_id: @account.id), as: :json, params: { blob: {
      filename: "report.pdf", byte_size: bytes.bytesize, checksum: Digest::MD5.base64digest(bytes),
      content_type: "application/pdf"
    } }

    assert_response :success
    upload = response.parsed_body
    blob = ActiveStorage::Blob.find_signed!(upload.fetch("signed_id"))
    assert_equal @account, Document::Upload.account_for(blob, user: @user)
    assert_equal blob.attachable_sgid, upload.fetch("attachable_sgid")
    assert upload.fetch("direct_upload").fetch("url").present?
  end

  test "duplicate url reuses the existing website without creating a new one" do
    existing = @account.websites.create!(url: "https://dup.example", index_status: :indexed)
    post chat_sources_url, params: { url: "https://dup.example" }, as: :json
    assert_response :success
    assert_equal existing.id, JSON.parse(response.body)["id"]
  end

  test "rejects when neither url nor attachable_sgid is provided" do
    post chat_sources_url, params: {}, as: :json
    assert_response :bad_request
  end

  test "an invalid attachable sgid is rejected as bad_request, not a 500" do
    post chat_sources_url, params: { attachable_sgid: "not-a-real-sgid" }, as: :json
    assert_response :bad_request
    assert_equal "invalid attachable sgid", JSON.parse(response.body)["error"]
  end
end
