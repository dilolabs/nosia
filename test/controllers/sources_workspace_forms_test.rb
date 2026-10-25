require "test_helper"
require_relative "../support/account_experience_fixtures"

class SourcesWorkspaceFormsTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures

  setup { sign_in_overview }

  test "all scoped forms share the layout and keep existing nested fields and fixed account" do
    SourceRow::TYPES.each do |type|
      source = experience(type.pluralize, "overview_second_#{type}")
      paths = [ public_send("new_account_sources_#{type}_path", @second), public_send("edit_account_sources_#{type}_path", @second, source) ]
      paths.each do |path|
        assert_no_enqueued_jobs { get path }
        assert_response :success
        assert_select "[data-source-workspace] h1", count: 1
        assert_select ".n-source-form-layout form[data-controller='source-form']", count: 1
        assert_select "form input[type='hidden'][name='#{type}[account_id]'][value='#{@second.id}']"
        assert_select "form select[name='#{type}[account_id]']", count: 0
        assert_select "form input[type='submit'][data-turbo-submits-with]"
        assert_select "[data-source-form-help]"
        assert_select "#accordion-right-actions, #drawer-right", count: 0
      end
    end
  end

  test "legacy editing is read-only for account identity and document replacement is explicit" do
    sign_in_overview(@member)
    SourceRow::TYPES.each do |type|
      source = experience(type.pluralize, "overview_second_#{type}")
      get public_send("edit_sources_#{type}_path", source)
      assert_response :success
      assert_select "form select[name='#{type}[account_id]']", count: 0
      assert_select "form [data-source-fixed-account]", text: @second.name
      if type == "document"
        assert_select "[data-source-current-file]", text: /#{Regexp.escape(source.file.filename.to_s)}/
        assert_select "input[type='file'][name='document[file]']"
      end
    end
  end

  test "failed legacy document creation retains its chosen filing account and connected error" do
    assert_no_enqueued_jobs do
      post sources_documents_path, params: { document: { title: "Keep this title", account_id: @second.id } }
    end
    assert_response :unprocessable_entity
    assert_select "[data-source-form-target='errors'][tabindex='-1'][role='alert'] a[href='#document_file']", text: "File can't be blank"
    assert_select "input[name='document[title]'][value='Keep this title']"
    assert_select "select[name='document[account_id]'] option[value='#{@second.id}'][selected]"
    assert_select "input#document_file[aria-invalid='true'][aria-describedby='document_file_help document_file_error']"
    assert_select "#document_file_error", text: "File can't be blank"
    assert_equal @first, @user.first_account
  end

  test "website 422 errors retain editor content without changing existing validation" do
    post account_sources_websites_path(@second), params: { website: { url: "", data: "Keep **this** content" } }
    assert_response :unprocessable_entity
    assert_select "[role='alert'] a[href='#website_url']", text: "Url can't be blank"
    assert_select "input#website_url[aria-invalid='true']"
    assert_select "lexxy-editor[name='website[data]'][attachments='false']" do |editors|
      assert_equal Commonmarker.to_html("Keep **this** content"), editors.first["value"]
    end
  end

  test "source-specific error summary escapes base messages and omits an empty summary" do
    source = experience(:texts, :overview_second_text)
    source.errors.add(:base, "<script>unsafe</script>")
    form = ActionView::Helpers::FormBuilder.new(:text, source, controller.view_context, {})
    html = ApplicationController.render(partial: "sources/form_errors", locals: { form: form, fields: [ :data ] })
    fragment = Nokogiri::HTML.fragment(html)
    assert_select fragment, "[role='alert'] li", text: "<script>unsafe</script>"
    assert_select fragment, "script, li a", count: 0
    source.errors.clear
    assert_empty ApplicationController.render(partial: "sources/form_errors", locals: { form: form, fields: [ :data ] }).strip
  end
end
