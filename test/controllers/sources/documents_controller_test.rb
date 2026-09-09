require "test_helper"

class Sources::DocumentsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(email: "doc@example.com", password: "testpassword123")
    @account = Account.create!(name: "Doc Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    post login_url, params: { email: @user.email, password: "testpassword123" }

    @stranger = User.create!(email: "doc-stranger@example.com", password: "testpassword123")
    @foreign_account = Account.create!(name: "Foreign Account", owner: @stranger)
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  def upload
    file = Tempfile.new([ "leak", ".pdf" ])
    file.write("x")
    file.close
    Rack::Test::UploadedFile.new(file.path, "application/pdf")
  end

  test "show renders PDF previews without violating the CSP" do
    document = @account.documents.new(title: "Readable")
    document.file.attach(io: StringIO.new("x"), filename: "readable.pdf", content_type: "application/pdf")
    document.save!

    get sources_document_url(document)

    assert_response :success
    assert_select "##{dom_id(document)} iframe[src*='active_storage']"
    assert_select "##{dom_id(document)} object", count: 0
    assert_includes response.headers["Content-Security-Policy"], "object-src 'none'"
  end

  test "create cannot file a document under another user's account" do
    post sources_documents_url, params: {
      document: { title: "Leaked", account_id: @foreign_account.id, file: upload }
    }

    assert_response :not_found
    assert_empty Document.where(title: "Leaked")
    assert_empty Document.where(account_id: @foreign_account.id)
  end

  test "update cannot move a document to another user's account" do
    @document = @account.documents.create!(title: "Mine") rescue nil
    unless @document&.persisted?
      @document = @account.documents.new(title: "Mine")
      @document.file.attach(io: StringIO.new("x"), filename: "mine.pdf", content_type: "application/pdf")
      @document.save!
    end

    patch sources_document_url(@document), params: {
      document: { title: "Mine", account_id: @foreign_account.id }
    }

    assert_equal @account.id, @document.reload.account_id
  end

  test "create still files a document under one of the user's own accounts" do
    own_other = Account.create!(name: "Doc Second", owner: @user)
    own_other.account_users.grant_to(@user)

    post sources_documents_url, params: {
      document: { title: "Filed Elsewhere", account_id: own_other.id, file: upload }
    }

    assert_equal own_other.id, Document.find_by!(title: "Filed Elsewhere").account_id
  end
end
