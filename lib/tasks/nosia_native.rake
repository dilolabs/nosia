require_relative "../nosia/native_stack"

namespace :nosia_native do
  validate_database_schema = lambda do
    schema = ActiveRecord::Base.connection.select_value("SELECT MAX(version)::bigint FROM schema_migrations").to_i
    supported_schema = Nosia::NativeStack.database_schema_version(root: Rails.root)
    raise "Database schema newer than this image" if schema > supported_schema
    raise "Database schema has pending migrations" if schema < supported_schema
  end

  embedding_column_type = lambda do
    ActiveRecord::Base.connection.select_value(<<~SQL)
      SELECT format_type(atttypid, atttypmod)
      FROM pg_attribute
      WHERE attrelid = 'chunks'::regclass AND attname = 'embedding'
    SQL
  end

  # Rails change_column skips this custom vector type in the audited server.
  # The dimension is parsed and bounded before reaching this internal helper.
  resize_embedding_column = lambda do |dimension|
    connection = ActiveRecord::Base.connection
    connection.remove_index(:chunks, :embedding) if connection.index_exists?(:chunks, :embedding)
    connection.execute("ALTER TABLE chunks ALTER COLUMN embedding TYPE vector(#{dimension})")
    connection.add_index(:chunks, :embedding, using: :hnsw, opclass: :vector_cosine_ops) if dimension <= 2000
    Chunk.reset_column_information
  end

  desc "Align an empty index after db:prepare without discarding any existing vectors"
  task prepare_empty_index: :environment do
    Nosia::NativeStack.require_enabled!
    validate_database_schema.call
    dimension = Integer(ENV.fetch("EMBEDDING_DIMENSIONS"))
    raise "Invalid dimensions" unless dimension.between?(1, 4096)
    actual = embedding_column_type.call
    unless actual == "vector(#{dimension})"
      Chunk.transaction do
        ActiveRecord::Base.connection.execute("LOCK TABLE chunks IN ACCESS EXCLUSIVE MODE")
        raise "Existing embeddings require explicit reindex" if Chunk.unscoped.where.not(embedding: nil).exists?
        resize_embedding_column.call(dimension)
      end
    end
  end

  desc "Verify the vector schema and space identity before starting writers"
  task validate_index: :environment do
    Nosia::NativeStack.require_enabled!
    validate_database_schema.call
    expected = Integer(ENV.fetch("EMBEDDING_DIMENSIONS"))
    actual = embedding_column_type.call
    raise "Embedding schema mismatch: explicit reindex required" unless actual == "vector(#{expected})"
    raise "Incomplete reindex: explicit reindex required" if Rails.root.join("storage", ".native-reindex-target").exist?
    fingerprint = Nosia::NativeStack.embedding_fingerprint
    file = Rails.root.join("storage", ".native-embedding-fingerprint")
    if File.exist?(file)
      raise "Embedding space mismatch: explicit reindex required" unless File.read(file) == fingerprint
    elsif Chunk.unscoped.where.not(embedding: nil).exists?
      raise "Unknown imported embedding space: explicit reindex required"
    end
    File.write(file, fingerprint)
  end

  desc "Verify all database connections and the queue heartbeat for the native stack"
  task check: :environment do
    Nosia::NativeStack.require_enabled!
    Rake::Task["nosia_native:validate_index"].invoke
    # No SolidCache gem is present in the pinned server. Check the real configured
    # PostgreSQL databases directly, including aliases resolved by Active Record.
    require "pg"
    ActiveRecord::Base.configurations.configs_for(env_name: Rails.env).each do |configuration|
      db = configuration.configuration_hash
      connection = PG.connect(host: db[:host], port: db[:port] || 5432, user: db[:username],
        password: db[:password], dbname: db[:database], connect_timeout: 5)
      begin
        connection.exec("SELECT 1")
      ensure
        connection.close
      end
    end
    [ ActiveRecord::Base, SolidQueue::Record ].each do |model|
      model.connection.execute("SELECT 1")
    end
    30.times do
      if SolidQueue::Process.where(kind: "Worker").where("last_heartbeat_at > ?", 2.minutes.ago).exists?
        puts "native-stack-ready"
        break
      end
      sleep 1
    end
    raise "Worker heartbeat missing" unless SolidQueue::Process.where(kind: "Worker").where("last_heartbeat_at > ?", 2.minutes.ago).exists?
  end

  desc "Explicitly invalidate every vector, change dimensions and regenerate the entire index"
  task reindex: :environment do
    Nosia::NativeStack.require_enabled!
    validate_database_schema.call
    dimension = Integer(ENV.fetch("EMBEDDING_DIMENSIONS"))
    raise "Invalid dimensions" unless dimension.between?(1, 4096)
    # The app stops web/workers and takes a pg_dumpall backup before invoking this task.
    # Resume only vectors created in this exact target space. A different target invalidates all.
    marker = Rails.root.join("storage", ".native-reindex-target")
    fingerprint = Nosia::NativeStack.embedding_fingerprint
    target = JSON.generate(fingerprint: fingerprint, dimensions: dimension)
    unless File.exist?(marker) && File.read(marker) == target && embedding_column_type.call == "vector(#{dimension})"
      # Mark the installation unavailable before touching vectors. If interrupted
      # before the target marker is written, retry invalidates all vectors again.
      File.write(marker, JSON.generate(preparing: true))
      Chunk.transaction do
        ActiveRecord::Base.connection.execute("LOCK TABLE chunks IN ACCESS EXCLUSIVE MODE")
        Chunk.unscoped.update_all(embedding: nil)
        resize_embedding_column.call(dimension)
      end
      File.write(marker, target)
    end
    Chunk.unscoped.where(embedding: nil).where.not(content: [ nil, "" ]).find_each(&:generate_embedding!)
    raise "Incomplete embedding reconstruction" if Chunk.unscoped.where.not(content: [ nil, "" ]).where(embedding: nil).exists?
    File.write(Rails.root.join("storage", ".native-embedding-fingerprint"), fingerprint)
    File.delete(marker)
    puts "native-index-rebuilt"
  end
end
