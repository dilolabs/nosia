module SourcesHelper
  SOURCE_ICONS = { "document" => "📄", "text" => "📝", "qna" => "❓", "website" => "🌐" }.freeze

  def source_type_icon(key)
    SOURCE_ICONS.fetch(key, "📄")
  end

  # Returns [css_classes, label] for a source's status chip.
  def source_status_display(record)
    if record.indexed?
      [ "bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-300", t("nosia.sources.status.indexed") ]
    elsif record.failed?
      [ "bg-red-100 text-red-800 dark:bg-red-900/40 dark:text-red-300", t("nosia.sources.status.failed") ]
    else
      label = t(record.is_a?(Website) ? "nosia.sources.status.crawling" : "nosia.sources.status.processing")
      [ "bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300", label ]
    end
  end

  # Record paths also work in background renders without request context.
  def source_show_path(record, **options)
    public_send("account_sources_#{record.model_name.element}_path", record.account_id, record, **options)
  end

  # Preserves scoped redirects without changing legacy upload response paths.
  # @param record [Document, Text, Qna, Website] The source being returned
  # @return [String] The scoped or legacy source path
  def source_response_path(record)
    @scoped_source_account ? source_show_path(record) : polymorphic_path([ :sources, record ])
  end

  def source_edit_path(record)
    public_send("edit_account_sources_#{record.model_name.element}_path", record.account_id, record)
  end

  def source_retry_path(record)
    public_send("account_sources_#{record.model_name.element}_retry_path", record.account_id, record)
  end

  def source_index_path(**options)
    if @scoped_source_account
      account_sources_path(@scoped_source_account, **options)
    else
      sources_path(**options)
    end
  end

  def source_new_path(type)
    parts = @scoped_source_account ? [ @scoped_source_account, :sources, type.to_sym ] : [ :sources, type.to_sym ]
    new_polymorphic_path(parts)
  end

  def source_form_model(record)
    @scoped_source_account ? [ @scoped_source_account, :sources, record ] : [ :sources, record ]
  end

  def source_collection_path(type)
    parts = @scoped_source_account ? [ @scoped_source_account, :sources, type.to_s.pluralize.to_sym ] : [ :sources, type.to_s.pluralize.to_sym ]
    polymorphic_path(parts)
  end
end
