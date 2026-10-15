require "test_helper"

class DocumentSourceRegistrationTest < ActiveJob::TestCase
  self.use_transactional_tests = false
  self.fixture_paths = [ Rails.root.join("test/support/fixtures/chat_accounts") ]
  fixtures :users, :accounts

  setup do
    @first = accounts(:picker_first)
    @second = accounts(:picker_second)
    @prior_tenant = ActsAsTenant.current_tenant
    @prior_adapter = ActiveJob::Base.queue_adapter
    ActsAsTenant.current_tenant = nil
    ActiveJob::Base.queue_adapter = :test
    @blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4\n%%EOF"),
      filename: "registration.pdf", content_type: "application/pdf")
    clear_enqueued_jobs
  end

  teardown do
    @first.documents.destroy_all
    @second.documents.destroy_all
    @blob.purge
    ActsAsTenant.current_tenant = @prior_tenant
    ActiveJob::Base.queue_adapter = @prior_adapter
  end

  test "registration reuses the resolved blob rather than the signed token and enqueues once" do
    first = second = nil

    assert_difference "Document.count", 1 do
      assert_enqueued_jobs 1, only: AddDocumentJob do
        first = Document.create_from_blob!(@first, @blob.signed_id(expires_in: 1.hour))
        second = Document.create_from_blob!(@first, @blob.signed_id(expires_in: 2.hours))
      end
    end

    assert_equal first.id, second.id
    assert_equal @blob, second.file.blob
    assert_enqueued_with job: AddDocumentJob, args: [ first.id ], queue: "background"
  end

  test "the same blob has separate registrations and jobs in separate accounts" do
    first = Document.create_from_attachable_sgid!(@first, @blob.attachable_sgid)
    second = Document.create_from_attachable_sgid!(@second, @blob.attachable_sgid)

    assert_not_equal first.id, second.id
    assert_equal @first.id, first.account_id
    assert_equal @second.id, second.account_id
    assert_enqueued_jobs 2, only: AddDocumentJob
    assert_no_enqueued_jobs only: AddDocumentJob do
      assert_equal first.id, Document.create_from_blob!(@first, @blob.signed_id).id
      assert_equal second.id, Document.create_from_blob!(@second, @blob.signed_id).id
    end
  end

  test "index publication waits for the outer transaction and committed document visibility" do
    document = nil
    assert_not Document.connection.transaction_open?

    Document.transaction do
      document = Document.create_from_blob!(@first, @blob.signed_id)
      assert_no_enqueued_jobs only: AddDocumentJob
    end

    assert_enqueued_with job: AddDocumentJob, args: [ document.id ]
    assert Thread.new { Document.connection_pool.with_connection { Document.exists?(document.id) } }.value
  end

  test "outer rollback cancels both registration and indexing publication" do
    document_id = nil

    assert_no_difference "Document.count" do
      assert_no_enqueued_jobs only: AddDocumentJob do
        Document.transaction do
          document_id = Document.create_from_blob!(@first, @blob.signed_id).id
          assert_no_enqueued_jobs only: AddDocumentJob
          raise ActiveRecord::Rollback
        end
      end
    end

    assert_not Document.exists?(document_id)
  end

  test "savepoint rollback does not publish a job for the discarded registration" do
    discarded_id = nil
    retained = nil

    Document.transaction do
      Document.transaction(requires_new: true) do
        discarded_id = Document.create_from_blob!(@first, @blob.signed_id).id
        raise ActiveRecord::Rollback
      end
      retained = Document.create_from_blob!(@first, @blob.signed_id)
      assert_no_enqueued_jobs only: AddDocumentJob
    end

    assert_not Document.exists?(discarded_id)
    assert_enqueued_jobs 1, only: AddDocumentJob
    assert_enqueued_with job: AddDocumentJob, args: [ retained.id ]
  end

  test "concurrent registrations serialize per account and enqueue one job" do
    # Load development-style lazy route helpers before concurrent broadcasts.
    Rails.application.routes.url_helpers.sources_document_path(0)
    ready = Queue.new
    start = Queue.new
    signed_id = @blob.signed_id
    threads = 2.times.map do
      Thread.new do
        Document.connection_pool.with_connection do
          account = Account.find(@first.id)
          ready << true
          start.pop
          Document.create_from_blob!(account, signed_id).id
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    ids = threads.map(&:value)

    assert_equal 1, ids.uniq.size
    assert_equal 1, @first.documents.count
    assert_enqueued_jobs 1, only: AddDocumentJob
  ensure
    threads&.each(&:join)
  end
end
