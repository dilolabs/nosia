require "test_helper"
require_relative "../support/account_experience_fixtures"

class SourcesWorkspaceDetailsTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures

  setup { sign_in_overview(@member) }

  test "long Q&A questions remain fully visible and escaped with custom or abbreviated titles" do
    source = experience(:qnas, :overview_second_qna)
    question = "How does the research policy preserve the full question when it exceeds the presentation title limit? <script>alert('question')</script>"
    answer = source.answer

    [ "Research policy in detail", nil ].each do |title|
      source.update_columns(title: title, question: question)
      before = source.reload.attributes

      assert_no_enqueued_jobs { get account_sources_qna_path(@second, source) }
      assert_response :success
      assert_select "[data-source-detail] h1", text: title || question.first(80)
      assert_select "[data-source-full-question]", text: question
      assert_select "[data-source-detail-content] h2", text: I18n.t("nosia.sources.question_label")
      assert_select "[data-source-detail-content] h2", text: I18n.t("nosia.sources.answer_label")
      assert_select "[data-source-answer]", text: answer
      assert_select "[data-source-detail] script, [data-source-detail] [onerror]", count: 0
      assert_equal before, source.reload.attributes
    end
  end

  test "a short Q&A question matching its title is not repeated in the body" do
    source = experience(:qnas, :overview_second_qna)

    get account_sources_qna_path(@second, source)
    assert_response :success
    assert_select "[data-source-detail] h1", text: source.question
    assert_select "[data-source-full-question]", count: 0
    assert_select "[data-source-detail-content]", text: source.answer
  end

  test "each legacy and scoped detail names the source and account with separate actions" do
    SourceRow::TYPES.each do |type|
      source = experience(type.pluralize, "overview_second_#{type}")
      scoped = public_send("account_sources_#{type}_path", @second, source)
      legacy = public_send("sources_#{type}_path", source)
      edit_path = public_send("edit_account_sources_#{type}_path", @second, source)
      [ legacy, scoped ].each do |path|
        before = source.reload.attributes
        assert_no_enqueued_jobs { get path }
        assert_response :success
        assert_select "[data-source-detail] h1", text: source.display_title
        assert_select "[data-workspace-scope]", text: "Account: #{@second.name}"
        assert_select "[data-source-detail] [data-source-type-label]", text: source.source_type_label
        status_key = source.pending? ? (type == "website" ? "crawling" : "processing") : source.index_status
        assert_select "[data-source-detail] [data-source-index-status='#{source.index_status}']",
          text: I18n.t("nosia.sources.status.#{status_key}")
        chunks_count = source.chunks.count
        chunks_value = source.pending? && chunks_count.zero? ? "—" : ActiveSupport::NumberHelper.number_to_delimited(chunks_count)
        assert_select "[data-source-detail] [data-source-chunks]", text: I18n.t("nosia.sources_workspace.chunk_value", value: chunks_value)
        assert_select "[data-source-detail] time[datetime='#{source.created_at.iso8601}']"
        assert_select "[data-source-detail] a[data-source-edit][href='#{edit_path}']", text: I18n.t("nosia.sources.#{type.pluralize}.edit_action")
        assert_select "[data-source-detail] a[data-turbo-method='delete'][href='#{scoped}']" do |links|
          assert_includes links.first["data-turbo-confirm"], source.display_title
          assert_includes links.first["data-turbo-confirm"], @second.name
        end
        assert_select "#accordion-right-actions, #drawer-right", count: 0
        assert_equal before, source.reload.attributes
        retry_path = public_send("account_sources_#{type}_retry_path", @second, source)
        assert_select "[data-source-detail] form[action='#{retry_path}']", count: source.failed? ? 1 : 0
      end
    end
  end

  {
    en: { indexed: "Indexed", failed: "Failed", crawling: "Crawling…", processing: "Processing…", chunks: "Chunks: " },
    fr: { indexed: "Indexé", failed: "En échec", crawling: "Exploration…", processing: "Traitement…", chunks: "Extraits : " }
  }.each do |locale, labels|
    test "#{locale} detail requests show localized statuses and distinguish pending chunks from real zero counts" do
      SourceRow::TYPES.each do |type|
        source = experience(type.pluralize, "overview_second_#{type}")
        before = source.reload.attributes
        chunks_count = source.chunks.count
        assert_equal 0, chunks_count
        status_key = source.pending? ? (type == "website" ? :crawling : :processing) : source.index_status.to_sym
        chunks_value = source.pending? ? "—" : ActiveSupport::NumberHelper.number_to_delimited(chunks_count, locale: locale)
        paths = [ public_send("sources_#{type}_path", source), public_send("account_sources_#{type}_path", @second, source) ]

        paths.each do |path|
          assert_no_enqueued_jobs { get path, headers: { "Accept-Language" => locale.to_s } }
          assert_response :success
          assert_select "[data-source-detail] [data-source-index-status='#{source.index_status}']", text: labels.fetch(status_key)
          assert_select "[data-source-detail] [data-source-chunks]", text: "#{labels.fetch(:chunks)}#{chunks_value}"
          assert_select "[data-source-detail] time[datetime='#{source.created_at.iso8601}']"
          assert_equal before, source.reload.attributes
        end
      end

      source = experience(:texts, :overview_second_text)
      source.update_columns(index_status: :pending)
      before = source.reload.attributes
      assert_equal 0, source.chunks.count

      [ sources_text_path(source), account_sources_text_path(@second, source) ].each do |path|
        assert_no_enqueued_jobs { get path, headers: { "Accept-Language" => locale.to_s } }
        assert_response :success
        assert_select "[data-source-detail] [data-source-index-status='pending']", text: labels.fetch(:processing)
        assert_select "[data-source-detail] [data-source-chunks]", text: "#{labels.fetch(:chunks)}—"
        assert_select "[data-source-detail] time[datetime='#{source.created_at.iso8601}']"
        assert_equal before, source.reload.attributes
      end
    end
  end

  test "text and Q&A stay escaped while website HTML keeps its existing sanitizer" do
    text = experience(:texts, :overview_second_text)
    qna = experience(:qnas, :overview_second_qna)
    website = experience(:websites, :overview_second_website)
    text.update_columns(data: "<script>alert('text')</script>")
    qna.update_columns(question: "<img src=x onerror=alert(1)>", answer: "<script>alert('answer')</script>")
    website.update_columns(data: "# Safe heading\n\n**Safe bold**\n\n<script>alert('website')</script>\n\n<img src=x onerror=alert(1)>")

    [ text, qna, website ].each do |source|
      type = source.model_name.element
      get public_send("account_sources_#{type}_path", @second, source)
      assert_response :success
      assert_select "[data-source-detail] script, [data-source-detail] [onerror]", count: 0
      assert_equal source.data, source.reload.data if source.respond_to?(:data)
    end
    get account_sources_text_path(@second, text)
    assert_select "[data-source-detail-content]", text: "<script>alert('text')</script>"
    get account_sources_qna_path(@second, qna)
    assert_select "[data-source-detail-content]", text: "<script>alert('answer')</script>"
    get account_sources_website_path(@second, website)
    assert_select "[data-source-detail-content] strong", text: "Safe bold"
  end

  test "empty permitted content has a presentation title but remains unchanged" do
    source = experience(:texts, :overview_second_text)
    source.update_columns(title: nil, data: "")

    get account_sources_text_path(@second, source)
    assert_response :success
    assert_select "[data-source-detail] .n-workspace-header h1", text: "Untitled Text"
    assert_empty source.reload.data
  end

  test "document details keep the original file link and MIME-specific preview" do
    source = experience(:documents, :overview_second_document)

    get account_sources_document_path(@second, source)
    assert_response :success
    assert_select "[data-source-file-link][target='_blank'][rel='noopener']", text: source.file.filename.to_s
    assert_select "[data-source-file-link][href*='/rails/active_storage/']"
    assert_select "[data-source-document-preview] iframe, [data-source-document-preview] img", count: 0

    source.file.blob.update_columns(content_type: "application/pdf")
    get account_sources_document_path(@second, source)
    assert_select "[data-source-document-preview] iframe[title='#{source.display_title}']"

    source.file.blob.update_columns(content_type: "image/png")
    get account_sources_document_path(@second, source)
    assert_select "[data-source-document-preview] img[alt='#{source.display_title}']"
  end
end
