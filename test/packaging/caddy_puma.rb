require "minitest/autorun"
require "yaml"

class CaddyPumaPackagingTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_gemfile_does_not_include_thruster
    assert_empty file_contents("Gemfile").lines.grep(/\A\s*gem\s+["']thruster["']/)
  end

  def test_lockfile_does_not_include_thruster
    assert_empty file_contents("Gemfile.lock").lines.grep(/\A\s+thruster(?:\s|\()/)
  end

  def test_thruster_binstub_is_absent
    refute File.exist?(File.join(ROOT, "bin/thrust"))
  end

  def test_procfile_runs_puma_directly_and_keeps_the_worker
    assert_equal "web: bin/start-app\nworker: bundle exec rake solid_queue:start\n", file_contents("Procfile")
  end

  def test_docker_image_exposes_only_the_internal_puma_port
    ports = file_contents("Dockerfile").lines.grep(/\AEXPOSE\s+/).flat_map { |line| line.split.drop(1) }

    assert_equal [ "3000" ], ports
  end

  def test_docker_image_omits_thruster_timeout_defaults
    assert_empty file_contents("Dockerfile").lines.grep(/\bHTTP_(?:IDLE|READ|WRITE)_TIMEOUT\b/)
  end

  def test_docker_image_keeps_the_process_monitor_command
    assert_includes file_contents("Dockerfile").lines.map(&:strip), 'CMD ["bin/boot"]'
  end

  def test_dockerfile_generator_disables_thruster
    assert_equal false, yaml_contents("config/dockerfile.yml").fetch("options").fetch("thruster")
  end

  def test_caddy_publishes_web_ports_and_preserves_certificate_storage
    services = yaml_contents("docker-compose.yml").fetch("services")
    proxy = services.fetch("reverse-proxy")

    assert_equal [ "80:80", "443:443" ], proxy.fetch("ports")
    assert_includes proxy.fetch("volumes"), "caddy-data:/data"
    refute services.fetch("web").key?("ports")
  end

  def test_caddy_forwards_to_puma_without_forcing_internal_certificates
    caddyfile = file_contents("Caddyfile")

    assert_match(/\breverse_proxy\s+web:3000\b/, caddyfile)
    refute_match(/^\s*tls\s+internal\s*$/, caddyfile)
  end

  def test_puma_keeps_the_internal_port_default
    assert_includes file_contents("config/puma.rb"), 'ENV.fetch("PORT", 3000)'
  end

  def test_compose_healthcheck_targets_puma
    web = yaml_contents("docker-compose.yml").fetch("services").fetch("web")

    assert_equal [ "CMD", "curl", "-f", "http://localhost:3000/up" ], web.fetch("healthcheck").fetch("test")
  end

  def test_start_app_preserves_database_setup_and_server_start
    assert_equal "#!/bin/bash -e\n\nrm -f tmp/pids/server.pid\n./bin/rails db:prepare\n./bin/rails server\n",
      file_contents("bin/start-app")
  end

  def test_boot_keeps_the_procfile_monitor
    assert_includes file_contents("bin/boot").lines.map(&:strip), 'ProcessMonitor.new("Procfile")'
  end

  def test_compose_keeps_migration_and_worker_commands
    services = yaml_contents("docker-compose.yml").fetch("services")

    assert_equal "bundle exec rails db:prepare", services.fetch("db-migrate").fetch("command")
    assert_equal "bundle exec rake solid_queue:start", services.fetch("solidq").fetch("command")
  end

  private
    def file_contents(path)
      File.read(File.join(ROOT, path))
    end

    def yaml_contents(path)
      YAML.load_file(File.join(ROOT, path))
    end
end
