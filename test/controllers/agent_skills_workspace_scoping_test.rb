require "test_helper"
require_relative "../support/agent_skills_workspace_fixtures"

class AgentSkillsWorkspaceScopingTest < ActionDispatch::IntegrationTest
  include AgentSkillsWorkspaceFixtures
  setup { sign_in_overview }

  test "legacy account input cannot retarget the default and scoped reads use the URL account" do
    first = workspace_skill(:skills_first)
    second = workspace_skill(:skills_second)
    before = workspace_records
    get agent_skills_path, params: { account_id: @second.id }
    assert_response :success
    assert_includes response.body, first.name
    refute_includes response.body, second.name
    get account_agent_skills_path(@second), params: { account_id: @foreign.id }
    assert_response :success
    assert_includes response.body, second.name
    refute_includes response.body, first.name
    [ new_account_agent_skill_path(@second), account_agent_skill_path(@second, second),
      edit_account_agent_skill_path(@second, second) ].each do |path|
      assert_no_enqueued_jobs { get path }
      assert_response :success
    end
    assert_equal before, workspace_records
    assert_equal @first, @user.reload.first_account
  end

  test "create update and delete stay in each route family without transferring accounts" do
    [ [ agent_skills_path, @first ], [ account_agent_skills_path(@second), @second ] ].each do |collection, account|
      name = "created-#{account.id}"
      before_other = workspace_skill(:skills_foreign).attributes
      assert_no_enqueued_jobs do
        assert_difference -> { account.agent_skills.count }, 1 do
          post collection, params: { agent_skill: { skill_content: workspace_source(name), account_id: @foreign.id } }
        end
      end
      assert_redirected_to collection
      record = account.agent_skills.find_by!(name: name)
      path = account == @first ? agent_skill_path(record) : account_agent_skill_path(account, record)
      patch path, params: { agent_skill: { priority: 64, account_id: @foreign.id } }
      assert_redirected_to collection
      assert_equal 64, record.reload.priority
      assert_equal account.id, record.account_id
      delete path
      assert_redirected_to collection
      assert_not account.agent_skills.exists?(record.id)
      assert_equal before_other, workspace_skill(:skills_foreign).reload.attributes
    end
  end

  test "foreign malformed revoked and cross-account records fail closed" do
    before = workspace_records
    foreign = workspace_skill(:skills_foreign)
    first = workspace_skill(:skills_first)
    [ account_agent_skills_path(@foreign), "/accounts/not-an-account/agent_skills",
      account_agent_skill_path(@second, foreign), account_agent_skill_path(@second, first),
      edit_account_agent_skill_path(@second, first) ].each do |path|
      get path, params: { account_id: @second.id }
      assert_response :not_found
    end
    post account_agent_skills_path(@foreign), params: { agent_skill: { skill_content: workspace_source } }
    assert_response :not_found
    patch account_agent_skill_path(@second, first), params: { agent_skill: { priority: 99 } }
    assert_response :not_found
    delete account_agent_skill_path(@second, first)
    assert_response :not_found
    experience(:account_users, :overview_owner_second).destroy!
    get account_agent_skills_path(@second), params: { account_id: @first.id }
    assert_response :not_found
    assert_equal before, workspace_records
  end

  test "non-owner members keep existing management rights" do
    sign_in_overview(@member)
    get account_agent_skills_path(@second)
    assert_response :success
    second = workspace_skill(:skills_second)
    patch account_agent_skill_path(@second, second), params: { agent_skill: { priority: 63 } }
    assert_redirected_to account_agent_skills_path(@second)
    assert_equal 63, second.reload.priority
  end

  test "no default account has setup guidance and no mutation route can file elsewhere" do
    sign_in_overview(experience(:users, :overview_no_account))
    before = workspace_records
    [ agent_skills_path, new_agent_skill_path ].each do |path|
      get path
      assert_response :success
      assert_select "[data-skills-setup] a[href='#{accounts_path}']"
      assert_select "textarea", count: 0
    end
    post agent_skills_path, params: { agent_skill: { skill_content: workspace_source, account_id: @first.id } }
    assert_response :not_found
    get agent_skill_path(workspace_skill(:skills_first))
    assert_response :not_found
    assert_equal before, workspace_records
  end

  test "numeric prefix malformed account path ids reject every read and mutation" do
    skill = workspace_skill(:skills_second)
    before = workspace_records.deep_dup
    %w[junk -suffix].each do |suffix|
      account_id = "#{@second.id}#{suffix}"
      collection = account_agent_skills_path(account_id)
      record = account_agent_skill_path(account_id, skill)
      enablement = account_agent_skill_enablement_path(account_id, skill)
      [ [ :get, collection ], [ :get, new_account_agent_skill_path(account_id) ],
        [ :get, record ], [ :get, edit_account_agent_skill_path(account_id, skill) ],
        [ :post, collection ], [ :patch, record ], [ :delete, record ],
        [ :post, enablement ], [ :delete, enablement ] ].each do |method, path|
        assert_no_enqueued_jobs do
          public_send(method, path, params: { account_id: @first.id,
            agent_skill: { skill_content: workspace_source("strict-account-id"), priority: 61 } })
        end
        assert_response :not_found, "#{method.upcase} #{path} must reject the whole malformed account ID"
        assert_equal before, workspace_records
        assert_equal @first, @user.reload.first_account
      end
    end
  end

  %i[legacy scoped].each do |family|
    test "numeric prefix malformed #{family} skill path ids reject every read and mutation" do
      skill = workspace_skill(family == :legacy ? :skills_first : :skills_second)
      before = workspace_records.deep_dup
      %w[junk -suffix].each do |suffix|
        id = "#{skill.id}#{suffix}"
        record = family == :legacy ? agent_skill_path(id) : account_agent_skill_path(@second, id)
        edit = family == :legacy ? edit_agent_skill_path(id) : edit_account_agent_skill_path(@second, id)
        enablement = family == :legacy ? agent_skill_enablement_path(id) : account_agent_skill_enablement_path(@second, id)
        requests = [ [ :get, record ], [ :get, edit ], [ :patch, record ], [ :delete, record ],
          [ :post, enablement ], [ :delete, enablement ] ]
        requests << [ :patch, toggle_agent_skill_path(id) ] if family == :legacy
        requests.each do |method, path|
          assert_no_enqueued_jobs do
            public_send(method, path, params: { account_id: @foreign.id, id: skill.id,
              agent_skill_id: skill.id, agent_skill: { priority: 61 } })
          end
          assert_response :not_found, "#{method.upcase} #{path} must reject the whole malformed skill ID"
          assert_equal before, workspace_records
          assert_equal @first, @user.reload.first_account
        end
      end
    end
  end

  test "tenant context is bounded on successful and failing lookups" do
    second = workspace_skill(:skills_second)
    first = workspace_skill(:skills_first)
    before = workspace_records
    callbacks_before = AgentSkillsController._process_action_callbacks.to_a
    foreign = @foreign
    restored_tenants = []
    # Rails resets CurrentAttributes around requests. Observe restoration inside
    # that boundary, outside the scoped account callback, even when lookup raises.
    with_ambient_tenant = ->(_controller, action) do
      ActsAsTenant.with_tenant(foreign) do
        begin
          action.call
        ensure
          restored_tenants << ActsAsTenant.current_tenant
        end
      end
    end
    AgentSkillsController.prepend_around_action with_ambient_tenant, only: :show

    get account_agent_skill_path(@second, second)
    assert_response :success
    assert_equal [ @foreign ], restored_tenants
    get account_agent_skill_path(@second, first)
    assert_response :not_found
    assert_equal [ @foreign, @foreign ], restored_tenants
    assert_equal before, workspace_records
  ensure
    AgentSkillsController.skip_around_action with_ambient_tenant, raise: false
    callbacks_after = AgentSkillsController._process_action_callbacks.to_a
    assert_equal callbacks_before, callbacks_after,
      "Callback chain must be restored exactly (#{callbacks_before.size} before, #{callbacks_after.size} after)"
  end
end
