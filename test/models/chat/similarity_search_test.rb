require "test_helper"
require "turbo/broadcastable/test_helper"

class Chat::SimilaritySearchTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper
  include ActionView::RecordIdentifier

  def setup
    @user = User.create!(email: "ss@example.com", password: "testpassword123")
    @account = Account.create!(name: "SS Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  # similarity_search must broadcast "searching" (embed + vector SQL) then "retrieving"
  # (context fetch + relevance scoring), in order, by rendering the thinking_animation
  # partial into #thinking_animation_content. Stubs the vector search so no pgvector /
  # embedding network call fires.
  test "similarity_search broadcasts searching then retrieving, in order" do
    fake_chunk = Struct.new(:context, :augmented_context, :chunkable).new("ctx", "aug", Object.new)
    proxy = Object.new
    proxy.define_singleton_method(:search_by_similarity) { |*| [ fake_chunk ] }
    acct = Object.new
    acct.define_singleton_method(:chunks) { proxy }
    @chat.define_singleton_method(:account) { acct }
    @chat.define_singleton_method(:context_relevance) { |*| true }
    @chat.define_singleton_method(:retrieval_fetch_k) { 5 }

    streams = capture_turbo_stream_broadcasts([ @chat, "messages" ]) do
      @chat.similarity_search("any question")
    end

    updates = streams.select { |s| s["action"] == "update" && s["target"] == "thinking_animation_content" }
    assert_equal 2, updates.size, "expected exactly searching + retrieving phase broadcasts"
    assert_includes updates[0].inner_html, "Searching", "first phase should be Searching"
    assert_includes updates[1].inner_html, "Retrieving", "second phase should be Retrieving"
  end

  test "similarity_search ignores chunks whose source no longer exists" do
    website = @account.websites.create!(url: "https://orphan.example")
    Chunk.insert_all!([ {
      chunkable_id: website.id,
      chunkable_type: "Website",
      account_id: @account.id,
      content: "orphaned content",
      metadata: { position: 1 },
      created_at: Time.current,
      updated_at: Time.current
    } ])
    orphan = Chunk.find_by!(chunkable_id: website.id, chunkable_type: "Website")
    website.delete

    proxy = Object.new
    proxy.define_singleton_method(:search_by_similarity) { |*| [ orphan ] }
    acct = Object.new
    acct.define_singleton_method(:chunks) { proxy }
    @chat.define_singleton_method(:account) { acct }
    @chat.define_singleton_method(:context_relevance) { |*| true }
    @chat.define_singleton_method(:retrieval_fetch_k) { 5 }

    original_augmented_context = ENV["AUGMENTED_CONTEXT"]
    ENV["AUGMENTED_CONTEXT"] = "true"

    assert_empty @chat.similarity_search("any question")
  ensure
    ENV["AUGMENTED_CONTEXT"] = original_augmented_context
  end
end
