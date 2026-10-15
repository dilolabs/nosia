require "test_helper"
require_relative "../support/chat_account_fixtures"

class ChatAccountTest < ActiveSupport::TestCase
  include ChatAccountFixtures

  test "persisted chats cannot be reassigned" do
    chat = chats(:picker_second_chat)

    assert_not chat.update(account: @first)
    assert_includes chat.errors[:account], "cannot be changed after creation"
    assert_equal @second.id, chat.reload.account_id
  end

  test "source attributes normalize references and reject other accounts" do
    chat = chats(:picker_second_chat)
    own = websites(:picker_second_website)

    assert_equal({ attached_website_ids: [ own.id.to_s ], attached_document_ids: [] },
      chat.source_attributes(website_ids: [ "", own.id, own.id ], document_ids: []))
    assert_raises(ActiveRecord::RecordNotFound) do
      chat.source_attributes(website_ids: [ websites(:picker_first_website).id ], document_ids: [])
    end
  end

  test "source attributes normalize document references and reject other accounts" do
    chat = chats(:picker_second_chat)
    own, other = [ @second, @first ].map do |account|
      account.documents.create!(title: "Reference", file: {
        io: StringIO.new("Reference"), filename: "reference.txt", content_type: "text/plain"
      })
    end

    assert_equal({ attached_website_ids: [], attached_document_ids: [ own.id.to_s ] },
      chat.source_attributes(website_ids: nil, document_ids: [ nil, "", own.id, own.id.to_s ]))
    assert_raises(ActiveRecord::RecordNotFound) do
      chat.source_attributes(website_ids: [], document_ids: [ own.id, other.id ])
    end
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
end
