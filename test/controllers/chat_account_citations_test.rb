require "test_helper"
require_relative "../support/chat_account_fixtures"

class ChatAccountCitationsTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures

  setup { sign_in_picker_user }

  test "document citations render the source PDF preview" do
    document = @second.documents.new(title: "Cited PDF")
    document.file.attach(io: StringIO.new("%PDF-1.4\n%%EOF"), filename: "cited.pdf", content_type: "application/pdf")
    document.save!
    width = Chunk.columns_hash.fetch("embedding").limit
    chunk = insert_picker_chunk(@second, document, "Document evidence", [ 1.0 ] + Array.new(width - 1, 0.0))

    get chunk_url(chunk), params: { chat_id: chats(:picker_second_chat).id }

    assert_response :success
    assert_select "blockquote", text: /Document evidence/
    assert_select "##{dom_id(document)} h2", text: "Cited PDF"
    assert_select "##{dom_id(document)} iframe[src*='active_storage']"
    assert_select "##{dom_id(document)} object", count: 0
    assert_includes response.headers["Content-Security-Policy"], "object-src 'none'"
  end

  test "citation lookup uses an owned chat account and preserves the old default" do
    width = Chunk.columns_hash.fetch("embedding").limit
    vector = [ 1.0 ] + Array.new(width - 1, 0.0)
    first = insert_picker_chunk(@first, texts(:picker_first_text), "First evidence", vector)
    second = insert_picker_chunk(@second, texts(:picker_second_text), "Research evidence", vector)
    chat = chats(:picker_second_chat)

    get chunk_url(second), params: { chat_id: chat.id }
    assert_response :success
    assert_includes response.body, "Research evidence"

    get chunk_url(first), params: { chat_id: chat.id }
    assert_response :not_found

    get chunk_url(second), params: { chat_id: chats(:picker_foreign_chat).id }
    assert_response :not_found

    get chunk_url(first)
    assert_response :success

    get chunk_url(second)
    assert_response :not_found

    @user.account_users.find_by!(account: @second).destroy!
    get chunk_url(second), params: { chat_id: chat.id }
    assert_response :not_found
  end

  test "inaccessible explicit chat contexts never fall back to first-account citations" do
    width = Chunk.columns_hash.fetch("embedding").limit
    first = insert_picker_chunk(@first, texts(:picker_first_text), "First evidence", [ 1.0 ] + Array.new(width - 1, 0.0))
    unowned = @first.chats.create!(user: users(:picker_outsider), ruby_llm_model_id: ruby_llm_models(:picker_model).id)

    [ "missing", chats(:picker_foreign_chat).id, unowned.id ].each do |chat_id|
      get chunk_url(first), params: { chat_id: chat_id }
      assert_response :not_found
    end

    @user.account_users.find_by!(account: @second).destroy!
    get chunk_url(first), params: { chat_id: chats(:picker_second_chat).id }
    assert_response :not_found
  end

  test "account overrides cannot change the citation account" do
    width = Chunk.columns_hash.fetch("embedding").limit
    vector = [ 1.0 ] + Array.new(width - 1, 0.0)
    first = insert_picker_chunk(@first, texts(:picker_first_text), "First evidence", vector)
    second = insert_picker_chunk(@second, texts(:picker_second_text), "Research evidence", vector)
    chat = chats(:picker_second_chat)

    get chunk_url(second), params: { chat_id: chat.id, account_id: @first.id }
    assert_response :success

    get chunk_url(first), params: { chat_id: chat.id, account_id: @first.id }
    assert_response :not_found

    get chunk_url(second), params: { account_id: @second.id }
    assert_response :not_found
  end

  test "array citation contexts are not treated as one or more authorized chats" do
    width = Chunk.columns_hash.fetch("embedding").limit
    vector = [ 1.0 ] + Array.new(width - 1, 0.0)
    first = insert_picker_chunk(@first, texts(:picker_first_text), "First evidence", vector)
    second = insert_picker_chunk(@second, texts(:picker_second_text), "Research evidence", vector)

    [ second, first ].each do |chunk|
      get chunk_url(chunk), params: { chat_id: [ chats(:picker_second_chat).id ] }

      assert_response :not_found
    end
  end

  test "hash citation contexts are rejected instead of resolving an account" do
    width = Chunk.columns_hash.fetch("embedding").limit
    vector = [ 1.0 ] + Array.new(width - 1, 0.0)
    first = insert_picker_chunk(@first, texts(:picker_first_text), "First evidence", vector)
    second = insert_picker_chunk(@second, texts(:picker_second_text), "Research evidence", vector)

    [ second, first ].each do |chunk|
      get chunk_url(chunk), params: { chat_id: { id: chats(:picker_second_chat).id } }

      assert_response :not_found
    end
  end

  test "empty array citation contexts never fall back to the first account" do
    width = Chunk.columns_hash.fetch("embedding").limit
    first = insert_picker_chunk(@first, texts(:picker_first_text), "First evidence", [ 1.0 ] + Array.new(width - 1, 0.0))

    get chunk_url(first), params: { chat_id: [] }, as: :json, headers: { "Accept" => "text/html" }

    assert_response :not_found
  end

  test "empty hash citation contexts never fall back to the first account" do
    width = Chunk.columns_hash.fetch("embedding").limit
    first = insert_picker_chunk(@first, texts(:picker_first_text), "First evidence", [ 1.0 ] + Array.new(width - 1, 0.0))

    get chunk_url(first), params: { chat_id: {} }, as: :json, headers: { "Accept" => "text/html" }

    assert_response :not_found
  end

  test "string and numeric chat contexts still resolve saved-account citations" do
    chat = chats(:picker_second_chat)
    width = Chunk.columns_hash.fetch("embedding").limit
    own = insert_picker_chunk(@second, texts(:picker_second_text), "Research evidence", [ 1.0 ] + Array.new(width - 1, 0.0))

    [ chat.id, chat.id.to_s ].each do |chat_id|
      get chunk_url(own), params: { chat_id: chat_id }, as: :json, headers: { "Accept" => "text/html" }

      assert_response :success
      assert_includes response.body, "Research evidence"
    end
  end

  test "rendered citations include the saved chat context" do
    chat = chats(:picker_second_chat)
    width = Chunk.columns_hash.fetch("embedding").limit
    own = insert_picker_chunk(@second, texts(:picker_second_text), "Research evidence", [ 1.0 ] + Array.new(width - 1, 0.0))
    chat.messages.create!(role: :assistant, content: "Cited answer", similar_chunk_ids: [ own.id.to_s ])

    get chat_url(chat)

    assert_response :success
    assert_select "a[href='#{chunk_path(own, chat_id: chat.id)}']", minimum: 1
  end
end
