require "minitest/autorun"
require "open3"
require "tmpdir"
require "fileutils"
require "pty"
require "timeout"
require "rbconfig"
require_relative "../support/caddy_certificate_fixtures"

class CaddyTrustPosixTest < Minitest::Test
  include CaddyCertificateFixtures

  HELPER = File.expand_path("../../bin/trust-caddy", __dir__)
  GUIDE = "https://github.com/dilolabs/nosia/blob/main/docs/LOCAL_HTTPS.md"
  ANCHORS = {
    debian: [ "/usr/local/share/ca-certificates", "update-ca-certificates", "/etc/ssl/certs/ca-certificates.crt" ],
    fedora: [ "/etc/pki/ca-trust/source/anchors", "update-ca-trust", "/etc/pki/tls/certs/ca-bundle.crt" ],
    arch: [ "/etc/ca-certificates/trust-source/anchors", "update-ca-trust", "/etc/ssl/certs/ca-certificates.crt" ]
  }.freeze

  def setup
    @sandbox = Dir.mktmpdir("caddy-trust-test-")
    @fixture = File.join(@sandbox, "fixture.crt")
    @bundle = File.join(@sandbox, "machine-bundle.crt")
    @log = File.join(@sandbox, "calls.log")
    @installed = File.join(@sandbox, "installed.crt")
    @admin_settings = File.join(@sandbox, "admin-settings.plist")
    File.write(@fixture, certificate_fixture)
    File.write(@bundle, "")
    File.write(@log, "")
    File.write(@admin_settings, '<plist version="1.0"><dict><key>trustVersion</key><integer>1</integer><key>trustList</key><dict/></dict></plist>')
    guard_bin = File.join(@sandbox, "guard-bin")
    FileUtils.mkdir_p(guard_bin)
    %w[ docker sudo install security update-ca-certificates update-ca-trust ].each do |command|
      path = File.join(guard_bin, command)
      File.write(path, "#!/bin/sh\nprintf 'FORBIDDEN native command\\n' >&2\nexit 98\n")
      FileUtils.chmod(0755, path)
    end
    File.write(File.join(@sandbox, "plutil.rb"), fake_plutil)
    File.write(File.join(guard_bin, "plutil"), "#!/bin/sh\nexec \"$TEST_RUBY\" \"$TEST_DIR/plutil.rb\" \"$@\"\n")
    FileUtils.chmod(0755, File.join(guard_bin, "plutil"))
    @environment = {
      "TEST_DIR" => @sandbox, "FIXTURE" => @fixture, "BUNDLE" => @bundle,
      "CALLS" => @log, "INSTALLED" => @installed, "TMPDIR" => @sandbox,
      "PLATFORM" => "Linux", "LAYOUT" => "debian", "DOCKER_CONTEXT" => "selected-remote",
      "COMPOSE_PROJECT_NAME" => "caller-project", "COMPOSE_FILE" => "caller-compose.yml",
      "PATH" => "#{guard_bin}:#{ENV.fetch('PATH')}", "TEST_RUBY" => RbConfig.ruby,
      "ADMIN_SETTINGS" => @admin_settings
    }
  end

  def teardown
    FileUtils.remove_entry(@sandbox)
  end

  def test_helper_exists_and_is_executable_posix_shell
    assert File.file?(HELPER), "Task 2 trust helper is missing"
    assert File.executable?(HELPER)
    assert_equal "#!/bin/sh\n", File.open(HELPER, &:readline)
  end

  def test_ephemeral_fixture_is_a_self_signed_ecdsa_v3_ca
    certificate = OpenSSL::X509::Certificate.new(certificate_fixture)

    assert_equal 2, certificate.version
    assert_equal "prime256v1", certificate.public_key.group.curve_name
    assert_equal "ecdsa-with-SHA256", certificate.signature_algorithm
    assert certificate.verify(certificate.public_key)
    assert certificate.extensions.find { |extension| extension.oid == "basicConstraints" }.critical?
    assert_includes certificate.extensions.find { |extension| extension.oid == "keyUsage" }.value, "Certificate Sign"
    refute_match(/PRIVATE KEY/, certificate_fixture)
  end

  def test_validates_and_canonicalizes_one_public_ca
    File.write(@fixture, " \n\t\n" + certificate_fixture + "\n \t\n")
    output, status = run_helper(body: validation_body)

    assert status.success?, output
    assert_equal der(certificate_fixture), der(File.read(File.join(@sandbox, "canonical.crt")))
    assert_includes output, fingerprint
    assert_includes output, sha1
  end

  [ :leaf, :expired, :future, :bad_self_signature, :other_issuer, :no_basic_constraints,
    :multiple, :private_key, :malformed, :trailing_text, :concatenated_der, :trailing_der_junk ].each do |kind|
    define_method("test_rejects_#{kind}_before_confirmation_or_admin") do
      File.write(@fixture, certificate_fixture(kind))
      output, status = run_helper

      refute status.success?, output
      assert_match(/certificate|CA|signature|valid|PEM/i, output)
      refute_match(/CONFIRM|ADMIN/, calls)
      assert_temp_clean
    end
  end

  def test_rejects_symlink_and_missing_or_directory_root
    [ "symlink", "missing", "directory" ].each do |mode|
      output, status = run_helper(environment: { "COPY_MODE" => mode })

      refute status.success?, output
      refute_match(/CONFIRM|ADMIN/, calls)
      assert_temp_clean
      assert File.file?(@fixture), "cleanup must not follow the copied symlink"
    end
  end

  def test_cleanup_removes_nested_copy_directory_without_following_external_symlinks
    outside = File.join(@sandbox, "outside")
    FileUtils.mkdir_p(outside)
    sentinel = File.join(outside, "keep.txt")
    File.write(sentinel, "caller data")
    output, status = run_helper(environment: { "COPY_MODE" => "nested_directory" })

    refute status.success?, output
    assert_match(/regular.*file/, output)
    refute_match(/CONFIRM|ADMIN/, calls)
    assert_equal "caller data", File.read(sentinel)
    assert_equal certificate_fixture, File.read(@fixture)
    assert_temp_clean
  end

  ANCHORS.each do |layout, (anchor, updater, bundle)|
    define_method("test_#{layout}_machine_store_and_canonical_install") do
      output, status = run_helper(environment: { "LAYOUT" => layout.to_s })

      assert status.success?, output
      assert_includes calls, "ADMIN install -m 0644"
      assert_includes calls, "#{anchor}/nosia-caddy-#{fingerprint}.crt"
      assert_includes calls, "ADMIN #{updater}"
      assert_includes calls, "MACHINE_BUNDLE #{bundle}"
      assert_operator calls.index("CONFIRM"), :<, calls.index("ADMIN")
      assert_equal der(certificate_fixture), der(File.read(@installed))
      assert_includes output, fingerprint
      assert_includes output, sha1
      assert_includes output, "beyond nosia.localhost"
      assert_includes output, "Docker"
      assert_includes output, "curl --fail https://nosia.localhost/up"
      refute_match(/all clients|application is healthy/i, output)
      assert_temp_clean
    end
  end

  def test_selected_context_and_project_are_preserved_and_only_public_root_is_copied_once
    output, status = run_helper

    assert status.success?, output
    assert_includes output, "selected-remote"
    assert_includes output, "reverse-proxy"
    assert_includes calls, "DOCKER selected-remote caller-project caller-compose.yml compose ps --status running -q reverse-proxy"
    copies = calls.lines.grep(/ compose cp /)
    assert_equal 1, copies.size
    assert_match(%r{compose cp reverse-proxy:/data/caddy/pki/authorities/local/root\.crt #{@sandbox}/nosia-caddy\.[^/]+/root\.crt\n}, copies.first)
    refute_match(/root\.key|intermediate\.key|\bcompose (?:up|start)\b|\bvolume\b|\bcurl\b/, calls)
    assert_match(/TEMP_MODE 700/, calls)
  end

  def test_permission_probe_does_not_require_gnu_stat
    output, status = run_helper(body: <<~'SH')
      stat() { printf 'UNEXPECTED_STAT\n' >> "$CALLS"; return 1; }
      main
    SH

    assert status.success?, output
    assert_includes calls, "TEMP_MODE 700"
    refute_includes calls, "UNEXPECTED_STAT"
    assert_temp_clean
  end

  def test_import_uses_the_confirmed_snapshot_even_if_source_changes
    replacement = File.join(@sandbox, "replacement.crt")
    File.write(replacement, certificate_fixture(:future))
    output, status = run_helper(environment: { "REPLACEMENT" => replacement })

    assert status.success?, output
    assert_equal der(certificate_fixture), der(File.read(@installed))
    assert_equal 1, calls.lines.grep(/ compose cp /).size
  end

  def test_linux_already_trusted_uses_only_the_selected_machine_bundle
    File.write(@bundle, certificate_fixture)
    output, status = run_helper(environment: { "SSL_CERT_FILE" => @fixture })

    assert status.success?, output
    assert_match(/already trusted/i, output)
    assert_includes output, fingerprint
    assert_includes output, sha1
    assert_includes calls, "MACHINE_BUNDLE /etc/ssl/certs/ca-certificates.crt"
    refute_match(/CONFIRM|ADMIN/, calls)
    assert_temp_clean
  end

  def test_caller_ssl_cert_file_is_not_used_as_machine_trust
    output, status = run_helper(environment: { "SSL_CERT_FILE" => @fixture })

    assert status.success?, output
    assert_includes calls, "CONFIRM"
    assert_includes calls, "ADMIN"
  end

  def test_linux_requires_exact_bundle_presence_and_successful_native_verification
    other = OpenSSL::X509::Certificate.new(certificate_fixture(:reissued_root))
    assert_equal OpenSSL::X509::Certificate.new(certificate_fixture).subject, other.subject
    assert_equal OpenSSL::X509::Certificate.new(certificate_fixture).public_key.to_der, other.public_key.to_der
    refute_equal der(certificate_fixture), other.to_der
    File.write(@bundle, other.to_pem)
    output, status = run_helper

    assert status.success?, output
    assert_includes calls, "MACHINE_BUNDLE /etc/ssl/certs/ca-certificates.crt"
    assert_includes calls, "ADMIN"

    File.write(@log, "")
    File.write(@bundle, certificate_fixture)
    output, status = run_helper(environment: { "NATIVE_VERIFY_FAIL" => "1" })
    assert status.success?, output
    assert_includes calls, "ADMIN"
  end

  def test_macos_routes_only_to_system_keychain
    output, status = run_helper(environment: { "PLATFORM" => "Darwin" })

    assert status.success?, output
    assert_includes calls, "SECURITY find-certificate -a -p /Library/Keychains/System.keychain"
    assert_includes calls, "ADMIN security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain"
    refute_match(/ADMIN install|update-ca-/, calls)
    assert_equal der(certificate_fixture), der(File.read(@installed))
    assert_includes output, sha1
    assert_temp_clean
  end

  def test_macos_already_trusted_requires_exact_presence_and_trust_query
    File.write(@bundle, certificate_fixture)
    write_admin_settings
    output, status = run_helper(environment: { "PLATFORM" => "Darwin" })

    assert status.success?, output
    assert_match(/already trusted/i, output)
    assert_match(%r{SECURITY verify-cert -c .*/public\.crt -p basic -l -L -k /Library/Keychains/System\.keychain}, calls)
    assert_match(%r{SECURITY trust-settings-export -d #{@sandbox}/nosia-caddy\.[^/]+/admin-trust\.plist}, calls)
    assert_includes calls, "PLUTIL -extract trustList.#{sha1.upcase} raw -expect dictionary"
    assert_includes output, fingerprint
    refute_match(/CONFIRM|ADMIN/, calls)
    assert_temp_clean
  end

  def test_macos_presence_without_trust_or_subject_only_match_does_not_skip_import
    [ [ certificate_fixture, "1" ], [ certificate_fixture(:reissued_root), "" ], [ "", "" ] ].each do |pem, failure|
      File.write(@bundle, pem)
      write_admin_settings
      File.write(@log, "")
      output, status = run_helper(environment: { "PLATFORM" => "Darwin", "NATIVE_VERIFY_FAIL" => failure })

      assert status.success?, output
      assert_includes calls, "ADMIN security add-trusted-cert"
    end
  end

  def test_macos_user_only_trust_cannot_grant_machine_deduplication
    File.write(@bundle, certificate_fixture)
    output, status = run_helper(environment: { "PLATFORM" => "Darwin" })

    assert status.success?, output
    refute_match(/already trusted/i, output)
    assert_includes calls, "CONFIRM"
    assert_includes calls, "ADMIN security add-trusted-cert"
    assert_temp_clean
  end

  def test_macos_absent_admin_domain_allows_first_machine_import_of_present_root
    File.write(@bundle, certificate_fixture)
    output, status = run_helper(environment: { "PLATFORM" => "Darwin", "ADMIN_EXPORT_MODE" => "absent" })

    assert status.success?, output
    refute_match(/already trusted/i, output)
    assert_includes calls, "SECURITY error -25263"
    assert_operator calls.index("CONFIRM"), :<, calls.index("ADMIN security add-trusted-cert")
    assert_equal der(certificate_fixture), der(File.read(@installed))
    assert_equal 1, calls.lines.grep(/SECURITY trust-settings-export /).size
    refute_includes calls, "PLUTIL"
    assert_temp_clean
  end

  def test_macos_absent_admin_domain_uses_native_localized_error_description
    File.write(@bundle, certificate_fixture)
    output, status = run_helper(environment: {
      "PLATFORM" => "Darwin", "ADMIN_EXPORT_MODE" => "absent",
      "NO_SETTINGS_MESSAGE" => "Aucun réglage de confiance trouvé."
    })

    assert status.success?, output
    assert_includes calls, "SECURITY error -25263"
    assert_includes calls, "ADMIN security add-trusted-cert"
    assert_temp_clean
  end

  def test_macos_absent_admin_domain_still_requires_confirmation
    File.write(@bundle, certificate_fixture)
    output, status = run_helper(environment: { "PLATFORM" => "Darwin", "ADMIN_EXPORT_MODE" => "absent", "CANCEL" => "1" })

    refute status.success?, output
    assert_match(/cancel/i, output)
    assert_includes calls, "CONFIRM"
    refute_includes calls, "ADMIN security add-trusted-cert"
    assert_temp_clean
  end

  [ "permission", "lookalike", "partial_absent" ].each do |mode|
    define_method("test_macos_#{mode}_export_error_cannot_be_treated_as_absent_admin_settings") do
      File.write(@bundle, certificate_fixture)
      output, status = run_helper(environment: { "PLATFORM" => "Darwin", "ADMIN_EXPORT_MODE" => mode })

      refute status.success?, output
      assert_match(/export.*admin|admin.*export/i, output)
      refute_match(/CONFIRM|ADMIN/, calls)
      assert_temp_clean
    end
  end

  def test_macos_absence_requires_a_confirmed_native_error_code_description
    File.write(@bundle, certificate_fixture)
    output, status = run_helper(environment: {
      "PLATFORM" => "Darwin", "ADMIN_EXPORT_MODE" => "absent", "ERROR_LOOKUP_FAIL" => "1"
    })

    refute status.success?, output
    refute_match(/CONFIRM|ADMIN/, calls)
    assert_temp_clean
  end

  {
    deny: "<array><dict><key>kSecTrustSettingsResult</key><integer>3</integer></dict></array>",
    policy_restricted: "<array><dict><key>kSecTrustSettingsPolicy</key><data>KoZIhvdjZAED</data><key>kSecTrustSettingsResult</key><integer>1</integer></dict></array>",
    application_restricted: "<array><dict><key>kSecTrustSettingsApplication</key><data>YW4gYXBwbGljYXRpb24=</data></dict></array>",
    hostname_restricted: "<array><dict><key>kSecTrustSettingsPolicyString</key><string>nosia.localhost</string></dict></array>",
    usage_restricted: "<array><dict><key>kSecTrustSettingsKeyUsage</key><integer>1</integer></dict></array>",
    allowed_error: "<array><dict><key>kSecTrustSettingsAllowedError</key><integer>-2147409654</integer></dict></array>",
    mixed_deny: "<array><dict/><dict><key>kSecTrustSettingsResult</key><integer>3</integer></dict></array>",
    malformed_array: "<string>unrestricted</string>",
    malformed_result: "<array><dict><key>kSecTrustSettingsResult</key><string>1</string></dict></array>",
    trust_as_root: "<array><dict><key>kSecTrustSettingsResult</key><integer>2</integer></dict></array>"
  }.each do |kind, settings|
    define_method("test_macos_#{kind}_admin_settings_do_not_grant_deduplication") do
      File.write(@bundle, certificate_fixture)
      write_admin_settings(trust_settings: settings)
      output, status = run_helper(environment: { "PLATFORM" => "Darwin" })

      assert status.success?, output
      refute_match(/already trusted/i, output)
      assert_includes calls, "CONFIRM"
      assert_includes calls, "ADMIN security add-trusted-cert"
      assert_temp_clean
    end
  end

  def test_macos_explicit_unrestricted_admin_trust_deduplicates
    [ "<array/>", "<array><dict/></array>", "<array><dict><key>kSecTrustSettingsResult</key><integer>1</integer></dict></array>" ].each do |settings|
      File.write(@log, "")
      File.write(@bundle, certificate_fixture)
      write_admin_settings(trust_settings: settings)
      output, status = run_helper(environment: { "PLATFORM" => "Darwin" })

      assert status.success?, output
      assert_match(/already trusted/i, output)
      refute_match(/CONFIRM|ADMIN/, calls)
      assert_temp_clean
    end
  end

  def test_macos_normal_import_admin_record_deduplicates_on_the_next_run
    output, status = run_helper(environment: { "PLATFORM" => "Darwin" })
    assert status.success?, output
    assert_includes calls, "ADMIN security add-trusted-cert"

    # Apple's default trustRoot export omits trustSettings for an unrestricted root.
    File.write(@bundle, File.read(@installed))
    write_admin_settings
    File.write(@log, "")
    output, status = run_helper(environment: { "PLATFORM" => "Darwin" })

    assert status.success?, output
    assert_match(/already trusted/i, output)
    refute_match(/CONFIRM|ADMIN/, calls)
    assert_temp_clean
  end

  def test_macos_admin_settings_for_a_different_fingerprint_do_not_grant_deduplication
    File.write(@bundle, certificate_fixture)
    write_admin_settings(key: OpenSSL::Digest::SHA1.hexdigest(der(certificate_fixture(:reissued_root))).upcase)
    output, status = run_helper(environment: { "PLATFORM" => "Darwin" })

    assert status.success?, output
    assert_includes calls, "ADMIN security add-trusted-cert"
    assert_temp_clean
  end

  def test_macos_unknown_or_malformed_admin_export_does_not_grant_deduplication
    [ "<not-a-plist>", '<plist version="1.0"><dict><key>trustVersion</key><integer>2</integer></dict></plist>' ].each do |xml|
      File.write(@log, "")
      File.write(@bundle, certificate_fixture)
      File.write(@admin_settings, xml)
      output, status = run_helper(environment: { "PLATFORM" => "Darwin" })

      assert status.success?, output
      assert_includes calls, "ADMIN security add-trusted-cert"
      assert_temp_clean
    end
  end

  def test_macos_failed_admin_export_stops_without_confirmation_or_native_writes
    File.write(@bundle, certificate_fixture)
    write_admin_settings
    output, status = run_helper(environment: { "PLATFORM" => "Darwin", "ADMIN_EXPORT_FAIL" => "1" })

    refute status.success?, output
    assert_match(/admin.*export|export.*admin/i, output)
    refute_match(/CONFIRM|ADMIN/, calls)
    assert_temp_clean
  end

  [ "docker", "openssl", "sudo", "awk", "mktemp", "cmp", "install", "update-ca-certificates" ].each do |command|
    define_method("test_missing_#{command.tr('-', '_')}_fails_before_tempfiles") do
      output, status = run_helper(environment: { "MISSING_COMMAND" => command })

      refute status.success?, output
      assert_includes output, command
      assert_includes output, GUIDE
      refute_match(/TEMP|CONFIRM|ADMIN| compose cp /, calls)
      assert_temp_clean
    end
  end

  def test_missing_macos_security_fails_before_tempfiles
    output, status = run_helper(environment: { "PLATFORM" => "Darwin", "MISSING_COMMAND" => "security" })

    refute status.success?, output
    assert_includes output, "security"
    refute_match(/TEMP|ADMIN/, calls)
  end

  def test_missing_macos_plutil_fails_before_tempfiles
    output, status = run_helper(environment: { "PLATFORM" => "Darwin", "MISSING_COMMAND" => "plutil" })

    refute status.success?, output
    assert_includes output, "plutil"
    refute_match(/TEMP|ADMIN/, calls)
    assert_temp_clean
  end

  def test_unsupported_macos_keychain_layout_fails_before_writes
    output, status = run_helper(environment: { "PLATFORM" => "Darwin", "LAYOUT" => "unknown" })

    refute status.success?, output
    assert_match(/keychain|layout/i, output)
    assert_includes output, GUIDE
    refute_match(/TEMP|CONFIRM|ADMIN/, calls)
    assert_temp_clean
  end

  def test_missing_fedora_and_arch_updater_fails_before_tempfiles
    %w[ fedora arch ].each do |layout|
      output, status = run_helper(environment: { "LAYOUT" => layout, "MISSING_COMMAND" => "update-ca-trust" })

      refute status.success?, output
      assert_includes output, "update-ca-trust"
      refute_match(/TEMP|CONFIRM|ADMIN/, calls)
      assert_temp_clean
    end
  end

  def test_real_command_preflight_rejects_a_missing_tool
    output, status = run_helper(body: "require_command nosia_nonexistent_command", real_boundaries: true)

    refute status.success?, output
    assert_includes output, "Missing required command: nosia_nonexistent_command"
    assert_includes output, GUIDE
    assert_temp_clean
  end

  def test_real_admin_boundary_uses_only_sudo_with_argument_separator
    output, status = run_helper(real_boundaries: true, body: <<~'SH')
      sudo() { printf '%s\n' "$*"; }
      admin example-command --option 'two words'
    SH

    assert status.success?, output
    assert_equal "-- example-command --option two words\n", output
    assert_empty calls
  end

  def test_missing_check_ss_sig_capability_fails_before_writes
    output, status = run_helper(environment: { "NO_CHECK_SS_SIG" => "1" })

    refute status.success?, output
    assert_includes output, "check_ss_sig"
    refute_match(/TEMP|CONFIRM|ADMIN/, calls)
  end

  def test_unsupported_platform_and_linux_layout_offer_manual_guide
    [ { "PLATFORM" => "FreeBSD" }, { "LAYOUT" => "unknown" } ].each do |environment|
      output, status = run_helper(environment: environment)

      refute status.success?, output
      assert_includes output, GUIDE
      refute_match(/TEMP|CONFIRM|ADMIN/, calls)
    end
  end

  [ "version", "context", "ps", "stopped", "cp" ].each do |failure|
    define_method("test_docker_#{failure}_failure_is_actionable_and_cleans_up") do
      output, status = run_helper(environment: { "DOCKER_FAILURE" => failure })

      refute status.success?, output
      assert_match(/Docker|Compose|reverse-proxy/, output)
      assert_match(/logs|context|Compose/i, output)
      refute_match(/CONFIRM|ADMIN/, calls)
      assert_temp_clean
    end
  end

  def test_no_unattended_flags_are_accepted
    [ "--yes", "-y", "anything" ].each do |argument|
      output, status = run_helper(body: "main #{argument}")

      refute status.success?, output
      assert_match(/usage|arguments|flags/i, output)
      refute_match(/TEMP|ADMIN/, calls)
    end
  end

  def test_cancellation_never_requests_elevation
    output, status = run_helper(environment: { "CANCEL" => "1" })

    refute status.success?, output
    assert_match(/cancel/i, output)
    assert_includes calls, "CONFIRM"
    refute_match(/ADMIN/, calls)
    assert_temp_clean
  end

  def test_failed_linux_install_discloses_possible_partial_anchor
    output, status = run_helper(environment: { "ADMIN_FAILURE" => "install" })

    refute status.success?, output
    assert_match(/partial/i, output)
    assert_includes output, "/usr/local/share/ca-certificates/nosia-caddy-#{fingerprint}.crt"
    refute_match(/ADMIN update-ca-certificates/, calls)
    assert_temp_clean
  end

  def test_failed_updater_discloses_written_anchor_and_exact_recovery
    output, status = run_helper(environment: { "ADMIN_FAILURE" => "update-ca-certificates" })

    refute status.success?, output
    assert_match(/anchor was written/i, output)
    assert_includes output, "sudo -- rm /usr/local/share/ca-certificates/nosia-caddy-#{fingerprint}.crt"
    assert_includes output, "sudo -- update-ca-certificates"
    refute_match(/System trust import succeeded/, output)
    assert_temp_clean
  end

  def test_failed_macos_import_discloses_possible_native_change_and_removal_identifier
    output, status = run_helper(environment: { "PLATFORM" => "Darwin", "ADMIN_FAILURE" => "security" })

    refute status.success?, output
    assert_match(/partial|native change/i, output)
    assert_includes output, sha1
    assert_includes output, "/Library/Keychains/System.keychain"
    refute_match(/System trust import succeeded/, output)
    assert_temp_clean
  end

  def test_redirected_yes_blank_and_eof_are_refused
    [ "yes\n", "\n", "" ].each do |input|
      output, status = run_helper(real_confirm: true, input: input)

      refute status.success?, output
      assert_match(/TTY|terminal|interactive/i, output)
      refute_match(/ADMIN/, calls)
      assert_temp_clean
    end
  end

  def test_real_terminal_yes_imports_but_no_blank_and_other_answers_refuse
    [ "yes", "no", "", "YES", " yes" ].each do |answer|
      File.write(@log, "")
      output, status = run_interactive(answer)

      assert_equal answer == "yes", status.success?, output
      if answer == "yes"
        assert_includes calls, "ADMIN"
        assert_equal der(certificate_fixture), der(File.read(@installed))
      else
        refute_match(/ADMIN/, calls)
      end
      assert_temp_clean
    end
  end

  def test_interrupt_during_confirmation_cleans_up_without_admin
    %w[ HUP INT TERM ].each do |signal|
      output, status = run_helper(environment: { "INTERRUPT" => signal })

      refute status.success?, output
      refute_match(/ADMIN/, calls)
      assert_temp_clean
    end
  end

  def test_cleanup_preserves_unrelated_files_in_caller_temp_directory
    unrelated = File.join(@sandbox, "unrelated.crt")
    File.write(unrelated, "caller data")
    output, status = run_helper

    assert status.success?, output
    assert_equal "caller data", File.read(unrelated)
    assert_temp_clean
  end

  private
    def der(pem)
      OpenSSL::X509::Certificate.new(pem).to_der
    end

    def fingerprint
      OpenSSL::Digest::SHA256.hexdigest(der(certificate_fixture))
    end

    def sha1
      OpenSSL::Digest::SHA1.hexdigest(der(certificate_fixture))
    end

    def write_admin_settings(trust_settings: nil, key: sha1.upcase)
      certificate = OpenSSL::X509::Certificate.new(certificate_fixture)
      issuer = [ certificate.issuer.to_der ].pack("m0")
      serial = [ certificate.serial.to_s(2) ].pack("m0")
      settings = trust_settings ? "<key>trustSettings</key>#{trust_settings}" : ""
      File.write(@admin_settings, <<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>trustVersion</key><integer>1</integer>
          <key>trustList</key><dict><key>#{key}</key><dict>
            <key>issuerName</key><data>#{issuer}</data>
            <key>serialNumber</key><data>#{serial}</data>
            <key>modDate</key><date>2026-10-22T00:00:00Z</date>
            #{settings}
          </dict></dict>
        </dict></plist>
      XML
    end

    def fake_plutil
      <<~'RUBY'
        require "rexml/document"
        require "base64"
        Node = Struct.new(:type, :value)

        def parse(element)
          case element.name
          when "dict"
            pairs = element.elements.to_a
            raise "invalid dictionary" unless pairs.size.even?
            values = pairs.each_slice(2).to_h do |key, value|
              raise "invalid key" unless key.name == "key"
              [ key.text.to_s, parse(value) ]
            end
            Node.new("dictionary", values)
          when "array"
            Node.new("array", element.elements.map { |child| parse(child) })
          when "integer"
            Node.new("integer", Integer(element.text, 10))
          when "data"
            Node.new("data", Base64.strict_encode64(Base64.strict_decode64(element.text.to_s.gsub(/\s/, ""))))
          when "date", "string"
            Node.new(element.name, element.text.to_s)
          else
            raise "unsupported plist type"
          end
        end

        begin
          File.open(ENV.fetch("CALLS"), "a") { |file| file.puts("PLUTIL #{ARGV.join(' ')}") }
          operation, path, format, expect, type, output, destination, filename = ARGV
          raise "unexpected command" unless [ operation, format, expect, output, destination ] == [ "-extract", "raw", "-expect", "-o", "-" ]
          document = REXML::Document.new(File.read(filename))
          raise "invalid plist" unless document.root.name == "plist" && document.root.elements.size == 1
          node = parse(document.root.elements[1])
          path.split(".").each do |key|
            node = case node.type
            when "dictionary" then node.value.fetch(key)
            when "array" then node.value.fetch(Integer(key, 10))
            else raise "missing key"
            end
          end
          raise "wrong type" unless node.type == type
          puts case type
          when "dictionary" then node.value.keys.sort.join("\n")
          when "array" then node.value.size
          else node.value
          end
        rescue StandardError
          exit 1
        end
      RUBY
    end

    def calls
      File.read(@log)
    end

    def assert_temp_clean
      assert_empty Dir.glob(File.join(@sandbox, "nosia-caddy.*")), "helper left temporary certificate material"
    end

    def validation_body
      <<~SH
        temp_dir=$(mktemp -d "$TMPDIR/nosia-caddy.XXXXXXXX")
        trap cleanup 0
        validate_root "$FIXTURE"
        printf '%s\n' "$public_pem" > "$TEST_DIR/canonical.crt"
        printf '%s\n%s\n' "$sha256" "$sha1"
      SH
    end

    def helper_script(real_confirm: false, real_boundaries: false, body: "main")
      assert File.file?(HELPER), "Task 2 trust helper is missing"
      definitions = File.read(HELPER).sub(/^main "\$@"\s*\z/, "")
      assert_match(/^main "\$@"\s*\z/, File.read(HELPER), "helper must end with its main entry point")
      definitions + "\n" + (real_boundaries ? "" : fake_boundaries) + (real_confirm ? "" : fake_confirmation) + "\n" + body + "\n"
    end

    def run_helper(environment: {}, real_confirm: false, real_boundaries: false, input: "", body: "main")
      script = helper_script(real_confirm: real_confirm, real_boundaries: real_boundaries, body: body)
      output, error, status = Open3.capture3(@environment.merge(environment), "/bin/sh", "-c", script, stdin_data: input)
      [ output + error, status ]
    end

    def run_interactive(answer)
      script = File.join(@sandbox, "interactive.sh")
      File.write(script, helper_script(real_confirm: true))
      output = +""
      status = nil
      pid = nil
      Timeout.timeout(12) do
        PTY.spawn(@environment, "/bin/sh", script) do |reader, writer, child|
          pid = child
          sent = false
          begin
            loop do
              output << reader.readpartial(4096)
              if !sent && output.include?("Type literal yes")
                writer.write("#{answer}\n")
                writer.flush
                sent = true
              end
            end
          rescue Errno::EIO, EOFError
            # PTY reports EIO when the child closes its terminal.
          end
          _, status = Process.wait2(child)
          pid = nil
        end
      end
      [ output, status ]
    ensure
      if pid
        Process.kill("KILL", pid) rescue Errno::ESRCH
        Process.wait(pid) rescue Errno::ECHILD
      end
    end

    def fake_confirmation
      <<~'SH'
        confirm() {
          printf 'CONFIRM\n' >> "$CALLS"
          if [ -n "${REPLACEMENT:-}" ]; then cp "$REPLACEMENT" "$FIXTURE"; fi
          if [ -n "${INTERRUPT:-}" ]; then kill -"$INTERRUPT" "$$"; fi
          [ -z "${CANCEL:-}" ]
        }
      SH
    end

    def fake_boundaries
      <<~'SH'
        # Never use real Docker, sudo, install, updater, or security commands.
        platform_name() { printf '%s\n' "$PLATFORM"; }
        directory_exists() {
          case "$LAYOUT:$1" in
            debian:/usr/local/share/ca-certificates|fedora:/etc/pki/ca-trust/source/anchors|arch:/etc/ca-certificates/trust-source/anchors|debian:/Library/Keychains) return 0 ;;
            *) return 1 ;;
          esac
        }
        require_command() {
          if [ "$1" = "${MISSING_COMMAND:-}" ]; then fail "Missing required command: $1"; fi
          case "$1" in docker|sudo|security|install|update-ca-certificates|update-ca-trust) return 0 ;; esac
          command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
        }
        sudo() { printf 'FORBIDDEN sudo\n' >&2; exit 98; }
        install() { printf 'FORBIDDEN install\n' >&2; exit 98; }
        docker() {
          printf 'DOCKER %s %s %s %s\n' "$DOCKER_CONTEXT" "$COMPOSE_PROJECT_NAME" "$COMPOSE_FILE" "$*" >> "$CALLS"
          case "$*" in
            'compose version') [ "${DOCKER_FAILURE:-}" != version ] ;;
            'context show')
              [ "${DOCKER_FAILURE:-}" != context ] || return 1
              printf '%s\n' "$DOCKER_CONTEXT" ;;
            'compose ps --status running -q reverse-proxy')
              [ "${DOCKER_FAILURE:-}" != ps ] || return 1
              if [ "${DOCKER_FAILURE:-}" != stopped ]; then printf 'container-id\n'; fi ;;
            'compose cp reverse-proxy:/data/caddy/pki/authorities/local/root.crt '*)
              [ "${DOCKER_FAILURE:-}" != cp ] || return 1
              [ "$#" = 4 ] || return 97
              printf 'TEMP_MODE %s\n' "$("$TEST_RUBY" -e 'printf "%o", File.stat(ARGV.fetch(0)).mode & 0777' "${4%/*}")" >> "$CALLS"
              case "${COPY_MODE:-}" in
                symlink) ln -s "$FIXTURE" "$4" ;;
                missing) : ;;
                directory) mkdir "$4" ;;
                nested_directory)
                  mkdir -p "$4/nested/inner"
                  printf 'unexpected copy\n' > "$4/nested/inner/file"
                  ln -s "$TEST_DIR/outside" "$4/external-directory"
                  ln -s "$FIXTURE" "$4/nested/external-certificate" ;;
                *) cp "$FIXTURE" "$4" ;;
              esac ;;
            *) printf 'Unexpected Docker invocation: %s\n' "$*" >&2; return 97 ;;
          esac
        }
        openssl() {
          if [ "$*" = 'verify -help' ] && [ -n "${NO_CHECK_SS_SIG:-}" ]; then printf 'unsupported\n'; return 0; fi
          case "$*" in
            *-CAfile\ /etc/*)
              previous=
              for argument do
                if [ "$previous" = -CAfile ]; then printf 'MACHINE_BUNDLE %s\n' "$argument" >> "$CALLS"; fi
                previous=$argument
              done
              [ -z "${NATIVE_VERIFY_FAIL:-}" ] || return 1
              command openssl verify -CAfile "$BUNDLE" "$temp_dir/public.crt"
              return ;;
          esac
          command openssl "$@"
        }
        # Redirect reads of machine bundles, without changing the helper's selected path.
        cat() {
          case "$1" in /etc/ssl/certs/ca-certificates.crt|/etc/pki/tls/certs/ca-bundle.crt) command cat "$BUNDLE" ;; *) command cat "$@" ;; esac
        }
        security() {
          printf 'SECURITY %s\n' "$*" >> "$CALLS"
          case "$1" in
            find-certificate) command cat "$BUNDLE" ;;
            verify-cert) [ -z "${NATIVE_VERIFY_FAIL:-}" ] ;;
            trust-settings-export)
              [ "$#" = 3 ] && [ "$2" = -d ] || return 97
              if [ -n "${ADMIN_EXPORT_FAIL:-}" ]; then printf 'partial export\n' > "$3"; return 1; fi
              case "${ADMIN_EXPORT_MODE:-}" in
                absent|partial_absent)
                  if [ "$ADMIN_EXPORT_MODE" = partial_absent ]; then printf 'partial export\n' > "$3"; fi
                  printf 'SecTrustSettingsCreateExternalRepresentation: %s\n' "${NO_SETTINGS_MESSAGE:-No Trust Settings were found.}" >&2
                  return 1 ;;
                permission)
                  printf 'SecTrustSettingsCreateExternalRepresentation: User interaction is not allowed.\n' >&2
                  return 1 ;;
                lookalike)
                  printf 'SecTrustSettingsCreateExternalRepresentation: No Trust Settings were found. Permission denied.\n' >&2
                  return 1 ;;
              esac
              cp "$ADMIN_SETTINGS" "$3" ;;
            error)
              [ "$#" = 2 ] && [ "$2" = -25263 ] || return 97
              [ -z "${ERROR_LOOKUP_FAIL:-}" ] || return 2
              printf 'Error: 0xFFFF9D51 -25263 %s\n' "${NO_SETTINGS_MESSAGE:-No Trust Settings were found.}"
              return 1 ;;
            *) printf 'FORBIDDEN security write\n' >&2; exit 98 ;;
          esac
        }
        admin() {
          printf 'ADMIN %s\n' "$*" >> "$CALLS"
          [ "$1" != "${ADMIN_FAILURE:-}" ] || return 1
          case "$1" in
            install) cp "$4" "$INSTALLED" ;;
            security)
              for argument do last=$argument; done
              cp "$last" "$INSTALLED" ;;
            update-ca-certificates|update-ca-trust) : ;;
            *) printf 'Unexpected admin invocation\n' >&2; exit 98 ;;
          esac
        }
      SH
    end
end
