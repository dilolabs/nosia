require "application_system_test_case"
require_relative "../support/mcp_oauth_fixtures"
require_relative "../support/mcp_outbound_tls"
require_relative "../support/orbite_browser_checks"

class McpOauthWorkspaceTest < ApplicationSystemTestCase
  include McpOauthFixtures
  include McpOutboundTls
  include OrbiteBrowserChecks

  test "keyboard selects OAuth and an ordinary save leaves authorization as a separate action" do
    sign_in(@alice)
    visit edit_account_mcp_server_path(@team, @server)

    find("#mcp_server_auth_mode").send_keys(:end)
    assert_no_selector "#mcp_server_configuration_values_token"
    click_on "Save"
    assert_current_path account_mcp_server_path(@team, @server)
    assert_text "Authorization required"
    assert_selector "form[data-turbo=false]", text: "Authorize with OAuth"
    assert_no_button "Test connection"
  end

  test "a native cross-origin consent form works without JavaScript and disconnect is per member" do
    old_origin = ENV["NOSIA_URL"]
    browser = nil
    stub_url_resolver("93.184.216.34")
    @wire.install(self) do
      ENV["NOSIA_URL"] = "https://nosia.example.test"
      sign_in(@alice)
      orbite_select_language("FR")
      assert_selector "html[lang=fr]"
      browser = page.driver.browser
      browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: true)
      browser.execute_cdp("Security.setIgnoreCertificateErrors", ignore: true)
      visit edit_account_mcp_server_path(@team, @server)
      select "OAuth", from: "Mode d’authentification"
      fill_in "mcp_server_configuration_values_token", with: "ignored-static-fixture-token"
      click_on I18n.t("nosia.actions.save", locale: :fr)
      assert_current_path account_mcp_server_path(@team, @server)
      assert_selector ".n-mcp-status", exact_text: "Autorisation requise"
      assert_empty @wire.oauth_requests
      assert_nil @server.reload.token
      @wire.authorize(@server.begin_oauth_grant_for!(@bob))

      with_local_consent_page do |consent_url|
        @wire.issuer_metadata["authorization_endpoint"] = consent_url

        find_button("Autoriser avec OAuth").send_keys(:enter)
        assert_text "Controlled provider"
        click_link "Approve"
        assert_current_path account_mcp_server_path(@team, @server)
        assert_selector ".n-mcp-status", exact_text: "Autorisé"
        assert_button "Tester la connexion"
        assert @server.oauth_grant_for(@alice).authorized?

        click_button "Déconnecter mon autorisation"
        assert_selector ".n-mcp-status", exact_text: "Autorisation requise"
        assert_no_button "Tester la connexion"
        assert_nil @server.oauth_grant_for(@alice)
        assert @server.oauth_grant_for(@bob).authorized?
      end
    end
  ensure
    browser&.execute_cdp("Emulation.setScriptExecutionDisabled", value: false)
    browser&.execute_cdp("Security.setIgnoreCertificateErrors", ignore: false)
    ENV["NOSIA_URL"] = old_origin
    unstub_url_resolver
  end

  private
    def sign_in(user)
      visit root_path
      fill_in "email", with: user.email
      fill_in "password", with: "fixture-password"
      click_on "Sign in"
      assert_selector "[data-dashboard]"
    end

    # The provider's browser origin is loopback-only; the adapter fixture
    # separately checks the registered public callback URI. Translate that URI
    # back to the local Capybara app link instead of navigating to public DNS.
    def with_local_consent_page
      listener = TCPServer.new("127.0.0.1", 0)
      context, = tls_context("localhost")
      tls = OpenSSL::SSL::SSLServer.new(listener, context)
      app_url = URI(page.current_url).origin
      peer = Thread.new do
        loop do
          socket = tls.accept
          begin
            target = socket.gets&.split&.[](1)
            next unless target

            headers = []
            while (header = socket.gets) && header != "\r\n"
              headers << header
            end
            uri = URI(target)
            body = if uri.path == "/authorize" && headers.grep(/\Areferer:/i).empty?
              query = URI.decode_www_form(uri.query).to_h
              raise "Unexpected callback URI" unless query.fetch("redirect_uri") == NativeMcpOAuthWire::REDIRECT_URI

              callback = URI("#{app_url}/mcp/oauth/callback")
              callback.query = URI.encode_www_form(@wire.callback(query))
              %(<h1>Controlled provider</h1><a href="#{ERB::Util.html_escape(callback.to_s)}">Approve</a>)
            else
              ""
            end
            socket.write("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
          ensure
            socket.close
          end
        rescue OpenSSL::SSL::SSLError, Errno::ECONNRESET
          # Chromium may cancel speculative connections.
        end
      end
      yield "https://localhost:#{listener.addr[1]}/authorize"
    ensure
      peer&.kill&.join if peer&.alive?
      listener&.close
    end
end
