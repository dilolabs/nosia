require "test_helper"

class GreenItTest < ActiveSupport::TestCase
  test "energy_kwh converts mWh-per-1000-tokens to kWh for a known model" do
    # glm-5.2: 4095 mWh / 1000 tokens → 1000 tokens × 4095 × 1e-9 = 0.004095 kWh
    result = GreenIt.energy_kwh(tokens: 1000, model_id: "glm-5.2")
    assert_in_delta 0.004095, result[:kwh], 1e-12
    assert_not result[:fallback]
  end

  test "energy_kwh is case-insensitive on model_id" do
    result = GreenIt.energy_kwh(tokens: 1000, model_id: "GLM-5.2")
    assert_in_delta 0.004095, result[:kwh], 1e-12
  end

  test "energy_kwh uses fallback for an unknown chat model and flags it" do
    result = GreenIt.energy_kwh(tokens: 1000, model_id: "claude-4-6-sonnet")
    assert_in_delta GreenIt.fallback_kwh_per_token, result[:kwh] / 1000, 1e-15
    assert result[:fallback]
  end

  test "energy_kwh uses the embedding coefficient for embeddings" do
    result = GreenIt.energy_kwh(tokens: 1000, model_id: "text-embedding-3-small", kind: :embedding)
    assert_in_delta GreenIt.embedding_kwh_per_input_token, result[:kwh] / 1000, 1e-15
    assert result[:fallback]
  end

  test "energy_kwh is zero for zero tokens" do
    result = GreenIt.energy_kwh(tokens: 0, model_id: "glm-5.2")
    assert_equal 0.0, result[:kwh]
  end

  test "co2e_g multiplies kWh by grid intensity" do
    assert_in_delta 475.0, GreenIt.co2e_g(kwh: 1.0), 1e-9
  end

  test "ENV grid intensity overrides config" do
    with_env("GREENIT_GRID_INTENSITY_GCO2E_PER_KWH" => "100") do
      GreenIt.instance_variable_set(:@config, nil)
      assert_in_delta 100.0, GreenIt.grid_intensity_gco2e_per_kwh, 1e-9
    end
    GreenIt.instance_variable_set(:@config, nil)
  end

  test "retroactive update: changing the dataset changes a historical figure" do
    # The whole point of computing live from raw tokens: a coefficient update
    # retroactively corrects history. Simulate a dataset update by swapping the
    # memoized model→mWh map, then assert the same tokens yield a new kWh.
    GreenIt.instance_variable_set(:@energy_models, { "glm-5.2" => 8000.0 })
    result = GreenIt.energy_kwh(tokens: 1000, model_id: "glm-5.2")
    assert_in_delta 0.008, result[:kwh], 1e-12
  ensure
    GreenIt.remove_instance_variable(:@energy_models)
  end

  private

  def with_env(vars)
    old = vars.keys.each_with_object({}) { |k, h| h[k] = ENV[k] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
