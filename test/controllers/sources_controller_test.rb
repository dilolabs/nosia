require "test_helper"

class SourcesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(email: "sc@example.com", password: "testpassword123")
    @account = Account.create!(name: "SC Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    post login_url, params: { email: @user.email, password: "testpassword123" }

    @text = @account.texts.create!(data: "findable alpha text")
    @qna  = @account.qnas.create!(question: "hidden beta", answer: "a")
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "index renders all sources by default" do
    get sources_url
    assert_response :success
    assert_select "[data-source-id='#{@text.id}']"
    assert_select "[data-source-id='#{@qna.id}']"
  end

  test "index filters by type" do
    get sources_url(type: "text")
    assert_response :success
    assert_select "[data-source-id='#{@text.id}']"
    assert_select "[data-source-id='#{@qna.id}']", false
  end

  test "index filters by search query" do
    get sources_url(q: "alpha")
    assert_response :success
    assert_select "[data-source-id='#{@text.id}']"
    assert_select "[data-source-id='#{@qna.id}']", false
  end

  test "index ignores an unknown type and shows all" do
    get sources_url(type: "bogus")
    assert_response :success
  end

  test "legacy per-type index redirects to unified view with type filter" do
    get sources_documents_url
    assert_redirected_to sources_url(type: "document")

    get sources_qnas_url
    assert_redirected_to sources_url(type: "qna")
  end
end
