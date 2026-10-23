require "test_helper"
require_relative "../support/chat_account_fixtures"

class LocalizedPagesTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures
  include ActionView::RecordIdentifier

  test "French usage dashboard translates kinds methodology and the fixed dataset snapshot" do
    sign_in_picker_user
    TokenUsage.create!(account: @first, kind: :completion, model_id: "<script>Original model</script>", input_tokens: 1234, output_tokens: 2)
    TokenUsage.create!(account: @first, kind: :embedding, input_tokens: 1, output_tokens: 0)
    TokenUsage.create!(account: @first, kind: :agent_skill, input_tokens: 2, output_tokens: 0)
    original = @first.token_usages.order(:id).pluck(:kind, :model_id, :input_tokens, :output_tokens)

    get token_usage_url, headers: { "Accept-Language" => "fr" }

    assert_response :success
    assert_select "title", text: /Utilisation des jetons et impact environnemental/
    assert_select "h2", text: "Utilisation des jetons et impact environnemental"
    [ "Entrée", "Sortie", "Total", "Énergie", "Par modèle (les 5 premiers)", "Par type", "Les 30 derniers jours" ].each do |label|
      assert_select "section", text: /#{Regexp.escape(label)}/
    end
    [ "génération", "vectorisation", "compétence d’agent" ].each do |kind|
      assert_select "li span.capitalize", text: kind
    end
    assert_select "li", text: /1[ \u00a0\u202f]236 jetons/
    assert_select "li", text: /0,\d{6} kWh\*/
    assert_select "section p", text: /kWh · \d+,\d{2} gCO₂e/
    assert_select "section p", text: "* estimation à l’aide d’un coefficient énergétique de repli (modèle absent du jeu de données Comparia)."
    assert_select "details summary", text: /Comment l’impact énergétique des modèles est-il calculé \?/
    assert_select "details p", text: /Nosia utilise la méthode développée par Ecologits \(GenAI Impact\), également utilisée par compar:IA/
    assert_select "details strong", text: "ISO 14044"
    assert_select "details strong", text: "équivalent CO₂"
    assert_select "details", text: /licence Etalab 2\.0.*2 juillet 2026/m
    assert_select "details code", text: "N/A"
    assert_select 'details a[href="https://ecologits.ai"][target="_blank"][rel="noopener"]', text: "Ecologits"
    assert_select 'details a[href="https://comparia.beta.gouv.fr"][target="_blank"][rel="noopener"]', text: "compar:IA"
    assert_select 'details a[href="https://comparia.beta.gouv.fr/ranking"][target="_blank"][rel="noopener"]', text: "Jeu de données Comparia sur l’énergie des modèles"
    assert_select "main script", count: 0
    assert_select "li span", text: "<script>Original model</script>"
    css_select("[style]").each { |element| assert_match(/\Awidth: \d+%\z/, element["style"]) }
    css_select("polygon, polyline").each { |element| assert_match(/\A\d+(?:\.\d+)?,\d+(?:\.\d+)?(?: \d+(?:\.\d+)?,\d+(?:\.\d+)?)*\z/, element["points"]) }
    assert_equal original, @first.token_usages.order(:id).pluck(:kind, :model_id, :input_tokens, :output_tokens)
  end

  test "usage display units pluralize native zero singular and plural counts" do
    Current.session = @user.sessions.create!

    { en: { 0 => "tokens", 1 => "token", 2 => "tokens" }, fr: { 0 => "jeton", 1 => "jeton", 2 => "jetons" } }.each do |locale, units|
      units.each do |count, unit|
        html = I18n.with_locale(locale) do
          ApplicationController.render(partial: "token_usages/summary", locals: {
            token_totals: { input: count, output: 0 },
            green_summary: { models: [ { model_id: "Original model", tokens: count, kwh: 0.1234567, fallback: false } ], kwh: 0.1234567, co2e_g: 12.345, fallback_used: false },
            tokens_by_kind: { "completion" => count }, tokens_by_day: {}
          })
        end
        fragment = Nokogiri::HTML.fragment(html)

        assert_select fragment, "div.grid > div:first-child > p:last-child", text: unit
        assert_select fragment, "li span", text: "#{count} #{unit}", count: 2
        assert_select fragment, "p", text: locale == :fr ? "0,123457" : "0.123457"
        assert_select fragment, "p", text: locale == :fr ? "kWh · 12,35 gCO₂e" : "kWh · 12.35 gCO₂e"
      end
    end
  end

  test "usage dashboard empty states translate in both locales" do
    sign_in_picker_user

    { en: "No usage yet.", fr: "Aucune utilisation pour le moment." }.each do |locale, sentence|
      get token_usage_url, headers: { "Accept-Language" => locale.to_s }

      assert_response :success
      assert_select "section li", text: sentence, count: 2
    end
  end

  test "French skill creation translates labels without changing machine values or field names" do
    sign_in_picker_user

    get new_agent_skill_url, headers: { "Accept-Language" => "fr" }

    assert_response :success
    assert_select "h2", text: "Créer une compétence d’agent"
    assert_select 'option[value="explicit"]', text: "Explicite"
    assert_select 'option[value="llm"]', text: "LLM"
    assert_select 'textarea[name="agent_skill[skill_content]"]'
    assert_select 'label[for="agent_skill_execution_mode"]', text: "Mode d’exécution"
    assert_select 'label[for="agent_skill_trigger_mode"]', text: "Mode de déclenchement"
    assert_select 'label[for="agent_skill_priority"]', text: "Priorité"
    assert_select 'label[for="agent_skill_enabled"]', text: "Activée"
    assert_select 'option[value="ruby"]', text: "Ruby"
    assert_select 'option[value="auto"]', text: "Automatique"
    assert_select 'option[value="combined"]', text: "Combiné"
    assert_select 'textarea[name="agent_skill[skill_content]"]' do |fields|
      assert_equal "---\nname: my_skill\ndescription: Description de ma compétence\nexecution_mode: llm\ntrigger_mode: explicit\n---\n\n# Instructions\nSaisissez ici les instructions de votre compétence…", fields.first["placeholder"]
    end
  end

  test "French skill read pages translate wrappers and preserve authored content metadata and enums" do
    sign_in_picker_user
    skill = agent_skills(:picker_first_skill)
    skill.update_columns(description: "Original skill description", metadata: { "tags" => [ "original", "English" ] }, requires_rag_context: true)
    original = skill.reload.attributes
    headers = { "Accept-Language" => "fr" }

    get agent_skills_url, headers: headers
    assert_response :success
    assert_select "h2", text: "Compétences d’agent"
    assert_select "span.sr-only", text: "Désactiver la compétence"
    assert_select "span", text: "Étiquettes :"
    assert_select ".n-tag", text: "LLM"
    assert_select ".n-tag", text: "Explicite"
    assert_includes response.body, "original, English"

    get agent_skill_url(skill), headers: headers
    assert_response :success
    assert_select "h2", text: skill.name
    assert_select "p", text: "Original skill description"
    assert_select "pre", text: skill.skill_content
    assert_select "dt", text: "Contexte RAG"
    assert_select "dd", text: "Oui"

    get edit_agent_skill_url(skill), headers: headers
    assert_response :success
    assert_select "h2", text: "Modifier la compétence d’agent"
    assert_select 'textarea[name="agent_skill[skill_content]"]', text: skill.skill_content
    assert_select 'input[type="submit"][value="Mettre à jour la compétence"]'
    assert_select 'main svg:not([aria-hidden="true"])', count: 0
    assert_equal original, skill.reload.attributes
  end

  test "French skill notices use complete messages without changing saved instructions" do
    sign_in_picker_user
    headers = { "Accept-Language" => "fr" }
    content = "---\nname: original-skill\ndescription: Original description\nexecution_mode: llm\ntrigger_mode: explicit\n---\nKeep these instructions."

    post agent_skills_url, params: { agent_skill: { skill_content: content } }, headers: headers
    assert_redirected_to agent_skills_url
    assert_equal "La compétence d’agent a été créée", flash[:notice]
    skill = @first.agent_skills.find_by!(name: "original-skill")
    assert_equal content, skill.skill_content

    patch agent_skill_url(skill), params: { agent_skill: { priority: 42 } }, headers: headers
    assert_redirected_to agent_skills_url
    assert_equal "La compétence d’agent a été mise à jour", flash[:notice]
    assert_equal content, skill.reload.skill_content
    assert_equal "Original description", skill.description
    assert_equal %w[llm explicit], [ skill.execution_mode, skill.trigger_mode ]

    [ "La compétence d’agent est désactivée", "La compétence d’agent est activée" ].each do |notice|
      patch toggle_agent_skill_url(skill), headers: headers
      assert_redirected_to agent_skills_url
      assert_equal notice, flash[:notice]
    end

    delete agent_skill_url(skill), headers: headers
    assert_redirected_to agent_skills_url
    assert_equal "La compétence d’agent a été supprimée", flash[:notice]
  end

  test "French skill empty state and error headings use complete sentences" do
    sign_in_picker_user
    @first.agent_skills.destroy_all
    headers = { "Accept-Language" => "fr" }

    get agent_skills_url, headers: headers
    assert_response :success
    assert_select "p", text: "Aucune compétence d’agent pour le moment"
    assert_select "p", text: "Créez votre première compétence pour enrichir les possibilités de votre assistant."
    assert_select 'main svg:not([aria-hidden="true"])', count: 0

    { "valid-skill" => "1 erreur empêche l’enregistrement de cette compétence :", "1bad" => "2 erreurs empêchent l’enregistrement de cette compétence :" }.each do |name, heading|
      post agent_skills_url, params: { agent_skill: { name: name, priority: 101, skill_content: "Keep these instructions." } }, headers: headers
      assert_response :unprocessable_entity
      assert_select "h4", text: heading
      assert_select "li", text: "Priorité doit être inférieur ou égal à 100"
    end
  end

  test "standard model attribute labels translate in their owning catalogs" do
    {
      User => { email: [ "Email", "E-mail" ], password: [ "Password", "Mot de passe" ], password_confirmation: [ "Password confirmation", "Confirmation du mot de passe" ] },
      Account => { name: [ "Name", "Nom" ], uid: [ "Uid", "UID" ], owner: [ "Owner", "Propriétaire" ] },
      AccountUser => { user: [ "User", "Utilisateur" ], account: [ "Account", "Compte" ] },
      ApiToken => { name: [ "Name", "Nom" ], account: [ "Account", "Compte" ] },
      Chat => { account: [ "Account", "Compte" ], prompt: [ "Prompt", "Message" ] },
      Message => { content: [ "Content", "Contenu" ], chat: [ "Chat", "Conversation" ] },
      Document => { title: [ "Title", "Titre" ], file: [ "File", "Fichier" ], account: [ "Account", "Compte" ] },
      Text => { title: [ "Title", "Titre" ], data: [ "Data", "Texte" ], account: [ "Account", "Compte" ] },
      Qna => { question: [ "Question", "Question" ], answer: [ "Answer", "Réponse" ], account: [ "Account", "Compte" ] },
      Website => { url: [ "Url", "URL" ], data: [ "Data", "Données" ], account: [ "Account", "Compte" ] },
      McpServer => { name: [ "Name", "Nom" ], endpoint: [ "Endpoint", "Adresse du serveur" ], transport_type: [ "Transport type", "Type de transport" ], account: [ "Account", "Compte" ] },
      AgentSkill => { name: [ "Name", "Nom" ], skill_content: [ "Skill content", "Contenu de la compétence" ], execution_mode: [ "Execution mode", "Mode d’exécution" ], trigger_mode: [ "Trigger mode", "Mode de déclenchement" ], priority: [ "Priority", "Priorité" ], enabled: [ "Enabled", "Activée" ], account: [ "Account", "Compte" ] },
      Prompt => { content: [ "Content", "Instructions" ], name: [ "Name", "Nom" ] }
    }.each do |model, attributes|
      attributes.each do |attribute, (english, french)|
        assert_equal english, model.human_attribute_name(attribute, locale: :en)
        assert_equal french, model.human_attribute_name(attribute, locale: :fr)
      end
    end
  end

  test "French MCP creation translates transport labels without changing form wiring" do
    sign_in_picker_user

    get new_mcp_server_url, headers: { "Accept-Language" => "fr" }

    assert_response :success
    assert_select "h2", text: "Nouveau serveur MCP"
    assert_select 'option[value="stdio"]', text: "STDIO (processus local)"
    assert_select '[data-controller~="mcp-form"]'
    assert_select '[data-mcp-form-target="httpFields"]'
    assert_select '[data-mcp-form-target="stdioFields"]'
  end

  test "French MCP catalog translates its heading and help without changing cached metadata" do
    sign_in_picker_user
    original = Marshal.dump([ McpCatalog.all, McpCatalog.categories ])

    get mcp_catalog_index_url, headers: { "Accept-Language" => "fr" }

    assert_response :success
    assert_select "h2", text: "Catalogue MCP"
    assert_select "p", text: "Activez des serveurs MCP prédéfinis en un clic."
    assert_select "p", text: "Consultez les messages récents de kChat et publiez des messages."
    assert_equal original, Marshal.dump([ McpCatalog.all, McpCatalog.categories ])
  end

  test "French catalog configuration translates owned fields without rewriting identifiers or metadata" do
    sign_in_picker_user
    original = Marshal.dump(McpCatalog.all)

    get mcp_catalog_url("kchat"), headers: { "Accept-Language" => "fr" }

    assert_response :success
    assert_select "h3", text: "Configuration requise"
    assert_select "label", text: /Jeton kChat/
    assert_select 'input[type="hidden"][name="id"][value="kchat"]'
    assert_select 'input[type="password"][name="config[kchat_token]"]'
    assert_select 'input[type="password"][name="config[kchat_team_name]"]'
    assert_select 'input[type="submit"][value="Activer Infomaniak kChat"]'
    assert_select "p", text: /https:\/\/your-team.kchat.infomaniak.com\/your-team\/channels\/town-square/
    assert_select 'main svg:not([aria-hidden="true"])', count: 0
    assert_equal original, Marshal.dump(McpCatalog.all)
  end

  test "French MCP management formats latency and time while preserving authored data" do
    sign_in_picker_user
    server = mcp_servers(:picker_first_tool)
    server.update_columns(latency_ms: 1234, last_connected_at: 2.hours.ago, notes: "Original English notes", tags: "production,original", last_error: "<script>Provider error</script>")
    original = server.reload.attributes
    headers = { "Accept-Language" => "fr" }

    get mcp_servers_url, headers: headers
    assert_response :success
    assert_select 'option[value="ready"]', text: "Prêt"
    assert_select 'option[value="streamable"]', text: "HTTP en flux"
    assert_select "span.sr-only", text: "Supprimer le serveur"
    assert_select ".n-tag-ready", text: "Prêt"
    assert_match(/1[ \u00a0\u202f]234[ \u00a0\u202f]ms/, response.body)

    get mcp_server_url(server), headers: headers
    assert_response :success
    assert_select "a[data-tab=tools]", text: /Outils/
    assert_select "dt", text: "Dernière connexion"
    assert_select "dd", text: /il y a environ 2 heures/
    assert_select "p", text: "Original English notes"
    assert_select "p", text: "<script>Provider error</script>"
    assert_select "main script", count: 0
    assert_match(/1[ \u00a0\u202f]234[ \u00a0\u202f]ms/, response.body)

    get edit_mcp_server_url(server), headers: headers
    assert_response :success
    assert_select "h2", text: "Modifier #{server.name}"
    assert_select 'textarea[name="mcp_server[notes]"]', text: "Original English notes"
    assert_select 'input[type="submit"][value="Enregistrer"]'
    assert_select 'main svg:not([aria-hidden="true"])', count: 0
    assert_equal original, server.reload.attributes
  end

  test "French MCP tool wrappers translate without changing status response keys or provider results" do
    sign_in_picker_user
    server = mcp_servers(:picker_first_tool)
    headers = { "Accept-Language" => "fr" }

    post execute_tool_mcp_server_url(server), params: { tool_name: "unknown", arguments: [] }, headers: headers, as: :json
    assert_response :bad_request
    assert_equal({ "error" => "Les arguments de l’outil doivent être un objet JSON" }, response.parsed_body)

    server.update_columns(status: "disconnected")
    post execute_tool_mcp_server_url(server), params: { tool_name: "unknown", arguments: {} }, headers: headers, as: :json
    assert_response :success
    assert_equal({ "error" => "Le serveur n’est pas prêt" }, response.parsed_body)

    server.update_columns(status: "ready")
    post execute_tool_mcp_server_url(server), params: { tool_name: "unknown", arguments: {} }, headers: headers, as: :json
    assert_response :success
    assert_equal({ "error" => "Outil introuvable : unknown" }, response.parsed_body)
  end

  test "French MCP CRUD notices preserve saved names and notes" do
    sign_in_picker_user
    headers = { "Accept-Language" => "fr" }

    post mcp_servers_url, params: { mcp_server: { name: "Original MCP name", transport_type: "local", notes: "Original notes" } }, headers: headers
    assert_response :redirect
    assert_equal "Le serveur MCP a été créé.", flash[:notice]
    server = @first.mcp_servers.find_by!(name: "Original MCP name")
    assert_equal "Original notes", server.notes

    patch mcp_server_url(server), params: { mcp_server: { notes: "Edited original notes" } }, headers: headers
    assert_redirected_to mcp_server_url(server)
    assert_equal "Le serveur MCP a été mis à jour.", flash[:notice]
    assert_equal "Edited original notes", server.reload.notes

    delete mcp_server_url(server), headers: headers
    assert_redirected_to mcp_servers_url
    assert_equal "Le serveur MCP a été supprimé.", flash[:notice]
  end

  test "French MCP validation headings pluralize as complete sentences" do
    sign_in_picker_user

    post mcp_servers_url, params: { mcp_server: { name: "", transport_type: "local" } }, headers: { "Accept-Language" => "fr" }

    assert_response :unprocessable_entity
    assert_select "h3", text: "1 erreur :"
  end

  test "French MCP connection feedback preserves machine statuses latency and diagnostics" do
    sign_in_picker_user
    server = mcp_servers(:picker_first_tool)
    server.update_columns(transport_type: "streamable", endpoint: "https://mcp.example.invalid/mcp")
    stub_url_resolver([ "93.184.216.34" ])
    client = Struct.new(:tools).new([])
    headers = { "Accept-Language" => "fr" }

    with_singleton_replacement(RubyLLM::MCP, :client, ->(**) { client }) do
      post test_connection_mcp_server_url(server), headers: headers, as: :json
      assert_response :success
      assert_equal %w[latency message status success], response.parsed_body.keys.sort
      assert_equal true, response.parsed_body["success"]
      assert_equal "ready", response.parsed_body["status"]
      assert_kind_of Integer, response.parsed_body["latency"]
      assert_equal "Connexion établie", response.parsed_body["message"]

      post connect_mcp_server_url(server), headers: headers
      assert_redirected_to mcp_server_url(server)
      assert_equal "Connecté au serveur MCP.", flash[:notice]

      post disconnect_mcp_server_url(server), headers: headers
      assert_redirected_to mcp_server_url(server)
      assert_equal "Déconnecté du serveur MCP.", flash[:notice]

      client.define_singleton_method(:tools) { raise "Original provider failure" }
      post test_connection_mcp_server_url(server), headers: headers, as: :json
      assert_response :unprocessable_entity
      assert_equal({ "success" => false, "status" => "error", "error" => "Original provider failure", "message" => "Échec de la connexion" }, response.parsed_body)

      post connect_mcp_server_url(server), headers: headers
      assert_redirected_to mcp_server_url(server)
      assert_equal "Échec de la connexion : Original provider failure.", flash[:alert]
    end
  ensure
    unstub_url_resolver
  end

  test "French MCP detail leaves runtime descriptions schemas and results escaped and untranslated" do
    sign_in_picker_user
    server = mcp_servers(:picker_first_tool)
    server.update_columns(transport_type: "streamable", endpoint: "https://mcp.example.invalid/mcp")
    tool = Struct.new(:name, :description, :input_schema).new("runtime_tool", "<script>Original tool description</script>", { "query" => "Original schema" })
    tool.define_singleton_method(:call) { |**| "Original tool result" }
    prompt = Struct.new(:name, :description, :arguments).new("runtime_prompt", "Original prompt description", [ { name: "query", description: "Original variable", required: true } ])
    resource = Struct.new(:uri, :description, :mime_type).new("file:///original", "Original resource description", "text/plain")
    client = Struct.new(:tools, :prompts, :resources).new([ tool ], [ prompt ], [ resource ])
    headers = { "Accept-Language" => "fr" }

    with_singleton_replacement(RubyLLM::MCP, :client, ->(**) { client }) do
      get mcp_server_url(server), headers: headers
      assert_response :success
      assert_select "p", text: "<script>Original tool description</script>"
      assert_select "p", text: "Original prompt description"
      assert_select "p", text: "Original resource description"
      assert_select "p", text: "Paramètres :"
      assert_select "p", text: "Variables :"
      assert_select "p", text: "Type : text/plain"
      assert_select "pre", text: /Original schema/
      assert_select "span", text: "- Original variable"
      assert_select "main script", count: 0

      post execute_tool_mcp_server_url(server), params: { tool_name: "runtime_tool", arguments: {} }, headers: headers, as: :json
      assert_response :success
      assert_equal({ "success" => true, "result" => "Original tool result" }, response.parsed_body)

      tool.define_singleton_method(:call) { |**| raise "Original runtime diagnostic" }
      post execute_tool_mcp_server_url(server), params: { tool_name: "runtime_tool", arguments: {} }, headers: headers, as: :json
      assert_response :success
      assert_equal({ "error" => "Original runtime diagnostic" }, response.parsed_body)
    end
  end

  test "French catalog feedback localizes wrappers without activating servers" do
    sign_in_picker_user
    headers = { "Accept-Language" => "fr" }

    get mcp_catalog_url("unknown"), headers: headers
    assert_redirected_to mcp_catalog_index_url
    assert_equal "Serveur introuvable.", flash[:alert]

    server = mcp_servers(:picker_first_tool)
    assert_no_difference "McpServer.count" do
      with_singleton_replacement(McpCatalog, :activate_for_account, ->(*) { server }) do
        post mcp_catalog_index_url, params: { id: "kchat" }, headers: headers
      end
      assert_redirected_to mcp_server_url(server)
      assert_equal "Infomaniak kChat a été activé.", flash[:notice]

      with_singleton_replacement(McpCatalog, :activate_for_account, ->(*) { raise "Original provider diagnostic" }) do
        post mcp_catalog_index_url, params: { id: "kchat" }, headers: headers
      end
      assert_redirected_to mcp_catalog_index_url
      assert_equal "Erreur d’activation : Original provider diagnostic.", flash[:alert]
    end
  end

  {
    accounts: "Comptes", new_account: "Nouveau compte", settings: "Paramètres",
    api_tokens: "Jetons API", system_prompts: "Instructions système", models: "Modèles"
  }.each do |page, heading|
    test "French #{page} page translates its heading" do
      sign_in_picker_user

      with_singleton_replacement(RubyLLM, :models, -> { RubyLLM::Models.new([]) }) do
        get public_send("#{page}_url"), headers: { "Accept-Language" => "fr" }
      end

      assert_response :success
      assert_select "h1, h2", text: heading
    end
  end

  test "French account members translate actions without changing form paths or email" do
    sign_in_picker_user

    get account_account_users_url(@second), headers: { "Accept-Language" => "fr" }

    assert_response :success
    assert_select "h2", text: "Paramètres de Research team"
    assert_select "form[action=?][method=post]", account_account_users_path(@second) do
      assert_select 'input[type="submit"][value="Ajouter un utilisateur"]'
      assert_select 'input[type="email"][name="account_user[email]"]'
    end
    assert_select "p", text: @user.email
    assert_select "p", text: "Utilisateur actuel"
  end

  test "administration decorations stay hidden from accessible names" do
    sign_in_picker_user
    prompt = prompts(:picker_second_prompt)

    [ new_account_url, edit_account_url(@second), account_settings_url(@second),
      account_account_users_url(@second), account_system_prompt_url(@second), edit_account_system_prompt_url(@second),
      settings_url, api_tokens_url, system_prompts_url, system_prompt_url(prompt), edit_system_prompt_url(prompt) ].each do |url|
      get url, headers: { "Accept-Language" => "fr" }
      assert_response :success
      assert_select 'main svg:not([aria-hidden="true"])', count: 0
    end
  end

  test "French account headings escape authored account names" do
    sign_in_picker_user
    @second.update!(name: "<script>Original account</script>")
    headers = { "Accept-Language" => "fr" }

    get edit_account_url(@second), headers: headers
    assert_response :success
    assert_select "h2", text: "Modifier le compte #{@second.name}"
    assert_select "h2 script", count: 0

    get account_settings_url(@second), headers: headers
    assert_response :success
    assert_select "h2", text: "Paramètres du compte #{@second.name}"
    assert_select "h2 script", count: 0
  end

  test "French prompt read pages preserve prompt IDs content and full names" do
    sign_in_picker_user
    original = @second.prompts.order(:id).pluck(:id, :content)
    prompt = prompts(:picker_second_prompt)
    name = prompt.full_name
    headers = { "Accept-Language" => "fr" }

    [ account_system_prompt_url(@second), edit_account_system_prompt_url(@second),
      system_prompts_url, system_prompt_url(prompt), edit_system_prompt_url(prompt) ].each do |url|
      get url, headers: headers
      assert_response :success
      assert_includes response.body, prompt.content unless url == system_prompts_url
      assert_equal original, @second.prompts.order(:id).pluck(:id, :content)
      assert_equal name, prompt.reload.full_name
    end

    assert_select "h2", text: "Modifier #{name}"
    assert_select "label", text: "Instructions système"
  end

  test "French missing prompt read pages do not materialize defaults" do
    sign_in_picker_user
    @second.prompts.destroy_all

    assert_no_difference "Prompt.count" do
      [ account_system_prompt_url(@second), edit_account_system_prompt_url(@second), system_prompts_url ].each do |url|
        get url, headers: { "Accept-Language" => "fr" }
        assert_response :success
      end
    end
    assert_empty @second.prompts.reload
  end

  test "French account and prompt notices translate without changing saved content" do
    sign_in_picker_user
    headers = { "Accept-Language" => "fr" }

    patch account_url(@second), params: { account: { name: "Original English name" } }, headers: headers
    assert_redirected_to accounts_url
    assert_equal "Le compte a été mis à jour.", flash[:notice]
    assert_equal "Original English name", @second.reload.name

    patch account_system_prompt_url(@second), params: { prompt: { content: "Original account instructions" } }, headers: headers
    assert_redirected_to account_system_prompt_url(@second)
    assert_equal "Les instructions système ont été mises à jour.", flash[:notice]
    prompt = prompts(:picker_second_prompt)
    assert_equal "Original account instructions", prompt.content

    patch system_prompt_url(prompt), params: { prompt: { content: "Original edited instructions" } }, headers: headers
    assert_redirected_to system_prompt_url(prompt)
    assert_equal "Les instructions système ont été mises à jour.", flash[:notice]
    assert_equal "Original edited instructions", prompt.reload.content

    delete system_prompt_url(prompt), headers: headers
    assert_redirected_to system_prompts_url
    assert_equal "Les instructions système ont été supprimées.", flash[:notice]
  end

  test "French membership feedback preserves owner authorization and membership lifecycle" do
    sign_in_picker_user
    headers = { "Accept-Language" => "fr" }
    outsider = users(:picker_outsider)

    post account_account_users_url(@second), params: { account_user: { email: "missing@example.invalid" } }, headers: headers
    assert_equal "Utilisateur introuvable.", flash[:alert]

    post account_account_users_url(@second), params: { account_user: { email: outsider.email } }, headers: headers
    assert_equal "L’utilisateur a été ajouté.", flash[:notice]
    membership = @second.account_users.find_by!(user: outsider)

    post account_account_users_url(@second), params: { account_user: { email: outsider.email } }, headers: headers
    assert_equal "Impossible d’ajouter l’utilisateur.", flash[:alert]

    owner_membership = @second.account_users.find_by!(user: @user)
    assert_no_difference "AccountUser.count" do
      delete account_account_user_url(@second, owner_membership), headers: headers
    end
    assert_equal "Le propriétaire du compte ne peut pas être retiré.", flash[:alert]

    delete account_account_user_url(@second, membership), headers: headers
    assert_equal "L’utilisateur a été retiré.", flash[:notice]
    refute @second.account_users.exists?(membership.id)

    @second.account_users.grant_to(outsider)
    sign_in_picker_user(outsider)
    assert_no_difference "AccountUser.count" do
      post account_account_users_url(@second), params: { account_user: { email: users(:picker_no_account).email } }, headers: headers
    end
    assert_response :forbidden
  end

  test "French token management translates show once and clipboard feedback without exposing digests" do
    sign_in_picker_user
    headers = { "Accept-Language" => "fr" }

    post api_tokens_url, params: { api_token: { account_id: @second.id, name: "Original token name" } }, headers: headers
    assert_redirected_to api_tokens_url
    plain = flash[:created_api_token]
    token = @user.api_tokens.find_by!(name: "Original token name")
    assert_equal ApiToken.digest(plain), token.token_digest
    follow_redirect!(headers: headers)

    assert_response :success
    assert_select 'input[data-clipboard-target="source"][value=?]', plain
    assert_select '[data-clipboard-success-content-value="Copié !"]'
    assert_select "span.sr-only", text: "Copier le jeton API"
    assert_select "span.sr-only", text: "Supprimer le jeton API"
    assert_select "h2", text: "Votre nouveau jeton API"
    assert_select 'main svg:not([aria-hidden="true"])', count: 0
    refute_includes response.body, token.token_digest

    get api_tokens_url, headers: headers
    refute_includes response.body, plain
    refute_includes response.body, token.token_digest

    post api_tokens_url, params: { api_token: { account_id: @second.id, name: "" } }, headers: headers
    assert_equal "Une erreur est survenue.", flash[:alert]
  end

  test "French sources translate search sorting type filters and upload messages" do
    sign_in_picker_user

    get sources_url, headers: { "Accept-Language" => "fr" }

    assert_response :success
    assert_select 'input[name="q"][placeholder="Rechercher des sources…"]'
    assert_select 'option[value="recent"]', text: "Ajout récent"
    assert_select 'a[href*="type=document"]', text: /Documents/
    assert_select "[data-controller~=dropzone][data-dropzone-messages-value]" do |roots|
      messages = JSON.parse(roots.first["data-dropzone-messages-value"])
      assert_equal "Fichier non valide : %{name}", messages.fetch("invalid")
    end
  end

  test "French Q&A creation retains its rich answer editor" do
    sign_in_picker_user

    get new_sources_qna_url, headers: { "Accept-Language" => "fr" }

    assert_response :success
    assert_select "h2", text: "Nouvelle question-réponse"
    assert_select "label", text: "Réponse"
    assert_select 'lexxy-editor[name="qna[answer]"]'
    assert_select 'textarea[name="qna[answer]"]', count: 0
    assert_select 'input[type="submit"][value="Enregistrer"]'
  end

  test "French pasted text subtitles pluralize at presentation time" do
    text = texts(:picker_second_text)

    I18n.with_locale(:fr) do
      { "bonjour" => "Texte collé · 1 mot", "bonjour monde" => "Texte collé · 2 mots" }.each do |data, subtitle|
        text.data = data

        assert_equal subtitle, text.source_subtitle
        assert_equal data, text.data
      end
    end
  end

  test "French source presentation translates labels and statuses without changing type keys" do
    sign_in_picker_user

    I18n.with_locale(:fr) do
      [ [ @second.documents.new, "Document", "document" ],
        [ texts(:picker_second_text), "Texte", "text" ],
        [ @second.qnas.new(answer: "  Original answer  "), "Question-réponse", "qna" ],
        [ websites(:picker_second_website), "Site web", "website" ] ].each do |source, label, key|
        assert_equal label, source.source_type_label
        assert_equal key, source.source_type_key
      end

      document = @second.documents.new
      assert_equal "Document sans titre", document.display_title
      assert_equal "R : Original answer", @second.qnas.new(answer: "  Original answer  ").source_subtitle

      text = texts(:picker_second_text)
      { "indexed" => "Indexé", "failed" => "En échec", "pending" => "Traitement…" }.each do |status, label|
        text.index_status = status
        assert_equal label, ApplicationController.helpers.source_status_display(text).last
      end
      website = websites(:picker_second_website)
      website.index_status = "pending"
      assert_equal "Exploration…", ApplicationController.helpers.source_status_display(website).last
    end
  end

  test "French empty source states use complete sentences and escape the query" do
    sign_in_picker_user

    I18n.with_locale(:fr) do
      { "document" => [ "Aucun document pour le moment", "Ajouter un document" ],
        "text" => [ "Aucun texte pour le moment", "Ajouter un texte" ],
        "qna" => [ "Aucune question-réponse pour le moment", "Ajouter une question-réponse" ],
        "website" => [ "Aucun site web pour le moment", "Ajouter un site web" ] }.each do |type, (sentence, action)|
        html = ApplicationController.render(partial: "sources/empty", locals: { type: type, status: "all", query: nil })
        fragment = Nokogiri::HTML.fragment(html)
        assert_select fragment, "h3", text: sentence
        assert_select fragment, "a", text: action
      end
    end

    get sources_url(q: '<script>alert("query")</script>'), headers: { "Accept-Language" => "fr" }

    assert_response :success
    assert_select ".sources-empty", text: /Aucune source ne correspond à « <script>/
    assert_select ".sources-empty script", count: 0
  end

  test "French source HTML notices translate creation updates retries and deletion" do
    sign_in_picker_user
    headers = { "Accept-Language" => "fr" }
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4 test"), filename: "original.pdf", content_type: "application/pdf")
    resources = [
      [ :texts, { data: "Original text" }, "Le texte", "créé", "mis", "supprimé", "Nouvelle indexation du texte." ],
      [ :qnas, { question: "Original question?", answer: "Original answer" }, "La question-réponse", "créée", "mise", "supprimée", "Nouvelle indexation de la question-réponse." ],
      [ :websites, { url: "https://example.invalid/task6" }, "Le site web", "créé", "mis", "supprimé", "Nouvelle exploration du site web." ],
      [ :documents, { title: "Original document", file: blob.signed_id }, "Le document", "créé", "mis", "supprimé", "Nouvelle indexation du document." ]
    ]

    resources.each do |type, attributes, label, created, updated, destroyed, retrying|
      model = type.to_s.classify.constantize
      key = model.model_name.element
      post polymorphic_url([ :sources, model ]), params: { key => attributes.merge(account_id: @first.id) }, headers: headers
      assert_response :redirect
      assert_equal "#{label} a été #{created}.", flash[:notice]
      source = @first.public_send(type).order(:created_at).last

      patch polymorphic_url([ :sources, source ]), params: { key => attributes.except(:file) }, headers: headers
      assert_response :redirect
      assert_equal "#{label} a été #{updated} à jour.", flash[:notice]

      post public_send("retry_sources_#{key}_url", source), headers: headers
      assert_response :redirect
      assert_equal retrying, flash[:notice]

      delete polymorphic_url([ :sources, source ]), headers: headers
      assert_response :redirect
      assert_equal "#{label} a été #{destroyed}.", flash[:notice]
    end
  end

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
    assert_equal({ "error" => "URL est déjà utilisé(e)" }, response.parsed_body)
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
