require "test_helper"

class HtmlToMarkdownFormattableTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "hf@example.com", password: "testpassword123")
    @account = Account.create!(name: "HF Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "Text converts data HTML to markdown on save" do
    text = @account.texts.new(data: "<p>Hello <strong>world</strong></p>")
    text.save!
    assert_equal "Hello **world**", text.data.strip
  end

  test "Qna converts answer HTML to markdown on save (question untouched)" do
    qna = @account.qnas.new(question: "What?", answer: "<p>Because <em>reasons</em></p>")
    qna.save!
    assert_equal "What?", qna.question
    assert_equal "Because *reasons*", qna.answer.strip
  end

  test "Website converts data HTML to markdown on save" do
    website = @account.websites.new(url: "https://e.example", data: "<p>Body <a href=\"https://e.example\">link</a></p>")
    website.save!
    refute_includes website.data, "<p>"
    assert_includes website.data, "link"
  end
end
