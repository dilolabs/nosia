module SourcesWorkspaceHelper
  # @return [Boolean] Whether the current page belongs to the Sources workspace
  def sources_workspace_page?
    controller_path == "sources" || controller_path.start_with?("sources/")
  end

  # @param account [Account, nil] The displayed, authorized account
  # @param default [Boolean] Whether this is the legacy default-account list
  # @return [String, nil] Escaped by the caller's ordinary ERB rendering
  def source_workspace_scope(account, default: false)
    if account
      key = default ? "default_account" : "account"
      t("nosia.workspace.#{key}", name: account.name)
    end
  end

  # @param title [String, nil] Current form/detail title, absent on the list
  # @return [Array<Hash>] Legacy breadcrumb; scoped pages use the account breadcrumb
  def source_workspace_trail(title: nil)
    if @scoped_source_account
      []
    else
      trail = [ { label: t("nosia.nav.home"), path: user_root_path } ]
      trail << { label: t("nosia.sources.title"), path: title ? source_index_path : nil }
      trail << { label: title, path: nil } if title
      trail
    end
  end

  # @param record [Document, Text, Qna, Website] Existing source; content may be empty
  # @return [String] Presentation fallback only, without mutating stored content
  def source_workspace_title(record)
    record.display_title.presence || t("nosia.sources_workspace.untitled_source", type: record.source_type_label)
  end

  # @param record [Document, Text, Qna, Website] Source being deleted
  # @param account_name [String, nil] Supplied by request/broadcast, never lazily loaded
  # @return [String] Plain confirmation text; standalone rendering falls back to account ID
  def source_delete_confirmation(record, account_name: nil)
    t("nosia.sources_workspace.delete_confirm", title: source_workspace_title(record), account: account_name.presence || record.account_id.to_s)
  end
end
