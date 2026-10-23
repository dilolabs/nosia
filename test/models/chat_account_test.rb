require "test_helper"
require "turbo/broadcastable/test_helper"
require_relative "../support/chat_account_fixtures"

class ChatAccountTest < ActiveSupport::TestCase
  include ChatAccountFixtures
  include Turbo::Broadcastable::TestHelper

  test "background unlock renders the read-only second account without Current" do
    chat = chats(:picker_second_chat)
    Current.reset

    streams = capture_turbo_stream_broadcasts([ chat, "messages", :en ]) { chat.finish_generation! }
    form = streams.find { |stream| stream["target"] == "chat_#{chat.id}_message_form" }

    assert form
    assert_includes form.inner_html, "Research team"
    assert_not_includes form.inner_html, "chat[account_id]"
  end

  test "persisted chats cannot be reassigned" do
    chat = chats(:picker_second_chat)

    assert_not chat.update(account: @first)
    assert_includes chat.errors[:account], "cannot be changed after creation"
    assert_equal @second.id, chat.reload.account_id
  end

  test "French immutable account validation preserves the saved chat account" do
    chat = chats(:picker_second_chat)

    I18n.with_locale(:fr) do
      refute chat.update(account: @first)
      assert_includes chat.errors[:account], "ne peut pas être modifié après la création"
      assert_includes chat.errors.full_messages, "Compte ne peut pas être modifié après la création"
    end
    assert_equal @second.id, chat.reload.account_id
  end

  test "source attributes normalize references and reject other accounts under another tenant" do
    chat = chats(:picker_second_chat)
    own_id = websites(:picker_second_website).id
    other_id = websites(:picker_first_website).id

    ActsAsTenant.with_tenant(@first) do
      assert_equal({ attached_website_ids: [ own_id.to_s ], attached_document_ids: [] },
        chat.source_attributes(website_ids: [ "", own_id, own_id ], document_ids: []))
      assert_equal @first, ActsAsTenant.current_tenant
      assert_raises(ActiveRecord::RecordNotFound) do
        chat.source_attributes(website_ids: [ other_id ], document_ids: [])
      end
      assert_equal @first, ActsAsTenant.current_tenant
    end
    assert_nil ActsAsTenant.current_tenant
  end

  test "source attributes normalize document references and reject other accounts under another tenant" do
    chat = chats(:picker_second_chat)
    own_id, other_id = [ @second, @first ].map do |account|
      account.documents.create!(title: "Reference", file: {
        io: StringIO.new("Reference"), filename: "reference.txt", content_type: "text/plain"
      }).id
    end

    ActsAsTenant.with_tenant(@first) do
      assert_equal({ attached_website_ids: [], attached_document_ids: [ own_id.to_s ] },
        chat.source_attributes(website_ids: nil, document_ids: [ nil, "", own_id, own_id.to_s ]))
      assert_equal @first, ActsAsTenant.current_tenant
      assert_raises(ActiveRecord::RecordNotFound) do
        chat.source_attributes(website_ids: [], document_ids: [ own_id, other_id ])
      end
      assert_equal @first, ActsAsTenant.current_tenant
    end
    assert_nil ActsAsTenant.current_tenant
  end

  test "source attributes reject missing references instead of dropping them" do
    chat = chats(:picker_second_chat)
    own_id = websites(:picker_second_website).id

    assert_raises(ActiveRecord::RecordNotFound) do
      chat.source_attributes(website_ids: [ own_id, "missing" ], document_ids: [])
    end
    assert_raises(ActiveRecord::RecordNotFound) do
      chat.source_attributes(website_ids: [], document_ids: [ "missing" ])
    end
  end

  test "empty source and tool selections normalize to empty arrays" do
    chat = chats(:picker_second_chat)

    assert_equal({ attached_website_ids: [], attached_document_ids: [] },
      chat.source_attributes(website_ids: nil, document_ids: [ nil, "", " " ]))
    assert_empty chat.selected_mcp_servers(nil)
    assert_empty chat.selected_mcp_servers([ nil, "", " " ])
  end

  test "tool snapshots use the chat account even under another tenant" do
    chat = chats(:picker_second_chat)
    own_id = mcp_servers(:picker_second_tool).id
    other_id = mcp_servers(:picker_first_tool).id

    ActsAsTenant.with_tenant(@first) do
      assert_equal [ own_id ], chat.selected_mcp_servers([ own_id ]).map(&:id)
      assert_equal @first, ActsAsTenant.current_tenant
      assert_raises(ActiveRecord::RecordNotFound) { chat.selected_mcp_servers([ other_id ]) }
      assert_equal @first, ActsAsTenant.current_tenant
    end
  end

  test "tool snapshots normalize duplicates and reject missing references" do
    chat = chats(:picker_second_chat)
    own_id = mcp_servers(:picker_second_tool).id

    assert_equal [ own_id ], chat.selected_mcp_servers([ nil, "", own_id, own_id.to_s ]).map(&:id)
    assert_raises(ActiveRecord::RecordNotFound) { chat.selected_mcp_servers([ own_id, "missing" ]) }
    assert_nil ActsAsTenant.current_tenant
  end

  test "persisted chats still allow generation state updates" do
    chat = chats(:picker_second_chat)

    assert chat.update(generating: true)
    assert_predicate chat.reload, :generating?
    assert_equal @second.id, chat.account_id
  end

  test "model-level tool linking rejects a different account" do
    chat = chats(:picker_second_chat)

    assert_raises(ActiveRecord::RecordNotFound) { chat.add_mcp_server(mcp_servers(:picker_first_tool)) }
  end

  test "helper snapshots restore a pre-existing tenant" do
    helper = ApplicationController.helpers

    ActsAsTenant.with_tenant(@first) do
      assert_equal [ "Second tool" ], helper.ready_chat_mcp_servers(@second).map(&:name)
      assert_equal [ "second-skill" ], JSON.parse(helper.agent_skill_autocomplete_data(@second)).map { |skill| skill.fetch("name") }
      assert_equal @first, ActsAsTenant.current_tenant
    end
  end

  test "skill snapshots use the explicit account under another tenant" do
    helper = ApplicationController.helpers
    observed = []
    original_skills = @second.method(:agent_skills)
    lookup = -> do
      observed << ActsAsTenant.current_tenant
      original_skills.call
    end

    ActsAsTenant.with_tenant(@first) do
      with_singleton_replacement(@second, :agent_skills, lookup) do
        assert_equal [ "second-skill" ], JSON.parse(helper.agent_skill_autocomplete_data(@second)).map { |skill| skill.fetch("name") }
      end
      assert_equal @first, ActsAsTenant.current_tenant
    end
    assert_equal [ @second ], observed
  end

  test "linked tools materialize within the chat tenant" do
    chat = chats(:picker_second_chat)
    server = mcp_servers(:picker_second_tool)
    server.update!(metadata: { engine: "open_alex" })
    chat.chat_mcp_sessions.create!(mcp_server: server)

    ActsAsTenant.with_tenant(@first) do
      assert_includes chat.mcp_tools.map(&:name), "openalex_search_works"
      assert_equal @first, ActsAsTenant.current_tenant
    end
  end

  test "background generation uses and restores the saved account tenant" do
    chat = chats(:picker_second_chat)
    observed = []
    chat.define_singleton_method(:complete_with_nosia) do |*args, **options|
      observed << ActsAsTenant.current_tenant
      nil
    end
    chat.define_singleton_method(:complete_with_agent_skills) do |*args, **options|
      observed << ActsAsTenant.current_tenant
      nil
    end
    original_find = Chat.method(:find)
    lookup = ->(*ids) { ids == [ chat.id ] ? chat : original_find.call(*ids) }

    Current.reset
    ActsAsTenant.with_tenant(@first) do
      with_singleton_replacement(Chat, :find, lookup) { ChatResponseJob.perform_now(chat.id, "Account context") }
      assert_equal @first, ActsAsTenant.current_tenant
    end
    assert_equal [ @second ], observed
  end

  test "cited evidence cannot include another account's chunk IDs" do
    width = Chunk.columns_hash.fetch("embedding").limit
    vector = [ 1.0 ] + Array.new(width - 1, 0.0)
    first = insert_picker_chunk(@first, texts(:picker_first_text), "First evidence", vector)
    second = insert_picker_chunk(@second, texts(:picker_second_text), "Research evidence", vector)
    message = chats(:picker_second_chat).messages.create!(role: :assistant, content: "Answer", similar_chunk_ids: [ first.id.to_s, second.id.to_s ])

    assert_equal [ second.id ], message.similar_chunks.pluck(:id)
  end

  test "cited evidence handles absent and duplicate chunk IDs" do
    chat = chats(:picker_second_chat)
    width = Chunk.columns_hash.fetch("embedding").limit
    own = insert_picker_chunk(@second, texts(:picker_second_text), "Research evidence", [ 1.0 ] + Array.new(width - 1, 0.0))
    message = chat.messages.build(role: :assistant, content: "Answer", similar_chunk_ids: nil)

    assert_empty message.similar_chunks

    message.similar_chunk_ids = [ own.id.to_s, own.id.to_s ]
    assert_equal [ own.id ], message.similar_chunks.pluck(:id)
  end

  test "real nearest-neighbor retrieval excludes a closer first-account vector" do
    original_limit = ENV["RETRIEVAL_FETCH_K"]
    chat = chats(:picker_second_chat)
    width = Chunk.columns_hash.fetch("embedding").limit
    query = [ 1.0, 0.0 ] + Array.new(width - 2, 0.0)
    research = [ 0.8, 0.2 ] + Array.new(width - 2, 0.0)
    insert_picker_chunk(@first, texts(:picker_first_text), "Closer but forbidden", query)
    own = insert_picker_chunk(@second, texts(:picker_second_text), "Research evidence", research)
    result = Struct.new(:vectors, :tokens).new(query, Struct.new(:input).new(3))
    ENV["RETRIEVAL_FETCH_K"] = "1"
    chat.define_singleton_method(:context_relevance) { |*args, **options| true }
    chat.define_singleton_method(:broadcast_thinking_phase) { |*args| }

    ActsAsTenant.with_tenant(@second) do
      with_singleton_replacement(RubyLLM, :embed, ->(*args, **options) { result }) do
        assert_equal [ own.id ], chat.similarity_search("Question").map(&:id)
      end
    end

    assert_equal @second.id, TokenUsage.where(chat: chat, kind: :embedding).last.account_id
  ensure
    ENV["RETRIEVAL_FETCH_K"] = original_limit
  end

  test "saved-account prompt and completion usage do not use the first account" do
    chat = chats(:picker_second_chat)
    model = ruby_llm_models(:picker_model).model_id
    instructions = []
    chat.define_singleton_method(:with_model) { |*args, **options| }
    chat.define_singleton_method(:with_provider_options) { |**options| }
    chat.define_singleton_method(:with_temperature) { |*args| }
    chat.define_singleton_method(:mcp_tools) { [] }
    chat.define_singleton_method(:similarity_search) { |*args| [] }
    chat.define_singleton_method(:with_instructions) { |content, **options| instructions << content }
    chat.define_singleton_method(:broadcast_thinking_phase) { |*args| }
    chat.define_singleton_method(:answer_relevance) { |*args, **options| true }
    chat.define_singleton_method(:complete) do |&stream|
      message = messages.create!(role: :assistant, content: "Answer")
      message.ruby_llm_usages.create!(chat: self, operation: "chat", provider: "openai", model: model,
        status: "succeeded", input_tokens: 7, output_tokens: 2)
      message
    end

    message = ActsAsTenant.with_tenant(@second) { chat.complete_with_nosia("Question") }

    assert_equal [ "Research account instructions" ], instructions
    assert_equal @second.id, TokenUsage.find_by!(source: message).account_id
  end

  test "background generation restores the prior tenant after a completion error" do
    chat = chats(:picker_second_chat)
    chat.start_generation!
    observed = []
    completion = ->(*) do
      observed << ActsAsTenant.current_tenant
      raise ArgumentError, "Completion failed"
    end
    chat.define_singleton_method(:complete_with_nosia, completion)
    chat.define_singleton_method(:complete_with_agent_skills, completion)
    original_find = Chat.method(:find)
    lookup = ->(*ids) { ids == [ chat.id ] ? chat : original_find.call(*ids) }

    Current.reset
    ActsAsTenant.with_tenant(@first) do
      with_singleton_replacement(Chat, :find, lookup) do
        assert_raises(ArgumentError) { ChatResponseJob.perform_now(chat.id, "Account context") }
      end
      assert_equal @first, ActsAsTenant.current_tenant
    end
    assert_equal [ @second ], observed
    assert_not chat.reload.generating?
    assert_nil ActsAsTenant.current_tenant
  end
end
