require "test_helper"
require_relative "../support/chat_account_fixtures"

class LocalizedPagesTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures
  include ActionView::RecordIdentifier

  test "French new chat keeps the selected account and translates the composer" do
    sign_in_picker_user

    [ new_chat_url(account_id: @second.id), user_root_url(account_id: @second.id) ].each do |url|
      get url, headers: { "Accept-Language" => "fr" }

      assert_response :success
      assert_select 'button[aria-label="Envoyer"]'
      assert_select 'lexxy-editor[name="chat[prompt]"][placeholder="Posez votre question…"]'
      assert_select "select[name='chat[account_id]'] option[selected][value='#{@second.id}']"
      assert_select ".n-chat-composer[data-composer-sources-messages-value]" do |composers|
        messages = JSON.parse(composers.first["data-composer-sources-messages-value"])
        assert_equal "Réessayer la source", messages.fetch("retry")
        assert_equal "Réinitialiser le brouillon", messages.fetch("reset")
      end
      assert_select "[data-chat-account-confirm-message-value=?]", "Changer de compte ? Votre message non envoyé, ses pièces jointes et les outils sélectionnés seront effacés. Les sources enregistrées restent dans le compte précédent."
      assert_select "#chat-account-help", text: "Les recherches et les pièces jointes utilisent ce compte."
      assert_select ".n-composer-hints", text: "Entrée pour envoyer · Maj+Entrée pour un saut de ligne · / pour les compétences"
      assert_select "form form", count: 0
    end
  end

  test "French saved chat translates Stop without rewriting messages or account names" do
    sign_in_picker_user
    chat = chats(:picker_second_chat)
    chat.messages.create!(role: "user", content: "Keep my original English question.")
    chat.start_generation!
    original_messages = chat.messages.order(:id).pluck(:id, :content)

    get chat_url(chat), headers: { "Accept-Language" => "fr" }

    assert_response :success
    assert_select "button[aria-label='Arrêter la génération'][form='#{dom_id(chat, :composer_stop)}']"
    assert_select "form[id='#{dom_id(chat, :composer_stop)}'][action='#{stop_chat_path(chat)}']"
    assert_select 'lexxy-editor[name="message[content]"][disabled][placeholder="Génération en cours…"]'
    assert_select "[data-chat-account-readonly]", text: "Compte : Research team"
    assert_select "form form", count: 0
    assert_equal original_messages, chat.messages.order(:id).pluck(:id, :content)
  end

  test "French composer without skills uses the whole keyboard hint without a skills suffix" do
    sign_in_picker_user
    @second.agent_skills.destroy_all

    get new_chat_url(account_id: @second.id), headers: { "Accept-Language" => "fr" }

    assert_response :success
    assert_select ".n-composer-hints", text: "Entrée pour envoyer · Maj+Entrée pour un saut de ligne"
  end

  test "French messages pluralize source counts and leave authored answers and reasoning unchanged" do
    sign_in_picker_user
    chat = chats(:picker_second_chat)
    width = Chunk.columns_hash.fetch("embedding").limit
    vector = [ 1.0 ] + Array.new(width - 1, 0.0)
    chunks = 2.times.map { |index| insert_picker_chunk(@second, texts(:picker_second_text), "Original evidence #{index}", vector) }
    message = chat.messages.create!(role: :assistant, content: "<think>Original English reasoning</think>Original English answer")

    [ 1, 2 ].each do |count|
      message.update!(similar_chunk_ids: chunks.first(count).map { |chunk| chunk.id.to_s })

      get chat_url(chat), headers: { "Accept-Language" => "fr" }

      assert_response :success
      assert_select "summary span", text: count == 1 ? "1 source" : "2 sources"
      assert_select "summary span", text: "Afficher le raisonnement"
      assert_includes response.body, "Original English answer"
      assert_includes response.body, "Original English reasoning"
      assert_select "[data-created-at=?]", message.created_at.iso8601
    end
  end

  test "French source requests translate owned errors without changing response keys or status" do
    sign_in_picker_user
    headers = { "Accept-Language" => "fr" }

    post chat_sources_url, params: { account_id: @second.id }, headers: headers, as: :json
    assert_response :bad_request
    assert_equal({ "error" => "Une URL ou un identifiant de pièce jointe est requis" }, response.parsed_body)

    post chat_sources_url, params: { account_id: @second.id, attachable_sgid: "not-a-real-sgid" }, headers: headers, as: :json
    assert_response :bad_request
    assert_equal({ "error" => "Identifiant de pièce jointe non valide" }, response.parsed_body)
  end

  test "French source validation errors retain the request locale after the action unwinds" do
    sign_in_picker_user
    original_locale = I18n.locale
    website = websites(:picker_second_website)

    # Simulate a lookup missing a competing registration, using real uniqueness validation.
    register_duplicate = ->(account, url) { account.websites.create!(url: url) }
    assert_no_difference "Website.count" do
      with_singleton_replacement(Website, :find_or_create_by_url!, register_duplicate) do
        post chat_sources_url, params: { account_id: @second.id, url: website.url },
          headers: { "Accept-Language" => "fr" }, as: :json
      end
    end

    assert_response :unprocessable_entity
    assert_equal "fr", response.headers["Content-Language"]
    assert_equal original_locale, I18n.locale
    assert_equal({ "error" => "Url est déjà utilisé(e)" }, response.parsed_body)
  end

  test "French users without an account receive translated page and request feedback" do
    sign_in_picker_user(users(:picker_no_account))
    headers = { "Accept-Language" => "fr" }
    message = "Vous devez avoir accès à un compte pour démarrer une conversation."

    get new_chat_url, headers: headers
    assert_response :success
    assert_select "[data-chat-no-account]", text: message

    post chat_sources_url, params: {}, headers: headers, as: :json
    assert_response :unprocessable_entity
    assert_equal({ "error" => message }, response.parsed_body)

    post chats_url, params: { chat: { prompt: "An unsent question" } }, headers: headers
    assert_response :unprocessable_entity
    assert_equal message, response.body
  end

  test "French MCP selector formats latency without changing its stored integer" do
    sign_in_picker_user
    server = mcp_servers(:picker_second_tool)
    server.update_columns(latency_ms: 1234)

    get chat_url(chats(:picker_second_chat)), headers: { "Accept-Language" => "fr" }

    assert_response :success
    assert_equal 1234, server.reload.latency_ms
    assert_select "#mcp-selector-modal .n-tag-ready", count: 1 do |badges|
      assert_match(/1[ \u00a0\u202f]234[ \u00a0\u202f]ms/, badges.first.text)
      refute_match(/1234\s*ms/, badges.first.text)
    end
  end

  test "French MCP chat notices and actions are translated" do
    sign_in_picker_user
    chat = chats(:picker_second_chat)
    server = mcp_servers(:picker_second_tool)
    headers = { "Accept-Language" => "fr" }

    post chat_mcp_sessions_url(chat), params: { mcp_server_id: server.id }, headers: headers
    assert_redirected_to chat_url(chat)
    assert_equal "Serveur MCP ajouté à la conversation.", flash[:notice]
    session = chat.chat_mcp_sessions.find_by!(mcp_server: server)

    delete chat_mcp_session_url(chat, session), headers: headers
    assert_redirected_to chat_url(chat)
    assert_equal "Serveur MCP retiré de la conversation.", flash[:notice]

    post chat_mcp_sessions_url(chat), params: { mcp_server_id: server.id }, headers: headers, as: :turbo_stream
    assert_response :success
    assert_select "button", text: "Retirer"
    session = chat.chat_mcp_sessions.find_by!(mcp_server: server)

    delete chat_mcp_session_url(chat, session), headers: headers, as: :turbo_stream
    assert_response :success
    assert_select "button", text: "Ajouter"
  end

  test "French thinking phases ignore English overrides and fall back for unknown phases" do
    {
      "preparing" => [ "Préparation", "Démarrage…" ],
      "indexing" => [ "Indexation", "Indexation de vos pièces jointes…" ],
      "searching" => [ "Recherche", "Recherche dans vos documents…" ],
      "retrieving" => [ "Récupération", "Récupération du contexte pertinent…" ],
      "generating" => [ "Génération", "Rédaction de la réponse…" ],
      "using_tool" => [ "Utilisation d’un outil", "Exécution de l’action…" ],
      "thinking" => [ "Réflexion", "Traitement…" ],
      "unknown" => [ "Réflexion", "Traitement…" ]
    }.each do |phase, (title, subtitle)|
      html = I18n.with_locale(:fr) do
        ApplicationController.render(partial: "messages/thinking_animation", locals: { phase: phase, message: "English worker status" })
      end
      fragment = Nokogiri::HTML.fragment(html)

      assert_select fragment, ".thinking-phase-text", text: /#{title}/
      assert_select fragment, ".thinking-subtext", text: subtitle
      refute_includes html, "English worker status"
    end
  end

  test "French visitors see translated sign in fields" do
    get root_url, headers: { "Accept-Language" => "fr" }

    assert_response :success
    assert_select 'input[type="email"][placeholder=?]', "Saisissez votre adresse e-mail"
    assert_select 'input[type="password"][placeholder=?]', "Saisissez votre mot de passe"
    assert_select 'input[type="submit"][value=?]', "Se connecter"
  end

  test "French visitors see a translated unauthorized error" do
    post login_url, params: { email: @user.email, password: "wrong-password" }, headers: { "Accept-Language" => "fr" }

    assert_response :unauthorized
    assert_includes response.body, "Trop de demandes ou accès non autorisé."
  end

  test "English visitors still see sign in" do
    get root_url, headers: { "Accept-Language" => "en" }

    assert_response :success
    assert_select 'input[type="submit"][value=?]', "Sign in"
  end
end
