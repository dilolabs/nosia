# Identifies the global Settings navigation hub for layout decisions.
module SettingsHelper
  # @return [Boolean] Whether this is the global Settings navigation hub
  def settings_workspace_page?
    controller_path == "settings" && action_name == "show"
  end
end
