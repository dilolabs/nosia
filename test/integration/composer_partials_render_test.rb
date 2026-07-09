require "test_helper"

class ComposerPartialsRenderTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(email: "pr@example.com", password: "testpassword123")
    @account = Account.create!(name: "PR Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    post login_url, params: { email: @user.email, password: "testpassword123" }
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "new_chat renders chats/_form with lexxy editor and hidden id seeds" do
    get new_chat_url
    assert_response :success
    assert_select "lexxy-editor[name=?]", "chat[prompt]"
    assert_select "input[type='hidden'][name='chat[attached_website_ids][]'][data-composer-target='websiteIds']"
    assert_select "input[type='hidden'][name='chat[attached_document_ids][]'][data-composer-target='documentIds']"
    assert_select "div[data-controller='composer'][data-composer-skills-value]"
    assert_select "div.n-skill-menu[data-composer-target='menu']"
    assert_select "lexxy-editor[data-composer-target='editor']"
  end

  test "chat show renders messages/_form with lexxy editor and hidden id seeds" do
    chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
    get chat_url(chat)
    assert_response :success
    assert_select "lexxy-editor[name=?]", "message[content]"
    assert_select "input[type='hidden'][name='message[attached_website_ids][]'][data-composer-target='websiteIds']"
    assert_select "input[type='hidden'][name='message[attached_document_ids][]'][data-composer-target='documentIds']"
    assert_select "div[data-controller='composer'][data-composer-skills-value]"
    assert_select "lexxy-editor[data-composer-target='editor']"
  end
end
