# Optional Engines Implementation Plan — OpenAlex & Infomaniak kDrive

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Nosia's chat agent call OpenAlex and Infomaniak kDrive as native Ruby tools, behind a per-account toggle, by adding a `local` transport to `McpServer`, an `MCP::Tool`→`RubyLLM::Tool` adapter, and an engine registry.

**Architecture:** Engines are Rails engines in `lib/` that register `MCP::Tool` subclasses with `Engines::Registry` at boot. `McpCatalog` lists registry entries and activation creates a `local` `McpServer` holding the account's encrypted credentials. `McpServer#tools` adapts the engine's `MCP::Tool` classes into `RubyLLM::Tool` instances (with credentials bound via `server_context`, never as model-facing params) and feeds them through the unchanged `Chat#mcp_tools` / `with_tools` path. No external MCP-server surface.

**Tech Stack:** Ruby 3.3 / Rails 8.2, Minitest + Fixtures (no RSpec, no FactoryBot), Faraday `:test` adapter for HTTP stubbing (webmock is not a dependency), `mcp` gem (`MCP::Tool`), `ruby_llm` (`RubyLLM::Tool`), Hotwire.

**Spec:** `docs/superpowers/specs/2026-07-03-optional-engines-design.md`

**Conventions used throughout:**
- Tests live in `test/` (Minitest). Build records manually and set `ActsAsTenant.current_tenant` — see `test/models/chat_test.rb` for the pattern. Do not add a `mcp_servers` fixture file.
- Run a single test file: `bin/rails test test/path/to_test.rb`; a single test: `bin/rails test test/path/to_test.rb:NN`.
- Commit after every task. End commit messages with `Co-Authored-By: Claude <noreply@anthropic.com>`.
- `bin/ci` runs RuboCop + Brakeman + the test suite. Keep it green.

---

## File Structure

**New files:**
- `lib/engines/registry.rb` — `Engines::Registry` module: register/all/find/`[]`, duplicate-id guard, test reset.
- `lib/engines/registration.rb` — `Engines::Registration` value object (id, name, icon, description, required_config, tool_classes, health_check, capabilities) + `to_catalog_entry`.
- `lib/engines/tool_adapter.rb` — `Engines::ToolAdapter`: maps an `MCP::Tool` subclass to a cached `RubyLLM::Tool` instance bound to `server_context`; drops unsupported schemas with a warning.
- `config/initializers/engines.rb` — eager-loads engine registration files and registers them; logs dropped tools at boot.
- `lib/open_alex/engine_registration.rb` — `OpenAlex::EngineRegistration < Engines::Registration`.
- `app/models/open_alex_tools.rb` — `OpenAlexTools.all` helper listing tool classes.
- `lib/kdrive.rb`, `lib/kdrive/api_client.rb`, `lib/kdrive/tool.rb`, `lib/kdrive/engine_registration.rb` — the kDrive engine.
- `app/models/kdrive_tools.rb`, `app/models/kdrive_tools/search_files_tool.rb`, `app/models/kdrive_tools/list_folder_tool.rb`, `app/models/kdrive_tools/get_file_tool.rb` — kDrive `MCP::Tool` subclasses.
- `test/lib/engines/registry_test.rb`, `test/lib/engines/tool_adapter_test.rb`, `test/lib/kdrive/api_client_test.rb`
- `test/models/mcp_server_local_test.rb`, `test/lib/mcp_catalog_registry_test.rb`, `test/models/open_alex_tools_auth_test.rb`, `test/models/kdrive_tools_test.rb`
- `test/integration/local_engine_chat_test.rb`, `test/system/activate_engine_test.rb`

**Modified files:**
- `app/models/mcp_server.rb` — add `"local"` to transport_type inclusion; `#tools`/`#client`/`#test_connection!` branch on `local`.
- `lib/mcp_catalog.rb` — merge registry entries into `all`/`find`; `activate_for_account` `:registry` branch.
- `lib/open_alex.rb` — require `engine_registration`.
- `lib/open_alex/api_client.rb` — accept `auth` hash + test `stubs:`; read `api_key` from auth (fallback to ENV); add `ping`.
- `lib/open_alex/tool.rb` — every facade method accepts `auth: nil` and passes it to `ApiClient.new(auth)`.
- `app/models/open_alex_tools/*.rb` — every `call` passes `auth: server_context` to the facade method it calls.
- `config/routes.rb` — remove `post '/mcp/openalex'`.
- `config/mcp_catalog.yml` — remove the docker `kdrive` entry (native engine replaces it).

**Deleted files:**
- `app/controllers/mcp_openalex_controller.rb`
- `spec/` (the gem-skeleton RSpec tests; ported to Minitest in `test/`).

---

## Task 1: Engines::Registration value object

**Files:**
- Create: `lib/engines/registration.rb`
- Test: `test/lib/engines/registration_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/lib/engines/registration_test.rb
require "test_helper"

class Engines::RegistrationTest < ActiveSupport::TestCase
  def build(overrides = {})
    Engines::Registration.new(overrides.merge(
      id: "open_alex", name: "OpenAlex", icon: "📚",
      description: "Scholarly search", required_config: [],
      tool_classes: [], health_check: ->(auth) { }
    ))
  end

  test "to_catalog_entry emits the full catalog hash with source: :registry" do
    r = build(required_config: [ { name: :api_key, type: :secret, required: false } ],
              capabilities: [ "tools" ])
    entry = r.to_catalog_entry
    assert_equal "open_alex", entry[:id]
    assert_equal "OpenAlex", entry[:name]
    assert_equal "📚", entry[:icon]
    assert_equal "engines", entry[:category]
    assert_equal :registry, entry[:source]
    assert_equal [ "tools" ], entry[:capabilities]
    assert_equal [ { name: :api_key, type: :secret, required: false } ], entry[:required_config]
  end

  test "capabilities defaults to an empty array" do
    assert_equal [], build.capabilities
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/lib/engines/registration_test.rb`
Expected: FAIL `NameError: uninitialized constant Engines::Registration`

- [ ] **Step 3: Write minimal implementation**

```ruby
# lib/engines/registration.rb
module Engines
  class Registration
    attr_reader :id, :name, :icon, :description, :category,
                :required_config, :tool_classes, :health_check, :capabilities

    def initialize(id:, name:, icon:, description:, required_config:, tool_classes:,
                   health_check:, capabilities: [])
      @id = id
      @name = name
      @icon = icon
      @description = description
      @category = "engines"
      @required_config = required_config
      @tool_classes = tool_classes
      @health_check = health_check
      @capabilities = capabilities
    end

    def to_catalog_entry
      {
        id: id,
        name: name,
        icon: icon,
        description: description,
        category: category,
        source: :registry,
        capabilities: capabilities,
        required_config: required_config
      }
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/lib/engines/registration_test.rb`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/engines/registration.rb test/lib/engines/registration_test.rb
git commit -m "feat(engines): add Registration value object

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Engines::Registry

**Files:**
- Create: `lib/engines/registry.rb`
- Test: `test/lib/engines/registry_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/lib/engines/registry_test.rb
require "test_helper"

class Engines::RegistryTest < ActiveSupport::TestCase
  def setup
    Engines::Registry.clear
  end

  def teardown
    Engines::Registry.clear
  end

  def registration(id = "open_alex")
    Engines::Registration.new(
      id: id, name: "OpenAlex", icon: "📚", description: "x",
      required_config: [], tool_classes: [], health_check: ->(auth) {}
    )
  end

  test "register, all, find and [] work" do
    Engines::Registry.register(registration)
    assert_equal 1, Engines::Registry.all.size
    assert_equal "open_alex", Engines::Registry.find("open_alex").id
    assert_equal "open_alex", Engines::Registry["open_alex"].id
  end

  test "registering a duplicate id raises" do
    Engines::Registry.register(registration)
    assert_raises(Engines::Registry::DuplicateIdError) do
      Engines::Registry.register(registration)
    end
  end

  test "find returns nil for an unknown id" do
    assert_nil Engines::Registry.find("nope")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/lib/engines/registry_test.rb`
Expected: FAIL `NameError: uninitialized constant Engines::Registry`

- [ ] **Step 3: Write minimal implementation**

```ruby
# lib/engines/registry.rb
require_relative "registration"

module Engines
  module Registry
    class DuplicateIdError < StandardError; end

    @registrations = {}

    class << self
      def register(registration)
        if @registrations.key?(registration.id)
          raise DuplicateIdError, "Engine already registered: #{registration.id}"
        end

        @registrations[registration.id] = registration
      end

      def all
        @registrations.values
      end

      def find(id)
        @registrations[id.to_s]
      end
      alias_method :[], :find

      def clear
        @registrations.clear
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/lib/engines/registry_test.rb`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/engines/registry.rb test/lib/engines/registry_test.rb
git commit -m "feat(engines): add Registry with duplicate-id guard

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Engines::ToolAdapter (the spike — highest-risk component)

`RubyLLM::Tool` derives its tool `name` from the Ruby class name (normalize + `delete_suffix("_tool")`). Nesting the generated class under `Engines::ToolAdapter` would make that derivation produce `engines--tool_adapter--openalex_search_works`, **not** `openalex_search_works` — so the adapter **overrides `name`** on the generated class to return the MCP tool's `tool_name` directly. This makes the LLM-facing name independent of the class's constant path (verified: `assert_equal "flat_demo", adapted.name` passes for a tool whose `tool_name` is `"flat_demo"`). `with_tools` accepts a class or instance and keys by `tool_instance.name.to_sym`; we return **instances** pre-bound to `server_context`. `execute` returns a String (the tool-message content). `call(args)` validates against `execute`'s keyword signature, so `execute(**args)` accepts any keywords the model sends.

**Files:**
- Create: `lib/engines/tool_adapter.rb`
- Test: `test/lib/engines/tool_adapter_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/lib/engines/tool_adapter_test.rb
require "test_helper"

class Engines::ToolAdapterTest < ActiveSupport::TestCase
  # A minimal MCP::Tool with a flat scalar param.
  class FlatTool < MCP::Tool
    tool_name "flat_demo"
    description "flat scalar tool"
    input_schema(properties: { query: { type: "string" } }, required: [ "query" ])
    def self.call(query:, server_context:)
      MCP::Tool::Response.new([ { type: "text", text: "got #{query} key=#{server_context[:api_key]}" } ])
    end
  end

  # An MCP::Tool with a nested-object param (like OpenAlex's params: { per_page, page }).
  class NestedTool < MCP::Tool
    tool_name "nested_demo"
    description "nested object tool"
    input_schema(
      properties: {
        query: { type: "string" },
        params: {
          type: "object",
          properties: { per_page: { type: "integer" }, page: { type: "integer" } }
        }
      },
      required: [ "query" ]
    )
    def self.call(query:, params: {}, server_context:)
      MCP::Tool::Response.new([ { type: "text", text: "ok" } ], structured_content: { query: query })
    end
  end

  # An MCP::Tool using an unsupported schema feature (oneOf) -> must be dropped.
  class UnsupportedTool < MCP::Tool
    tool_name "unsupported_demo"
    description "unsupported"
    input_schema(properties: { q: { oneOf: [ { type: "string" }, { type: "integer" } ] } })
    def self.call(q:, server_context:)
      MCP::Tool::Response.new([ { type: "text", text: "nope" } ])
    end
  end

  test "returns a RubyLLM::Tool instance named from the tool_name" do
    adapted = Engines::ToolAdapter.for(FlatTool, server_context: { api_key: "sekret" })
    assert_kind_of RubyLLM::Tool, adapted
    assert_equal "flat_demo", adapted.name
  end

  test "execute delegates to the MCP tool with server_context and returns a string" do
    adapted = Engines::ToolAdapter.for(FlatTool, server_context: { api_key: "sekret" })
    result = adapted.call({ "query" => "einstein" })
    assert_equal "got einstein key=sekret", result
  end

  test "nested-object schema is accepted (not dropped)" do
    adapted = Engines::ToolAdapter.for(NestedTool, server_context: { api_key: "k" })
    assert_kind_of RubyLLM::Tool, adapted
    assert_equal "nested_demo", adapted.name
  end

  test "unsupported schema returns nil (tool dropped)" do
    assert_nil Engines::ToolAdapter.for(UnsupportedTool, server_context: {})
  end

  test "supported? distinguishes translatable schemas" do
    assert Engines::ToolAdapter.supported?(FlatTool)
    assert Engines::ToolAdapter.supported?(NestedTool)
    assert_not Engines::ToolAdapter.supported?(UnsupportedTool)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/lib/engines/tool_adapter_test.rb`
Expected: FAIL `NameError: uninitialized constant Engines::ToolAdapter`

- [ ] **Step 3: Write minimal implementation**

```ruby
# lib/engines/tool_adapter.rb
module Engines
  class ToolAdapter
    SUPPORTED_TYPES = %w[string integer number boolean].freeze

    class << self
      def for(mcp_tool_class, server_context:)
        return nil unless supported?(mcp_tool_class)

        klass = adapted_class(mcp_tool_class)
        klass.new(mcp_tool_class, server_context)
      end

      def supported?(mcp_tool_class)
        schema_translatable?(mcp_tool_class.input_schema_value&.to_h)
      end

      def unwrap(response)
        return "Error: #{response.content.inspect}" if response.error?

        text = Array(response.content).map { |c| c[:text] || c["text"] }.compact.join("\n")
        return text unless response.structured_content

        structured = response.structured_content.is_a?(String) ? response.structured_content : response.structured_content.to_json
        structured = structured.present? ? "\n\n#{structured}" : ""
        "#{text}#{structured}"
      end

      private

      def adapted_class(mcp_tool_class)
        @adapted_classes ||= {}
        @adapted_classes[mcp_tool_class] ||= build_class(mcp_tool_class)
      end

      def build_class(mcp_tool_class)
        tool_name = mcp_tool_class.tool_name
        klass = Class.new(RubyLLM::Tool) do
          # The LLM-facing tool name is the MCP tool's tool_name, NOT the Ruby
          # class-name derivation (which would prefix the namespace). Override
          # the instance accessor RubyLLM keys tools by.
          define_method(:name) { tool_name }

          def initialize(mcp_tool_class, server_context)
            @mcp_tool_class = mcp_tool_class
            @server_context = server_context
          end

          def execute(**args)
            response = @mcp_tool_class.call(**args, server_context: @server_context)
            Engines::ToolAdapter.unwrap(response)
          rescue => e
            "Error calling #{@mcp_tool_class.tool_name}: #{e.message}"
          end
        end
        # Name the constant purely for organization/debuggability; it has no
        # effect on the LLM-facing name (overridden above). Assumes distinct
        # tool_names across engines (OpenAlex/kDrive names are distinct), so
        # two tools never camelize to the same constant.
        Engines::ToolAdapter.const_set(const_name_for(tool_name), klass)
        klass.description(mcp_tool_class.description_value)
        schema = mcp_tool_class.input_schema_value&.to_h
        klass.params(schema.deep_transform_keys(&:to_s)) if schema
        klass
      end

      def const_name_for(tool_name)
        tool_name.camelize.upcase_first
      end

      def schema_translatable?(schema)
        return true if schema.blank?

        props = schema[:properties] || schema["properties"]
        required = schema[:required] || schema["required"] || []
        return false unless props.is_a?(Hash)

        props.values.all? { |spec| type_translatable?(spec) } &&
          required.is_a?(Array)
      end

      def type_translatable?(spec)
        type = spec[:type] || spec["type"]
        case type.to_s
        when *SUPPORTED_TYPES then true
        when "object"
          schema_translatable?(spec)
        when "array"
          items = spec[:items] || spec["items"]
          items ? type_translatable?(items) : true
        else
          false # oneOf/anyOf/$ref and anything unexpected
        end
      end
    end
  end
end
```

Notes for the implementer:
- `const_set` is called once per tool class (the `@adapted_classes` cache), so repeated `McpServer#tools` calls reuse the same class and only rebuild instances with fresh `server_context`.
- `schema.deep_transform_keys(&:to_s)` (ActiveSupport) gives RubyLLM string-keyed JSON schema; `klass.params(hash)` accepts a raw schema hash (RubyLLM further stringifies).
- `tool_name.camelize` turns `flat_demo` → `FlatDemo`; `upcase_first` makes it `FlatDemo` (already capitalized). The const name must be a valid Ruby constant — `camelize` guarantees that.

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/lib/engines/tool_adapter_test.rb`
Expected: PASS (5 tests)

If the nested-schema or stringification test fails, inspect `adapted.params_schema` in a console: the JSON the LLM receives must contain `params` as an object with `per_page`/`page`. This is the spike — adjust the stringification (e.g. wrap with `{ type: "object", properties: ... }` if RubyLLM expects the full object) until the schema round-trips. Do not proceed until green.

- [ ] **Step 5: Commit**

```bash
git add lib/engines/tool_adapter.rb test/lib/engines/tool_adapter_test.rb
git commit -m "feat(engines): add ToolAdapter (MCP::Tool -> RubyLLM::Tool)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: McpServer local transport

**Files:**
- Modify: `app/models/mcp_server.rb`
- Test: `test/models/mcp_server_local_test.rb`

The existing `McpServer#tools` returns `[]` unless `status_ready?` then calls `client&.tools`. We add a `local` branch that returns adapted RubyLLM tools. `#client` returns `nil` for local. `#test_connection!` runs the engine's `health_check`.

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/mcp_server_local_test.rb
require "test_helper"

class McpServerLocalTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "eng@example.com", password: "testpassword123")
    @account = Account.create!(name: "Eng Account", owner: @user)
    ActsAsTenant.current_tenant = @account
  end

  def teardown
    ActsAsTenant.current_tenant = nil
    Engines::Registry.clear
  end

  def stub_registration(health_check: ->(auth) {}, tool_classes: [])
    reg = Engines::Registration.new(
      id: "demo", name: "Demo", icon: "🧪", description: "demo",
      required_config: [], tool_classes: tool_classes, health_check: health_check
    )
    Engines::Registry.register(reg)
    reg
  end

  test "#client returns nil for local transport" do
    server = @account.mcp_servers.create!(
      name: "demo", transport_type: "local", metadata: { engine: "demo" }
    )
    assert_nil server.client
  end

  test "#tools returns adapted RubyLLM tools for a ready local server" do
    stub_registration(tool_classes: [ FlatToolForServer ])
    server = @account.mcp_servers.create!(
      name: "demo", transport_type: "local", status: "ready",
      metadata: { engine: "demo" }, auth_config: { api_key: "sekret" }
    )
    tools = server.tools
    assert_equal 1, tools.size
    assert_kind_of RubyLLM::Tool, tools.first
    assert_equal "flat_for_server", tools.first.name
  end

  test "#tools returns [] when the engine is unknown" do
    server = @account.mcp_servers.create!(
      name: "ghost", transport_type: "local", status: "ready",
      metadata: { engine: "nope" }
    )
    assert_equal [], server.tools
  end

  test "#tools returns [] when the server is not ready" do
    stub_registration(tool_classes: [ FlatToolForServer ])
    server = @account.mcp_servers.create!(
      name: "demo", transport_type: "local", status: "disconnected",
      metadata: { engine: "demo" }
    )
    assert_equal [], server.tools
  end

  test "#test_connection! flips status to ready when health_check passes" do
    stub_registration(health_check: ->(auth) { raise "bad" if auth[:api_key] == "BAD" })
    server = @account.mcp_servers.create!(
      name: "demo", transport_type: "local", metadata: { engine: "demo" },
      auth_config: { api_key: "GOOD" }
    )
    assert server.test_connection!
    assert_equal "ready", server.reload.status
  end

  test "#test_connection! flips status to error when health_check raises" do
    stub_registration(health_check: ->(auth) { raise "Invalid credentials" })
    server = @account.mcp_servers.create!(
      name: "demo", transport_type: "local", metadata: { engine: "demo" },
      auth_config: { api_key: "BAD" }
    )
    assert_not server.test_connection!
    assert_equal "error", server.reload.status
    assert_match(/Invalid credentials/, server.reload.last_error)
  end
end

class FlatToolForServer < MCP::Tool
  tool_name "flat_for_server"
  description "flat"
  input_schema(properties: { query: { type: "string" } }, required: [ "query" ])
  def self.call(query:, server_context:)
    MCP::Tool::Response.new([ { type: "text", text: "ok" } ])
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/mcp_server_local_test.rb`
Expected: FAIL on validation (`transport_type` not included) and/or `NoMethodError` on `#tools`/`#client` for local.

- [ ] **Step 3: Modify `app/models/mcp_server.rb`**

3a. Add `"local"` to the transport_type inclusion:

```ruby
validates :transport_type, presence: true, inclusion: { in: %w[stdio streamable sse local] }
```

3b. Add a `local?` helper near the top of the class body (after the enums):

```ruby
def local?
  transport_type == "local"
end
```

3c. Make `#client` short-circuit for local (insert at the top of the existing `client` method, before `@client ||= begin`):

```ruby
def client
  return nil if local?

  @client ||= begin
    # ... existing body unchanged ...
  end
rescue => e
  Rails.logger.error "Failed to create MCP client for #{name}: #{e.message}"
  nil
end
```

3d. Add a `local_tools` private method and branch `#tools`:

```ruby
# Replace the existing `def tools` with:
def tools
  return [] unless status_ready?

  return local_tools if local?

  begin
    client&.tools || []
  rescue => e
    Rails.logger.error "Failed to fetch tools from #{name}: #{e.message}"
    []
  end
end

private

def local_tools
  registration = Engines::Registry[metadata["engine"]]
  return [] unless registration

  registration.tool_classes.filter_map do |tool_class|
    Engines::ToolAdapter.for(tool_class, server_context: auth_config_for_tools)
  end
end

def auth_config_for_tools
  # auth_config round-trips through JSON (store_accessor + encrypts), so it
  # comes back string-keyed. with_indifferent_access lets tools read either
  # auth[:api_key] or auth["api_key"].
  (auth_config || {}).with_indifferent_access
end

def test_local_connection!
  start_time = Time.current
  update!(status: "connecting", last_error: nil)

  registration = Engines::Registry[metadata["engine"]]
  raise "Unknown engine: #{metadata["engine"]}" unless registration

  registration.health_check.call(auth_config_for_tools)
  latency = ((Time.current - start_time) * 1000).to_i
  update!(
    status: "ready",
    last_connected_at: Time.current,
    latency_ms: latency,
    last_error: nil,
    metadata: metadata.merge(last_test_at: Time.current.iso8601)
  )
  true
rescue => e
  update!(
    status: "error",
    last_error: e.message,
    metadata: metadata.merge(last_test_at: Time.current.iso8601)
  )
  false
end
```

3e. Branch `#test_connection!` (insert at the top of the existing method):

```ruby
def test_connection!
  return test_local_connection! if local?

  start_time = Time.current
  # ... existing body unchanged ...
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/models/mcp_server_local_test.rb`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add app/models/mcp_server.rb test/models/mcp_server_local_test.rb
git commit -m "feat(mcp): add local transport to McpServer

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 5: McpCatalog registry listing + :registry activation branch

**Files:**
- Modify: `lib/mcp_catalog.rb`
- Test: `test/lib/mcp_catalog_registry_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/lib/mcp_catalog_registry_test.rb
require "test_helper"

class McpCatalogRegistryTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "cat@example.com", password: "testpassword123")
    @account = Account.create!(name: "Cat Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    Engines::Registry.clear
    Engines::Registry.register(Engines::Registration.new(
      id: "demo", name: "Demo", icon: "🧪", description: "demo engine",
      required_config: [ { name: "api_key", label: "Key", type: "secret", required: true } ],
      tool_classes: [], health_check: ->(auth) {}
    ))
  end

  def teardown
    ActsAsTenant.current_tenant = nil
    Engines::Registry.clear
    # `McpCatalog.all`/`categories` memoize at the class level; clear so
    # registry changes between tests are picked up.
    McpCatalog.instance_variable_set(:@catalog, nil)
    McpCatalog.instance_variable_set(:@categories, nil)
  end

  test "all merges registry entries tagged source: :registry" do
    entry = McpCatalog.all.find { |s| s[:id] == "demo" }
    assert entry
    assert_equal :registry, entry[:source]
    assert_equal "engines", entry[:category]
  end

  test "find returns a registry entry" do
    assert_equal "demo", McpCatalog.find("demo")[:id]
  end

  test "activate_for_account creates a local McpServer with engine + auth" do
    server = McpCatalog.activate_for_account(@account, "demo", { "api_key" => "sekret" })
    assert server.persisted?
    assert_equal "local", server.transport_type
    assert_nil server.endpoint
    # metadata round-trips through Postgres JSONB as a string-keyed Hash,
    # so read back with string keys (not symbols).
    assert_equal "demo", server.metadata["engine"]
    assert_equal "demo", server.metadata["catalog_id"]
    assert_equal "sekret", server.auth_config["api_key"]
  end

  test "activation raises when a required config value is missing" do
    assert_raises(ActiveRecord::RecordInvalid) do
      McpCatalog.activate_for_account(@account, "demo", { "api_key" => "" })
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/lib/mcp_catalog_registry_test.rb`
Expected: FAIL (registry entries not listed; no `:registry` branch)

- [ ] **Step 3: Modify `lib/mcp_catalog.rb`**

3a. `load_catalog` merges registry entries:

```ruby
def load_catalog
  catalog_path = Rails.root.join("config", "mcp_catalog.yml")
  yaml = YAML.load_file(catalog_path)
  yaml_servers = yaml["servers"].map(&:deep_symbolize_keys).map { |s| s.merge(source: :yaml) }
  yaml_servers + Engines::Registry.all.map(&:to_catalog_entry)
end
```

3a2. `load_categories` adds an `engines` category so registry entries group under a labeled heading (the YAML has no such entry):

```ruby
def load_categories
  catalog_path = Rails.root.join("config", "mcp_catalog.yml")
  yaml = YAML.load_file(catalog_path)
  categories = yaml["categories"].map(&:deep_symbolize_keys)
  categories << { id: "engines", name: "Built-in engines", icon: "🔧",
                  description: "Native integrations bundled with Nosia." } \
    unless categories.any? { |c| c[:id] == "engines" }
  categories
end
```

> Both `all` and `categories` are memoized (`@catalog`, `@categories`). Tests that mutate `Engines::Registry` must clear these caches in `teardown` (see Step 1).

3b. `activate_for_account` — branch on `template[:source]` at the top:

```ruby
def activate_for_account(account, server_id, config_values = {})
  template = find(server_id)
  return nil unless template

  return activate_registry(account, template, config_values) if template[:source] == :registry

  # ... existing YAML/stdio body unchanged ...
end
```

3c. Add the registry activation helper (private, after `activate_for_account`):

```ruby
def activate_registry(account, template, config_values)
  auth = build_registry_auth(template, config_values)
  validate_required!(template, auth)

  account.mcp_servers.create!(
    name: template[:name],
    transport_type: "local",
    endpoint: nil,
    enabled: true,
    tags: [ template[:category], "catalog" ].join(","),
    notes: template[:description],
    connection_config: {},
    auth_config: auth,
    metadata: {
      catalog_id: template[:id],
      engine: template[:id],
      icon: template[:icon],
      capabilities: template[:capabilities]
    }
  )
end

def build_registry_auth(template, config_values)
  Array(template[:required_config]).each_with_object({}) do |field, auth|
    auth[field[:name].to_s] = config_values[field[:name].to_s].to_s
  end
end

def validate_required!(template, auth)
  missing = Array(template[:required_config]).select do |field|
    field[:required] && auth[field[:name].to_s].blank?
  end
  return if missing.empty?

  record = McpServer.new(name: template[:name])
  record.errors.add(:base, "Missing required config: #{missing.map { |f| f[:name] }.join(", ")}")
  raise ActiveRecord::RecordInvalid.new(record)
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/lib/mcp_catalog_registry_test.rb`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/mcp_catalog.rb test/lib/mcp_catalog_registry_test.rb
git commit -m "feat(mcp): list + activate registry engines in McpCatalog

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 6: OpenAlex ApiClient — auth threading + ping + test stubs

OpenAlex authenticates via an `api_key` **query parameter** (see existing `ApiClient#get`). We make `ApiClient.new` accept an `auth` hash whose `api_key` overrides the ENV-derived `Configuration` default, add a `ping` for `health_check`, and allow injecting Faraday `:test` stubs (webmock is not a dependency).

**Files:**
- Modify: `lib/open_alex/api_client.rb`
- Test: `test/lib/open_alex/api_client_test.rb` (ported from the deleted `spec/open_alex/api_client_spec.rb`)

- [ ] **Step 1: Write the failing test**

```ruby
# test/lib/open_alex/api_client_test.rb
require "test_helper"

class OpenAlex::ApiClientTest < ActiveSupport::TestCase
  def stubs
    @stubs ||= Faraday::Adapter::Test::Stubs.new
  end

  def client(auth = {}, connection: nil)
    OpenAlex::ApiClient.new(auth, connection: connection)
  end

  def connection_with_stubs
    Faraday.new(url: "https://api.openalex.org") do |f|
      f.request :url_encoded
      f.adapter :test, stubs
    end
  end

  test "#get injects api_key from auth into query params" do
    stubs.get("/works") { |env| [ 200, {}, '{"results":[]}' ] }
    response = client({ api_key: "sekret" }, connection: connection_with_stubs).get("/works")
    assert_equal({ "results" => [] }, response)
    stubs.verify_stubbed_calls
  end

  test "#ping returns true on a successful one-row request" do
    stubs.get("/works") { |env| [ 200, {}, '{"results":[{"id":"W1"}]}' ] }
    assert client({}, connection: connection_with_stubs).ping
  end

  test "#get raises on 401" do
    stubs.get("/works") { |env| [ 401, {}, '{"error":"unauthorized"}' ] }
    assert_raises(RuntimeError) do
      client({}, connection: connection_with_stubs).get("/works")
    end
  end

  test "#get retries 429 then succeeds" do
    stubs.get("/works") { |env| [ 429, {}, '' ] }
    stubs.get("/works") { |env| [ 200, {}, '{"results":[]}' ] }
    response = client({}, connection: connection_with_stubs).get("/works")
    assert_equal({ "results" => [] }, response)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/lib/open_alex/api_client_test.rb`
Expected: FAIL (`ArgumentError` for `connection:` / no `ping`)

- [ ] **Step 3: Modify `lib/open_alex/api_client.rb`**

```ruby
module OpenAlex
  class ApiClient
    def initialize(auth = {}, connection: nil)
      @config = OpenAlex::Configuration.new
      @auth = auth || {}
      @connection = connection || build_default_connection
    end

    def get(path, params = {})
      params[:api_key] = api_key
      fetch_with_retry(path, params)
    end

    # Lightweight authenticated request used by McpServer#test_connection!.
    def ping
      get("/works", per_page: 1)
      true
    rescue
      false
    end

    private

    def api_key
      @auth[:api_key].presence || @auth["api_key"].presence || @config.api_key
    end

    def build_default_connection
      Faraday.new(url: @config.base_url) do |f|
        f.request :url_encoded
        f.adapter Faraday.default_adapter
      end
    end

    def fetch_with_retry(path, params, attempt = 0)
      response = @connection.get(path, params)

      case response.status
      when 200
        JSON.parse(response.body)
      when 429, 500..599
        if attempt < @config.max_retries
          sleep(2 ** attempt)
          fetch_with_retry(path, params, attempt + 1)
        else
          raise "Max retries exceeded: #{response.status}"
        end
      else
        raise "HTTP Error #{response.status}: #{response.body}"
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/lib/open_alex/api_client_test.rb`
Expected: PASS (4 tests). If the 429-retry test is flaky due to `sleep`, that is expected — keep the existing retry behavior; the test asserts the final result, not timing.

- [ ] **Step 5: Commit**

```bash
git add lib/open_alex/api_client.rb test/lib/open_alex/api_client_test.rb
git commit -m "feat(open_alex): ApiClient accepts auth, adds ping + test stubs

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 7: Thread server_context auth through OpenAlex tools

Each `OpenAlexTools::*` tool's `call` currently calls `OpenAlex::Tool.<method>(...)` with no auth. We add an `auth:` keyword to every facade method and pass `auth: server_context` from each tool. This is a **mechanical pattern** applied to all 15 tools + facade methods; the test verifies auth threads through one representative tool and the rest follow the identical edit.

**Files:**
- Modify: `lib/open_alex/tool.rb`
- Modify: every file in `app/models/open_alex_tools/*.rb` (15 files)
- Test: `test/models/open_alex_tools_auth_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/open_alex_tools_auth_test.rb
require "test_helper"

class OpenAlexToolsAuthTest < ActiveSupport::TestCase
  test "search_works threads server_context[:api_key] into the ApiClient" do
    received_key = nil
    stubs = Faraday::Adapter::Test::Stubs.new
    stubs.get("/works") do |env|
      received_key = env.params["api_key"]
      [ 200, {}, '{"results":[]}' ]
    end
    connection = Faraday.new(url: "https://api.openalex.org") do |f|
      f.request :url_encoded
      f.adapter :test, stubs
    end

    OpenAlex.stub :default_connection, connection do
      response = OpenAlexTools::SearchWorksTool.call(query: "einstein", server_context: { api_key: "sekret" })
      assert_equal "sekret", received_key
      assert_kind_of MCP::Tool::Response, response
    end
  end
end
```

> This test requires `OpenAlex.default_connection` (an injectable connection used by the facade when no auth-specific client is built). Add it in Step 3. If you'd rather inject via the facade directly, adjust the stub target — but the assertion is unchanged: `server_context[:api_key]` reaches the request.

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/open_alex_tools_auth_test.rb`
Expected: FAIL (no auth threading / no `OpenAlex.default_connection`)

- [ ] **Step 3: Apply the auth-threading pattern**

3a. In `lib/open_alex.rb`, add a default-connection accessor used in tests:

```ruby
module OpenAlex
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    # Used by tests to inject a Faraday :test-adapter connection.
    def default_connection
      @default_connection
    end

    def default_connection=(connection)
      @default_connection = connection
    end
  end
end
```

3b. In `lib/open_alex/tool.rb`, give **every** facade method an `auth: nil` keyword and build the client from auth (or the test connection). Example for `search_works`:

```ruby
def self.search_works(query, params = {}, auth: nil)
  client = build_client(auth)
  response = client.get("/works", params.merge(search: query))
  response['results'].map { |result| {
    id: result['id'], doi: result['doi'], title: result['title'],
    year: result['publication_year'], citations: result['cited_by_count']
  } }
end

def self.build_client(auth)
  return OpenAlex::ApiClient.new(auth || {}) unless OpenAlex.default_connection

  OpenAlex::ApiClient.new(auth || {}, connection: OpenAlex.default_connection)
end
private_class_method :build_client
```

Apply the same `auth: nil` keyword + `build_client(auth)` swap to the other 14 facade methods (`search_authors`, `get_author_works`, `get_work_by_doi`, `search_sources`, `get_source_works`, `search_institutions`, `get_institution_works`, `search_topics`, `get_topic_works`, `search_publishers`, `get_publisher_works`, `search_funders`, `get_funder_works`, `get_author_comprehensive_works`). The single change per method: replace `OpenAlex::ApiClient.new` (where present) with `build_client(auth)`, and add `auth: nil` to the signature. Methods that delegate to an entity (e.g. `get_author_works` → `Author.new(id:)...works`) currently take no client — for those, leave them on the entity path (entities already use `ApiClient.new` internally with ENV); accept `auth: nil` in the signature for a consistent call site but do not need to thread it for the first iteration. Document this in a code comment.

3c. In each `app/models/open_alex_tools/*.rb` tool, change the `call` to pass `auth: server_context`. Example for `search_works_tool.rb`:

```ruby
def self.call(query:, params: {}, server_context:)
  results = OpenAlex::Tool.search_works(query, params, auth: server_context)
  MCP::Tool::Response.new([{
    type: "text",
    text: "Found #{results.length} works matching '#{query}'"
  }], structured_content: results)
end
```

Apply the identical edit to the other 14 tools: add `, auth: server_context` to the `OpenAlex::Tool.<method>(...)` call inside `call`. The 15 tool files are:
- `search_authors_tool.rb` → `OpenAlex::Tool.search_authors(...)`
- `get_author_works_tool.rb` → `OpenAlex::Tool.get_author_works(...)`
- `get_author_comprehensive_works_tool.rb`
- `get_work_by_doi_tool.rb`
- `search_works_tool.rb`
- `search_sources_tool.rb`, `get_source_works_tool.rb`
- `search_institutions_tool.rb`, `get_institution_works_tool.rb`
- `search_topics_tool.rb`, `get_topic_works_tool.rb`
- `search_publishers_tool.rb`, `get_publisher_works_tool.rb`
- `search_funders_tool.rb`, `get_funder_works_tool.rb`

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/models/open_alex_tools_auth_test.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/open_alex.rb lib/open_alex/tool.rb app/models/open_alex_tools/ test/models/open_alex_tools_auth_test.rb
git commit -m "feat(open_alex): thread server_context auth through tools + facade

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 8: kDrive API spike (research)

Confirm the exact Infomaniak kDrive REST endpoints and auth header before implementing the client. Record findings in the spec's "Open questions" by editing the design doc, so the implementer (and reviewer) can verify.

**Files:**
- Modify: `docs/superpowers/specs/2026-07-03-optional-engines-design.md` (append a "kDrive API findings" section)

- [ ] **Step 1: Research the Infomaniak kDrive API**

Fetch the official docs and confirm:
- Base URL (expected: `https://api.infomaniak.com/2`).
- Auth header format (expected: `Authorization: Bearer <token>`).
- Search files endpoint + query param name.
- List folder contents endpoint (by folder id; root id).
- Get file metadata + download endpoint.
- Drive id path component (`/drive/{drive_id}/...`).

Run: `WebFetch` the Infomaniak kDrive API docs (search "Infomaniak kDrive API documentation"). If the docs are gated, record the best-supported endpoint shapes from the public reference and mark any uncertain path with `# SPIKE: confirm` in the client code.

- [ ] **Step 2: Append findings to the design doc**

Add a "## kDrive API findings (post-spike)" section with the confirmed endpoints, e.g.:

```
- Base: https://api.infomaniak.com/2
- Auth: Authorization: Bearer <token>
- Search: GET /drive/{drive_id}/search?query=<q>&with=files
- List: GET /drive/{drive_id}/files?parent_id=<id>&with=files  (root: parent_id=0)
- File:  GET /drive/{drive_id}/files/{file_id}  (+ GET /drive/{drive_id}/files/{file_id}/file for bytes)
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-07-03-optional-engines-design.md
git commit -m "docs(kdrive): record confirmed kDrive API endpoints (spike)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 9: Kdrive::ApiClient

**Files:**
- Create: `lib/kdrive.rb`, `lib/kdrive/api_client.rb`
- Test: `test/lib/kdrive/api_client_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/lib/kdrive/api_client_test.rb
require "test_helper"

class Kdrive::ApiClientTest < ActiveSupport::TestCase
  def stubs; @stubs ||= Faraday::Adapter::Test::Stubs.new; end

  def connection
    Faraday.new(url: Kdrive::ApiClient::BASE_URL) do |f|
      f.request :url_encoded
      f.adapter :test, stubs
    end
  end

  def client(auth = { token: "t", drive_id: "12" }, connection: self.connection)
    Kdrive::ApiClient.new(auth, connection: connection)
  end

  test "sends the Bearer token and drive_id in the path" do
    stubs.get("/drive/12/search") do |env|
      assert_equal "Bearer t", env.request_headers["Authorization"]
      [ 200, {}, '{"data":[]}' ]
    end
    client.get("/search", query: "report")
    stubs.verify_stubbed_calls
  end

  test "ping returns true on success" do
    stubs.get("/drive/12/file") { |env| [ 200, {}, '{"data":[]}' ] }
    assert client.ping
  end

  test "get raises on 404 (wrong drive_id)" do
    stubs.get("/drive/12/file") { |env| [ 404, {}, '{"error":"not found"}' ] }
    err = assert_raises(RuntimeError) { client.get("/file") }
    assert_match(/404/, err.message)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/lib/kdrive/api_client_test.rb`
Expected: FAIL `NameError: uninitialized constant Kdrive`

- [ ] **Step 3: Write minimal implementation**

```ruby
# lib/kdrive.rb
require_relative "kdrive/api_client"
require_relative "kdrive/tool"
require_relative "kdrive/engine_registration"

module Kdrive
end
```

```ruby
# lib/kdrive/api_client.rb
module Kdrive
  class ApiClient
    BASE_URL = "https://api.infomaniak.com/2".freeze

    def initialize(auth, connection: nil)
      @token = auth[:token] || auth["token"]
      @drive_id = auth[:drive_id] || auth["drive_id"]
      @connection = connection || build_default_connection
    end

    def get(path, params = {})
      response = @connection.get("/drive/#{@drive_id}#{path}", params) do |req|
        req.headers["Authorization"] = "Bearer #{@token}"
      end

      case response.status
      when 200..299
        JSON.parse(response.body)
      when 404
        raise "kDrive not found — check your drive id (HTTP 404)"
      when 401, 403
        raise "Invalid kDrive credentials (HTTP #{response.status})"
      else
        raise "HTTP Error #{response.status}: #{response.body}"
      end
    end

    def ping
      get("/file", per_page: 1)
      true
    rescue
      false
    end

    private

    def build_default_connection
      Faraday.new(url: BASE_URL) do |f|
        f.request :url_encoded
        f.adapter Faraday.default_adapter
      end
    end
  end
end
```

> If the spike (Task 8) found different endpoint paths, update `ping` and the tool paths in Tasks 10–11 to match. The `/file` and `/search` paths here are the documented shapes; tests stub them, so the suite stays green regardless.

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/lib/kdrive/api_client_test.rb`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/kdrive.rb lib/kdrive/api_client.rb test/lib/kdrive/api_client_test.rb
git commit -m "feat(kdrive): add ApiClient with Bearer auth + ping

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 10: Kdrive::Tool facade + 3 read-only tools

**Files:**
- Create: `lib/kdrive/tool.rb`
- Create: `app/models/kdrive_tools.rb`, `app/models/kdrive_tools/search_files_tool.rb`, `app/models/kdrive_tools/list_folder_tool.rb`, `app/models/kdrive_tools/get_file_tool.rb`
- Test: `test/models/kdrive_tools_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/kdrive_tools_test.rb
require "test_helper"

class KdriveToolsTest < ActiveSupport::TestCase
  def stubs; @stubs ||= Faraday::Adapter::Test::Stubs.new; end

  def connection
    Faraday.new(url: Kdrive::ApiClient::BASE_URL) do |f|
      f.request :url_encoded
      f.adapter :test, stubs
    end
  end

  def auth; { token: "t", drive_id: "12" }; end

  setup do
    Kdrive.default_connection = connection
  end

  teardown do
    Kdrive.default_connection = nil
  end

  test "search_files returns a Response with structured results" do
    stubs.get("/drive/12/search") do |env|
      [ 200, {}, '{"data":[{"id":"f1","name":"report.pdf","file_type":"file"}]}' ]
    end
    response = KdriveTools::SearchFilesTool.call(query: "report", server_context: auth)
    assert_kind_of MCP::Tool::Response, response
    assert_match(/Found/, response.content.first[:text])
    assert_equal "f1", response.structured_content.first[:id]
  end

  test "list_folder returns a Response" do
    stubs.get("/drive/12/files") do |env|
      [ 200, {}, '{"data":[{"id":"f1","name":"doc.txt"}]}' ]
    end
    response = KdriveTools::ListFolderTool.call(folder_id: "0", server_context: auth)
    assert_kind_of MCP::Tool::Response, response
  end

  test "get_file inlines a text-able file's bounded content" do
    stubs.get("/drive/12/files/77") do |env|
      [ 200, {}, '{"data":{"id":"77","name":"note.txt","size":42,"content_type":"text/plain"}}' ]
    end
    stubs.get("/drive/12/files/77/file") do |env|
      [ 200, { "Content-Type" => "text/plain" }, "hello world" ]
    end
    response = KdriveTools::GetFileTool.call(file_id: "77", server_context: auth)
    assert_kind_of MCP::Tool::Response, response
    assert_match(/hello world/, response.content.first[:text])
  end

  test "get_file returns metadata-only for a binary file" do
    stubs.get("/drive/12/files/88") do |env|
      [ 200, {}, '{"data":{"id":"88","name":"img.png","size":99999,"content_type":"image/png"}}' ]
    end
    response = KdriveTools::GetFileTool.call(file_id: "88", server_context: auth)
    assert_match(/binary|too large|metadata/i, response.content.first[:text])
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/kdrive_tools_test.rb`
Expected: FAIL `NameError: uninitialized constant KdriveTools`

- [ ] **Step 3: Write minimal implementation**

3a. Facade:

```ruby
# lib/kdrive/tool.rb
module Kdrive
  class Tool
    INLINEABLE_TYPES = %w[text/plain text/markdown text/csv application/json].freeze
    INLINE_CAP_BYTES = 1.megabyte

    def self.search_files(query, auth:)
      client = build_client(auth)
      client.get("/search", query: query, with: "files")
    end

    def self.list_folder(folder_id, auth:)
      client = build_client(auth)
      client.get("/files", parent_id: folder_id, with: "files")
    end

    def self.get_file(file_id, auth:)
      client = build_client(auth)
      meta = client.get("/files/#{file_id}")
      { meta: meta, content: maybe_inline(client, meta) }
    end

    class << self
      private

      def build_client(auth)
        return Kdrive::ApiClient.new(auth) unless Kdrive.default_connection

        Kdrive::ApiClient.new(auth, connection: Kdrive.default_connection)
      end

      def maybe_inline(client, meta)
        data = meta["data"] || meta[:data]
        type = data["content_type"]
        size = data["size"].to_i
        return nil unless type.to_s.start_with?("text/") || INLINEABLE_TYPES.include?(type.to_s)
        return nil if size > INLINE_CAP_BYTES

        download(client, data["id"])
      end

      def download(client, file_id)
        # raw bytes endpoint (spike-confirmed in Task 8)
        client.get("/files/#{file_id}/file")
      rescue
        nil
      end
    end
  end
end
```

3b. Test-connection accessor in `lib/kdrive.rb` (extend the module added in Task 9):

```ruby
module Kdrive
  class << self
    def default_connection; @default_connection; end
    def default_connection=(c); @default_connection = c; end
  end
end
```

3c. Tools:

```ruby
# app/models/kdrive_tools.rb
module KdriveTools
  def self.all
    [ SearchFilesTool, ListFolderTool, GetFileTool ]
  end
end
```

```ruby
# app/models/kdrive_tools/search_files_tool.rb
class KdriveTools::SearchFilesTool < MCP::Tool
  tool_name "kdrive_search_files"
  title "Search kDrive files"
  description "Search files and folders in the user's Infomaniak kDrive by query"
  input_schema(properties: { query: { type: "string" } }, required: [ "query" ])
  annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

  def self.call(query:, server_context:)
    results = Kdrive::Tool.search_files(query, auth: server_context)
    items = results["data"] || []
    MCP::Tool::Response.new(
      [ { type: "text", text: "Found #{items.size} files matching '#{query}'" } ],
      structured_content: items
    )
  end
end
```

```ruby
# app/models/kdrive_tools/list_folder_tool.rb
class KdriveTools::ListFolderTool < MCP::Tool
  tool_name "kdrive_list_folder"
  title "List kDrive folder"
  description "List the contents of a folder in the user's Infomaniak kDrive (defaults to drive root)"
  input_schema(
    properties: { folder_id: { type: "string", description: "Folder id; '0' for the drive root" } },
    required: []
  )
  annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

  def self.call(folder_id: "0", server_context:)
    results = Kdrive::Tool.list_folder(folder_id, auth: server_context)
    items = results["data"] || []
    MCP::Tool::Response.new(
      [ { type: "text", text: "Folder has #{items.size} items" } ],
      structured_content: items
    )
  end
end
```

```ruby
# app/models/kdrive_tools/get_file_tool.rb
class KdriveTools::GetFileTool < MCP::Tool
  tool_name "kdrive_get_file"
  title "Get kDrive file"
  description "Fetch a file's metadata from Infomaniak kDrive, inlining a bounded text excerpt for text-able types"
  input_schema(properties: { file_id: { type: "string" } }, required: [ "file_id" ])
  annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

  def self.call(file_id:, server_context:)
    result = Kdrive::Tool.get_file(file_id, auth: server_context)
    data = (result[:meta]["data"] || result[:meta][:data] || {})
    content = result[:content]
    text = if content
             "File #{file_id} (#{data['name']}): #{content}"
           else
             "File #{file_id} (#{data['name']}, #{data['content_type']}, #{data['size']} bytes) — binary or too large to inline"
           end
    MCP::Tool::Response.new([ { type: "text", text: text } ], structured_content: data)
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/models/kdrive_tools_test.rb`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/kdrive.rb lib/kdrive/tool.rb app/models/kdrive_tools.rb app/models/kdrive_tools/ test/models/kdrive_tools_test.rb
git commit -m "feat(kdrive): add Tool facade + read-only tools (search, list, get)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 11: Engine registrations + boot initializer

**Files:**
- Create: `lib/open_alex/engine_registration.rb`, `lib/kdrive/engine_registration.rb`
- Modify: `lib/open_alex.rb` (require engine_registration)
- Create: `config/initializers/engines.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/integration/engines_boot_test.rb
require "test_helper"

class EnginesBootTest < ActiveSupport::TestCase
  test "open_alex and kdrive are registered at boot" do
    assert Engines::Registry["open_alex"], "open_alex engine not registered"
    assert Engines::Registry["kdrive"], "kdrive engine not registered"
  end

  test "every registered tool class is translatable by the adapter" do
    Engines::Registry.all.each do |reg|
      reg.tool_classes.each do |tool_class|
        assert Engines::ToolAdapter.supported?(tool_class),
               "#{reg.id}/#{tool_class.tool_name} has an unsupported schema"
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/integration/engines_boot_test.rb`
Expected: FAIL (engines not registered)

- [ ] **Step 3: Write minimal implementation**

3a. `lib/open_alex.rb` — add the require:

```ruby
require "open_alex/engine_registration"
```

3b. `lib/open_alex/engine_registration.rb`:

```ruby
module OpenAlex
  class EngineRegistration < Engines::Registration
    def initialize
      super(
        id: "open_alex",
        name: "OpenAlex",
        icon: "📚",
        description: "Search scholarly works, authors, institutions, sources, topics, publishers and funders.",
        required_config: [
          { name: "api_key", label: "OpenAlex API key (optional, for the polite pool)", type: "secret", required: false }
        ],
        tool_classes: OpenAlexTools.all,
        health_check: ->(auth) { OpenAlex::ApiClient.new(auth).ping || raise("OpenAlex unreachable") },
        capabilities: [ "tools" ]
      )
    end
  end
end
```

3c. `lib/kdrive/engine_registration.rb`:

```ruby
module Kdrive
  class EngineRegistration < Engines::Registration
    def initialize
      super(
        id: "kdrive",
        name: "Infomaniak kDrive",
        icon: "📁",
        description: "Search, browse and read files from your Infomaniak kDrive.",
        required_config: [
          { name: "token", label: "kDrive Token", type: "secret", required: true },
          { name: "drive_id", label: "kDrive ID", type: "string", required: true }
        ],
        tool_classes: KdriveTools.all,
        health_check: ->(auth) { Kdrive::ApiClient.new(auth).ping || raise("kDrive unreachable") },
        capabilities: [ "tools" ]
      )
    end
  end
end
```

3d. `config/initializers/engines.rb`:

```ruby
# Register built-in optional engines. Each engine is always bundled;
# an account activates it per-tenant via the MCP Catalog.
require_dependency "engines/registry" unless defined?(Engines::Registry)

Rails.application.config.to_prepare do
  # Register once; guard against re-loading in development.
  unless Engines::Registry.find("open_alex")
    require_dependency "open_alex/engine_registration"
    require_dependency "kdrive/engine_registration"
    Engines::Registry.register(OpenAlex::EngineRegistration.new)
    Engines::Registry.register(Kdrive::EngineRegistration.new)

    Engines::Registry.all.each do |registration|
      registration.tool_classes.each do |tool_class|
        next if Engines::ToolAdapter.supported?(tool_class)

        Rails.logger.warn "Engines: dropping unsupported tool #{registration.id}/#{tool_class.tool_name}"
      end
    end
  end
end
```

> `config.to_prepare` runs on boot and on each code-reload in development. The `unless Engines::Registry.find(...)` guard makes registration idempotent so reloading does not raise `DuplicateIdError`. The `OpenAlexTools` / `KdriveTools` classes live under `app/models` and are autoloaded.

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/integration/engines_boot_test.rb`
Expected: PASS (2 tests). If the "translatable" assertion fails for a tool, fix that tool's `input_schema` (the spike in Task 3 covers the shapes) rather than weakening the assertion.

- [ ] **Step 5: Commit**

```bash
git add lib/open_alex.rb lib/open_alex/engine_registration.rb lib/kdrive/engine_registration.rb config/initializers/engines.rb test/integration/engines_boot_test.rb
git commit -m "feat(engines): register open_alex + kdrive at boot

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 12: Remove the MCP provider surface + old RSpec skeleton

Per the spec's non-goals, Nosia is not an MCP server for external clients. Remove the provider controller, its route, and the gem-skeleton RSpec tests (now ported to Minitest).

**Files:**
- Delete: `app/controllers/mcp_openalex_controller.rb`
- Delete: `spec/` (entire directory)
- Modify: `config/routes.rb`

- [ ] **Step 1: Remove the route**

In `config/routes.rb`, delete the line:

```ruby
  post '/mcp/openalex', to: 'mcp_openalex#create'
```

and the preceding comment line if it exists.

- [ ] **Step 2: Delete the controller and the spec directory**

```bash
git rm app/controllers/mcp_openalex_controller.rb
git rm -r spec/
```

- [ ] **Step 3: Verify the app still boots and tests pass**

Run: `bin/rails test test/lib/engines test/models/mcp_server_local_test.rb test/lib/mcp_catalog_registry_test.rb test/lib/open_alex/api_client_test.rb test/lib/kdrive test/models/open_alex_tools_auth_test.rb test/models/kdrive_tools_test.rb test/integration/engines_boot_test.rb`
Expected: PASS (no load errors referencing the removed controller or route)

- [ ] **Step 4: Commit**

```bash
git add config/routes.rb
git commit -m "chore(engines): remove MCP provider surface + old RSpec skeleton

Nosia consumes engines in-process; the external MCP server endpoint
and the gem-skeleton RSpec tests are no longer needed (tests ported
to Minitest under test/).

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 13: Replace the docker kDrive catalog entry with the native engine

The native kDrive engine replaces the docker-based entry. Remove the `kdrive` YAML entry so the catalog shows only the native "Infomaniak kDrive" (source `:registry`). Existing accounts that activated the docker entry keep their `McpServer` rows (we delete nothing from the DB); new activations use the native engine.

**Files:**
- Modify: `config/mcp_catalog.yml`

- [ ] **Step 1: Remove the docker `kdrive` entry**

In `config/mcp_catalog.yml`, delete the entire `# Infomaniak kDrive` block (the `- id: "kdrive"` entry with its `command`, `args`, `requires_config`, `env`). Leave the `infomaniak-calender` and `kchat` entries untouched.

- [ ] **Step 2: Verify the catalog lists the native kDrive engine**

```bash
bin/rails runner 'p McpCatalog.all.select { |s| s[:id] == "kdrive" }.first'
```
Expected: a single entry with `source: :registry` (the native engine), no docker `kdrive` entry.

- [ ] **Step 3: Commit**

```bash
git add config/mcp_catalog.yml
git commit -m "feat(kdrive): replace docker catalog entry with native engine

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 14: Integration test — chat wires local-engine tools end-to-end

**Files:**
- Test: `test/integration/local_engine_chat_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/integration/local_engine_chat_test.rb
require "test_helper"

class LocalEngineChatTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "int@example.com", password: "testpassword123")
    @account = Account.create!(name: "Int Account", owner: @user)
    ActsAsTenant.current_tenant = @account

    stubs = Faraday::Adapter::Test::Stubs.new
    stubs.get("/works") { |env| [ 200, {}, '{"results":[{"id":"W1","title":"Relativity"}]}' ] }
    @connection = Faraday.new(url: "https://api.openalex.org") do |f|
      f.request :url_encoded
      f.adapter :test, stubs
    end
    OpenAlex.default_connection = @connection
  end

  teardown do
    ActsAsTenant.current_tenant = nil
    OpenAlex.default_connection = nil
  end

  test "a ready local OpenAlex server contributes an adapted tool to the chat" do
    server = @account.mcp_servers.create!(
      name: "OpenAlex", transport_type: "local", status: "ready",
      metadata: { engine: "open_alex" }, auth_config: { api_key: "sekret" }
    )
    chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai,
                                  assume_model_exists: true)
    chat.add_mcp_server(server)

    tools = chat.mcp_tools
    assert tools.any? { |t| t.name == "openalex_search_works" }, "OpenAlex tool not wired into chat"

    adapted = tools.find { |t| t.name == "openalex_search_works" }
    result = adapted.call({ "query" => "einstein" })
    assert_match(/Relativity/, result)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/integration/local_engine_chat_test.rb`
Expected: FAIL if wiring is broken; PASS once Tasks 4–7 + 11 are in place. If it already passes, that confirms the end-to-end wiring — still keep the test.

- [ ] **Step 3: (No new implementation expected — this is a verification test)**

If the test fails, debug the wiring path: `chat.mcp_tools` → `McpServer#tools` (local branch) → `Engines::ToolAdapter.for` → `with_tools`. The most likely failure is a wrong tool `name` (adapter class-naming) or credentials not reaching the stubbed connection.

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/integration/local_engine_chat_test.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add test/integration/local_engine_chat_test.rb
git commit -m "test(engines): integration test for local OpenAlex chat wiring

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 15: System test — activate an engine from the catalog

**Files:**
- Test: `test/system/activate_engine_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/system/activate_engine_test.rb
require "test_helper"

class ActivateEngineSystemTest < ApplicationSystemTestCase
  setup do
    @user = users(:one) # adjust to an existing fixture, or build one as in ChatTest
    visit root_url
    # sign in per the app's auth flow (see an existing system test for the exact steps)
  end

  test "admin activates the OpenAlex engine and sees ready status" do
    visit mcp_catalog_index_url
    click_on "OpenAlex"
    fill_in "OpenAlex API key", with: ""  # api_key is optional
    click_on "Activate"

    assert_text "ready" # or "Activated", matching the existing flash
  end
end
```

> Adjust the sign-in step and the activation form selectors to match the existing catalog UI (`app/views/mcp_catalog/index.html.erb`, `show.html.erb`). If building records manually is the project pattern (see `ChatTest`), prefer that over relying on a `users` fixture. This is one journey — keep it minimal.

- [ ] **Step 2: Run test to verify it fails or passes**

Run: `bin/rails test:system test/system/activate_engine_test.rb`
Expected: PASS after adjusting selectors. System tests run Capybara + Selenium; ensure `bin/dev`-compatible env or the system test driver is configured.

- [ ] **Step 3: Commit**

```bash
git add test/system/activate_engine_test.rb
git commit -m "test(engines): system test activating OpenAlex from catalog

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 16: Full CI green

- [ ] **Step 1: Run RuboCop with autocorrect**

Run: `bundle exec rubocop -a`
Expected: no offenses remaining in new/modified files (the project's `.rubocop.yml` is the source of truth).

- [ ] **Step 2: Run Brakeman**

Run: `bundle exec brakeman --no-pager`
Expected: no new warnings. The adapter uses no `eval`/`constantize` on user data; `const_set` is on a camelize'd tool name (controlled). If Brakeman flags `const_set`, add a `:safe`-style comment or scope and re-run.

- [ ] **Step 3: Run the full suite**

Run: `bin/rails test && bin/rails test:system`
Expected: all green.

- [ ] **Step 4: Run bin/ci**

Run: `bin/ci`
Expected: green (RuboCop + Brakeman + tests).

- [ ] **Step 5: Commit any auto-fixes**

```bash
git add -A
git commit -m "chore: rubocop/brakeman cleanup for optional engines

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Notes for the implementer

- **The spike (Task 3) is the gate.** Do not start the engine tasks until `ToolAdapter` passes all five adapter tests, including the nested-schema one. If the nested schema won't round-trip through RubyLLM's `params(schema:)`, that is the central design risk — resolve it there, not downstream.
- **Credentials never enter the prompt.** They live in `server_context`, bound at adapter-instance construction in `McpServer#local_tools`. Never add `api_key`/`token`/`drive_id` to a tool's `input_schema`.
- **Adding a third engine** requires only: a new `lib/<engine>/` with an `ApiClient`, `Tool` facade, `MCP::Tool` subclasses, an `EngineRegistration`, a require + `Engines::Registry.register` in `config/initializers/engines.rb`, and a `KdriveTools`-style `.all` helper. No framework changes.
- **Faraday `:test` adapter** is used everywhere instead of webmock. Inject a connection via the `connection:` kwarg (OpenAlex) or `Kdrive.default_connection=` (kDrive). See `test/lib/open_alex/api_client_test.rb` for the pattern.
- **`ActsAsTenant`**: set `ActsAsTenant.current_tenant = @account` in `setup` and clear it in `teardown` for model tests that create `McpServer` rows.