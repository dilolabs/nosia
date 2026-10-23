module McpCatalogHelper
  OWNED_ENTRIES = %w[infomaniak-calender kchat kdrive open_alex].freeze
  OWNED_CATEGORIES = %w[communication productivity development database search utility automation engines].freeze

  def catalog_entry_description(entry)
    if OWNED_ENTRIES.include?(entry[:id])
      t("nosia.mcp.catalog_entries.#{entry[:id]}.description")
    else
      entry[:description]
    end
  end

  def catalog_category_name(category)
    if OWNED_CATEGORIES.include?(category[:id])
      t("nosia.mcp.categories.#{category[:id]}")
    else
      category[:name]
    end
  end

  def catalog_category_description(category)
    if category[:id] == "engines"
      t("nosia.mcp.engines_description")
    else
      category[:description]
    end
  end

  def catalog_capability_label(value)
    if %w[tools prompts resources].include?(value)
      t("nosia.mcp.#{value}")
    else
      value
    end
  end

  def catalog_field_text(entry, field, kind)
    if OWNED_ENTRIES.include?(entry[:id]) && field[kind].present?
      t("nosia.mcp.catalog_entries.#{entry[:id]}.fields.#{field[:name]}.#{kind}")
    else
      field[kind]
    end
  end
end
