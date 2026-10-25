require "test_helper"
require_relative "../support/account_experience_fixtures"

class SourcesWorkspaceFiltersTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures

  setup { sign_in_overview }

  test "type and status links preserve other selections but reset pagination" do
    get account_sources_path(@second), params: { type: "text", status: "failed", q: "Research", sort: "title", page: 3 }
    assert_response :success
    assert_select "form[data-source-toolbar][action='#{account_sources_path(@second)}'][method='get']", count: 1
    assert_select "input[name='page']", count: 0
    assert_select "input[name='type'][value='text']", count: 1
    assert_select "input[name='q'][value='Research']", count: 1
    assert_select "select[name='status'] option[selected][value='failed']"
    assert_select "select[name='sort'] option[selected][value='title']"
    assert_link_state "[data-source-filter-type='document']", { "type" => "document", "status" => "failed", "sort" => "title", "q" => "Research" }
    assert_link_state "[data-source-filter-type='all']", { "status" => "failed", "sort" => "title", "q" => "Research" }
    assert_link_state "[data-source-filter-status='pending']", { "type" => "text", "status" => "pending", "sort" => "title", "q" => "Research" }
    assert_select "[data-source-reset][href='#{account_sources_path(@second)}']"
  end

  test "legacy controls remain default-account controls with all seven zero-capable count IDs" do
    get sources_path, params: { type: "document", status: "indexed", q: "First", sort: "chunks" }
    assert_select "form[data-source-toolbar][action='#{sources_path}']"
    assert_select "select[name='status'] option[value='indexed'][selected]"
    assert_select "[data-source-filter-status='failed'] #source_count_status-failed", text: "0"
    assert_select "[data-source-filter-status='pending'] #source_count_status-pending", text: "0"
    keys = %w[all type-document type-text type-qna type-website status-failed status-pending]
    keys.each { |key| assert_select "#source_count_#{key}", count: 1 }
    assert_select "#source_count_all", text: SourceRow.counts_for(@first).fetch(:total).to_s
    assert_link_state "[data-source-filter-type='website']", { "type" => "website", "status" => "indexed", "sort" => "chunks", "q" => "First" }, path: sources_path
  end

  private
    def assert_link_state(selector, expected, path: account_sources_path(@second))
      elements = css_select(selector)
      assert_equal 1, elements.length
      uri = URI.parse(elements.first["href"])
      assert_equal path, uri.path
      assert_equal expected, Rack::Utils.parse_nested_query(uri.query.to_s)
    end
end
