require "test_helper"
require_relative "../support/account_experience_fixtures"

class AccountExperienceTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures

  setup do
    sign_in_overview
  end

  test "settings and account editing return to the hub with useful breadcrumbs" do
    get account_settings_path(@second)
    assert_redirected_to account_path(@second)
    get edit_account_path(@second)
    assert_response :success
    assert_select "a[href='#{account_path(@second)}']", minimum: 1
    patch account_path(@second), params: { account: { name: "Research renamed", uid: "research-renamed" } }
    assert_redirected_to account_path(@second)
    [ account_sources_path(@second), account_chats_path(@second), account_api_tokens_path(@second),
      account_token_usage_path(@second), account_system_prompt_path(@second), account_account_users_path(@second) ].each do |path|
      get path
      assert_response :success
      breadcrumb = I18n.t(path == account_system_prompt_path(@second) ? "nosia.workspace.breadcrumb" : "nosia.account_experience.breadcrumb")
      assert_select "nav[aria-label=?] a[href=?]", breadcrumb, account_path(@second)
      assert_select "#accordion-right-actions", count: 0
      assert_select "#drawer-right", count: 0
    end
  end

  test "every scoped source editor and detail page has a hub breadcrumb" do
    SourceRow::TYPES.each do |type|
      source = experience(type.pluralize, "overview_second_#{type}")
      [ public_send("new_account_sources_#{type}_path", @second),
        public_send("edit_account_sources_#{type}_path", @second, source),
        public_send("account_sources_#{type}_path", @second, source) ].each do |path|
        get path
        assert_response :success
        assert_select "nav[aria-label='Breadcrumb']" do
          assert_select "a[href='#{accounts_path}']", text: "Accounts"
          assert_select "a[href='#{account_path(@second)}']", text: @second.name
          assert_select "[aria-current='page']", text: "Knowledge sources"
        end
        assert_select "#accordion-right-actions, #drawer-right", count: 0
      end
    end
  end

  test "hub and account form breadcrumbs escape names and keep cancel context" do
    @second.update_columns(name: "<script>Account name</script>")

    get account_path(@second)
    assert_response :success
    assert_select "nav[aria-label='Breadcrumb'] [aria-current='page']", text: @second.name
    assert_select "nav[aria-label='Breadcrumb'] a[href='#{account_path(@second)}']", count: 0
    assert_select "nav script", count: 0

    get edit_account_path(@second)
    assert_response :success
    assert_select "nav[aria-label='Breadcrumb'] a[href='#{account_path(@second)}']", text: @second.name
    assert_select "nav[aria-label='Breadcrumb'] [aria-current='page']", text: "Edit account"
    assert_select "form a[href='#{account_path(@second)}']", text: "Cancel"
    assert_select "nav script", count: 0

    get new_account_path
    assert_response :success
    assert_select "nav[aria-label='Breadcrumb']", count: 1 do
      assert_select "a[href='#{accounts_path}']", text: "Accounts"
      assert_select "[aria-current='page']", text: "New Account"
      assert_select "a[href='#{account_path(@second)}']", count: 0
      assert_select "a", count: 1
    end
    assert_select "form a[href='#{accounts_path}']", text: "Cancel"
  end

  test "new and edit accounts share translated form presentation without changing their actions" do
    @second.update_columns(name: "<script>Account name</script>", uid: "research-uid")

    %i[en fr].each do |locale|
      headers = { "Accept-Language" => locale.to_s }
      [ [ new_account_path, false ], [ edit_account_path(@second), true ] ].each do |path, editing|
        get path, headers: headers

        assert_response :success
        title = I18n.t(editing ? "nosia.accounts.edit" : "nosia.accounts.new", name: @second.name, locale: locale)
        assert_select ".n-title-container h2.n-main-title.mt-0\\.5.mb-2", text: title
        assert_select "nav[aria-label='#{I18n.t('nosia.account_experience.breadcrumb', locale: locale)}']" do
          assert_select "a[href='#{accounts_path}']", text: I18n.t("nosia.nav.accounts", locale: locale)
          assert_select "a", count: editing ? 2 : 1
          assert_select "li[aria-hidden='true']", count: editing ? 2 : 1
          assert_select "[aria-current='page']", text: I18n.t(editing ? "nosia.account_experience.edit_account" : "nosia.accounts.new", locale: locale)
          assert_select "a[href='#{account_path(@second)}']", text: @second.name if editing
        end
        assert_select ".n-form-container form[action='#{editing ? account_path(@second) : accounts_path}'][method='post']" do
          assert_select "input[name='_method'][value='patch']", count: editing ? 1 : 0
          assert_select "label[for='account_name']", text: I18n.t("nosia.accounts.name", locale: locale)
          assert_select "label[for='account_uid']", text: I18n.t("nosia.accounts.uid", locale: locale)
          assert_select "input[name='account[name]']" do |fields|
            assert_equal editing ? @second.name : "", fields.first["value"].to_s
          end
          assert_select "input[name='account[uid]']" do |fields|
            assert_equal editing ? @second.uid : "", fields.first["value"].to_s
          end
          assert_select "input[type='submit'][value='#{I18n.t('nosia.actions.save', locale: locale)}']"
          assert_select "a[href='#{editing ? account_path(@second) : accounts_path}']", text: I18n.t("nosia.actions.cancel", locale: locale)
        end
        assert_select "main script, main svg:not([aria-hidden='true'])", count: 0
        assert_select "#accordion-right-actions, #drawer-right", count: 0
      end
    end
  end

  test "members can open the new account form but cannot edit account details" do
    sign_in_overview(@member)

    get new_account_path
    assert_response :success
    assert_select ".n-form-container form[action='#{accounts_path}']"

    get edit_account_path(@second)
    assert_response :forbidden
  end

  test "global tools retain their own contextual navigation and drawer boundaries" do
    prompt_path = system_prompt_path(experience(:prompts, :overview_second_shared))
    [ sources_path, new_sources_text_path, api_tokens_path, token_usage_path, prompt_path ].each do |path|
      get path
      assert_response :success
      sources = [ sources_path, new_sources_text_path ].include?(path)
      report = path == token_usage_path
      prompts = path == prompt_path
      assert_select "nav[aria-label=?]", prompts ? I18n.t("nosia.workspace.breadcrumb") : I18n.t("nosia.account_experience.breadcrumb"), count: prompts ? 1 : 0
      assert_select "#accordion-right-actions, #drawer-right", count: sources || report || prompts ? 0 : 2
      if sources || report || prompts
        workspace = sources ? "[data-source-workspace]" : (report ? "[data-usage-workspace]" : "[data-settings-tool]")
        assert_select workspace, count: 1
        assert_select "#{workspace} a[href='#{new_chat_path}']", text: I18n.t("nosia.nav.new_chat")
      end
    end
  end

  test "settings alias requires route membership without requiring ownership" do
    sign_in_overview(@member)
    get account_settings_path(@second)
    assert_redirected_to account_path(@second)

    get account_settings_path(@foreign), params: { account_id: @second.id }
    assert_response :not_found

    sign_in_overview
    experience(:account_users, :overview_owner_second).destroy!
    get account_settings_path(@second)
    assert_response :not_found
  end

  test "directory exposes accessible account and new-conversation links" do
    get accounts_path

    assert_response :success
    assert_select "[data-account-id]", count: 3
    assert_select "a[href='#{account_path(@second)}']"
    assert_select "a[href='#{new_chat_path(account_id: @second.id)}']"
    refute_includes response.body, @foreign.name
  end

  test "hub uses second-account summaries without exposing other members' private data" do
    get account_path(@second)

    assert_response :success
    assert_select "[data-conversation-id]", count: 5
    assert_select "[data-source-type]", count: 4
    assert_select "a[href='#{account_sources_path(@second, type: 'text')}']"
    assert_select "a[href='#{account_token_usage_path(@second)}']"
    assert_select "a[href='#{account_api_tokens_path(@second)}']"
    assert_select "a[href='#{edit_account_path(@second)}']"
    assert_includes response.body, "Shared research instructions"
    refute_includes response.body, "Personal research override"
    refute_includes response.body, "Member private question"
    refute_includes response.body, "Alpha private question"
    refute_includes response.body, experience(:api_tokens, :overview_second_token).token_digest
    assert_select "a[href='#{account_sources_path(@second, status: 'failed')}']"
    assert_select "a[href='#{account_sources_path(@second, status: 'pending')}']"
    assert_select "dd", text: "900"
    assert_select "dd", text: "100"
    assert_select "#accordion-collapse, #drawer-right", count: 0
    assert_equal @first, @user.first_account
  end

  test "member hub hides management but retains read-only prompt, own tokens, and account usage" do
    sign_in_overview(@member)
    get account_path(@second)

    assert_response :success
    assert_select "a[href='#{edit_account_path(@second)}']", count: 0
    assert_select "a[href='#{account_account_users_path(@second)}']", count: 0
    assert_select "a[href='#{account_system_prompt_path(@second)}']"
    assert_select "a[href='#{account_api_tokens_path(@second)}']"
    assert_select "a[href='#{account_token_usage_path(@second)}']"
    assert_select "[data-conversation-id]", count: 1
    assert_includes response.body, "Shared research instructions"
    refute_includes response.body, "Personal research override"
    refute_includes response.body, @user.email
  end

  test "history is private, account-specific, stable, and paginated" do
    expected_ids = @second.conversations_for(@user).pluck(:id).map(&:to_s)
    get account_chats_path(@second)

    assert_response :success
    assert_select "[data-conversation-id]", count: 25
    assert_equal expected_ids.first(25), css_select("[data-conversation-id]").map { |row| row["data-conversation-id"] }
    assert_select "a[rel=next][href='#{account_chats_path(@second, page: 2)}']"
    assert_select "a[rel=prev]", count: 0
    refute_includes response.body, "Member private question"
    refute_includes response.body, "Alpha private question"

    get account_chats_path(@second, page: 2)

    assert_response :success
    assert_select "[data-conversation-id]", count: 3
    assert_equal expected_ids.drop(25), css_select("[data-conversation-id]").map { |row| row["data-conversation-id"] }
    assert_select "a[rel=prev][href='#{account_chats_path(@second, page: 1)}']"
    assert_select "a[rel=next]", count: 0

    get account_path(@foreign)
    assert_response :not_found
    get account_chats_path(@foreign)
    assert_response :not_found
  end

  test "empty hub reads do not create prompts chats sources or provider jobs" do
    before = [ Prompt.count, Chat.count, Document.count, Text.count, Qna.count, Website.count ]

    get account_path(@empty)

    assert_response :success
    assert_equal before, [ Prompt.count, Chat.count, Document.count, Text.count, Qna.count, Website.count ]
    assert_no_enqueued_jobs only: ChatResponseJob
    assert_select "a[href='#{new_chat_path(account_id: @empty.id)}']", minimum: 1
    assert_select "a[href='#{account_sources_path(@empty)}']", minimum: 1
    assert_select ".n-account-prompt", text: /#{Regexp.escape(Prompts.system_prompt.first(100))}/
    assert_empty @empty.prompts.reload
  end

  test "directory bounds accounts and provides separate navigation actions" do
    25.times do |index|
      Account.create!(name: "Additional account #{index}", owner: @user).account_users.grant_to(@user)
    end
    expected_ids = @user.accounts.order(:name, :id).pluck(:id).map(&:to_s)
    statements = []
    subscriber = ->(_name, _start, _finish, _id, payload) { statements << payload[:sql] unless payload[:cached] || payload[:name] == "SCHEMA" }

    Account.uncached do
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { get accounts_path }
    end

    assert_response :success
    source_queries = statements.grep(/\ASELECT\b.*\bFROM\s+["`]?\b(documents|texts|qnas|websites)\b["`]?/im)
    assert_equal 4, source_queries.size
    source_queries.each { |sql| assert_match(/COUNT\(.*GROUP BY/im, sql) }
    assert_select "[data-account-id]", count: 24
    assert_equal expected_ids.first(24), css_select("[data-account-id]").map { |row| row["data-account-id"] }
    assert_select "a[rel=next][href='#{accounts_path(page: 2)}']"
    assert_select "a a", count: 0

    get accounts_path(page: 2)

    assert_response :success
    assert_select "[data-account-id]", count: 4
    assert_equal expected_ids.drop(24), css_select("[data-account-id]").map { |row| row["data-account-id"] }
    assert_select "a[rel=prev][href='#{accounts_path(page: 1)}']"
    assert_select "a[rel=next]", count: 0
  end

  test "invalid page values fall back to the first page" do
    [ "nonsense", "0", "-3", [ "2" ], { number: "2" } ].each do |page|
      get accounts_path, params: { page: page }
      assert_response :success
      assert_select "[data-account-id]", count: 3
      assert_select "a[rel=prev]", count: 0

      get account_chats_path(@second), params: { page: page }
      assert_response :success
      assert_select "[data-conversation-id]", count: 25
      assert_select "a[rel=prev]", count: 0
    end
  end

  test "oversized directory pages normalize before calculating the SQL offset" do
    get accounts_path, params: { page: "999999999999999999999999999999" }

    assert_response :success
    assert_select "[data-account-id]", count: 3
    assert_select "a[rel=prev]", count: 0
  end

  test "oversized history pages normalize before calculating the SQL offset" do
    get account_chats_path(@second), params: { page: "999999999999999999999999999999" }

    assert_response :success
    assert_select "[data-conversation-id]", count: 25
    assert_select "a[rel=prev]", count: 0
  end

  test "history ties use descending IDs and pages beyond the end remain actionable" do
    @second.conversations_for(@user).update_all(updated_at: Time.utc(2026, 1, 4))
    expected_ids = 28.times.map { |index| experience(:chats, "overview_second_chat_#{index}").id }.sort.reverse.map(&:to_s)

    get account_chats_path(@second)
    assert_response :success
    assert_equal expected_ids.first(25), css_select("[data-conversation-id]").map { |row| row["data-conversation-id"] }

    get account_chats_path(@second, page: 3)
    assert_response :success
    assert_select "[data-conversation-id]", count: 0
    assert_select "a[rel=prev][href='#{account_chats_path(@second, page: 2)}']"
    assert_select "a[rel=next]", count: 0
    assert_select "a[href='#{new_chat_path(account_id: @second.id)}']", minimum: 1
  end

  test "query parameters cannot replace route account IDs" do
    get account_path(@foreign), params: { id: @second.id }
    assert_response :not_found

    get account_chats_path(@foreign), params: { account_id: @second.id }
    assert_response :not_found

    get account_path(@second), params: { id: @foreign.id }
    assert_response :success
    assert_select "[data-account-overview='#{@second.id}']"

    get account_chats_path(@second), params: { account_id: @foreign.id }
    assert_response :success
    assert_select "[data-conversation-id]", count: 25
  end

  test "revoked membership prevents owner hub and history reads" do
    experience(:account_users, :overview_owner_second).destroy!

    get account_path(@second)
    assert_response :not_found

    get account_chats_path(@second)
    assert_response :not_found
  end

  test "authored account prompt and conversation text cannot inject markup" do
    @second.update_columns(name: "<script>Account name</script>", uid: "<img src=x onerror=alert(1)>")
    experience(:prompts, :overview_second_shared).update_columns(content: "<script>Shared prompt</script>")
    experience(:messages, :overview_second_question_27).update_columns(content: "<context>Private evidence</context><b>Safe question</b>")
    experience(:messages, :overview_second_question_26).update_columns(content: "<p> </p>")

    get account_path(@second)

    assert_response :success
    assert_select "h1", text: @second.name
    assert_select ".n-account-prompt", text: "<script>Shared prompt</script>"
    assert_select "[data-conversation-id] a", text: "Safe question"
    assert_select "[data-conversation-id] a", text: "Untitled conversation"
    assert_select "main script, main img[onerror], [data-conversation-id] b", count: 0
    refute_includes response.body, "Private evidence"
  end

  test "directory empty state offers account creation without global conversation drawers" do
    sign_in_overview(experience(:users, :overview_no_account))

    get accounts_path

    assert_response :success
    assert_select "[data-account-id]", count: 0
    assert_select "h2", text: "No accounts yet"
    assert_select "a[href='#{new_account_path}']"
    assert_select "#accordion-collapse, #drawer-right", count: 0
  end

  test "French account overview and history translate navigation and privacy labels" do
    headers = { "Accept-Language" => "fr" }
    prompt = experience(:prompts, :overview_second_shared).attributes
    memberships = @user.account_users.order(:id).map(&:attributes)

    get accounts_path, headers: headers
    assert_response :success
    assert_equal "fr", response.headers["Content-Language"]
    assert_select "h1", text: "Comptes"
    assert_select "a", text: "Voir le compte", count: 3
    refute_match(/translation missing|missing translation/i, response.body)

    get account_path(@second), headers: headers
    assert_response :success
    assert_select "h2", text: "Vos conversations récentes"
    assert_select "p", text: "Seules vos conversations sont affichées."
    assert_select "p", text: "Depuis la création · tous les membres du compte"
    assert_select 'main svg:not([aria-hidden="true"])', count: 0
    refute_match(/translation missing|missing translation/i, response.body)

    get account_chats_path(@second), headers: headers
    assert_response :success
    assert_select "h2", text: "Vos conversations"
    assert_select "a[rel=next]", text: "Suivant"
    assert_select 'nav[aria-label="Pagination"]'
    refute_match(/translation missing|missing translation/i, response.body)

    get account_path(@empty), headers: headers
    assert_response :success
    assert_select "p", text: "Ajoutez des sources pour enrichir les connaissances de ce compte. Vous pouvez déjà démarrer une conversation."
    assert_select "p", text: "Votre historique privé de conversations apparaîtra ici."
    refute_match(/translation missing|missing translation/i, response.body)
    assert_equal prompt, experience(:prompts, :overview_second_shared).reload.attributes
    assert_equal memberships, @user.account_users.order(:id).map(&:attributes)
    assert_equal @first, @user.first_account
    assert_nil cookies[:locale]
  end

  test "invalid account creation renders submitted details with 422" do
    account = Account.new(name: "Rejected account", owner: @user)
    account.errors.add(:name, :invalid)

    with_creation_error(account) do
      assert_no_difference [ "Account.count", "Prompt.count" ] do
        post accounts_path, params: { account: { name: account.name } }
      end
    end

    assert_response :unprocessable_entity
    assert_select ".n-title-container h2.n-main-title.mb-2", text: "New Account"
    assert_select "nav[aria-label='Breadcrumb'] [aria-current='page']", text: "New Account"
    assert_select "nav[aria-label='Breadcrumb'] a", count: 1
    assert_select ".n-form-container form[action='#{accounts_path}'][method='post']"
    assert_select "input[name='account[name]'][value='Rejected account']"
    assert_select "form [role='alert'] li", text: /Name/
    assert_select "form a[href='#{accounts_path}']", text: "Cancel"
  end

  test "unrelated prompt validation errors are not rescued as account input errors" do
    previous = Rails.application.env_config["action_dispatch.show_exceptions"]
    Rails.application.env_config["action_dispatch.show_exceptions"] = :none
    prompt = Prompt.new(content: "")
    prompt.errors.add(:content, :blank)

    with_creation_error(prompt) do
      error = assert_raises(ActiveRecord::RecordInvalid) do
        post accounts_path, params: { account: { name: "Valid account" } }
      end
      assert_equal prompt, error.record
    end
  ensure
    Rails.application.env_config["action_dispatch.show_exceptions"] = previous
  end

  test "recent and history conversation previews shorten long prompts without changing stored content" do
    chat = experience(:chats, :overview_second_chat_27)
    message = experience(:messages, :overview_second_question_27)
    prompt = "Résumé détaillé " * 30
    message.update_columns(content: prompt)
    expected = "#{prompt[0, 119]}…"

    get account_path(@second)
    assert_response :success
    assert_select "[data-conversation-id='#{chat.id}'] a", text: expected
    assert_equal prompt, message.reload.content

    get account_chats_path(@second)
    assert_response :success
    assert_select "[data-conversation-id='#{chat.id}'] a", text: expected
    assert_equal prompt, message.reload.content
  end

  test "recent and history conversation previews retain short and exact-limit titles" do
    chat = experience(:chats, :overview_second_chat_27)
    message = experience(:messages, :overview_second_question_27)

    [ "Short question?", "é" * 120, "é" * 121 ].each do |prompt|
      message.update_columns(content: prompt)

      expected = prompt.length > 120 ? "#{prompt[0, 119]}…" : prompt
      [ account_path(@second), account_chats_path(@second) ].each do |path|
        get path
        assert_response :success
        assert_select "[data-conversation-id='#{chat.id}'] a", text: expected
        assert_equal prompt, message.reload.content
      end
    end
  end

  private
    def with_creation_error(record)
      original = Account.method(:create_with_system_prompt!)
      Account.define_singleton_method(:create_with_system_prompt!) { |*| raise ActiveRecord::RecordInvalid, record }
      yield
    ensure
      Account.define_singleton_method(:create_with_system_prompt!, original)
    end
end
