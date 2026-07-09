require "test_helper"
require "active_job/test_helper"

class DocumentCreateFromBlobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    @user = User.create!(email: "db@example.com", password: "testpassword123")
    @account = Account.create!(name: "DB Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  def teardown
    ActsAsTenant.current_tenant = nil
    ActiveJob::Base.queue_adapter = @original_queue_adapter
  end

  test "creates a document, owns the blob, and enqueues AddDocumentJob" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 fake"),
      filename: "report.pdf",
      content_type: "application/pdf"
    )
    assert_enqueued_with(job: AddDocumentJob) do
      @document = Document.create_from_blob!(@account, blob.signed_id)
    end
    assert @document.persisted?
    assert @document.file.attached?
    assert_equal blob, @document.file.blob
    assert @document.pending?
  end

  test "create_from_attachable_sgid! resolves the blob and delegates to create_from_blob!" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 fake"),
      filename: "report.pdf",
      content_type: "application/pdf"
    )
    assert_enqueued_with(job: AddDocumentJob) do
      @document = Document.create_from_attachable_sgid!(@account, blob.attachable_sgid)
    end
    assert @document.persisted?
    assert_equal blob, @document.file.blob
    assert @document.pending?
  end
end