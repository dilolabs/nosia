require "test_helper"
require_relative "../support/settings_tool_fixtures"

class SettingsToolsHelperTest < ActionView::TestCase
  include SettingsToolFixtures

  test "header opts in once and never gives a global page scoped navigation" do
    @account = @second
    request.path_parameters = { controller: "system_prompts", action: "index" }
    refute view.settings_tool_workspace_page?
    render partial: "settings_tools/header", locals: {
      title: "Owned title", trail: [ { label: "Owned title", path: nil } ]
    }
    assert view.settings_tool_workspace_page?
    assert_includes rendered, new_chat_path
    refute_includes rendered, new_chat_path(account_id: @second.id)
    assert_equal "Owned title", view.content_for(:title)
  end

  test "account route trail and new chat use the authorized URL account" do
    @account = @second
    request.path_parameters = { controller: "api_tokens", action: "index", account_id: @second.id }
    assert_equal new_chat_path(account_id: @second.id), settings_tool_new_chat_path
    trail = settings_tool_trail(resource: "Tokens", path: account_api_tokens_path(@second))
    assert_equal [ user_root_path, accounts_path, account_path(@second), nil ], trail.map { |item| item[:path] }
    assert_equal "Tokens", trail.last[:label]
    assert_equal @first, @user.reload.first_account
  end

  test "summary counts displayed items and escapes authored messages" do
    render partial: "settings_tools/errors", locals: { items: [
      { message: "<script>One</script>", target: "first" },
      { message: "Two", target: "second" }
    ] }
    assert_includes rendered, I18n.t("nosia.settings_tools.errors", count: 2)
    assert_includes rendered, 'data-error-field="first"'
    refute_includes rendered, "<script>"
  end

  test "global edit trail keeps settings and the authorized record ancestor" do
    request.path_parameters = { controller: "system_prompts", action: "edit" }
    record = { label: "Research", path: "/authorized-prompt" }

    trail = settings_tool_trail(resource: "Prompts", path: "/prompts", record: record, current: "Edit")

    refute settings_tool_account_route?
    assert_equal [ user_root_path, settings_path, "/prompts", "/authorized-prompt", nil ], trail.map { |item| item[:path] }
    assert_equal record, trail[-2]
    assert_equal "Edit", trail.last[:label]
  end

  test "record errors link only to fields rendered by the form" do
    @shared.errors.add(:content, "cannot be blank")
    @shared.errors.add(:base, "could not be saved")

    items = settings_tool_errors(@shared, targets: { content: "prompt_content" })

    assert_equal @shared.errors.full_messages, items.map { |item| item[:message] }
    assert_equal [ "prompt_content", nil ], items.map { |item| item[:target] }
  end

  test "field aria connects help and only rendered inline errors" do
    assert_equal({ invalid: nil, describedby: "prompt_content_help" }, settings_tool_field_aria("prompt_content", invalid: false))
    assert_equal({ invalid: "true", describedby: "prompt_content_help prompt_content_error" }, settings_tool_field_aria("prompt_content", invalid: true))
  end
end
