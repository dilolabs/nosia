require "test_helper"

class Nosia::NativeReadinessesControllerTest < ActionController::TestCase
  tests Nosia::NativeReadinessesController

  setup do
    @previous_environment = ENV.to_h.slice("NOSIA_NATIVE_LOCAL", "AI_API_KEY")
    ENV["NOSIA_NATIVE_LOCAL"] = "1"
    ENV["AI_API_KEY"] = "native-readiness-test-key"
    @routes = ActionDispatch::Routing::RouteSet.new
    @routes.draw { get "/native/ready", to: "nosia/native_readinesses#show" }
    SolidQueue::Process.delete_all
  end

  teardown do
    %w[NOSIA_NATIVE_LOCAL AI_API_KEY].each { |key| ENV.delete(key) }
    ENV.update(@previous_environment)
  end

  test "mode disabled or missing credentials denies access" do
    get :show
    assert_response :unauthorized
    @request.headers["Authorization"] = "Bearer native-readiness-test-key"
    ENV.delete("NOSIA_NATIVE_LOCAL")
    get :show
    assert_response :unauthorized
    ENV["NOSIA_NATIVE_LOCAL"] = "1"
    ENV.delete("AI_API_KEY")
    get :show
    assert_response :unauthorized
  end

  test "wrong credentials deny access" do
    @request.headers["Authorization"] = "Bearer wrong-key"
    get :show
    assert_response :unauthorized
  end

  test "worker must have a recent heartbeat" do
    @request.headers["Authorization"] = "Bearer native-readiness-test-key"
    get :show
    assert_response :service_unavailable
    worker = SolidQueue::Process.create!(kind: "Worker", name: "native-test-worker", pid: 12345,
      hostname: "test", last_heartbeat_at: 3.minutes.ago)
    get :show
    assert_response :service_unavailable
    worker.update!(last_heartbeat_at: Time.current)
    get :show
    assert_response :ok
  end

  test "a supervisor alone does not prove jobs can run" do
    @request.headers["Authorization"] = "Bearer native-readiness-test-key"
    SolidQueue::Process.create!(kind: "Supervisor", name: "native-test-supervisor", pid: 12346,
      hostname: "test", last_heartbeat_at: Time.current)
    get :show
    assert_response :service_unavailable
  end
end
