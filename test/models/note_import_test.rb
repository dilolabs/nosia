require "test_helper"

class NoteImportTest < ActiveSupport::TestCase
  self.fixture_paths = [ Rails.root.join("test/support/fixtures/chat_accounts") ]
  fixtures :users, :accounts, :account_users

  setup do
    @account = accounts(:picker_first)
    @initiator = users(:picker_owner)
  end

  test "confirmation retries compare normalized metadata without opening a new import" do
    key = SecureRandom.uuid
    original = start_import(confirmation_key: key, root_name: "Cafe\u0301",
      files: [ { path: "Cafe\u0301/Plan.MD", size: 2 }, { path: "Other.md", size: 0 } ])

    assert original.uploading?
    assert_equal "Café", original.root_name
    assert_equal({ "Café/Plan.MD" => 2, "Other.md" => 0 }, original.manifest)
    assert_no_difference -> { @account.note_imports.count } do
      assert_equal original, start_import(confirmation_key: key.upcase, root_name: "Café",
        files: [ { path: "Other.md", size: 0 }, { path: "Café/Plan.MD", size: 2 } ])
    end
  end

  test "a confirmation key cannot be reused with changed metadata" do
    original = start_import

    [
      { root_name: "Different" },
      { files: [ { path: "Plan.md", size: 3 } ] },
      { ignored_counts: { obsidian: 1, other: 0 } }
    ].each do |changes|
      assert_invalid :confirmation_conflict do
        start_import(confirmation_key: original.confirmation_key, **changes)
      end
    end
  end

  test "only one live import per account and initiator and terminal keys are never revived" do
    original = start_import

    assert_invalid(:import_in_progress) { start_import }
    assert_not_equal original, start_import(account: accounts(:picker_second), confirmation_key: original.confirmation_key)

    original.update!(status: :expired)
    assert_predicate start_import(confirmation_key: original.confirmation_key), :expired?
    assert_invalid(:expired) { original.seal! }
    assert_not_equal original, start_import
  end

  test "confirmation requires valid UUID and exact bounded ignored counts" do
    assert_invalid(:invalid_confirmation_key) { start_import(confirmation_key: "not a UUID") }

    [
      { obsidian: 0 }, { obsidian: 0, other: 0, extras: 0 },
      { obsidian: 0, "obsidian" => 0, other: 0 },
      { obsidian: -1, other: 0 }, { obsidian: 0, other: "0" },
      { obsidian: 0, other: 2_147_483_648 },
      Hash.new(0).merge(unrelated: 0, other: 0)
    ].each { |counts| assert_invalid(:invalid_ignored_counts) { start_import(ignored_counts: counts) } }

    assert_equal({ "obsidian" => 2_147_483_647, "other" => 0 },
      start_import(ignored_counts: { "obsidian" => 2_147_483_647, "other" => 0 }).ignored_counts)
  end

  test "confirmation requires fresh membership even when replaying an existing import" do
    assert_invalid(:membership_required) { start_import(initiator: users(:picker_outsider)) }
    assert_invalid(:membership_required) { start_import(account: accounts(:picker_foreign)) }

    key = start_import.confirmation_key
    assert_includes @account.account_users.load.map(&:user_id), @initiator.id
    account_users(:picker_first_membership).destroy!

    assert_invalid(:membership_required) { start_import(confirmation_key: key) }
  end

  test "the manifest rejects an empty plan and malformed logical paths" do
    assert_invalid(:invalid_file_count) { manifest_for([]) }
    [ "/Plan.md", "C:\\Plan.md", "C:Plan.md", "a/../Plan.md", "a/./Plan.md",
      "a//Plan.md", "Plan.md/", ".obsidian/Plan.md", "a/.obsidian/Plan.md",
      "a\\Plan.md", "A\u0000.md", "A\u0085.md", "A\xFF.md".b, "Plan.txt" ].each do |path|
      error = assert_invalid(:invalid_path) { manifest_for([ { path:, size: 0 } ]) }
      assert_nil error.path
    end
    [ "nested/Coffre", ".", "..", "", ".obsidian", "C:Coffre" ].each do |root_name|
      assert_invalid(:invalid_root_name) { manifest_for([ { path: "Plan.md", size: 0 } ], root_name:) }
    end
  end

  test "manifest identity respects Unicode equivalence and case and rejects directory clashes" do
    assert_invalid :duplicate_path do
      manifest_for([ { path: "Cafe\u0301.md", size: 0 }, { path: "Café.md", size: 0 } ])
    end
    [ "Plan.md Plan.md/Inner.md", "Plan.md/Inner.md Plan.md" ].each do |paths|
      assert_invalid(:path_collision) { manifest_for(paths.split.map { |path| { path:, size: 0 } }) }
    end

    assert_equal({ "Plan.MD" => 0, "plan.md" => 0 }, manifest_for([
      { path: "Plan.MD", size: 0 }, { path: "plan.md", size: 0 }
    ]).files)
  end

  test "manifest limits file bytes, total bytes and file count before any upload" do
    [ -1, 1.5, "2", 2.megabytes + 1 ].each do |size|
      assert_invalid(:invalid_file_size) { manifest_for([ { path: "Plan.md", size: } ]) }
    end
    assert_invalid(:invalid_file_size) { manifest_for([ Hash.new(0).merge(path: "Plan.md") ]) }

    full = Array.new(16) { |i| { path: "#{i}.md", size: 2.megabytes } }
    assert_equal 16, manifest_for(full).files.size
    assert_invalid(:total_size_exceeded) { manifest_for(full + [ { path: "Extra.md", size: 1 } ]) }

    files = Array.new(500) { |i| { path: "#{i}.md", size: 0 } }
    assert_equal 500, manifest_for(files).files.size
    assert_invalid(:invalid_file_count) { manifest_for(files + [ { path: "Extra.md", size: 0 } ]) }
  end

  test "manifest counts the root and unique directory prefixes and caps depth" do
    files = Array.new(249) { |i| { path: "#{i}/Plan.md", size: 0 } }
    assert_equal 250, manifest_for(files + [ { path: "0/Other.md", size: 0 } ]).files.size
    assert_invalid(:folder_limit_exceeded) { manifest_for(files + [ { path: "0/Extra/Plan.md", size: 0 } ]) }

    deep = "a/" * 32
    assert_equal({ "#{deep}Plan.md" => 0 }, manifest_for([ { path: "#{deep}Plan.md", size: 0 } ]).files)
    assert_invalid(:depth_limit_exceeded) { manifest_for([ { path: "#{deep}a/Plan.md", size: 0 } ]) }
  end

  test "manifest measures both individual components and whole paths in UTF-8 bytes" do
    max_component = "é" * 126 + ".md"
    assert_equal({ max_component => 0 }, manifest_for([ { path: max_component, size: 0 } ]).files)
    assert_invalid(:invalid_path) { manifest_for([ { path: "a#{max_component}", size: 0 } ]) }

    max_path = ("a" * 255 + "/") * 3 + "a" * 252 + "/.md"
    assert_equal 1_024, max_path.bytesize
    assert_equal({ max_path => 0 }, manifest_for([ { path: max_path, size: 0 } ]).files)
    assert_invalid(:invalid_path) { manifest_for([ { path: max_path.sub("/.md", "/a.md"), size: 0 } ]) }
  end

  test "staging normalizes paths and encrypts UTF-8 bytes without serializing or inspecting them" do
    content = "Café des idées privées"
    import = start_import(files: [ { path: "Café.MD", size: content.bytesize } ])
    bytes = content.b.freeze

    travel 1.minute do
      import.stage!([ { path: "Cafe\u0301.MD", bytes: } ])
      assert_in_delta Time.current, import.reload.activity_at, 0.01
    end

    staged = import.staged_files.sole
    assert_equal @account.id, staged.account_id
    assert_equal "Café.MD", staged.path
    assert_equal Digest::SHA256.hexdigest(content), staged.digest
    assert_equal content, staged.payload
    assert_equal Encoding::BINARY, bytes.encoding
    ciphertext = NoteImport.connection_pool.with_connection do |connection|
      connection.select_value("SELECT payload FROM note_import_staged_files WHERE id = #{connection.quote(staged.id)}")
    end
    refute_includes ciphertext, content
    refute staged.serializable_hash.key?("payload")
    refute staged.serializable_hash(only: :payload, methods: :payload).key?("payload")
    refute_includes staged.serializable_hash(methods: :payload_in_database).values, content
    refute staged.serializable_hash(include: :payload).key?("payload")
    refute_includes staged.inspect, content
  end

  test "staging rejects invalid UTF-8, NUL, unexpected paths and mismatched bytes with safe errors" do
    import = start_import

    [
      [ "Plan.md", "a\xFF".b, :invalid_payload, "Plan.md" ],
      [ "Plan.md", "a\0", :invalid_payload, "Plan.md" ],
      [ "Plan.md", "a", :size_mismatch, "Plan.md" ],
      [ "plan.md", "ok", :unexpected_path, "plan.md" ],
      [ "/Plan.md", "ok", :invalid_path, nil ]
    ].each do |path, bytes, code, logical_path|
      error = assert_invalid(code) { import.stage!([ { path:, bytes: } ]) }
      assert_equal logical_path, error.path if logical_path
      assert_nil error.path unless logical_path
      assert_equal code.to_s, error.message
    end
    assert_empty import.staged_files
  end

  test "a batch exceeding sixteen entries is rejected and invalid entries leave no staged files" do
    import = start_import(files: [ { path: "Plan.md", size: 2 }, { path: "Other.md", size: 2 } ])
    assert_invalid(:invalid_batch) { import.stage!(Array.new(17) { { path: "Plan.md", bytes: "ok" } }) }

    last_activity = import.reload.activity_at
    assert_invalid :size_mismatch do
      import.stage!([ { path: "Plan.md", bytes: "ok" }, { path: "Other.md", bytes: "bad" } ])
    end

    assert_empty import.staged_files
    assert_equal last_activity, import.reload.activity_at
  end

  test "identical retries are no-ops and a conflicting retry cannot overwrite or insert files" do
    import = start_import(files: [ { path: "Plan.md", size: 2 }, { path: "Other.md", size: 2 } ])
    entry = { path: "Plan.md", bytes: "ok" }

    assert_difference -> { import.staged_files.count }, 1 do
      import.stage!([ entry, entry ])
      import.stage!([ entry ])
    end
    assert_invalid :content_conflict do
      import.stage!([ { path: "Other.md", bytes: "ok" }, { path: "Plan.md", bytes: "no" } ])
    end
    assert_equal "ok", import.staged_files.sole.payload
  end

  test "sealing requires every file, is retry-safe and prevents any later staging" do
    import = start_import(files: [ { path: "Plan.md", size: 2 }, { path: "Empty.md", size: 0 } ])
    first = { path: "Plan.md", bytes: "ok" }

    import.stage!([ first ])
    assert_invalid(:incomplete_upload) { import.seal! }
    assert_predicate import.reload, :uploading?
    assert_nil import.sealed_at

    import.stage!([ { path: "Empty.md", bytes: "" } ])
    assert_predicate import.seal!, :sealed?
    assert_in_delta Time.current, import.sealed_at, 0.01
    assert_equal import.sealed_at, import.activity_at
    sealed_at = import.reload.sealed_at

    travel 1.minute do
      assert_equal sealed_at, import.seal!.sealed_at
      assert_invalid(:not_uploading) { import.stage!([ first ]) }
      import.update!(status: :queued)
      assert_predicate import.seal!, :queued?
      import.update!(status: :succeeded)
      assert_predicate import.seal!, :succeeded?
    end
  end

  test "revoked initiators cannot stage or seal even if they already hold an import" do
    import = start_import
    import.stage!([ { path: "Plan.md", bytes: "ok" } ])
    account_users(:picker_first_membership).destroy!

    assert_invalid(:membership_required) { import.stage!([ { path: "Plan.md", bytes: "ok" } ]) }
    assert_invalid(:membership_required) { import.seal! }
  end

  test "a staged file cannot be associated with a foreign account" do
    import = start_import
    staged = NoteImport::StagedFile.new(note_import: import, account: accounts(:picker_second),
      path: "Plan.md", payload: "ok", digest: Digest::SHA256.hexdigest("ok"))

    refute staged.save
    assert_equal 0, import.staged_files.count
  end

  test "destroying the account removes staged bytes even if the import association was preloaded" do
    assert_empty @account.note_imports.load
    import = start_import(account: Account.find(@account.id))
    import.stage!([ { path: "Plan.md", bytes: "ok" } ])

    @account.destroy!

    refute NoteImport.exists?(import.id)
    refute NoteImport::StagedFile.exists?(note_import_id: import.id)
  end

  private
    def start_import(**overrides)
      NoteImport.start!(**{
        account: @account, initiator: @initiator, confirmation_key: SecureRandom.uuid, root_name: "Coffre",
        files: [ { path: "Plan.md", size: 2 } ], ignored_counts: { obsidian: 0, other: 0 }
      }.merge(overrides))
    end

    def manifest_for(files, root_name: "Coffre")
      NoteImport::Manifest.new(root_name:, files:, ignored_counts: { obsidian: 0, other: 0 })
    end

    def assert_invalid(code, &block)
      assert_raises(NoteImport::Invalid, &block).tap { |error| assert_equal code, error.code }
    end
end
