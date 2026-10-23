require "test_helper"
require_relative "../../support/account_experience_fixtures"

class Accounts::ScopedSourceOperationsTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures

  TYPES = { document: Document, text: Text, qna: Qna, website: Website }.freeze
  INGESTION_JOBS = [ AddDocumentJob, AddTextJob, AddQnaJob, CrawlWebsiteUrlJob ].freeze

  setup { sign_in_overview }

  TYPES.each do |type, model|
    test "#{type} scoped edit keeps fixed account identity and a nested form action" do
      source = experience(type.to_s.pluralize, "overview_second_#{type}")
      path = public_send("account_sources_#{type}_path", @second, source)

      get public_send("edit_account_sources_#{type}_path", @second, source)
      assert_response :success
      assert_select "form[action='#{path}']" do
        assert_select "input[name='_method'][value='patch']"
        assert_select "input[type='hidden'][name='#{type}[account_id]'][value='#{@second.id}']"
        assert_select "select[name='#{type}[account_id]']", count: 0
        assert_select "label[for='#{type}_account_id']", count: 0
        assert_select "p", text: @second.name
        assert_select "a[href='#{path}']", text: I18n.t("nosia.actions.cancel")

        case type
        when :document
          assert_select "input[name='document[title]'][value='#{source.title}']"
          assert_select "input[type='file'][name='document[file]']"
        when :text, :qna, :website
          field = type == :qna ? :answer : :data
          value = type == :website ? source.to_html : Commonmarker.to_html(source.public_send(field).to_s.encode("UTF-8"))
          assert_select "lexxy-editor[name='#{type}[#{field}]'][attachments='false']" do |editors|
            assert_equal value, editors.first["value"]
          end
        end
      end
    end

    test "#{type} new edit and show links retain the route account" do
      source = experience(type.to_s.pluralize, "overview_second_#{type}")
      path = public_send("account_sources_#{type}_path", @second, source)
      index_path = account_sources_path(@second, type: type.to_s)
      edit_path = public_send("edit_account_sources_#{type}_path", @second, source)

      get public_send("new_account_sources_#{type}_path", @second)
      assert_response :success
      assert_select "a[href='#{index_path}'] .sr-only", text: I18n.t("nosia.actions.back")
      assert_select "form a[href='#{account_sources_path(@second)}']", text: I18n.t("nosia.actions.cancel")

      get edit_path
      assert_response :success
      assert_select "a[href='#{path}'] .sr-only", text: I18n.t("nosia.actions.back")
      assert_select "form a[href='#{path}']", text: I18n.t("nosia.actions.cancel")

      get path
      assert_response :success
      assert_select "a[href='#{index_path}'] .sr-only", text: I18n.t("nosia.actions.back")
      assert_select "a[href='#{edit_path}'] .sr-only", text: I18n.t("nosia.sources.#{type.to_s.pluralize}.edit_action")
      assert_select "a[href='#{path}'][data-turbo-method='delete'][data-turbo-confirm] .sr-only",
        text: I18n.t("nosia.sources.#{type.to_s.pluralize}.delete_action")
    end

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

  test "all scoped forms have fixed account identity and nested form actions" do
    TYPES.each_key do |type|
      get public_send("new_account_sources_#{type}_path", @second)
      assert_response :success
      assert_select "form[action='#{public_send("account_sources_#{type.to_s.pluralize}_path", @second)}']"
      assert_select "input[type='hidden'][name='#{type}[account_id]'][value='#{@second.id}']"
      assert_select "select[name='#{type}[account_id]']", count: 0
      assert_select "label[for='#{type}_account_id']", count: 0
      assert_select "form p", text: @second.name
    end
  end

  test "invalid document and website retain account and visible errors" do
    post account_sources_documents_path(@second), params: { document: { title: "Keep this title" } }
    assert_response :unprocessable_entity
    assert_select "[role='alert'] li", minimum: 1
    assert_select "input[name='document[title]'][value='Keep this title']"
    assert_select "input[type='hidden'][name='document[account_id]'][value='#{@second.id}']"
    assert_select "form[action='#{account_sources_documents_path(@second)}']"

    post account_sources_websites_path(@second), params: { website: { url: "", data: "Keep this content" } }
    assert_response :unprocessable_entity
    assert_select "[role='alert'] li", minimum: 1
    assert_select "input[type='hidden'][name='website[account_id]'][value='#{@second.id}']"
    assert_select "form[action='#{account_sources_websites_path(@second)}']"
    assert_select "lexxy-editor[name='website[data]'][attachments='false']" do |editors|
      assert_equal Commonmarker.to_html("Keep this content"), editors.first["value"]
    end
  end

  test "invalid website edit retains rich text account and nested action" do
    website = experience(:websites, :overview_second_website)
    path = account_sources_website_path(@second, website)

    assert_no_enqueued_jobs only: INGESTION_JOBS do
      patch path, params: { website: { url: "", data: "Keep **edited** content" } }
    end
    assert_response :unprocessable_entity
    assert_select "[role='alert'] li", text: "Url can't be blank"
    assert_select "form[action='#{path}']"
    assert_select "input[type='hidden'][name='website[account_id]'][value='#{@second.id}']"
    assert_select "lexxy-editor[name='website[data]'][attachments='false']" do |editors|
      assert_equal Commonmarker.to_html("Keep **edited** content"), editors.first["value"]
    end
    assert_select "form a[href='#{path}']", text: I18n.t("nosia.actions.cancel")
  end

  test "legacy new forms retain labeled membership selectors and global form actions" do
    TYPES.each_key do |type|
      get public_send("new_sources_#{type}_path")
      assert_response :success
      assert_select "form[action='#{public_send("sources_#{type.to_s.pluralize}_path")}']" do
        assert_select "label[for='#{type}_account_id']", text: I18n.t("nosia.sources.account_label")
        assert_select "select[name='#{type}[account_id]']" do
          assert_select "option[value='#{@first.id}'][selected]"
          assert_select "option[value='#{@second.id}']"
          assert_select "option[value='#{@foreign.id}']", count: 0
        end
        assert_select "input[type='hidden'][name='#{type}[account_id]']", count: 0
      end
    end
  end

  test "document JSON advertises its canonical account URL" do
    document = experience(:documents, :overview_second_document)

    get account_sources_document_path(@second, document, format: :json)
    assert_response :success
    assert_equal account_sources_document_path(@second, document, format: :json), response.parsed_body.fetch("url")
    assert_equal document.title, response.parsed_body.fetch("title")
  end

  test "validation summaries escape messages and omit an empty error list" do
    source = experience(:texts, :overview_second_text)
    message = "<script>alert('unsafe')</script>"
    source.errors.add(:base, message)

    html = ApplicationController.render(partial: "application/validation_errors", locals: { record: source })
    fragment = Nokogiri::HTML.fragment(html)
    assert_select fragment, "[role='alert'] li", text: message
    assert_select fragment, "script", count: 0

    source.errors.clear
    assert_empty ApplicationController.render(partial: "application/validation_errors", locals: { record: source }).strip
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
