require_relative "chat_account_fixtures"

module NoteRetrievalFixtures
  extend ActiveSupport::Concern
  include ChatAccountFixtures

  included do
    setup do
      @prior_note_env = ENV.to_h.slice("AUGMENTED_CONTEXT", "GUARD_MODEL", "RETRIEVAL_FETCH_K")
      ENV.update("AUGMENTED_CONTEXT" => "false", "GUARD_MODEL" => nil, "RETRIEVAL_FETCH_K" => "5")
      @first_note = indexed_note(@first, "FIRST_NOTE_MARKER")
      @second_note = indexed_note(@second, "SECOND_NOTE_MARKER")
      @foreign_note = indexed_note(@foreign, "FOREIGN_NOTE_MARKER")
      @first_chunk = @first_note.chunks.sole
      @second_chunk = @second_note.chunks.sole
      @foreign_chunk = @foreign_note.chunks.sole
      @first_text = insert_picker_chunk(@first, texts(:picker_first_text), "FIRST_TEXT_MARKER", other_vector)
      @second_text = insert_picker_chunk(@second, texts(:picker_second_text), "SECOND_TEXT_MARKER", other_vector)
      @first.prompts.find_by!(name: "system_prompt").update!(content: "First account %{documents}")
      @second.prompts.find_by!(name: "system_prompt").update!(content: "Research account %{documents}")
    end

    teardown do
      %w[AUGMENTED_CONTEXT GUARD_MODEL RETRIEVAL_FETCH_K].each { |key| ENV[key] = @prior_note_env[key] }
    end
  end

  private
    def with_note_sql_barrier(before: nil, after: nil, &test)
      subscriber = Object.new
      subscriber.define_singleton_method(:start) { |_name, _id, payload| before&.call(payload.fetch(:sql)) }
      subscriber.define_singleton_method(:finish) { |_name, _id, payload| after&.call(payload.fetch(:sql)) }
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record", &test)
    end

    def query_vector
      @vector ||= [ 1.0 ] + Array.new(Chunk.embedding_dimensions - 1, 0.0)
    end

    def indexed_note(account, marker, folder: account.general_note_folder, title: "Cited Note", vector: query_vector)
      note = Note.save_draft!(account:, folder:, draft_key: SecureRandom.uuid, title:, body_html: "<p>#{marker}</p>")
      note.update!(embedding_status: :ready, indexed_generation: note.embedding_generation)
      insert_note_chunk(note, marker, vector:)
      note
    end

    def insert_note_chunk(note, marker, position: 1, generation: note.embedding_generation, account: note.account, vector: query_vector)
      insert_picker_chunk(account, note, marker, vector).tap do |chunk|
        chunk.update!(metadata: { "position" => position, "note_generation" => generation })
      end
    end

    def other_vector
      [ 0.8, 0.6 ] + query_vector.drop(2)
    end

    def with_note_provider(after_request: nil, tools_on_first_completion: false)
      requests = []
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/v1/chat/completions") do |env|
        request = JSON.parse(env.body)
        requests << request
        after_request&.call(request)
        if env.request.on_data
          env.status = 200
          if tools_on_first_completion && requests.one?
            deltas = [ { tool_calls: [ { index: 0, id: "test-tool-1", type: "function",
              function: { name: "test_note_change", arguments: "{}" } } ] } ]
            frames = deltas.map { |delta| provider_frame(request, delta, finish: "tool_calls") }
          else
            frames = [ provider_frame(request, { role: "assistant", content: "Synthetic answer" }, finish: "stop") ]
          end
          frames.each do |frame|
            data = "data: #{frame.to_json}\n\n"
            env.request.on_data.call(data, data.bytesize, env)
          end
          env.request.on_data.call("data: [DONE]\n\n", 14, env)
          [ 200, { "content-type" => "text/event-stream" }, "" ]
        else
          body = { model: request.fetch("model"),
            choices: [ { message: { role: "assistant", content: "0" }, finish_reason: "stop" } ],
            usage: { prompt_tokens: 5, completion_tokens: 1 } }
          [ 200, { "content-type" => "application/json" }, body.to_json ]
        end
      end
      adapter = Class.new(Faraday::Adapter::Test) do
        define_method(:initialize) { |app, **| super(app, stubs, &nil) }
      end
      original_adapter = RubyLLM.config.faraday_adapter
      RubyLLM.config.faraday_adapter = adapter
      embedding = RubyLLM::Embedding.new(vectors: query_vector, model: ENV.fetch("EMBEDDING_MODEL"), input_tokens: 3)
      with_singleton_replacement(RubyLLM, :embed, ->(*, **) { embedding }) { yield requests }
    ensure
      RubyLLM.config.faraday_adapter = original_adapter
    end

    def provider_frame(request, delta, finish:)
      { choices: [ { delta:, index: 0, finish_reason: finish } ], model: request.fetch("model"),
        usage: { prompt_tokens: 7, completion_tokens: 4 } }
    end

    def provider_text(requests)
      requests.flat_map { |request| request.fetch("messages") }.pluck("content").join("\n")
    end
end
