require "test_helper"
require "stringio"
require "timeout"
require_relative "../../support/note_import_test_support"

class NoteImportPublishJobTest < ActiveJob::TestCase
  include NoteImportTestSupport

  self.use_transactional_tests = false
  self.fixture_paths = [ Rails.root.join("test/support/fixtures/chat_accounts") ]
  fixtures :users, :accounts, :account_users

  setup do
    @initiator = users(:picker_owner)
    @member = users(:picker_outsider)
    @account = Account.create!(owner: @initiator, name: "Disposable Notes import worker")
    @account.account_users.grant_to([ @initiator, @member ])
  end

  teardown do
    @account&.destroy!
    ActiveRecord::FixtureSet.reset_cache
  end

  test "normal handoff enqueues only the receipt id and duplicate delivery does not rewrite it" do
    import = sealed_import
    assert_enqueued_with(job: NoteImport::PublishJob, args: [ import.id ]) { import.enqueue_publication }
    assert_predicate import.reload, :queued?
    assert_in_delta Time.current.to_f, import.enqueued_at.to_f, 1
    assert_equal 1, import.staged_files.count

    assert_enqueued_jobs 1, only: Note::IndexJob do
      first = NoteImport::PublishJob.perform_now(import.id)
      root_id = import.reload.root_note_folder_id
      assert_equal root_id, first.root_note_folder_id
      assert_no_changes -> { import.reload.attributes } do
        assert_no_difference [ "@account.notes.count", "@account.note_folders.count" ] do
          replay = NoteImport::PublishJob.perform_now(import.id)
          assert_equal root_id, replay.root_note_folder_id
        end
      end
    end
    assert_equal 1, @account.notes.sole.content_revision
    assert_empty import.staged_files
  end

  test "a failed adapter leaves a durable seal and reconciliation recovers it" do
    import = sealed_import
    adapter = NoteImport::PublishJob.queue_adapter
    log = StringIO.new
    logger = ActiveSupport::Logger.new(log)
    Rails.logger.broadcast_to(logger)
    adapter.define_singleton_method(:enqueue) { |_job| raise ActiveJob::EnqueueError, "secret adapter exception" }

    assert_no_enqueued_jobs { import.enqueue_publication }
    assert_predicate import.reload, :sealed?
    assert_nil import.enqueued_at
    assert_equal 1, import.staged_files.count
    refute_includes log.string, "secret adapter exception"

    adapter.singleton_class.remove_method(:enqueue)
    assert_enqueued_with(job: NoteImport::PublishJob, args: [ import.id ]) { NoteImport::ReconcileJob.perform_now }
    assert_predicate import.reload, :queued?
    assert_equal 1, import.staged_files.count
    assert_no_enqueued_jobs { NoteImport::ReconcileJob.perform_now }
  ensure
    adapter&.singleton_class&.remove_method(:enqueue) if adapter&.singleton_methods(false)&.include?(:enqueue)
    Rails.logger.stop_broadcasting_to(logger) if logger
  end

  test "false handoff and Solid Queue refusal leave the seal eligible for reconciliation" do
    import = sealed_import
    deny = -> { throw :abort }
    NoteImport::PublishJob.before_enqueue(deny)

    assert_no_enqueued_jobs { import.enqueue_publication }
    assert_equal [ "sealed", nil ], import.reload.values_at(:status, :enqueued_at)
    NoteImport::PublishJob.skip_callback(:enqueue, :before, deny)
    deny = nil

    adapter = NoteImport::PublishJob.queue_adapter
    adapter.define_singleton_method(:enqueue) { |_job| raise SolidQueue::Job::EnqueueError, "adapter refused" }
    assert_no_enqueued_jobs { NoteImport::ReconcileJob.perform_now }
    assert_equal [ "sealed", nil ], import.reload.values_at(:status, :enqueued_at)
  ensure
    NoteImport::PublishJob.skip_callback(:enqueue, :before, deny) if deny
    adapter&.singleton_class&.remove_method(:enqueue)
  end

  test "enqueue waits for the outer commit and never publishes a rolled back seal" do
    import = start_import({ "A.md" => "a" })
    import.stage!([ { path: "A.md", bytes: "a" } ])
    assert_no_enqueued_jobs do
      NoteImport.transaction do
        import.seal!
        import.enqueue_publication
        assert_predicate in_another_session { NoteImport.find(import.id) }, :uploading?
        assert_empty enqueued_jobs
        raise ActiveRecord::Rollback
      end
    end
    assert_predicate import.reload, :uploading?
    assert_nil import.sealed_at

    assert_enqueued_with(job: NoteImport::PublishJob, args: [ import.id ]) do
      NoteImport.transaction do
        import.seal!
        import.enqueue_publication
        assert_empty enqueued_jobs
      end
    end
    assert_predicate import.reload, :queued?
  end

  test "a worker can finish before the enqueue returns without losing success" do
    import = sealed_import
    adapter = NoteImport::PublishJob.queue_adapter
    other_session = method(:in_another_session)
    adapter.define_singleton_method(:enqueue) do |job|
      other_session.call do
        NoteImport::PublishJob.perform_now(*job.arguments)
      end
    end

    import.enqueue_publication

    assert_predicate import.reload, :succeeded?
    assert_equal @account.note_folders.sole.id, import.root_note_folder_id
    assert_nil import.enqueued_at
    assert_empty import.staged_files
  ensure
    adapter&.singleton_class&.remove_method(:enqueue)
  end

  test "reconciliation expires idle uploads and old never-claimed seals without resetting their deadlines" do
    travel_to Time.current.change(usec: 0) do
      idle = start_import({ "A.md" => "a", "B.md" => "b" })
      idle.stage!([ { path: "A.md", bytes: "a" } ])
      queued = sealed_import(initiator: @member)
      queued.enqueue_publication
      sealed_account = accounts(:picker_second)
      @other_import = sealed_import(account: sealed_account)
      begin
        travel 24.hours - 1.second
        @other_upload = start_import({ "Fresh.md" => "fresh" }, account: accounts(:picker_foreign), initiator: @member)
        assert_predicate idle.reload, :uploading?
        assert_predicate queued.reload, :queued?
        assert_equal 1, queued.staged_files.count
        travel 1.second

        assert_nil queued.claim
        assert_no_enqueued_jobs { NoteImport::ReconcileJob.perform_now }
        assert_predicate idle.reload, :expired?
        assert_nil idle.sealed_at
        assert_empty idle.staged_files
        [ queued, @other_import ].each do |import|
          assert_predicate import.reload, :failed?
          assert_equal({ "error" => "processing_timeout" }, import.report)
          assert_empty import.staged_files
        end
        assert_predicate @other_upload.reload, :uploading?
      ensure
        @other_import&.destroy!
        @other_upload&.destroy!
      end
    end
  end

  test "a committed claim excludes a duplicate and can only renew before its expiry" do
    import = sealed_import
    travel_to Time.current.change(usec: 0) do
      token = nil
      duplicate = nil
      ready = Queue.new
      NoteImport.transaction do
        token = import.claim
        duplicate = Thread.new do
          NoteImport.with_connection do |connection|
            ready << connection.raw_connection.backend_pid
            NoteImport.find(import.id).claim
          end
        end
        assert_waiting_for_my_lock(ready.pop(timeout: 5))
      end
      assert duplicate.join(5)
      assert_nil duplicate.value
      assert_match NoteImport::CONFIRMATION_KEY, token
      assert_equal 15.minutes.from_now, import.reload.claim_expires_at
      assert_equal "Private Markdown", import.read_staged_payload(token, "Private.md")
      refute import.renew_claim(SecureRandom.uuid)
      travel 14.minutes
      assert import.renew_claim(token)
      assert_equal 15.minutes.from_now, import.reload.claim_expires_at
      assert_equal 1, import.staged_files.count
      travel 15.minutes
      refute import.renew_claim(token)
      queries = []
      observe_staging = ->(event) { queries << event if event.payload[:sql].include?("note_import_staged_files") }
      ActiveSupport::Notifications.subscribed(observe_staging, "sql.active_record") do
        assert_raises(NoteImport::Invalid) { import.read_staged_payload(token, "Private.md") }
      end
      assert_empty queries
      assert_equal 1, import.staged_files.count

      in_another_session { NoteImport::ReconcileJob.perform_now }
      assert_predicate import.reload, :failed?
      assert_equal({ "error" => "worker_claim_expired" }, import.report)
      assert_nil import.claim_token
      assert_nil import.claim_expires_at
      assert_empty import.staged_files
      assert_raises(NoteImport::Invalid) { import.read_staged_payload(token, "Private.md") }
    ensure
      duplicate&.kill&.join if duplicate&.alive?
    end
  end

  test "a stale worker with prepared content cannot publish after reconciliation" do
    import = sealed_import
    token = import.claim
    prepared = NoteImport::Markdown.new(import.manifest.keys).prepare("Private.md", import.read_staged_payload(token, "Private.md"))
    travel 16.minutes do
      [ false, true ].each do |reconciled|
        in_another_session { NoteImport::ReconcileJob.perform_now } if reconciled
        assert_no_difference [ "@account.note_folders.count", "@account.notes.count" ] do
          assert_raises(NoteImport::Invalid) { import.publish_prepared(token, [ prepared ]) }
        end
      end
    end
    assert_predicate import.reload, :failed?
    assert_nil import.root_note_folder_id
  end

  test "reconciliation cannot revoke a claim after an eligible publication takes the write locks" do
    import = sealed_import
    sweeper = nil
    worker = Thread.current
    ready = Queue.new
    observe_note_insert = ->(event) do
      next if sweeper || Thread.current != worker || !event.payload[:sql].start_with?('INSERT INTO "notes"')

      travel 16.minutes
      sweeper = Thread.new do
        NoteImport.with_connection do |connection|
          ready << connection.raw_connection.backend_pid
          NoteImport::ReconcileJob.perform_now
        end
      end
      assert_waiting_for_my_lock(ready.pop(timeout: 5))
    end
    travel_to Time.current.change(usec: 0) do
      ActiveSupport::Notifications.subscribed(observe_note_insert, "sql.active_record") do
        NoteImport::PublishJob.perform_now(import.id)
      end
      assert sweeper&.join(5), "the sweeper did not finish"
      sweeper.value
    end
    assert_predicate import.reload, :succeeded?
    assert_equal @account.note_folders.sole.id, import.root_note_folder_id
    assert_empty import.staged_files
  ensure
    sweeper&.kill&.join if sweeper&.alive?
  end

  test "membership revoked on a second connection during preparation blocks publication" do
    import = sealed_import(initiator: @member)
    worker = Thread.current
    removed = false
    revoke = ->(event) do
      next if removed || Thread.current != worker || !event.payload[:sql].start_with?('SELECT "note_import_staged_files".*')

      removed = true
      in_another_session { @account.account_users.find_by!(user: @member).destroy! }
    end
    assert_no_difference [ "@account.note_folders.count", "@account.notes.count" ] do
      NoteImport.cache do
        assert @account.account_users.exists?(user_id: @member.id)
        ActiveSupport::Notifications.subscribed(revoke, "sql.active_record") { NoteImport::PublishJob.perform_now(import.id) }
      end
    end
    assert removed, "membership should be removed before the publication lock"
    assert_predicate import.reload, :failed?
    assert_equal({ "error" => "membership_revoked" }, import.report)
    assert_empty import.staged_files
  end

  test "worker debug logs omit Markdown, paths, and root names" do
    import = sealed_import
    log = StringIO.new
    logger = ActiveSupport::Logger.new(log)
    Rails.logger.broadcast_to(logger)

    NoteImport::PublishJob.perform_now(import.id)

    [ "Private.md", "Private Markdown", "Coffre" ].each { |secret| refute_includes log.string, secret }
  ensure
    Rails.logger.stop_broadcasting_to(logger)
  end

  test "failed cleanup leaves a successful receipt intact and does not starve another cleanup" do
    first = sealed_import
    second = sealed_import(initiator: @member)
    original = NoteImport::StagedFile.method(:where)
    failing = [ first.id, second.id ]
    NoteImport::StagedFile.define_singleton_method(:where) do |*args|
      if args.first.is_a?(Hash) && failing.include?(args.first[:note_import_id])
        raise ActiveRecord::StatementInvalid, "private cleanup details"
      end
      original.call(*args)
    end

    NoteImport::PublishJob.perform_now(first.id)
    NoteImport::PublishJob.perform_now(second.id)
    second.reload
    assert_predicate first.reload, :succeeded?
    assert_predicate second, :succeeded?
    assert_equal 1, first.staged_files.count
    assert_equal 1, second.staged_files.count

    assert_no_changes -> { first.reload.attributes } do
      failing.delete(second.id)
      NoteImport::ReconcileJob.perform_now
      assert_equal 1, first.staged_files.count
      assert_empty second.staged_files
      failing.clear
      NoteImport::ReconcileJob.perform_now
      assert_empty first.staged_files
    end
  ensure
    NoteImport::StagedFile.singleton_class.remove_method(:where) if original
  end

  private
    def assert_waiting_for_my_lock(pid)
      assert pid
      Timeout.timeout(5) do
        NoteImport.with_connection do |connection|
          NoteImport.uncached do
            Thread.pass until connection.select_value("SELECT pg_backend_pid() = ANY(pg_blocking_pids(#{Integer(pid)}))")
          end
        end
      end
    end
end
