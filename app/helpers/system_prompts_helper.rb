# Presentation-only paths, labels, and navigation for authorized system prompts.
module SystemPromptsHelper
  # @param prompt [Prompt] Existing or unsaved authorized account fallback
  # @return [String] Existing context-preserving read URL
  def prompt_workspace_read_path(prompt)
    settings_tool_account_route? ? account_system_prompt_path(@account) : system_prompt_path(prompt)
  end

  # @param prompt [Prompt] Existing or unsaved authorized account fallback
  # @return [String] Existing edit URL
  def prompt_workspace_edit_path(prompt)
    settings_tool_account_route? ? edit_account_system_prompt_path(@account) : edit_system_prompt_path(prompt)
  end

  # @param prompt [Prompt] Already-authorized record
  # @return [Boolean] Mirrors existing controller/view permissions, not new ownership policy
  def prompt_workspace_editable?(prompt)
    prompt.user_id.present? || account_owner?(prompt.account)
  end

  # @param prompt [Prompt] Authorized saved prompt
  # @return [String] Kind without disclosing another user's personal identity
  def prompt_workspace_kind(prompt)
    t(prompt.user_id.nil? ? "nosia.settings_tools.account_default" : "nosia.settings_tools.user_specific")
  end

  # @param prompt [Prompt] Authorized record or fallback
  # @param editing [Boolean] Whether Edit is current
  # @return [Array<Hash>] One context-correct resource breadcrumb
  def prompt_workspace_trail(prompt, editing: false)
    if settings_tool_account_route?
      settings_tool_trail(resource: t("nosia.settings_tools.prompt_title"), path: account_system_prompt_path(@account), current: editing ? t("nosia.actions.edit") : nil)
    else
      record = { label: prompt.account.name, path: editing ? system_prompt_path(prompt) : nil }
      settings_tool_trail(resource: t("nosia.prompts.title"), path: system_prompts_path, record: record, current: editing ? t("nosia.actions.edit") : nil)
    end
  end
end
