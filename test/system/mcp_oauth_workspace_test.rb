require "application_system_test_case"
require_relative "../support/mcp_oauth_fixtures"
require_relative "../support/mcp_outbound_tls"
require_relative "../support/orbite_browser_checks"

class McpOauthWorkspaceTest < ApplicationSystemTestCase
  include McpOauthFixtures
  include McpOutboundTls
  include OrbiteBrowserChecks
  include ActionView::RecordIdentifier

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
    old_app_host = Capybara.app_host
    browser = nil
    stub_url_resolver("93.184.216.34")
    @wire.install(self) do
      browser = page.driver.browser
      browser.execute_cdp("Security.setIgnoreCertificateErrors", ignore: true)
      with_https_app do |app_origin|
        Capybara.app_host = ENV["NOSIA_URL"] = app_origin
        sign_in(@alice)
        orbite_select_language("FR")
        assert_selector "html[lang=fr]"
        browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: true)
        visit edit_account_mcp_server_path(@team, @server)
        select "OAuth", from: "Mode d’authentification"
        fill_in "mcp_server_configuration_values_token", with: "ignored-static-fixture-token"
        click_on I18n.t("nosia.actions.save", locale: :fr)
        assert_current_path account_mcp_server_path(@team, @server)
        assert_selector ".n-mcp-status", exact_text: "Autorisation requise"
        assert_empty @wire.oauth_requests
        assert_nil @server.reload.token
        @wire.authorize(@server.begin_oauth_grant_for!(@bob))

        with_local_consent_page("#{app_origin}/mcp/oauth/callback") do |consent_url|
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
    end
  ensure
    browser&.execute_cdp("Emulation.setScriptExecutionDisabled", value: false)
    browser&.execute_cdp("Security.setIgnoreCertificateErrors", ignore: false)
    Capybara.app_host = old_app_host
    ENV["NOSIA_URL"] = old_origin
    unstub_url_resolver
  end

  [ true, false ].each do |javascript|
    test "the OAuth edit can switch to static and change credentials #{javascript ? 'with' : 'without'} JavaScript" do
      browser = nil
      @server.update!(auth_mode: "oauth", token: "fixture-old-token", api_key: "fixture-old-key")
      sign_in(@alice)
      browser = page.driver.browser
      browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: !javascript)
      visit edit_account_mcp_server_path(@team, @server)
      assert_no_selector "#mcp_server_configuration_values_token"
      select "None, bearer token, or API key", from: "Authentication mode"
      find("summary", exact_text: "Static credentials").send_keys(:enter) unless javascript
      assert_selector "#mcp_server_configuration_values_token[value='']"
      assert_selector "#mcp_server_configuration_values_api_key[value='']"
      fill_in "mcp_server_configuration_values_token", with: "fixture-new-token"
      find("#mcp_server_configuration_values_api_key").ancestor(".n-mcp-field").check("Remove saved credential on Save")
      click_on "Save"
      assert_current_path account_mcp_server_path(@team, @server)
      assert_equal "static", @server.reload.auth_mode
      assert_equal "fixture-new-token", @server.token
      assert_nil @server.api_key
    ensure
      browser&.execute_cdp("Emulation.setScriptExecutionDisabled", value: false)
    end
  end

  [ :en, :fr ].each do |locale|
    test "new and saved tool controls preserve unavailable links in #{locale}" do
      previous_queue_adapter = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      @server.update!(auth_mode: "oauth", status: "error")
      chat = @team.chats.create!(user: @alice, model: ENV.fetch("LLM_MODEL"), provider: :openai, assume_model_exists: true)
      @wire.install(self) do
        grant = @server.begin_oauth_grant_for!(@alice)
        @wire.authorize(grant)
        request_counts = [ @wire.requests.size, @wire.oauth_requests.size ]
        sign_in(@alice)
        orbite_select_language("FR") if locale == :fr
        assert_selector "html[lang=#{locale}]"

        visit new_chat_path(account_id: @team.id)
        open_chat_tools
        find("input[type=checkbox][value='#{@server.id}']").check
        assert_selector "#mcp-selected-count", exact_text: "1"
        find("lexxy-editor .lexxy-editor__content").send_keys("A new chat with tools")
        find("button.n-composer-send").click
        assert_selector "[data-chat-reconnect-generating-value=true]"
        created = @alice.chats.find_by!(id: URI(page.current_url).path.split("/").last)
        assert_equal @team, created.account
        assert_equal [ @server.id ], created.chat_mcp_sessions.pluck(:mcp_server_id)

        visit chat_path(chat)
        find("details[data-composer-tools] > summary").send_keys(:enter)
        assert_selector "details[data-composer-tools][open] .n-composer-tools-panel"
        page.driver.browser.action.send_keys(:tab).perform
        checkbox = "##{dom_id(@server, :chat_mcp_checkbox)}"
        form = "##{dom_id(@server, :chat_mcp_form)}"
        assert_selector "#{checkbox}:focus-visible"

        page.driver.browser.action.send_keys(:space).perform
        assert_selector "#mcp-selected-count", exact_text: "1"
        link = chat.chat_mcp_sessions.find_by!(mcp_server: @server)
        assert_selector "details[data-composer-tools][open] .n-composer-tools-panel"
        assert_selector "#{checkbox}:checked:not(:disabled):focus-visible"
        assert_selector "#chat-mcp-forms[hidden] form#{form}[hidden][action='#{chat_mcp_session_path(chat, link)}']", visible: :hidden
        assert_selector "#{form} input[name=_method][value=delete]", visible: :all

        page.driver.browser.action.send_keys(:space).perform
        assert_selector "#mcp-selected-count", exact_text: "0"
        assert_selector "details[data-composer-tools][open] .n-composer-tools-panel"
        assert_selector "#{checkbox}:not(:checked):not(:disabled):focus-visible"
        assert_selector "#chat-mcp-forms[hidden] form#{form}[hidden][action='#{chat_mcp_sessions_path(chat, mcp_server_id: @server.id)}']", visible: :hidden
        assert_no_selector "#{form} input[name=_method]", visible: :all
        assert_not chat.chat_mcp_sessions.exists?(link.id)

        page.driver.browser.action.send_keys(:space).perform
        assert_selector "#mcp-selected-count", exact_text: "1"
        link = chat.chat_mcp_sessions.find_by!(mcp_server: @server)
        assert_equal request_counts, [ @wire.requests.size, @wire.oauth_requests.size ]
        grant.retire!

        visit chat_path(chat)
        open_chat_tools
        assert_selector "#mcp-selected-count", exact_text: "0"
        assert_no_selector "input[type=checkbox][value='#{@server.id}']"
        assert_text(locale == :fr ? "Outils indisponibles" : "Unavailable tools")

        reconnected = @server.begin_oauth_grant_for!(@alice)
        @wire.authorize(reconnected)
        visit chat_path(chat)
        open_chat_tools
        assert_selector "#mcp-selected-count", exact_text: "1"
        assert_selector "input[type=checkbox][value='#{@server.id}']:checked"
        assert chat.chat_mcp_sessions.exists?(link.id)
        reconnected.retire!

        visit chat_path(chat)
        open_chat_tools
        within("##{dom_id(@server, :chat_mcp_option)}") do
          find_button(locale == :fr ? "Retirer" : "Remove").click
        end
        assert_no_text @server.name
        assert_no_selector "#chat-mcp-unavailable"
        assert_selector "#mcp-selected-count", exact_text: "0"
        assert_not chat.chat_mcp_sessions.exists?(link.id)
      end
    ensure
      ActiveJob::Base.queue_adapter = previous_queue_adapter
    end
  end

  private
    def open_chat_tools
      find("details[data-composer-tools] > summary").click
      assert_selector "details[data-composer-tools][open]"
    end

    def sign_in(user)
      visit root_path
      fill_in "email", with: user.email
      fill_in "password", with: "fixture-password"
      click_on "Sign in"
      assert_selector "[data-dashboard]"
    end

    # Both browser origins use local TLS listeners; the resolver stub stands
    # in for the configured application's public DNS.
    def with_https_app
      certificate, = tls_context("localhost")
      tls = Puma::MiniSSL::Context.new
      tls.cert_pem = certificate.cert.to_pem
      tls.key_pem = certificate.key.to_pem
      server = Puma::Server.new(Rails.application)
      server.add_ssl_listener("127.0.0.1", 0, tls)
      server.run
      yield "https://localhost:#{server.connected_ports.first}"
    ensure
      server&.stop(true)
    end

    def with_local_consent_page(expected_callback)
      listener = TCPServer.new("127.0.0.1", 0)
      context, = tls_context("localhost")
      tls = OpenSSL::SSL::SSLServer.new(listener, context)
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
              raise "Unexpected callback URI" unless query.fetch("redirect_uri") == expected_callback

              callback = URI(expected_callback)
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
      yield "https://127.0.0.1:#{listener.addr[1]}/authorize"
    ensure
      peer&.kill&.join if peer&.alive?
      listener&.close
    end
end
