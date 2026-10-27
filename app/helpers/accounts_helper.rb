# Presentation helpers for account-scoped navigation and private conversation summaries.
module AccountsHelper
  ACCOUNT_SOURCE_ICONS = { "document" => "files.svg", "text" => "file-lines.svg", "qna" => "question-circle.svg", "website" => "window.svg" }.freeze

  # @param account [Account] An account accessible to the current user
  # @return [String] The viewer's localized role within the account
  def account_role_label(account)
    t("nosia.account_experience.roles.#{account_owner?(account) ? 'owner' : 'member'}")
  end

  # @param chat [Chat] A conversation included in the bounded summary
  # @param titles [Hash{Integer => String, nil}] Batched first-question text by chat ID
  # @return [String] A plain-text title or localized fallback for a blank first question
  def account_conversation_title(chat, titles:)
    strip_tags(titles[chat.id].to_s).strip.presence || t("nosia.account_experience.untitled")
  end

  # @return [Boolean] Whether global conversation drawers must be suppressed for this account page
  def account_page?
    controller_path == "accounts" || controller_path.start_with?("accounts/") || request.path_parameters.key?(:account_id)
  end

  # @return [Boolean] Whether the page owns an Accounts workspace header/trail
  def account_workspace_header?
    controller_path == "accounts" && %w[index show].include?(action_name)
  end

  # @param account [Account, nil] An already-authorized overview account
  # @return [Array<Hash>] Explicit localized ancestor/current-page breadcrumb items
  def account_workspace_trail(account: nil)
    trail = [ { label: t("nosia.nav.home"), path: user_root_path } ]
    trail << { label: t("nosia.nav.accounts"), path: account ? accounts_path : nil }
    trail << { label: account.name, path: nil } if account
    trail
  end
end
