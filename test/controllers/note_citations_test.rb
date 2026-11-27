require "test_helper"
require_relative "../support/note_retrieval_fixtures"

class NoteCitationsTest < ActionDispatch::IntegrationTest
  include NoteRetrievalFixtures

  setup do
    sign_in_picker_user
    @chat = chats(:picker_second_chat)
  end

  test "a current Note citation is labeled and links to its saved account workspace" do
    note = indexed_note(@second, "UNTITLED_EVIDENCE", title: "")
    chunk = note.chunks.sole
    answer_citing(chunk, @second_text, @foreign_chunk)

    get chat_url(@chat)

    assert_response :success
    assert_select "a[href='#{account_note_path(@second, note)}']" do
      assert_select "p", text: "Untitled"
      assert_select "p", text: "Note"
    end
    assert_select "a[href='#{chunk_path(@second_text, chat_id: @chat.id)}']"
    assert_select "a[href='#{account_note_path(@foreign, @foreign_note)}']", count: 0

    get chunk_url(chunk), params: { chat_id: @chat.id, account_id: @first.id }
    assert_redirected_to account_note_path(@second, note)

    get chunk_url(@first_chunk)
    assert_redirected_to account_note_path(@first, @first_note)
  end

  test "previous citation IDs do not expose inactive, stale, or foreign Note chunks" do
    folder = @second.note_folders.create!(name: "Archived")
    @second_note.move_to(folder)
    old_note = indexed_note(@second, "STALE_CITATION")
    old_chunk = old_note.chunks.sole
    message = answer_citing(@second_chunk, old_chunk, @foreign_chunk, @second_text)
    folder.trash
    old_note.edit_content!(expected_revision: old_note.content_revision, title: "Changed", body_html: "<p>Edited</p>")

    assert_equal [ @second_text.id ], message.similar_chunks.ids
    get chat_url(@chat)
    assert_response :success
    assert_includes response.body, "Previously generated answer"
    assert_select "a[href='#{chunk_path(@second_text, chat_id: @chat.id)}']"
    [ @second_note, old_note, @foreign_note ].each do |note|
      assert_select "a[href='#{account_note_path(note.account, note)}']", count: 0
    end
    [ @second_chunk, old_chunk, @foreign_chunk ].each do |chunk|
      get chunk_url(chunk), params: { chat_id: @chat.id }
      assert_response :not_found
    end
  end

  test "revoked chat membership hides Notes from saved citations and direct URLs" do
    answer = answer_citing(@second_chunk, @second_text)
    assert_includes answer.similar_chunks.ids, @second_chunk.id
    @second.account_users.find_by!(user: @user).destroy!

    assert_equal [ @second_text.id ], answer.similar_chunks.ids
    get chunk_url(@second_chunk), params: { chat_id: @chat.id }
    assert_response :not_found
  end

  private
    def answer_citing(*chunks)
      @chat.messages.create!(role: :assistant, content: "Previously generated answer", similar_chunk_ids: chunks.map(&:id))
    end
end
