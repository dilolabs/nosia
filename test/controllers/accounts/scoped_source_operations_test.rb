require "test_helper"
require_relative "../../support/account_experience_fixtures"

class Accounts::ScopedSourceOperationsTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures

  TYPES = { document: Document, text: Text, qna: Qna, website: Website }.freeze
  INGESTION_JOBS = [ AddDocumentJob, AddTextJob, AddQnaJob, CrawlWebsiteUrlJob ].freeze

  setup { sign_in_overview }

  TYPES.each do |type, model|
    test "#{type} creation uses the route account and rejects conflicting or malformed filing accounts" do
      path = public_send("account_sources_#{type.to_s.pluralize}_path", @second)

      [ @first.id, @foreign.id, [], {}, [ @first.id ], { id: @first.id }, true, false, "" ].each do |bad|
        assert_no_difference [ -> { model.count }, "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ] do
          rejected = type == :document ? { title: "Rejected" } : attributes_for_source(type)
          post path, params: { type => rejected.merge(account_id: bad) }, as: :json
          assert_response :not_found
        end
        assert_no_enqueued_jobs only: INGESTION_JOBS
      end

      assert_difference -> { model.where(account: @second).count }, 1 do
        post path, params: { type => attributes_for_source(type) }
        assert_response :redirect
      end
      assert_match %r{/accounts/#{@second.id}/sources/}, response.location
    end

    test "#{type} cannot be read, updated, deleted, or retried through a different account" do
      source = experience(type.to_s.pluralize, "overview_second_#{type}")
      path = public_send("account_sources_#{type}_path", @first, source)
      get path
      assert_response :not_found
      original = source.attributes

      assert_no_enqueued_jobs only: INGESTION_JOBS do
        patch path, params: { type => attributes_for_source(type) }
        assert_response :not_found
        assert_equal original, source.reload.attributes

        assert_no_difference -> { model.count } do
          delete path
          assert_response :not_found
        end

        post public_send("account_sources_#{type}_retry_path", @first, source)
        assert_response :not_found
        assert_equal original, source.reload.attributes
      end
    end

    test "#{type} update cannot reassign account and scoped retry enqueues only that source" do
      source = experience(type.to_s.pluralize, "overview_second_#{type}")
      other = experience(:texts, :overview_first_text)
      original = source.attributes
      other_original = other.attributes
      path = public_send("account_sources_#{type}_path", @second, source)

      [ @first.id, @foreign.id, [], {}, [ @first.id ], { id: @first.id }, true, false, "" ].each do |bad|
        assert_no_difference [ "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ] do
          patch path, params: { type => attributes_for_source(type).except(:file).merge(account_id: bad) }, as: :json
          assert_response :not_found
        end
        assert_equal original, source.reload.attributes
        assert_no_enqueued_jobs only: INGESTION_JOBS
      end
      assert_equal @second.id, source.account_id

      clear_enqueued_jobs
      assert_enqueued_jobs 1, only: INGESTION_JOBS do
        post public_send("account_sources_#{type}_retry_path", @second, source)
      end
      assert_redirected_to account_sources_path(@second, type: type.to_s)
      assert_equal "pending", source.reload.index_status
      assert_equal other_original, other.reload.attributes
      assert_enqueued_with job: ingestion_job(type), args: [ source.id ]
    end

    test "ordinary members can create read update retry and delete #{type} sources in their account" do
      sign_in_overview(@member)
      source = experience(type.to_s.pluralize, "overview_second_#{type}")
      path = public_send("account_sources_#{type}_path", @second, source)

      get public_send("new_account_sources_#{type}_path", @second)
      assert_response :success
      get path
      assert_response :success
      get public_send("edit_account_sources_#{type}_path", @second, source)
      assert_response :success

      created_attributes = attributes_for_source(type).merge(account_id: @second.id)
      created_attributes[:url] = "https://member-created.example/reference" if type == :website
      assert_difference -> { model.where(account: @second).count }, 1 do
        post public_send("account_sources_#{type.to_s.pluralize}_path", @second),
          params: { type => created_attributes }
        assert_response :redirect
      end
      created = model.where(account: @second).order(:id).last
      assert_redirected_to public_send("account_sources_#{type}_path", @second, created)

      clear_enqueued_jobs
      assert_enqueued_jobs 1, only: INGESTION_JOBS do
        patch path, params: { type => attributes_for_source(type).except(:file) }
      end
      assert_redirected_to path
      assert_equal @second.id, source.reload.account_id
      field = { document: :title, text: :data, qna: :question, website: :url }.fetch(type)
      assert_equal attributes_for_source(type).fetch(field), source.public_send(field)
      assert_enqueued_with job: ingestion_job(type), args: [ source.id ]

      clear_enqueued_jobs
      assert_enqueued_jobs 1, only: INGESTION_JOBS do
        post public_send("account_sources_#{type}_retry_path", @second, source)
      end
      assert_redirected_to account_sources_path(@second, type: type.to_s)
      assert_enqueued_with job: ingestion_job(type), args: [ source.id ]

      assert_difference -> { model.count }, -1 do
        delete path
      end
      options = type == :document ? {} : { type: type.to_s }
      assert_redirected_to account_sources_path(@second, **options)
      assert_not model.exists?(source.id)
    end

    test "outsiders cannot access or write #{type} sources in another account" do
      sign_in_overview(experience(:users, :overview_outsider))
      source = experience(type.to_s.pluralize, "overview_second_#{type}")
      original = source.attributes
      path = public_send("account_sources_#{type}_path", @second, source)

      assert_no_enqueued_jobs only: INGESTION_JOBS do
        assert_no_difference [ -> { model.count }, "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ] do
          get public_send("new_account_sources_#{type}_path", @second)
          assert_response :not_found
          get path
          assert_response :not_found
          get public_send("edit_account_sources_#{type}_path", @second, source)
          assert_response :not_found

          rejected = type == :document ? { title: "Rejected" } : attributes_for_source(type)
          post public_send("account_sources_#{type.to_s.pluralize}_path", @second), params: { type => rejected }, as: :json
          assert_response :not_found
          patch path, params: { type => rejected }, as: :json
          assert_response :not_found
          delete path
          assert_response :not_found
          post public_send("account_sources_#{type}_retry_path", @second, source)
          assert_response :not_found
        end
      end
      assert_equal original, source.reload.attributes
    end

    test "revoked membership denies every #{type} operation even for the account owner" do
      source = experience(type.to_s.pluralize, "overview_second_#{type}")
      path = public_send("account_sources_#{type}_path", @second, source)

      get path
      assert_response :success
      @second.account_users.find_by!(user: @user).destroy!
      assert @first.account_users.exists?(user: @user)
      assert_not @second.account_users.exists?(user: @user)
      assert_equal @user.id, @second.reload.owner_id
      original_sources = model.order(:id).map(&:attributes)

      assert_no_enqueued_jobs only: INGESTION_JOBS do
        assert_no_difference [ -> { model.count }, "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ] do
          get public_send("new_account_sources_#{type}_path", @second)
          assert_response :not_found
          get path
          assert_response :not_found
          get public_send("edit_account_sources_#{type}_path", @second, source)
          assert_response :not_found
          post public_send("account_sources_#{type.to_s.pluralize}_path", @second), params: { type => attributes_for_source(type) }
          assert_response :not_found
          patch path, params: { type => attributes_for_source(type) }
          assert_response :not_found
          delete path
          assert_response :not_found
          post public_send("account_sources_#{type}_retry_path", @second, source)
          assert_response :not_found
        end
      end
      assert_equal original_sources, model.order(:id).map(&:attributes)
    end
  end

  test "scoped source operations do not change the legacy first-account context" do
    source = experience(:texts, :overview_second_text)
    patch account_sources_text_path(@second, source), params: { text: { data: "Scoped update" } }
    assert_redirected_to account_sources_text_path(@second, source)

    get sources_path
    assert_response :success
    assert_select "[data-source-id='#{experience(:texts, :overview_first_text).id}']"
    assert_select "[data-source-id='#{source.id}']", count: 0
  end

  private
    def attributes_for_source(type)
      case type
      when :document
        { title: "Uploaded evidence", file: Rack::Test::UploadedFile.new(file_fixture("account_source.txt"), "text/plain") }
      when :text
        { data: "New account evidence" }
      when :qna
        { question: "New question?", answer: "New answer" }
      when :website
        { url: "https://new-research.example/reference", data: "New research page" }
      end
    end

    def ingestion_job(type)
      { document: AddDocumentJob, text: AddTextJob, qna: AddQnaJob, website: CrawlWebsiteUrlJob }.fetch(type)
    end
end
