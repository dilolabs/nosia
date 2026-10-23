require "test_helper"

module Api
  module V1
    # The API is the machine boundary of the app: bearer-token auth must fail
    # closed, and every write must land in the token's account.
    class ApiAuthenticationTest < ActionDispatch::IntegrationTest
      def setup
        @user = User.create!(email: "api@example.com", password: "testpassword123")
        @account = Account.create!(name: "API Account", owner: @user)
        @account.account_users.grant_to(@user)
        @token = ApiToken.create!(account: @account, user: @user, name: "ci")
        ActsAsTenant.current_tenant = @account
      end

      def teardown
        ActsAsTenant.current_tenant = nil
      end

      def auth_header(token)
        { "Authorization" => "Bearer #{token}" }
      end

      test "valid token without params[user] files into the token's account" do
        post "/api/v1/texts", params: { data: "hello corpus" }, headers: auth_header(@token.plain_token), as: :json

        assert_response :success
        assert_equal @account.id, Text.find_by!(data: "hello corpus").account_id
      end

      test "invalid token is rejected with 401 even when params[user] is present" do
        post "/api/v1/texts",
          params: { data: "sneaky", user: "ghost-account" },
          headers: auth_header("not-a-real-token"), as: :json

        assert_response :unauthorized
        assert_empty Text.where(data: "sneaky")
      end

      test "missing token is rejected with 401" do
        post "/api/v1/texts", params: { data: "anon" }, as: :json

        assert_response :unauthorized
        assert_empty Text.where(data: "anon")
      end

      test "valid token with params[user] provisions an account owned by the caller" do
        post "/api/v1/texts",
          params: { data: "scoped corpus", user: "team-alpha" },
          headers: auth_header(@token.plain_token), as: :json

        assert_response :success
        account = @user.accounts.find_by!(uid: "team-alpha")
        assert_equal account.id, Text.find_by!(data: "scoped corpus").account_id
      end

      test "agent skills index responds for a valid token" do
        ActsAsTenant.current_tenant = @account
        skill = @account.agent_skills.create!(
          name: "summarizer", description: "d", execution_mode: :llm,
          trigger_mode: :explicit, skill_content: "do things"
        )

        get "/api/v1/agent_skills", headers: auth_header(@token.plain_token)

        assert_response :success
        body = JSON.parse(response.body)
        assert_equal [ skill.id ], body.map { |s| s["id"] }
      end

      test "agent skills index rejects an invalid token" do
        get "/api/v1/agent_skills", headers: auth_header("bogus")

        assert_response :unauthorized
      end

      test "French header and cookie preserve English skill validation and authentication contracts" do
        patch "/language_preference", params: { locale: "fr" }
        headers = auth_header(@token.plain_token).merge("Accept-Language" => "fr")

        post "/api/v1/agent_skills", params: { agent_skill: { name: "1bad", execution_mode: "llm", trigger_mode: "explicit", skill_content: "Original instructions" } }, headers: headers, as: :json

        assert_response :unprocessable_entity
        assert_equal "en", response.headers["Content-Language"]
        assert_equal({ "errors" => [ "Name must start with a letter and contain only alphanumeric, underscore, and hyphen" ] }, response.parsed_body)

        get "/api/v1/agent_skills", headers: auth_header("bogus").merge("Accept-Language" => "fr")
        assert_response :unauthorized
        assert_equal "en", response.headers["Content-Language"]
        assert_equal "Unauthorized", response.parsed_body["error"]
      end

      # Per-IP ceiling on the machine boundary: a valid token can otherwise
      # drive unbounded LLM spend and crawling. Uses its own remote_addr so the
      # counter never bleeds into the other examples in this file.
      test "api requests are rate limited per ip" do
        self.remote_addr = "10.8.8.8"
        310.times do |i|
          post "/api/v1/texts", params: { data: "rl #{i}" }, headers: auth_header(@token.plain_token), as: :json

          break if response.status == 429
        end

        assert_response :too_many_requests
      end
    end
  end
end
