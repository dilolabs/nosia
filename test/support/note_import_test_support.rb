module NoteImportTestSupport
  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  private
    def start_import(files, root_name: "Coffre", account: @account, initiator: @initiator)
      NoteImport.start!(account:, initiator:, confirmation_key: SecureRandom.uuid, root_name:,
        files: files.map { |path, bytes| { path:, size: bytes.bytesize } }, ignored_counts: { obsidian: 0, other: 0 })
    end

    def sealed_import(files = { "Private.md" => "Private Markdown" }, **options)
      start_import(files, **options).tap do |import|
        files.map { |path, bytes| { path:, bytes: } }.each_slice(NoteImport::MAX_BATCH_FILES) { |batch| import.stage!(batch) }
        import.seal!
      end
    end

    def in_another_session(&block)
      worker = Thread.new { ApplicationRecord.with_connection(&block) }
      assert worker.join(5), "the second database session did not finish"
      worker.value
    ensure
      worker&.kill&.join if worker&.alive?
    end
end
