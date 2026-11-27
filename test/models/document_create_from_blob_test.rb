require "test_helper"
require "active_job/test_helper"

class DocumentCreateFromBlobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    @user = User.create!(email: "db@example.com", password: "testpassword123")
    @account = Account.create!(name: "DB Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  def teardown
    ActsAsTenant.current_tenant = nil
    ActiveJob::Base.queue_adapter = @original_queue_adapter
  end

  test "creates a document, owns the blob, and enqueues AddDocumentJob" do
    blob = create_document_upload(account: @account, user: @user)
    assert_enqueued_with(job: AddDocumentJob) do
      @document = Document.create_from_blob!(@account, blob.signed_id, user: @user)
    end
    assert @document.persisted?
    assert @document.file.attached?
    assert_equal blob, @document.file.blob
    assert @document.pending?
  end

  test "create_from_attachable_sgid! resolves an attachable sgid to a blob and creates the document" do
    blob = create_document_upload(account: @account, user: @user)
    assert_enqueued_with(job: AddDocumentJob) do
      @document = Document.create_from_attachable_sgid!(@account, blob.attachable_sgid, user: @user)
    end
    assert @document.persisted?
    assert_equal blob, @document.file.blob
    assert @document.pending?
  end
end
