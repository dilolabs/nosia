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

  def test_local_https_has_a_canonical_guide
    assert File.file?(File.join(ROOT, "docs/LOCAL_HTTPS.md")), "Missing canonical local HTTPS guide"
  end

  def test_local_https_entrypoints_link_to_the_canonical_guide
    { "README.md" => "docs/LOCAL_HTTPS.md", "CONTRIBUTING.md" => "docs/LOCAL_HTTPS.md",
      "docs/DEPLOYMENT.md" => "LOCAL_HTTPS.md" }.each do |path, target|
      assert_match(/\]\(#{Regexp.escape(target)}(?:#[^)]*)?\)/, file_contents(path), "#{path} must link to #{target}")
    end
  end

  def test_live_architecture_documents_do_not_claim_a_thruster_proxy
    %w[ docs/ARCHITECTURE.md docs/DIAGRAMS.md ].each do |path|
      refute_match(/Thruster/i, file_contents(path), "#{path} must describe Caddy forwarding directly to Puma")
    end
    assert_match(/Puma \(port 3000\)/, file_contents("docs/DIAGRAMS.md"))
  end

  def test_local_https_explains_the_proxy_and_certificate_boundary
    guide = local_https_guide

    %w[ Caddy Puma HTTPS HTTP web:3000 ACME ].each { |term| assert_includes guide, term }
    assert_match(/self-signed root/i, guide)
    assert_match(/not a self-signed (?:leaf|server)/i, guide)
    assert_match(/no Thruster/i, guide)
    assert_match(/tls internal/, guide)
  end

  def test_local_https_starts_and_inspects_the_selected_compose_project
    guide = local_https_guide

    [ "docker compose up -d", "docker context show", "docker compose logs reverse-proxy",
      "DOCKER_CONTEXT", "DOCKER_HOST", "COMPOSE_FILE", "COMPOSE_PROJECT_NAME" ].each do |command|
      assert_includes guide, command
    end
    assert_match(/unknown remote Docker/i, guide)
  end

  def test_local_https_documents_unix_prerequisites_and_native_stores
    guide = local_https_guide

    %w[ Linux Debian Ubuntu Fedora RHEL Arch macOS OpenSSL sudo update-ca-certificates update-ca-trust ].each do |term|
      assert_includes guide, term
    end
    [ "bin/trust-caddy", "-check_ss_sig", "-ext basicConstraints", "macOS 12", "plutil",
      "/Library/Keychains/System.keychain", "admin trust" ].each { |term| assert_includes guide, term }
    assert_match(/normal user/i, guide)
    assert_match(/literal `yes`/, guide)
  end

  def test_local_https_documents_native_windows_trust_and_elevation_limits
    guide = local_https_guide

    [ '.\\bin\\trust-caddy.ps1', "PowerShell 5.1", "PowerShell 7", 'Cert:\\LocalMachine\\Root',
      "UAC", "SHA1", "Thumbprint", "SHA256" ].each { |term| assert_includes guide, term }
    assert_match(/execution policy/i, guide)
    assert_match(/organization-approved/i, guide)
    refute_match(/Set-ExecutionPolicy/, guide)
  end

  def test_local_https_warns_about_machine_wide_authority_and_private_keys
    guide = local_https_guide

    assert_match(/beyond `?nosia\.localhost`?/i, guide)
    assert_match(/private key/i, guide)
    assert_match(/other hostnames/i, guide)
    assert_match(/protect.*Docker/i, guide)
    assert_match(/never.*(?:private keys|whole PKI)/i, guide)
    assert_includes guide, "SHA256"
  end

  def test_local_https_verification_does_not_bypass_certificate_checks
    guide = local_https_guide

    [ "curl --fail https://nosia.localhost/up", "curl.exe --fail https://nosia.localhost/up",
      "curl --cacert ./nosia-caddy-root.crt --fail https://nosia.localhost/up" ].each do |command|
      assert_includes guide, command
    end
    refute_match(/^\s*curl(?:\.exe)?[^\n]*(?:\s-k\b|--insecure\b)/, guide)
    assert_match(/disables.*verification/i, guide)
    assert_match(/application health/i, guide)
  end

  def test_local_https_covers_browser_runtime_and_wsl_trust_boundaries
    guide = local_https_guide

    %w[ Firefox Chrome Ruby Python Java curl WSL ].each { |term| assert_includes guide, term }
    assert_match(/restart.*browser/i, guide)
    assert_match(/CA bundles/i, guide)
    assert_match(/separate.*Windows.*store/i, guide)
    assert_match(/browser.*runtime.*remov/i, guide)
  end

  def test_local_https_manual_export_copies_only_the_public_root
    guide = local_https_guide

    assert_includes guide, "docker compose cp reverse-proxy:/data/caddy/pki/authorities/local/root.crt ./nosia-caddy-root.crt"
    %w[ -subject -issuer -dates -sha256 X509Certificate2 ].each { |term| assert_includes guide, term }
    assert_match(/compare.*fingerprint/i, guide)
    assert_match(/delete.*export/i, guide)
    assert_match(/never commit/i, guide)
  end

  def test_local_https_removal_targets_exact_native_store_certificates
    guide = local_https_guide

    [ "/usr/local/share/ca-certificates/nosia-caddy-$fp.crt",
      "/etc/pki/ca-trust/source/anchors/nosia-caddy-$fp.crt",
      "/etc/ca-certificates/trust-source/anchors/nosia-caddy-$fp.crt",
      "remove-trusted-cert -d", 'delete-certificate -Z "$identifier"', "-inform DER",
      "Read-Host", "Get-Item -LiteralPath", "Remove-Item -LiteralPath", "-Confirm" ].each do |command|
      assert_includes guide, command
    end
    assert_match(/64.*hex/i, guide)
    assert_match(/40.*hex/i, guide)
    assert_includes guide, "tr '[:upper:]' '[:lower:]'"
    assert_match(/old.*(?:stored|exported).*certificate/i, guide)
    assert_match(/never.*(?:whole CA store|all Caddy)/i, guide)
    refute_match(/(?:rm|Remove-Item)[^\n]*nosia-caddy-\*/, guide)
  end

  def test_local_https_explains_ca_persistence_and_replacement
    guide = local_https_guide

    assert_includes guide, "caddy-data"
    assert_match(/container recreat/i, guide)
    assert_match(/new CA/i, guide)
    assert_match(/does not revoke/i, guide)
    assert_match(/old root/i, guide)
    assert_match(/partial.*(?:change|state)/i, guide)
    assert_match(/existing helpers.*preserved/i, guide)
    assert_match(/download.*fail/i, guide)
  end

  private
    def local_https_guide
      assert File.file?(File.join(ROOT, "docs/LOCAL_HTTPS.md")), "Missing canonical local HTTPS guide"
      file_contents("docs/LOCAL_HTTPS.md")
    end

    def file_contents(path)
      File.read(File.join(ROOT, path))
    end

    def yaml_contents(path)
      YAML.load_file(File.join(ROOT, path))
    end
end
