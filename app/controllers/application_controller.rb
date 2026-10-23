class ApplicationController < ActionController::Base
  include Authentication
  include Localization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  # allow_browser versions: :modern

  private
  # Resolves the account a source should be filed under from form params.
  # The forms offer a picker over the user's own accounts; a forged id fails
  # closed with a 404, and no id falls back to the active account.
  def filing_account(param_root)
    if (account_id = params.dig(param_root, :account_id)).present?
      Current.user.accounts.find(account_id)
    else
      Current.account
    end
  end
end
