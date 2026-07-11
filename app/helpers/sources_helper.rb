module SourcesHelper
  SOURCE_ICONS = { "document" => "📄", "text" => "📝", "qna" => "❓", "website" => "🌐" }.freeze

  def source_type_icon(key)
    SOURCE_ICONS.fetch(key, "📄")
  end

  # Returns [css_classes, label] for a source's status chip.
  def source_status_display(record)
    if record.indexed?
      [ "bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-300", "Indexed" ]
    elsif record.failed?
      [ "bg-red-100 text-red-800 dark:bg-red-900/40 dark:text-red-300", "Failed" ]
    else
      label = record.is_a?(Website) ? "Crawling…" : "Processing…"
      [ "bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300", label ]
    end
  end

  # Polymorphic path helpers so one partial serves all four types.
  def source_show_path(record)   = polymorphic_path([ :sources, record ])
  def source_retry_path(record)  = send("retry_sources_#{record.model_name.element}_path", record)
end
