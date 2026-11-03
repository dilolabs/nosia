require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"
require "timeout"
require_relative "../../../lib/nosia/native_stack"

class NativeStackContractTest < Minitest::Test
  def test_native_mode_requires_explicit_opt_in
    [ {}, { "NOSIA_NATIVE_LOCAL" => "true" }, { "NOSIA_NATIVE_LOCAL" => "0" } ].each do |environment|
      refute Nosia::NativeStack.enabled?(environment)
      assert_raises(Nosia::NativeStack::ConfigurationError) { Nosia::NativeStack.require_enabled!(environment) }
    end
    assert Nosia::NativeStack.enabled?("NOSIA_NATIVE_LOCAL" => "1")
  end

  def test_local_origin_is_explicit_and_limited_to_loopback
    assert_equal 8271, Nosia::NativeStack.origin("NOSIA_URL" => "http://127.0.0.1:8271").port
    [ "", "http://localhost:8271", "http://192.168.1.2:8271", "https://127.0.0.1:8271",
      "http://127.0.0.1:80", "http://user@127.0.0.1:8271", "http://127.0.0.1:8271/path",
      "http://127.0.0.1:8271?key=x", "http://127.0.0.1:8271#x", "invalid origin" ].each do |value|
      assert_raises(Nosia::NativeStack::ConfigurationError) { Nosia::NativeStack.origin("NOSIA_URL" => value) }
    end
  end

  def test_capabilities_identify_actual_source_and_latest_migration
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "db/migrate"))
      %w[20261014152721_current.rb 20250101000000_old.rb invalid.rb].each do |name|
        File.write(File.join(root, "db/migrate", name), "")
      end
      revision = "b" * 40
      assert_equal({ protocolVersion: 1, serverCommit: revision, databaseSchemaVersion: 20261014152721 },
        Nosia::NativeStack.capabilities(root: root, revision: revision))
      assert_raises(Nosia::NativeStack::ConfigurationError) { Nosia::NativeStack.capabilities(root: root, revision: "main") }
    end
  end

  def test_missing_schema_cannot_be_advertised_as_compatible
    Dir.mktmpdir do |root|
      assert_raises(Nosia::NativeStack::ConfigurationError) { Nosia::NativeStack.capabilities(root: root, revision: "a" * 40) }
    end
  end

  def test_standard_entrypoint_preserves_exact_arguments_without_native_setup
    root = File.expand_path("../../..", __dir__)
    arguments = [ "space in an argument", "$(touch SHOULD_NOT_EXIST)", "--option=value" ]
    output, errors, status = Open3.capture3({ "NOSIA_NATIVE_LOCAL" => nil }, "sh", File.join(root, "bin/nosia-entrypoint"),
      RbConfig.ruby, "-rjson", "-e", "puts JSON.generate(ARGV)", "--", *arguments)
    assert status.success?, errors
    assert_equal arguments, JSON.parse(output)
  end

  def test_child_failure_stops_its_sibling_and_fails_the_container
    with_supervisor("failure") do |directory, waiter|
      status = Timeout.timeout(10) { waiter.value }
      assert_equal 7, status.exitstatus
      assert File.exist?(File.join(directory, "puma.stopped"))
      assert_owned_children_gone(directory)
    end
  end

  def test_unexpected_clean_exit_also_makes_the_container_unavailable
    with_supervisor("clean-exit") do |directory, waiter|
      status = Timeout.timeout(10) { waiter.value }
      assert_equal 1, status.exitstatus
      assert_owned_children_gone(directory)
    end
  end

  def test_shutdown_waits_for_both_owned_children
    with_supervisor("running") do |directory, waiter|
      Timeout.timeout(10) do
        sleep 0.02 until %w[puma.ready rake.ready].all? { |file| File.exist?(File.join(directory, file)) }
      end
      Process.kill("TERM", waiter.pid)
      assert Timeout.timeout(10) { waiter.value }.success?
      assert File.exist?(File.join(directory, "puma.stopped"))
      assert File.exist?(File.join(directory, "rake.stopped"))
      assert_owned_children_gone(directory)
    end
  end

  private
    def with_supervisor(mode)
      Dir.mktmpdir do |directory|
        bundle = File.join(directory, "bundle")
        File.write(bundle, "#!#{RbConfig.ruby}\n" + <<~'RUBY')
          directory = ENV.fetch("NATIVE_TEST_EVENTS")
          role = ARGV.fetch(1)
          File.write(File.join(directory, "#{role}.pid"), Process.pid.to_s)
          Signal.trap("TERM") do
            File.write(File.join(directory, "#{role}.stopped"), "done")
            exit 0
          end
          File.write(File.join(directory, "#{role}.ready"), "ready")
          if role == "rake" && ENV.fetch("NATIVE_TEST_MODE") != "running"
            sleep 0.02 until File.exist?(File.join(directory, "puma.ready"))
            exit(ENV["NATIVE_TEST_MODE"] == "failure" ? 7 : 0)
          end
          loop { sleep 0.05 }
        RUBY
        File.chmod(0755, bundle)
        root = File.expand_path("../../..", __dir__)
        environment = { "PATH" => "#{directory}:#{ENV.fetch('PATH')}", "NATIVE_TEST_EVENTS" => directory, "NATIVE_TEST_MODE" => mode }
        Open3.popen3(environment, RbConfig.ruby, File.join(root, "bin/nosia-native-boot")) do |input, output, errors, waiter|
          input.close
          begin
            yield directory, waiter
          ensure
            Process.kill("TERM", waiter.pid) if waiter.alive?
            Timeout.timeout(30) { waiter.value }
            output.close
            errors.close
          end
        end
      end
    end

    def assert_owned_children_gone(directory)
      Dir.glob(File.join(directory, "*.pid")).each do |file|
        pid = Integer(File.read(file))
        assert_raises(Errno::ESRCH) { Process.kill(0, pid) }
      end
    end
end
