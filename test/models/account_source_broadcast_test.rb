require "test_helper"
require "turbo/broadcastable/test_helper"
require_relative "../support/account_experience_fixtures"

class AccountSourceBroadcastTest < ActiveSupport::TestCase
  include AccountExperienceFixtures
  include Turbo::Broadcastable::TestHelper

  test "background rows retain canonical second-account show delete and retry URLs" do
    source = experience(:texts, :overview_second_text)
    Current.reset
    html = ApplicationController.render(partial: "sources/source", locals: { row: SourceRow.new(source, chunks_count: 0) })
    assert_includes html, Rails.application.routes.url_helpers.account_sources_text_path(@second, source)
    assert_includes html, Rails.application.routes.url_helpers.account_sources_text_retry_path(@second, source)
    delete_link = Nokogiri::HTML.fragment(html).at_css("a[data-turbo-method='delete']")
    assert_equal Rails.application.routes.url_helpers.account_sources_text_path(@second, source), delete_link["href"]
    streams = capture_turbo_stream_broadcasts([ @second, "sources", :en ]) { source.mark_indexing_failed! }
    row = streams.find { |stream| stream["target"] == ActionView::RecordIdentifier.dom_id(source, :source_row) }
    assert row
    assert_includes row.to_html, "/accounts/#{@second.id}/sources/texts/#{source.id}"
    refute_includes row.to_html, "/accounts/#{@first.id}/"
  end

  test "background row actions have localized accessible names and decorative icons" do
    source = experience(:texts, :overview_second_text)
    Current.reset

    %i[en fr].each do |locale|
      I18n.with_locale(locale) do
        html = ApplicationController.render(partial: "sources/source", locals: { row: SourceRow.new(source, chunks_count: 0) })
        row = Nokogiri::HTML.fragment(html)
        retry_button = row.at_css("form button")
        delete_link = row.at_css("a[data-turbo-method='delete']")

        assert_equal I18n.t("nosia.actions.retry"), retry_button["aria-label"]
        assert_equal I18n.t("nosia.actions.delete"), delete_link["aria-label"]
        assert retry_button.at_css("span[aria-hidden='true']")
        assert delete_link.at_css("svg[aria-hidden='true']")
        assert_includes retry_button["class"].split, "n-main-focus-tertiary"
        assert_includes delete_link["class"].split, "n-main-focus-danger"
        assert row.at_css("a.n-main-focus")
      end
    end
  end
end
