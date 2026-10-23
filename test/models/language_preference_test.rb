require "test_helper"

class LanguagePreferenceTest < ActiveSupport::TestCase
  test "explicit supported overrides beat the browser" do
    assert_equal :fr, LanguagePreference.resolve(override: "fr", header: "en-US")
    assert_equal :en, LanguagePreference.resolve(override: "en", header: "fr-FR")
  end

  test "invalid overrides use browser negotiation" do
    [ nil, "auto", "de", "FR", [ "fr" ], { locale: "fr" } ].each do |value|
      assert_equal :fr, LanguagePreference.resolve(override: value, header: "fr-CA")
    end
  end

  test "concrete ranges respect quality order case and regions" do
    {
      "fr-FR" => :fr,
      "fr-CA" => :fr,
      "FR-ca" => :fr,
      "en-US" => :en,
      "en-GB" => :en,
      "en;q=0.2,fr;q=0.9" => :fr,
      "fr;q=0.5,en;q=0.5" => :fr,
      "en;q=0.5,fr;q=0.5" => :en,
      "de,fr-CA;q=0.8,en;q=0.7" => :fr,
      "fr;q=0,en;q=0.2" => :en,
      "fr;q=bogus,en;q=0.1" => :en,
      "fr;q=1.1,en" => :en,
      "fr;q=-1,en" => :en,
      "fr;q=0.1234,en" => :en,
      "*;q=1,fr;q=0.5" => :fr,
      "fr_CA,en" => :en
    }.each do |header, expected|
      assert_equal expected, LanguagePreference.resolve(override: nil, header: header), header
    end
  end

  test "English is the unconditional final fallback" do
    [ nil, "", "de-DE,es;q=0.8", "*", "???", "fr;q=0,en;q=0" ].each do |header|
      assert_equal :en, LanguagePreference.resolve(override: nil, header: header)
    end
  end

  test "framework locales are available and fallback is English" do
    assert_equal [ :en, :fr ], I18n.available_locales.sort
    assert_equal :en, I18n.default_locale
    assert_includes I18n.fallbacks[:fr], :en
    assert_equal "janvier", I18n.t("date.month_names", locale: :fr).fetch(1)
  end
end
