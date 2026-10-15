require "test_helper"
require "turbo/broadcastable/test_helper"
require_relative "../support/chat_account_fixtures"

class ChatAccountTest < ActiveSupport::TestCase
  include ChatAccountFixtures
  include Turbo::Broadcastable::TestHelper

  test "background unlock renders the read-only second account without Current" do
    chat = chats(:picker_second_chat)
    Current.reset

    streams = capture_turbo_stream_broadcasts([ chat, "messages" ]) { chat.finish_generation! }
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
