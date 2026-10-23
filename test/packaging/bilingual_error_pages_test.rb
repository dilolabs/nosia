require "minitest/autorun"
require "nokogiri"

class BilingualErrorPagesTest < Minitest::Test
  FILES = {
    "404.html" => {
      title: "404 — Page not found / Page introuvable",
      en: [ "The page you were looking for doesn't exist.", "You may have mistyped the address or the page may have moved." ],
      fr: [ "La page que vous cherchez n’existe pas.", "L’adresse est peut-être incorrecte ou la page a été déplacée." ]
    },
    "406-unsupported-browser.html" => {
      title: "406 — Unsupported browser / Navigateur non pris en charge",
      en: [ "Your browser is not supported.", "Please upgrade your browser to continue." ],
      fr: [ "Votre navigateur n’est pas pris en charge.", "Veuillez mettre à jour votre navigateur pour continuer." ]
    },
    "422.html" => {
      title: "422 — Change rejected / Modification refusée",
      en: [ "The change you wanted was rejected.", "Maybe you tried to change something you didn't have access to." ],
      fr: [ "La modification demandée a été refusée.", "Vous avez peut-être essayé de modifier un élément auquel vous n’avez pas accès." ]
    },
    "500.html" => {
      title: "500 — Application error / Erreur de l’application",
      en: [ "We're sorry, but something went wrong." ],
      fr: [ "Une erreur est survenue. Veuillez nous en excuser." ]
    }
  }.freeze

  FILES.each do |name, copy|
    define_method("test_#{name}_has_readable_English_and_French_body_sections") do
      document = error_page(name)

      %i[en fr].each do |locale|
        section = document.at_css("body .dialog div[lang='#{locale}']")
        refute_nil section, "#{name} needs a #{locale} body section"
        heading = section.at_css("h1")
        refute_nil heading
        refute_empty heading.text.strip
        assert_equal copy.fetch(locale).first, heading.text.strip
        assert_equal copy.fetch(locale).drop(1), section.css("p").map { |paragraph| paragraph.text.strip }
      end
      unless name.start_with?("406")
        assert_equal "If you are the application owner check the logs for more information.", document.at_css(".dialog > p[lang='en']")&.text
        assert_equal "Si vous gérez cette application, consultez les journaux pour plus d’informations.", document.at_css(".dialog > p[lang='fr']")&.text
      end
    end

    define_method("test_#{name}_retains_its_status_title_and_document_metadata") do
      document = error_page(name)

      assert_equal "en", document.at_css("html")["lang"]
      assert_equal copy.fetch(:title), document.at_css("title").text
      assert_includes document.at_css("title").text, name.to_i.to_s
      refute_nil document.at_css('meta[name="viewport"]')
      refute_empty document.css("style").text.strip
    end

    define_method("test_#{name}_needs_no_Rails_JavaScript_or_external_stylesheets") do
      document = error_page(name)

      assert_empty document.css("script, link[rel='stylesheet']")
      refute_match(/<%|url\s*\(|@import/i, document.to_html)
    end
  end

  private
    def error_page(name)
      Nokogiri::HTML(File.read(File.expand_path("../../public/" + name, __dir__)))
    end
end
