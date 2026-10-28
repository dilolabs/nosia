require "test_helper"
require "yaml"

class CatalogsTest < ActiveSupport::TestCase
  PLURAL_PATHS = %w[
    nosia.account_experience.conversations_count
    nosia.account_experience.failed
    nosia.account_experience.processing
    nosia.account_experience.sources_count
    nosia.chat.sources
    nosia.sources.pasted_words
    nosia.sources.types.document
    nosia.sources.types.text
    nosia.sources.types.qna
    nosia.sources.types.website
    nosia.mcp.errors
    nosia.settings_tools.errors
    nosia.skills.errors
    nosia.skills_workspace.counts
    nosia.usage.token_unit
    nosia.usage.token_quantity
  ].freeze

  test "application catalogs have identical nonempty string leaves including owned Rails keys" do
    english = catalog_leaves(application_catalog(:en))
    french = catalog_leaves(application_catalog(:fr))

    assert_not_empty english
    assert english.keys.any? { |key| key.start_with?("nosia.chat.") }
    %w[errors.messages activerecord.attributes date.formats].each do |root|
      assert english.keys.any? { |key| key.start_with?("#{root}.") }, "Missing owned #{root} keys"
    end
    assert_equal english.keys.sort, french.keys.sort

    { en: english, fr: french }.each do |locale, leaves|
      leaves.each do |key, value|
        assert_kind_of String, value, "#{locale}.#{key}"
        assert_not_empty value.strip, "#{locale}.#{key}"
      end
    end
  end

  test "paired application messages have compatible interpolation placeholders" do
    english = catalog_leaves(application_catalog(:en))
    french = catalog_leaves(application_catalog(:fr))

    english.each do |key, value|
      assert_equal value.scan(/%\{([^}]+)\}/).flatten.sort,
        french.fetch(key).scan(/%\{([^}]+)\}/).flatten.sort, key
    end
  end

  test "English fallback works in an isolated backend without adding catalog probes" do
    backend = Class.new(I18n::Backend::Simple) { include I18n::Backend::Fallbacks }.new
    backend.store_translations(:en, nosia_fallback_probe: "English fallback")

    assert_equal "English fallback", backend.translate(:fr, :nosia_fallback_probe)
  end

  test "every application plural uses native runtime rules without fallback" do
    %i[en fr].each do |locale|
      catalog = application_catalog(locale)
      paths = catalog_leaves(catalog).keys.grep(/\.one\z/).map { |key| key.delete_suffix(".one") }
      assert_equal PLURAL_PATHS.sort, paths.sort

      PLURAL_PATHS.each do |key|
        [ 0, 1, 2, 1_000_000 ].each do |count|
          branch = (locale == :fr ? count < 2 : count == 1) ? "one" : "other"
          interpolations = { count: count, formatted_count: count.to_s, total: count.to_s, enabled: [ count, 1 ].min.to_s }
          expected = catalog.dig(*key.split("."), branch) % interpolations
          actual = I18n.t(key, locale: locale, **interpolations, fallback: false, raise: true)

          assert_equal expected, actual, "#{locale}.#{key} count=#{count}"
          refute_match(/translation missing|%\{/, actual)
        end
      end
    end
  end

  private
    def application_catalog(locale)
      files = Dir.glob(Rails.root.join("config/locales/#{locale}.nosia_*.yml")).sort
      assert_not_empty files
      seen = {}
      catalogs = files.map do |path|
        assert_unique_yaml_mappings(Psych.parse_stream(File.read(path)), path)
        catalog = YAML.safe_load_file(path, aliases: false).fetch(locale.to_s)
        catalog_leaves(catalog).each_key do |key|
          refute seen.key?(key), "Duplicate #{locale}.#{key} in #{seen[key]} and #{path}"
          seen[key] = path
        end
        catalog
      end
      catalogs.reduce({}) { |merged, catalog| merged.deep_merge(catalog) }
    end

    def catalog_leaves(value, prefix = [])
      if value.is_a?(Hash)
        value.flat_map { |key, child| catalog_leaves(child, prefix + [ key.to_s ]).to_a }.to_h
      else
        { prefix.join(".") => value }
      end
    end

    def assert_unique_yaml_mappings(node, path)
      if node.is_a?(Psych::Nodes::Mapping)
        keys = node.children.each_slice(2).map { |key, _value| key.value }
        assert_equal keys.uniq, keys, "Duplicate YAML mapping key in #{path}: #{keys.tally.select { |_key, count| count > 1 }.keys.join(', ')}"
      end
      Array(node.children).each { |child| assert_unique_yaml_mappings(child, path) }
    end
end
