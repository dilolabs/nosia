module ChatAccountScoped
  extend ActiveSupport::Concern

  class MissingAccount < StandardError; end

  NO_ACCOUNT_MESSAGE = "You need access to an account to start a chat.".freeze

  included do
    rescue_from MissingAccount do
      respond_to do |format|
        format.json { render json: { error: I18n.t("nosia.chat.no_account", locale: request_locale) }, status: :unprocessable_entity }
        format.any { render plain: I18n.t("nosia.chat.no_account", locale: request_locale), status: :unprocessable_entity }
      end
    end
  end

  private
    def selected_chat_account(account_id = nil)
      validate_chat_context_id(account_id)

      if account_id.present?
        Current.user.accounts.find(account_id)
      else
        Current.user.first_account
      end
    end

    def required_chat_account(account_id = nil)
      selected_chat_account(account_id) || raise(MissingAccount)
    end

    def authorized_chat(chat_id)
      raise ActiveRecord::RecordNotFound unless chat_id.is_a?(String) || chat_id.is_a?(Numeric)

      chat = Current.user.chats.find(chat_id)
      Current.user.accounts.find(chat.account_id)
      chat
    end

    def validate_chat_context_id(id)
      raise ActiveRecord::RecordNotFound unless id.nil? || id.is_a?(String) || id.is_a?(Numeric)
    end
end
