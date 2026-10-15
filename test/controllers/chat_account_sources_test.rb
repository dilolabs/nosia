require "test_helper"
require_relative "../support/chat_account_fixtures"

class ChatAccountSourcesTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures

  setup { sign_in_picker_user }

  test "new and saved chat URL registrations use explicit context" do
    [ { account_id: @second.id }, { chat_id: chats(:picker_second_chat).id } ].each_with_index do |context, index|
      url = "https://context-#{index}.example/reference"

      post chat_sources_url, params: context.merge(url: url), as: :json

      assert_response :success
      assert_equal @second.id, Website.find(response.parsed_body.fetch("id")).account_id
    end
  end

  test "conflicting saved-chat context is rejected before creating a source" do
    assert_no_difference "Website.count" do
      post chat_sources_url, params: { chat_id: chats(:picker_second_chat).id,
        account_id: @first.id, url: "https://conflict.example" }, as: :json
    end

    assert_response :not_found
  end

  test "PDF registration and dashboard upload use the second account" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4\n%%EOF"),
      filename: "account.pdf", content_type: "application/pdf")

    post chat_sources_url, params: { account_id: @second.id, attachable_sgid: blob.attachable_sgid }, as: :json

    assert_response :success
    assert_equal @second.id, Document.find(response.parsed_body.fetch("id")).account_id

    post sources_documents_url, params: { document: { account_id: @second.id,
      title: "Dashboard upload", file: blob.signed_id } }, as: :json

    assert_response :created
    assert_equal @second.id, Document.find(response.parsed_body.fetch("id")).account_id
  end

  test "saved chat PDF registration accepts matching account context" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4\n%%EOF"),
      filename: "saved.pdf", content_type: "application/pdf")

    post chat_sources_url, params: { chat_id: chats(:picker_second_chat).id,
      account_id: @second.id, attachable_sgid: blob.attachable_sgid }, as: :json

    assert_response :success
    assert_equal @second.id, Document.find(response.parsed_body.fetch("id")).account_id
  end

  test "unavailable source context remains not found before SGID validation" do
    contexts = [
      { account_id: @foreign.id },
      { chat_id: chats(:picker_foreign_chat).id },
      { chat_id: chats(:picker_second_chat).id, account_id: @first.id }
    ]

    contexts.each do |context|
      assert_no_difference "Document.count" do
        post chat_sources_url, params: context.merge(attachable_sgid: "invalid"), as: :json
      end

      assert_response :not_found
    end
  end

  test "unavailable explicit source accounts never fall back to the first account" do
    assert_no_difference "Website.count" do
      post chat_sources_url, params: { account_id: @foreign.id, url: "https://foreign.example" }, as: :json
    end

    assert_response :not_found
  end

  test "follow-up URLs and references use the saved account and ignore overrides" do
    chat = chats(:picker_second_chat)
    own = websites(:picker_second_website)

    post chat_messages_url(chat), params: { message: { account_id: @first.id,
      content: "https://follow-up.example/reference", attached_website_ids: [ own.id ] } }

    assert_response :redirect
    assert_equal @second.id, chat.reload.account_id
    assert @second.websites.exists?(url: "https://follow-up.example/reference")
    assert_includes chat.messages.user.last.attached_website_ids, own.id.to_s

    assert_no_difference "Message.count" do
      assert_no_enqueued_jobs only: ChatResponseJob do
        post chat_messages_url(chat), params: { message: { content: "Wrong account",
          attached_website_ids: [ websites(:picker_first_website).id ] } }
      end
    end

    assert_response :not_found
  end

  test "PDF references cannot come from another account" do
    document = @first.documents.new(title: "First account PDF")
    document.file.attach(io: StringIO.new("%PDF-1.4\n%%EOF"), filename: "first.pdf", content_type: "application/pdf")
    document.save!
    counts = [ Chat.count, Message.count ]

    assert_no_enqueued_jobs only: ChatResponseJob do
      post chats_url, params: { chat: { account_id: @second.id, prompt: "Wrong PDF",
        model: "picker-test-model", attached_document_ids: [ document.id ] } }
    end

    assert_response :not_found
    assert_equal counts, [ Chat.count, Message.count ]
  end

  test "malformed SGIDs retain a 400 response" do
    post chat_sources_url, params: { account_id: @second.id, attachable_sgid: "invalid" }, as: :json

    assert_response :bad_request
  end
end
