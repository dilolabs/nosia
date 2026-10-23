module Localization
  extend ActiveSupport::Concern

  included do
    prepend_around_action :with_request_locale
    helper_method :language_preference_value
  end

  private
    def with_request_locale(&operation)
      I18n.with_locale(request_locale) do
        set_locale_response_headers
        operation.call
      ensure
        set_locale_response_headers unless response.committed?
      end
    end

    def set_locale_response_headers
      response.set_header("Content-Language", I18n.locale.to_s)

      if locale_varies_by_request?
        vary = response.get_header("Vary").to_s.split(",").map(&:strip)

        unless vary.include?("*")
          response.set_header("Vary", (vary + %w[Accept-Language Cookie]).uniq(&:downcase).join(", "))
        end
      end
    end

    def request_locale
      LanguagePreference.resolve(override: cookies.signed[:locale], header: request.headers["Accept-Language"])
    end

    def language_preference_value
      value = cookies.signed[:locale]
      LanguagePreference.explicit?(value) ? value : "auto"
    end

    def locale_varies_by_request?
      true
    end
end
