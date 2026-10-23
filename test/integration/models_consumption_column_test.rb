require "test_helper"

class ModelsConsumptionColumnTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(email: "mc@example.com", password: "testpassword123")
    @account = Account.create!(name: "MC Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    @models = [
      RubyLLM::Model.new(id: "glm-5.2", name: "GLM 5.2", provider: "openai", context_window: 10000,
        max_output_tokens: 1, capabilities: [ "streaming" ],
        pricing: { text_tokens: { standard: { input_per_million: 0, output_per_million: 2.5 } } }),
      RubyLLM::Model.new(id: "glm-5.2", name: "Other GLM", provider: "openrouter"),
      RubyLLM::Model.new(id: "org/slash.model.v2", name: "Slash model", provider: "openrouter",
        pricing: { text_tokens: { standard: { output_per_million: 0 } } })
    ]
    post login_url, params: { email: @user.email, password: "testpassword123" }
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "index shows Comparia consumption for matched models and — for unmatched" do
    with_registry do
      get models_path
      assert_response :success
      assert_select "th", text: "Average consumption (1000 tokens)"
      assert_select "td", text: "4,095", count: 2 # glm-5.2 mWh/1000tok, independent of provider
      assert_select "td", text: "—"
      assert_select "tbody tr", count: 3
      assert_select "tbody tr" do |rows|
        ids = rows.map { |row| row["id"] }
        assert_equal 3, ids.uniq.size
        assert ids.all? { |id| /\Amodel_[a-f0-9]{64}\z/.match?(id) }
      end
      assert_select "td", text: "$0.00 / $2.50"
      assert_select "td", text: "— / —"
      assert_select "td", text: "— / $0.00"
    end
  end

  test "show links qualify overlapping IDs by provider and keep slash and dot IDs in query parameters" do
    with_registry do
      get models_path
      assert_response :success
      links = css_select("a").select { |link| link.text == "Show" }.map { |link| link["href"] }
      assert_equal @models.map { |model| model_path("model", model_id: model.id, provider: model.provider) }, links
      @models.zip(links).each do |model, link|
        assert_equal "/models/model", URI.parse(link).path
        get link
        assert_response :success
        assert_select "h1", model.name
        assert_select "p", text: "ID: #{model.id}"
        assert_select "p", text: "Provider: #{model.provider}"
        assert_select "a[href=?]", new_chat_path(model: model.id)
      end
    end
  end

  test "show distinguishes free and unknown prices and retains Comparia consumption" do
    with_registry do
      get model_path("model", model_id: "glm-5.2", provider: "openai")
      assert_response :success
      assert_select "p", text: /\$0\.00 \/ \$2\.50/
      assert_select "p", text: /Average consumption \(1000 tokens\).*4,095/

      get model_path("model", model_id: "org/slash.model.v2", provider: "openrouter")
      assert_response :success
      assert_select "p", text: /— \/ \$0\.00/
      assert_select "p", text: /Average consumption \(1000 tokens\).*—/
    end
  end

  test "show rejects missing malformed and unknown identities with 404" do
    with_registry do |registry|
      lookups = []
      original = registry.method(:find)
      registry.define_singleton_method(:find) do |id, **options|
        lookups << [ id, options ]
        original.call(id, **options)
      end
      [ {}, { model_id: "glm-5.2" }, { provider: "openai" },
        { model_id: "", provider: "openai" }, { model_id: "glm-5.2", provider: " " },
        { model_id: [ "glm-5.2" ], provider: "openai" }, { model_id: { value: "glm-5.2" }, provider: "openai" },
        { model_id: "glm-5.2", provider: [ "openai" ] }, { model_id: "glm-5.2", provider: { value: "openai" } },
        { model_id: "missing", provider: "openai" }, { model_id: "glm-5.2", provider: "missing" }
      ].each do |identity|
        get model_path("model"), params: identity
        assert_response :not_found
      end
      get model_path("123"), params: { model_id: "glm-5.2", provider: "openai" }
      assert_response :not_found
      assert_equal [ [ "missing", { provider: "openai" } ], [ "glm-5.2", { provider: "missing" } ] ], lookups
    end
  end

  test "refresh uses the registry and preserves the existing redirect" do
    with_registry do |registry|
      refreshed = false
      registry.define_singleton_method(:refresh) { refreshed = true; self }
      post refresh_models_path
      assert refreshed
      assert_redirected_to models_path
      assert_equal "Models refreshed successfully", flash[:notice]
    end
  end

  test "French model presentation localizes USD quantities and consumption without changing identifiers" do
    with_registry do |registry|
      headers = { "Accept-Language" => "fr" }
      get models_path, headers: headers
      assert_response :success
      assert_select "th", text: "Consommation moyenne (1 000 jetons)"
      assert_select "td", text: /10[ \u00a0\u202f]000 jetons/
      assert_select "td", text: /0,00.*\$ \/ 2,50.*\$/
      assert_select "td", text: /4[ \u00a0\u202f]095/, count: 2
      assert_select "td", text: "— / —"

      get model_path("model", model_id: "glm-5.2", provider: "openai"), headers: headers
      assert_response :success
      assert_select "h1", text: "GLM 5.2"
      assert_select "p", text: "ID : glm-5.2"
      assert_select "p", text: "Fournisseur : openai"
      assert_select "p", text: /Fenêtre de contexte : 10[ \u00a0\u202f]000 jetons/
      assert_select "p", text: "Sortie maximale : 1 jeton"
      assert_select "p", text: "Capacités : streaming"
      assert_select "p", text: /Consommation moyenne \(1 000 jetons\) :.*4[ \u00a0\u202f]095/

      get model_path("model", model_id: "glm-5.2", provider: "openrouter"), headers: headers
      assert_response :success
      assert_select "p", text: "Fenêtre de contexte : —"
      assert_select "p", text: "Sortie maximale : —"
      assert_select "p", text: /— \/ —/

      registry.define_singleton_method(:refresh) { self }
      post refresh_models_path, headers: headers
      assert_redirected_to models_path
      assert_equal "Les modèles ont été actualisés", flash[:notice]
    end
  end

  test "English model quantities distinguish unknown values from singular and plural counts" do
    with_registry do
      get model_path("model", model_id: "glm-5.2", provider: "openai")
      assert_response :success
      assert_select "p", text: "Context Window: 10,000 tokens"
      assert_select "p", text: "Max Output: 1 token"

      get model_path("model", model_id: "glm-5.2", provider: "openrouter")
      assert_response :success
      assert_select "p", text: "Context Window: —"
      assert_select "p", text: "Max Output: —"
    end
  end

  private
    def with_registry
      registry = RubyLLM::Models.new(@models)
      original = RubyLLM.method(:models)
      RubyLLM.define_singleton_method(:models) { registry }
      yield registry
    ensure
      RubyLLM.define_singleton_method(:models, original) if original
    end
end
