require "test_helper"
require_relative "../support/settings_tool_fixtures"

class PromptsWorkspaceTest < ActionDispatch::IntegrationTest
  include SettingsToolFixtures

  setup { sign_in_overview }

  test "five variants own bilingual shells without other resource management" do
    %i[en fr].each do |locale|
      paths = [ system_prompts_path, system_prompt_path(@shared), edit_system_prompt_path(@shared),
        account_system_prompt_path(@second), edit_account_system_prompt_path(@second) ]
      paths.each do |path|
        assert_no_difference [ "Prompt.count", "Chat.count", "ApiToken.count", "AccountUser.count" ] do
          get path, headers: { "Accept-Language" => locale.to_s }
        end
        assert_response :success
        assert_select "main h1", count: 1
        assert_equal css_select("main h1").first.text, css_select("head title").first.text
        assert_select "main .n-workspace-header nav", count: 1
        assert_select "main nav [aria-current=page]", count: 1
        assert_select "#drawer-right, #accordion-right-actions", count: 0
        assert_select "[data-settings-tool] [data-token-row], [data-settings-tool] [data-member-row]", count: 0
        assert_select "[data-settings-tool] input[name^='api_token'], [data-settings-tool] input[name^='account_user']", count: 0
        refute_match(/translation missing|missing translation/i, response.body)
      end
    end
  end

  test "directory preserves both saved record kinds without listing personal identity data" do
    before = @user.accounts.flat_map { |account| account.prompts.where(name: "system_prompt").pluck(:id) }
    get system_prompts_path
    assert_select "[data-prompt-row]", count: before.size
    [ @shared, @personal ].each { |prompt| assert_select "[data-prompt-row] a[href=?]", system_prompt_path(prompt) }
    assert_select "[data-prompt-row]", text: /#{Regexp.escape(I18n.t('nosia.settings_tools.account_default'))}/
    assert_select "[data-prompt-row]", text: /#{Regexp.escape(I18n.t('nosia.settings_tools.user_specific'))}/
    refute_includes css_select("[data-prompt-row]").map(&:text).join, @member.email
  end

  test "read pages escape literal prompt text and preserve placeholders without writes" do
    content = "<script>Literal instructions</script>\n\nReference: %{documents}"
    @shared.update!(content: content)
    [ system_prompt_path(@shared), account_system_prompt_path(@second) ].each do |path|
      get path
      assert_select "main script", count: 0
      assert_select "[data-prompt-content]", count: 1 do |elements|
        assert_equal content, elements.first.content
      end
      assert_equal content, @shared.reload.content
      assert_select "[data-settings-tool] a[href=?]", path == system_prompt_path(@shared) ? edit_system_prompt_path(@shared) : edit_account_system_prompt_path(@second), count: 1
    end
  end

  test "invalid global save stays on its editor with linked errors and unchanged stored data" do
    stored = @shared.content
    patch system_prompt_path(@shared), params: { prompt: { content: " \n ", account_id: @foreign.id } }
    assert_response :unprocessable_entity
    assert_select "[data-settings-screen=prompt-edit]"
    assert_select "[data-form-errors-target=summary][role=alert][tabindex='-1'] a[href='#prompt_content']"
    assert_select "#prompt_content[aria-invalid=true][aria-describedby='prompt_content_help prompt_content_error']"
    assert_equal " \n ", css_select("#prompt_content").first.content
    assert_select "a[href=?]", system_prompt_path(@shared), text: I18n.t("nosia.actions.cancel")
    assert_equal stored, @shared.reload.content
    assert_equal @second.id, @shared.account_id
  end

  test "missing account fallback is truthful and materializes only on valid explicit update" do
    [ account_system_prompt_path(@first), edit_account_system_prompt_path(@first) ].each do |path|
      assert_no_difference("Prompt.count") { get path }
      assert_response :success
      assert_select "[data-prompt-state]", text: I18n.t("nosia.settings_tools.prompt_builtin")
    end
    assert_no_difference("Prompt.count") do
      patch account_system_prompt_path(@first), params: { prompt: { content: "" } }
    end
    assert_response :unprocessable_entity
    assert_select "[data-settings-screen=account-prompt-edit] #prompt_content[aria-invalid=true]"
    content = "Saved exactly\n%{documents}"
    assert_difference("Prompt.count", 1) do
      patch account_system_prompt_path(@first), params: { prompt: { content: content, account_id: @foreign.id } }
    end
    assert_redirected_to account_system_prompt_path(@first)
    assert_equal content, @first.reload.system_prompt
    get account_system_prompt_path(@first)
    assert_select "[data-prompt-state]", text: I18n.t("nosia.settings_tools.prompt_saved")
    assert_equal "Personal research override", @second.system_prompt(user: @member)
    assert_equal @first, @user.reload.first_account
  end

  test "current mutation permissions are preserved rather than inferred from display labels" do
    sign_in_overview(@member)
    get account_system_prompt_path(@second)
    assert_response :success
    assert_select "a[href=?]", edit_account_system_prompt_path(@second), count: 0
    get edit_account_system_prompt_path(@second)
    assert_response :forbidden
    patch system_prompt_path(@shared), params: { prompt: { content: "forbidden" } }
    assert_response :forbidden
    patch system_prompt_path(@personal), params: { prompt: { content: "Existing permitted override" } }
    assert_redirected_to system_prompt_path(@personal)
    assert_equal "Existing permitted override", @personal.reload.content
    sign_in_overview(@outsider)
    get system_prompt_path(@shared)
    assert_response :not_found
    get account_system_prompt_path(@second), params: { account_id: @foreign.id }
    assert_response :not_found
  end

  test "global and account New chat keep their distinct context and legacy destroy remains" do
    get edit_system_prompt_path(@shared)
    assert_select ".n-workspace-header a[href=?]", new_chat_path
    assert_select ".lg\\:hidden a[href=?]", new_chat_path
    get edit_account_system_prompt_path(@second)
    assert_select ".n-workspace-header a[href=?]", new_chat_path(account_id: @second.id)
    assert_select ".lg\\:hidden a[href=?]", new_chat_path(account_id: @second.id)
    assert_select "[data-settings-tool] form input[name=_method][value=delete]", count: 0
    assert_difference("Prompt.count", -1) { delete system_prompt_path(@personal) }
    assert_redirected_to system_prompts_path
    assert_equal @first, @user.reload.first_account
  end
end
