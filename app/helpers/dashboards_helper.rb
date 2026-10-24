# Fixed dashboard navigation metadata and layout identification.
module DashboardsHelper
  # @return [Boolean] Whether the dashboard replaces the global history drawers
  def dashboard_page?
    controller_path == "dashboards" && action_name == "show"
  end

  # @param account [Account, nil] The user's existing default account, not the draft selection
  # @return [Array<Hash>] Fixed, labeled navigation destinations
  def dashboard_shortcuts(account:)
    scope = account ? t("nosia.dashboard.default_account", name: account.name) : t("nosia.dashboard.choose_account")

    [
      { key: "accounts", path: accounts_path, icon: "folders", scope: t("nosia.dashboard.your_accounts") },
      { key: "sources", path: account ? sources_path : accounts_path, icon: "file-search", scope: scope },
      { key: "usage", path: token_usage_path, icon: "chart-bar", scope: t("nosia.dashboard.usage_scope") },
      { key: "profile", path: profile_path, icon: "identification", scope: t("nosia.dashboard.your_profile") },
      { key: "skills", path: account ? agent_skills_path : accounts_path, icon: "code-bracket", scope: scope },
      { key: "tokens", path: api_tokens_path, icon: "clipboard", scope: t("nosia.dashboard.your_tokens") },
      { key: "mcp", path: account ? mcp_servers_path : accounts_path, icon: "window", scope: scope },
      { key: "prompts", path: system_prompts_path, icon: "chats", scope: t("nosia.dashboard.prompts_scope") }
    ]
  end
end
