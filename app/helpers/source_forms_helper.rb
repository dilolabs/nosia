# Connects existing source fields with their help and validation messages.
module SourceFormsHelper
  # @param form [ActionView::Helpers::FormBuilder] Existing source builder
  # @param attribute [Symbol] Existing field
  # @param help [String, nil] Optional help element ID
  # @param options [Hash] Ordinary field options such as class or attachments
  # @return [Hash] Stable field ID and connected validation attributes
  def source_field_options(form, attribute, help: nil, **options)
    invalid = form.object.errors.include?(attribute)
    described_by = [ help, invalid ? form.field_id(attribute, :error) : nil ].compact
    options.merge(id: form.field_id(attribute), aria: { invalid: invalid, describedby: described_by.presence&.join(" ") })
  end

  # Renders failed drafts through the existing normalization without changing the source.
  # @param website [Website] Source whose editor value is being rendered
  # @return [String] Editor HTML using the existing Markdown and frontmatter policy
  def source_website_editor_value(website)
    if website.errors.any? && website.will_save_change_to_data?
      presentation = website.dup
      presentation.normalize_data_to_markdown
      presentation.to_html
    else
      website.to_html
    end
  end
end
