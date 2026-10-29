# Presentation-only conventions for the separately rendered Settings tools.
module SettingsToolsHelper
  # @return [Boolean] Whether this view has opted into its own workspace shell
  def settings_tool_workspace_page?
    content_for?(:settings_tool_workspace)
  end

  # @return [Boolean] Whether the existing route contains an account context
  def settings_tool_account_route?
    request.path_parameters.key?(:account_id)
  end

  # @return [String] Existing composer; never changes the user's default
  def settings_tool_new_chat_path
    settings_tool_account_route? ? new_chat_path(account_id: @account.id) : new_chat_path
  end

  # @param resource [String] Localized resource label
  # @param path [String] Existing resource index/read path
  # @param record [Hash, nil] Optional already-authorized detail ancestor
  # @option record [String] :label Display label for the authorized ancestor
  # @option record [String, nil] :path Existing authorized ancestor path
  # @param current [String, nil] Optional current Edit/detail label
  # @return [Array<Hash>] Linked ancestors followed by one plain current item
  def settings_tool_trail(resource:, path:, record: nil, current: nil)
    trail = [ { label: t("nosia.nav.home"), path: user_root_path } ]
    if settings_tool_account_route?
      trail += [ { label: t("nosia.nav.accounts"), path: accounts_path },
        { label: @account.name, path: account_path(@account) } ]
    else
      trail << { label: t("nosia.nav.settings"), path: settings_path }
    end
    trail << { label: resource, path: (record || current) ? path : nil }
    trail << record if record
    trail << { label: current, path: nil } if current
    trail
  end

  # @param record [ActiveRecord::Base] Invalid record; no values are serialized
  # @param targets [Hash{Symbol => String, nil}] Rendered field IDs; omitted/nil targets leave messages unlinked
  # @return [Array<Hash>] Escaped by the partial; uneditable errors have no link
  def settings_tool_errors(record, targets:)
    record.errors.map { |error| { message: error.full_message, target: targets[error.attribute] } }
  end

  # @param id [String] Rendered input ID
  # @param invalid [Boolean] Whether an inline error with this ID is rendered
  # @return [Hash] Connected help/error attributes
  def settings_tool_field_aria(id, invalid:)
    { invalid: invalid ? "true" : nil, describedby: "#{id}_help#{invalid ? " #{id}_error" : ""}" }
  end
end
