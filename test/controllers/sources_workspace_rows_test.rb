require "test_helper"
require "turbo/broadcastable/test_helper"
require_relative "../support/account_experience_fixtures"

class SourcesWorkspaceRowsTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures
  include Turbo::Broadcastable::TestHelper

  setup { sign_in_overview }

  test "rows show type status metadata and independent actions with named account confirmation" do
    source = experience(:texts, :overview_second_text)
    source.update_columns(title: "<script>Source title</script>")

    get account_sources_path(@second)

    row = "##{ActionView::RecordIdentifier.dom_id(source, :source_row)}"
    assert_select "#{row} [data-source-type-label]", text: "Text"
    assert_select "#{row} [data-source-index-status='failed']", text: "Failed"
    assert_select "#{row} [data-source-chunks]"
    assert_select "#{row} time[datetime]"
    assert_select "#{row} [data-source-type-icon] svg[aria-hidden='true']"
    assert_select "#{row} a[data-source-edit][href='#{edit_account_sources_text_path(@second, source)}']"
    assert_select "#{row} form[action='#{account_sources_text_retry_path(@second, source)}'][data-turbo-confirm]", count: 0
    assert_select "#{row} a a, #{row} a button, [data-source-workspace] script", count: 0
    confirmation = css_select("#{row} a[data-turbo-method='delete']").first["data-turbo-confirm"]
    assert_includes confirmation, source.display_title
    assert_includes confirmation, @second.name
    assert_select "[data-source-upload] button[data-action='source-upload#browse']"
    assert_select "[data-source-upload] [data-dropzone-variant-value='dashboard']", count: 0
    assert_select "[data-source-upload][data-dropzone-variant-value='dashboard']"
  end

  test "standalone and live rows do not require request context or per-row account queries" do
    source = experience(:texts, :overview_second_text)
    source.association(:account).reset
    source.strict_loading!
    Current.reset

    html = ApplicationController.render(partial: "sources/source", locals: { row: SourceRow.new(source, chunks_count: 7) })
    fragment = Nokogiri::HTML.fragment(html)
    assert_select fragment, "[data-source-chunks][data-value='7']"
    assert_select fragment, "a[data-source-edit][href='#{edit_account_sources_text_path(@second, source)}']"
    assert_not source.association(:account).loaded?

    source = Text.find(source.id)
    streams = capture_turbo_stream_broadcasts([ @second, "sources", :en ]) { source.mark_indexing_failed! }
    row = streams.find { |stream| stream["target"] == ActionView::RecordIdentifier.dom_id(source, :source_row) }
    assert row
    assert_includes row.to_html, @second.name
    refute_includes row.to_html, "/accounts/#{@first.id}/"
  end

  test "permitted empty text keeps an accessible title without a new validation rule" do
    source = experience(:texts, :overview_second_text)
    source.update_columns(title: nil, data: "")

    get account_sources_path(@second)

    assert_select "[data-source-id='#{source.id}'] .n-source-title", text: "Untitled Text"
    confirmation = css_select("[data-source-id='#{source.id}'] a[data-turbo-method='delete']").first["data-turbo-confirm"]
    assert_includes confirmation, "Untitled Text"
    assert_empty source.reload.data
    assert source.valid?
  end

  test "empty searches are escaped and all type-empty states retain their add destination" do
    get account_sources_path(@second), params: { q: "<script>missing</script>" }
    assert_select ".sources-empty script", count: 0
    assert_select ".sources-empty [data-source-reset][href='#{account_sources_path(@second)}']"

    get account_sources_path(@empty), params: { status: "indexed" }
    assert_select ".sources-empty h3", text: I18n.t("nosia.sources_workspace.empty_filtered")
    assert_select ".sources-empty [data-source-reset][href='#{account_sources_path(@empty)}']"

    SourceRow::TYPES.each do |type|
      get account_sources_path(@empty), params: { type: type }
      path = public_send("new_account_sources_#{type}_path", @empty)
      assert_select ".sources-empty h3", text: I18n.t("nosia.sources.empty.#{type}")
      assert_select ".sources-empty a[href='#{path}']"
    end
  end
end
