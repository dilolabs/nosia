require_relative "native_mcp_oauth_wire"

module McpOauthFixtures
  extend ActiveSupport::Concern

  included do
    setup do
      @prior_tenant = ActsAsTenant.current_tenant
      ActsAsTenant.current_tenant = nil
      @oauth_fixtures = %w[users accounts account_users mcp_servers].index_with do |table|
        path = Rails.root.join("test/support/fixtures/mcp_oauth", table)
        set = ActiveRecord::FixtureSet.new(nil, table, nil, path)
        ActiveRecord::Base.with_connection do |db|
          set.table_rows.fetch(table).each { |row| db.insert_fixture(row, table) }
        end
        set.fixtures
      end
      @alice = oauth_fixture("users", :oauth_alice)
      @bob = oauth_fixture("users", :oauth_bob)
      @team = oauth_fixture("accounts", :oauth_team)
      @member = oauth_fixture("account_users", :oauth_team_alice)
      @server = oauth_fixture("mcp_servers", :oauth_team)
      @wire = NativeMcpOAuthWire.new
    end

    teardown do
      ActsAsTenant.current_tenant = @prior_tenant
    end
  end

  def oauth_fixture(table, name)
    @oauth_fixtures.fetch(table).fetch(name.to_s).find
  end

  def with_singleton_replacement(object, name, replacement)
    own_method = object.singleton_class.instance_methods(false).include?(name)
    original = object.method(name)
    object.define_singleton_method(name, replacement)
    yield
  ensure
    if own_method
      object.define_singleton_method(name, original)
    else
      object.singleton_class.remove_method(name)
    end
  end

  def native_credentials
    RubyLLM::ActiveRecord::MCPCredential
  end

  def credential(grant)
    native_credentials.find_by!(owner: grant)
  end
end
