class LanguagePreferencesController < ApplicationController
  allow_unauthenticated_access only: :update

  def update
    locale = params[:locale]

    if locale == "auto" || LanguagePreference.explicit?(locale)
      if locale == "auto"
        cookies.delete(:locale, path: "/")
      else
        cookies.signed[:locale] = {
          value: locale, expires: 1.year.from_now, path: "/",
          httponly: true, same_site: :lax, secure: request.ssl?
        }
      end

      redirect_to return_path, status: :see_other
    else
      render plain: I18n.t("nosia.language.invalid"), status: :unprocessable_entity
    end
  end

  private
    def return_path
      value = params[:return_to]

      if value.is_a?(String) && value.start_with?("/") && !value.start_with?("//", "/\\")
        url_from(value) || root_path
      else
        root_path
      end
    end
end
