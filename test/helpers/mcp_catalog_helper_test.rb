require "test_helper"

class McpCatalogHelperTest < ActionView::TestCase
  test "owned catalog descriptions translate only at presentation time" do
    entry = McpCatalog.find("kchat")
    original = Marshal.dump(entry)

    I18n.with_locale(:fr) do
      assert_equal "Consultez les messages récents de kChat et publiez des messages.", catalog_entry_description(entry)
    end
    I18n.with_locale(:en) do
      assert_equal entry[:description], catalog_entry_description(entry)
    end

    assert_equal original, Marshal.dump(entry)
  end

  test "extension descriptions remain unchanged in French" do
    entry = { id: "external", description: "Unmodified external description" }

    I18n.with_locale(:fr) do
      assert_equal entry[:description], catalog_entry_description(entry)
    end
  end

  test "all owned English catalog entry and field text matches raw metadata" do
    I18n.with_locale(:en) do
      McpCatalog.all.each do |entry|
        assert_equal entry[:description], catalog_entry_description(entry)
        Array(entry[:requires_config]).each do |field|
          %i[label description placeholder help_text].each do |kind|
            assert_equal field[kind], catalog_field_text(entry, field, kind) if field[kind].present?
          end
        end
      end
    end
  end

  test "owned category and capability labels translate without changing their values" do
    category = McpCatalog.categories.find { |item| item[:id] == "engines" }
    original = Marshal.dump(category)

    I18n.with_locale(:fr) do
      assert_equal "Intégrations natives", catalog_category_name(category)
      assert_equal "Intégrations natives incluses dans Nosia.", catalog_category_description(category)
      %w[tools prompts resources].zip([ "Outils", "Instructions", "Ressources" ]).each do |value, label|
        assert_equal label, catalog_capability_label(value)
      end
      assert_equal "custom", catalog_capability_label("custom")
      assert_equal "External", catalog_category_name({ id: "external", name: "External" })
      assert_equal "Raw category", catalog_category_description({ id: "external", description: "Raw category" })
    end

    assert_equal original, Marshal.dump(category)
  end

  test "owned fields translate present text and preserve absent or extension metadata" do
    entry = McpCatalog.find("kchat")
    field = entry[:requires_config].find { |item| item[:name] == "kchat_token" }
    original = Marshal.dump(entry)

    I18n.with_locale(:fr) do
      assert_equal "Jeton kChat", catalog_field_text(entry, field, :label)
      assert_equal "Votre jeton kChat.", catalog_field_text(entry, field, :description)
      assert_nil catalog_field_text(entry, field, :placeholder)
      assert_nil catalog_field_text(entry, field, :help_text)
      external = { id: "external" }
      %i[label description placeholder help_text].each do |kind|
        assert_equal "Raw #{kind}", catalog_field_text(external, { kind => "Raw #{kind}" }, kind)
      end
    end

    assert_equal original, Marshal.dump(entry)
  end
end
