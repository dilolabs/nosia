class GreenIt
  class << self
    # Total tokens × per-model kWh/token. tokens = input + output (the Comparia
    # figure is a blended per-token average, so it applies to total tokens).
    # Returns a hash so the UI can tell whether the fallback was used.
    def energy_kwh(tokens:, model_id:, kind: :completion)
      return { kwh: 0.0, fallback: false } if tokens.nil? || tokens.zero?

      coeff = kwh_per_token(model_id:, kind:)
      { kwh: tokens * coeff, fallback: fallback_used?(model_id:, kind:, coeff:) }
    end

    def co2e_g(kwh:)
      return 0.0 if kwh.nil? || kwh.zero?

      kwh * grid_intensity_gco2e_per_kwh
    end

    def grid_intensity_gco2e_per_kwh
      ENV["GREENIT_GRID_INTENSITY_GCO2E_PER_KWH"]&.to_f || config.fetch("grid_intensity_gco2e_per_kwh", 475)
    end

    def fallback_kwh_per_token
      ENV["GREENIT_FALLBACK_KWH_PER_TOKEN"]&.to_f || config.fetch("fallback_kwh_per_token", 0.00000009)
    end

    def embedding_kwh_per_input_token
      ENV["GREENIT_EMBEDDING_KWH_PER_INPUT_TOKEN"]&.to_f || config.dig("embedding", "kwh_per_input_token") || 0.00000001
    end

    # The Comparia mWh-per-1000-tokens value for a model id, or nil if absent.
    def dataset_mwh_per_1000_tokens(model_id)
      return nil if model_id.blank?

      energy_models[model_id.to_s.downcase]
    end

    private

    def kwh_per_token(model_id:, kind:)
      return embedding_kwh_per_input_token if kind.to_s == "embedding"

      mwh = dataset_mwh_per_1000_tokens(model_id)
      return fallback_kwh_per_token if mwh.nil?

      mwh * 1e-9 # mWh per 1000 tokens → kWh per token
    end

    def fallback_used?(model_id:, kind:, coeff:)
      return true if kind.to_s == "embedding" # embeddings always use the fallback (not in Comparia)
      return false if dataset_mwh_per_1000_tokens(model_id)

      coeff == fallback_kwh_per_token
    end

    def energy_models
      @energy_models ||= load_energy_models
    end

    def load_energy_models
      path = Rails.root.join("config", "model_energy.yml")
      YAML.load_file(path).fetch("models", {})
    end

    def config
      @config ||= YAML.load_file(Rails.root.join("config", "green_it.yml"))
    end
  end
end