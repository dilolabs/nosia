module HtmlToMarkdownFormattable
  extend ActiveSupport::Concern

  class_methods do
    def html_to_markdown_attribute(attribute)
      define_method :"normalize_#{attribute}_to_markdown" do
        value = public_send(attribute)
        return if value.blank?
        # Skip saves that don't touch this attribute (e.g. Website re-crawl
        # updates index_status), so the callback only fires when the editor
        # actually submitted new content.
        return unless changes.key?(attribute.to_s)
        return unless value.to_s.match?(/<[a-z!]/i) # only convert HTML, leave plain markdown alone

        public_send("#{attribute}=", HtmlToMarkdown.convert(value, skip_images: true).content)
      end

      before_save :"normalize_#{attribute}_to_markdown"
    end
  end
end
