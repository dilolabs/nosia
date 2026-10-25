require "test_helper"
require_relative "../../support/account_experience_fixtures"

class Accounts::ScopedSourcesTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures

  setup { sign_in_overview }

  test "second-account list renders only its sources and keeps account context in every list control" do
    get "/accounts/#{@second.id}/sources"
    assert_response :success
    assert_select "[data-source-id='#{experience(:texts, :overview_second_text).id}']"
    assert_select "[data-source-id='#{experience(:texts, :overview_first_text).id}']", count: 0
    assert_select "form[action='#{account_sources_path(@second)}']", minimum: 1
    assert_select "a[href='#{account_sources_path(@second, type: 'document')}']"
    assert_select "[data-dropzone-url-value='#{account_sources_documents_path(@second)}']"
    assert_select "[data-dropzone-account-id-value='#{@second.id}']"
    assert_select "a[href='#{new_account_sources_document_path(@second)}']"

    get account_sources_path(@second, type: "text", q: "Research", sort: "title")
    assert_response :success
    assert_select "[data-source-id]", count: 1
  end

  test "all four type filters stay within the second account" do
    %w[document text qna website].each do |type|
      get "/accounts/#{@second.id}/sources", params: { type: type }
      assert_response :success
      assert_select "[data-source-id]", count: 1
    end

    get "/accounts/#{@foreign.id}/sources"
    assert_response :not_found
  end

  test "legacy list retains its first-account default" do
    get sources_path
    assert_response :success
    assert_select "[data-source-id='#{experience(:texts, :overview_first_text).id}']"
    assert_select "[data-source-id='#{experience(:texts, :overview_second_text).id}']", count: 0
  end

  test "scoped load-more responses use account paths" do
    get "/accounts/#{@second.id}/sources", params: { format: :turbo_stream, type: "text", page: 2 }
    assert_response :success
    assert_includes response.media_type, "turbo-stream"
    assert_includes response.body, "sources_load_more"
  end

  test "only the route account controls scoped access and the legacy list ignores account parameters" do
    get "/accounts/#{@second.id}/sources", params: { account_id: @foreign.id }
    assert_response :success
    assert_select "[data-source-id='#{experience(:texts, :overview_second_text).id}']"

    get "/accounts/#{@foreign.id}/sources", params: { account_id: @second.id }
    assert_response :not_found

    get sources_path, params: { account_id: @second.id }
    assert_response :success
    assert_select "[data-source-id='#{experience(:texts, :overview_first_text).id}']"
    assert_select "[data-source-id='#{experience(:texts, :overview_second_text).id}']", count: 0
    assert_select "[data-dropzone-url-value='#{sources_documents_path}']"
    assert_select "[data-dropzone-account-id-value]", count: 0
  end

  test "members can read sources but revoked membership cannot" do
    sign_in_overview(@member)
    get "/accounts/#{@second.id}/sources"
    assert_response :success
    assert_select "[data-source-id='#{experience(:texts, :overview_second_text).id}']"

    sign_in_overview
    experience(:account_users, :overview_owner_second).destroy!
    get "/accounts/#{@second.id}/sources"
    assert_response :not_found
  end

  test "list stream subscriptions use the requested account and searched lists skip live prepends" do
    get "/accounts/#{@second.id}/sources", params: { type: "text", status: "failed" }
    assert_response :success
    assert_select "turbo-cable-stream-source", count: 2 do |elements|
      names = elements.map { |element| Turbo::StreamsChannel.verified_stream_name(element["signed-stream-name"]) }
      assert_equal [ "#{@second.to_gid_param}:sources:#{I18n.locale}",
        "#{@second.to_gid_param}:sources:list:text:failed:#{I18n.locale}" ], names
    end

    get "/accounts/#{@second.id}/sources", params: { q: "Research" }
    assert_response :success
    assert_select "turbo-cable-stream-source", count: 1
  end

  test "filters toolbar add menu and empty states retain scoped or legacy paths" do
    options = { type: "text", status: "failed", sort: "title", q: "Research" }
    get account_sources_path(@second), params: options
    assert_response :success
    assert_select "form[data-source-toolbar][action='#{account_sources_path(@second)}'][method='get']", count: 1
    assert_select "input[name='type'][value='text']", count: 1
    assert_select "select[name='status'] option[selected][value='failed']"
    assert_select "input[name='q'][value='Research']", count: 1
    assert_select "select[name='sort'] option[selected][value='title']"
    %w[failed pending].each do |status|
      assert_select "a[href='#{account_sources_path(@second, **options.merge(status: status))}']"
    end
    SourceRow::TYPES.each do |type|
      assert_select "a[href='#{account_sources_path(@second, **options.merge(type: type))}']"
      new_path = public_send("new_account_sources_#{type}_path", @second)
      assert_select "a[href='#{new_path}']"
    end
    SourceRow::TYPES.each do |type|
      get account_sources_path(@empty), params: { type: type }
      assert_response :success
      new_path = public_send("new_account_sources_#{type}_path", @empty)
      assert_select ".sources-empty a[href='#{new_path}']"
    end
    get sources_path
    assert_response :success
    assert_select "form[data-source-toolbar][action='#{sources_path}'][method='get']", count: 1
    assert_select "[data-dropzone-url-value='#{sources_documents_path}']"
    assert_select "[data-dropzone-account-id-value]", count: 0
    SourceRow::TYPES.each do |type|
      new_path = public_send("new_sources_#{type}_path")
      assert_select "a[href='#{new_path}']"
    end
  end

  test "HTML and turbo load-more links preserve scoped filters search and sort" do
    101.times do |index|
      @second.texts.create!(title: "Research page #{index}", data: "Research pagination", index_status: :failed)
    end
    options = { type: "text", status: "failed", q: "Research", sort: "title" }

    get "/accounts/#{@second.id}/sources", params: options
    assert_response :success
    assert_select "[data-source-id]", count: SourcesController::PAGE_SIZE
    assert_select "#sources_load_more a[href='#{account_sources_path(@second, **options, page: 2, format: :turbo_stream)}']"

    get "/accounts/#{@second.id}/sources", params: options.merge(page: 2, format: :turbo_stream)
    assert_response :success
    assert_select "turbo-stream[action='append'][target='sources_list'] template" do
      assert_select "[data-source-id]", count: SourcesController::PAGE_SIZE
      assert_select "#sources_load_more a[href='#{account_sources_path(@second, **options, page: 3, format: :turbo_stream)}']"
    end
  end

  test "record paths and background rows use record account IDs without loading the account" do
    Current.reset
    paths = Class.new do
      include Rails.application.routes.url_helpers
      include SourcesHelper
    end.new

    SourceRow::TYPES.each do |type|
      record = experience(type.pluralize, "overview_second_#{type}")
      record.file.blob if record.is_a?(Document)
      record.association(:account).reset
      record.strict_loading!
      base = "/accounts/#{@second.id}/sources/#{type.pluralize}/#{record.id}"

      assert_equal "#{base}.html", paths.source_show_path(record, format: :html)
      assert_equal "#{base}/edit", paths.source_edit_path(record)
      assert_equal "#{base}/retry", paths.source_retry_path(record)
      html = ApplicationController.render(partial: "sources/source", locals: { row: SourceRow.new(record, chunks_count: 0) })
      assert_includes html, "href=\"#{base}\""
      assert_includes html, "action=\"#{base}/retry\"" if record.failed?
      assert_not record.association(:account).loaded?
    end
  end

  test "collection new and form helpers use explicit request context with a global fallback" do
    [ [ "/accounts/#{@second.id}/sources", [ @second, :sources ], "/accounts/#{@second.id}/sources" ],
      [ sources_path, [ :sources ], "/sources" ] ].each do |path, prefix, base|
      get path
      assert_response :success
      view = controller.view_context
      assert_equal base, view.source_index_path
      assert_equal "#{base}?type=text", view.source_index_path(type: "text")

      SourceRow::TYPES.each do |type|
        record = experience(type.pluralize, "overview_second_#{type}")
        assert_equal "#{base}/#{type.pluralize}/new", view.source_new_path(type)
        assert_equal "#{base}/#{type.pluralize}", view.source_collection_path(type)
        assert_equal [ *prefix, record ], view.source_form_model(record)
        assert_equal "/accounts/#{@second.id}/sources/#{type.pluralize}/#{record.id}", view.source_show_path(record)
      end
    end
  end

  test "account tool routes are available alongside legacy route helpers" do
    assert_equal "/accounts/#{@second.id}", account_path(@second)
    assert_equal "/accounts/#{@second.id}/chats", account_chats_path(@second)
    assert_equal "/accounts/#{@second.id}/api_tokens", account_api_tokens_path(@second)
    assert_equal "/accounts/#{@second.id}/token_usage", account_token_usage_path(@second)
    assert_equal "/token_usage", token_usage_path
    assert_equal "/api_tokens", api_tokens_path

    SourceRow::TYPES.each do |type|
      record = experience(type.pluralize, "overview_second_#{type}")
      assert_equal "/accounts/#{@second.id}/sources/#{type.pluralize}/#{record.id}/retry",
        public_send("account_sources_#{type}_retry_path", @second, record)
      assert_equal "/sources/#{type.pluralize}/#{record.id}/retry", public_send("retry_sources_#{type}_path", record)
    end
  end
end
