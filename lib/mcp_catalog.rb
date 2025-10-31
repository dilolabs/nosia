class McpCatalog
  class << self
    def all
      @catalog ||= load_catalog
    end

    def find(id)
      all.find { |server| server[:id] == id.to_s }
    end

    def by_category(category)
      all.select { |server| server[:category] == category.to_s }
    end

    def categories
      @categories ||= load_categories
    end

    def activate_for_account(account, server_id, config_values = {})
      template = find(server_id)
      return nil unless template

      # Remplacer les variables {{variable}} par les valeurs
      auth_config = build_auth_config(template, config_values)
      env_config = build_env_config(template, config_values)

      # Configuration différente selon le type de transport
      is_stdio = template[:transport_type] == "stdio"

      if is_stdio
        # Pour stdio: pas d'endpoint, utiliser command/args/env
        connection_config = {
          command: template[:command],
          args: interpolate_array(template[:args], config_values),
          env: env_config
        }
        endpoint = nil
      else
        # Pour streamable/http: utiliser endpoint et headers
        connection_config = build_connection_config(template, config_values)
        endpoint = template[:url]
      end

      # Créer le serveur MCP
      mcp_server = account.mcp_servers.create!(
        name: template[:name],
        transport_type: template[:transport_type],
        endpoint: endpoint,
        enabled: true,
        tags: [template[:category], "catalog"].join(","),
        notes: template[:description],
        connection_config: connection_config,
        auth_config: auth_config,
        metadata: {
          catalog_id: template[:id],
          icon: template[:icon],
          capabilities: template[:capabilities]
        }
      )

      mcp_server
    end

    private

    def load_catalog
      catalog_path = Rails.root.join("config", "mcp_catalog.yml")
      yaml = YAML.load_file(catalog_path)
      yaml["servers"].map(&:deep_symbolize_keys)
    end

    def load_categories
      catalog_path = Rails.root.join("config", "mcp_catalog.yml")
      yaml = YAML.load_file(catalog_path)
      yaml["categories"].map(&:deep_symbolize_keys)
    end

    def build_connection_config(template, values)
      config = {}
      config[:url] = template[:url] if template[:url]
      config[:headers] = template[:headers] if template[:headers]
      config
    end

    def build_auth_config(template, values)
      return {} unless template[:auth_config]

      auth = template[:auth_config].dup
      auth.each do |key, value|
        if value.is_a?(String) && value.include?("{{")
          auth[key] = interpolate(value, values)
        end
      end
      auth.stringify_keys
    end

    def build_env_config(template, values)
      return {} unless template[:env]

      env = template[:env].dup
      env.each do |key, value|
        if value.is_a?(String) && value.include?("{{")
          env[key] = interpolate(value, values)
        end
      end
      env.stringify_keys
    end

    def interpolate_array(array, values)
      return [] unless array

      array.map do |item|
        interpolate(item, values)
      end
    end

    def interpolate(string, values)
      return string unless string.is_a?(String)

      result = string.dup
      values.each do |key, value|
        result.gsub!("{{#{key}}}", value.to_s)
      end
      result
    end
  end
end
