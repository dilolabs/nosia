require "test_helper"

class AccountTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "at@example.com", password: "testpassword123")
    @account = Account.create!(name: "AT Account", owner: @user)
    ActsAsTenant.current_tenant = @account
  end

  test "recount! repairs drifted account counters" do
    TokenUsage.create!(account: @account, kind: :embedding, input_tokens: 70, output_tokens: 0)
    @account.update!(input_tokens_count: 0, output_tokens_count: 0) # simulate drift
    @account.recount!
    assert_equal 70, @account.reload.input_tokens_count
  end
end
