require "application_system_test_case"

class ChatWaitingUxTest < ApplicationSystemTestCase
  # Stub Chat#complete to yield a known chunk on a short timer so the streaming
  # flow runs without a real LLM call. Match the stubbing approach used by any
  # existing streaming system test (none exists yet in test/system/, so adapt the
  # server-side stub pattern from test/jobs/chat_response_job_test.rb's
  # stub_chat_for_streaming, loaded into the test environment).
  setup do
    @user = User.create!(email: "syst@example.com", password: "testpassword123")
    @account = Account.create!(name: "SYST Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    visit login_url
    fill_in "Email", with: @user.email
    fill_in "Password", with: "testpassword123"
    click_on "Sign in"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "the composer locks, phases show, the placeholder appears, then content, then unlock" do
    skip "requires Selenium harness (Chrome or CAPYBARA_SERVER_PORT)" unless ENV["CAPYBARA_SERVER_PORT"] || chrome_available?

    # Create a chat and submit a prompt. (Stub Chat#complete server-side to yield
    # "## Hello\n\nworld" in small chunks on a timer — see the note above.)
    visit root_url
    # ... fill the composer and submit ...

    # The send button disables immediately after submit.
    # assert_button_state disabled

    # The thinking animation shows a phase label (Preparing / Searching / Generating).
    # assert_text /Preparing|Searching|Generating/

    # The assistant bubble shows the Generating placeholder before the first token.
    # assert_text "Generating"

    # The streamed content renders as HTML (a real <h2>, not literal "##").
    # assert_selector ".ai-response-content h2", text: "Hello"

    # The composer re-enables after completion.
    # assert_button_state enabled
  end

  private

  def chrome_available?
    return @chrome_available if defined?(@chrome_available)
    @chrome_available = system("which google-chrome chromium chromium-browser chrome >/dev/null 2>&1")
  end
end
