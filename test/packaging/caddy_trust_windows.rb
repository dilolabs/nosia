require "minitest/autorun"
require "open3"
require "tmpdir"
require "fileutils"
require "base64"
require_relative "../support/caddy_certificate_fixtures"

class CaddyTrustWindowsPackagingTest < Minitest::Test
  HELPER = File.expand_path("../../bin/trust-caddy.ps1", __dir__)

  def test_standalone_helper_is_packaged
    assert File.file?(HELPER), "Task 3 Windows trust helper is missing"
  end

  def test_helper_is_dot_sourceable_and_uses_strict_windows_compatible_boundaries
    source = helper_source

    assert_includes source, "Set-StrictMode -Version Latest"
    assert_includes source, "$ErrorActionPreference = 'Stop'"
    assert_match(/\$MyInvocation\.InvocationName -ne '\.'/i, source)
    %w[ Get-CaddyFingerprint Test-CaddyRootSignature Get-CaddyCertificate Invoke-CaddyDocker
        Get-CaddyRootCertificates Test-CaddyTrusted Test-CaddyInteractive Confirm-CaddyTrust
        New-CaddyImportScript Invoke-CaddyElevatedImport Invoke-CaddyTrust ].each do |name|
      assert_match(/function #{Regexp.escape(name)}\b/, source)
    end
    refute_match(/CreateFromPem|HashData|Set-ExecutionPolicy|Invoke-WebRequest|DownloadString/, source)
  end

  def test_encoded_child_contract_is_packaged_without_elevating_docker_or_the_helper
    source = helper_source

    assert_includes source, "[Text.Encoding]::Unicode.GetBytes"
    assert_match(/Start-Process[^\n]*-Verb RunAs[^\n]*-Wait[^\n]*-PassThru/, source)
    assert_includes source, 'System32\WindowsPowerShell\v1.0\powershell.exe'
    assert_includes source, "'-NoProfile', '-NonInteractive', '-EncodedCommand'"
    assert_includes source, "[IO.FileShare]::Read"
    assert_includes source, "[IO.FileAccess]::Read"
    assert_match(/Import-Certificate[^\n]*-CertStoreLocation 'Cert:\\LocalMachine\\Root'/, source)
    assert_includes source, "CryptVerifyCertificateSignatureEx"
    assert_includes source, "curl.exe --fail https://nosia.localhost/up"
    refute_match(/-ExecutionPolicy|Cert:\\CurrentUser\\Root/, source)
  end

  private
    def helper_source
      assert File.file?(HELPER), "Task 3 Windows trust helper is missing"
      File.read(HELPER)
    end
end

# These subprocess tests must run on Windows under BOTH Windows PowerShell 5.1
# and PowerShell 7. Linux packaging checks do not verify crypt32 or native APIs.
class CaddyTrustWindowsNativeTest < Minitest::Test
  include CaddyCertificateFixtures

  HELPER = CaddyTrustWindowsPackagingTest::HELPER
  INSTALLER = File.expand_path("../../install.ps1", __dir__)
  GUIDE = "https://github.com/dilolabs/nosia/blob/main/docs/LOCAL_HTTPS.md"

  def setup
    skip "Native Windows required (crypt32/store/PowerShell); run Windows CI with 5.1 and 7" unless Gem.win_platform?
    @sandbox = Dir.mktmpdir("caddy-windows-test-")
    @fixture = File.join(@sandbox, "fixture.crt")
    @log = File.join(@sandbox, "calls.log")
    @payload = File.join(@sandbox, "child.ps1")
    File.write(@fixture, certificate_fixture)
    File.write(@log, "")
    @environment = {
      "CADDY_TEST_HELPER" => HELPER, "CADDY_TEST_INSTALLER" => INSTALLER,
      "TEST_DIR" => @sandbox, "FIXTURE" => @fixture,
      "CALLS" => @log, "PAYLOAD" => @payload, "TEMP" => @sandbox, "TMP" => @sandbox,
      "DOCKER_CONTEXT" => "selected-remote", "COMPOSE_PROJECT_NAME" => "caller-project",
      "COMPOSE_FILE" => "caller-compose.yml"
    }
  end

  def teardown
    FileUtils.remove_entry(@sandbox) if @sandbox
  end

  def test_native_parser_accepts_both_full_scripts_without_running_their_entrypoints
    output, status = run_helper(body: <<~'PS', boundaries: false, source_helper: false)
      foreach ($path in @($env:CADDY_TEST_HELPER, $env:CADDY_TEST_INSTALLER)) {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        if ($errors.Count -ne 0) { throw ($errors | Out-String) }
        if ($ast -isnot [Management.Automation.Language.ScriptBlockAst]) { throw "Missing script AST: $path" }
        "PARSE_OK $path"
      }
    PS

    assert status.success?, output
    assert_includes output, "PARSE_OK #{HELPER}"
    assert_includes output, "PARSE_OK #{INSTALLER}"
    assert_equal 2, output.lines.grep(/^PARSE_OK /).size
    assert_empty calls
  end

  def test_real_ecdsa_root_validation_and_sha256_of_exact_raw_data
    File.write(@fixture, " \n\t" + certificate_fixture + "\n\t ")
    output, status = run_helper(body: <<~'PS')
      $certificate = Get-CaddyCertificate $env:FIXTURE
      try {
        Get-CaddyFingerprint $certificate.RawData
        $certificate.Thumbprint
        [Convert]::ToBase64String($certificate.RawData)
      } finally { $certificate.Dispose() }
    PS

    assert status.success?, output
    assert_includes output, fingerprint
    assert_includes output, thumbprint
    assert_includes output, Base64.strict_encode64(der)
    refute_match(/CONFIRM|IMPORT/, calls)
  end

  [ :leaf, :expired, :future, :bad_self_signature, :multiple, :private_key, :malformed,
    :trailing_text, :other_issuer, :no_basic_constraints, :concatenated_der, :trailing_der_junk ].each do |kind|
    define_method("test_rejects_#{kind}_before_confirmation_or_elevation") do
      File.write(@fixture, certificate_fixture(kind))
      output, status = run_helper

      refute status.success?, output
      assert_match(/certificate|CA|signature|valid|PEM|DER/i, output)
      refute_match(/CONFIRM|IMPORT/, calls)
      assert_temp_clean
    end
  end

  def test_workflow_preserves_docker_environment_and_copies_only_the_public_root_once
    output, status = run_helper

    assert status.success?, output
    assert_includes output, "selected-remote"
    assert_includes output, "reverse-proxy:/data/caddy/pki/authorities/local/root.crt"
    assert_includes calls, "DOCKER selected-remote caller-project caller-compose.yml compose ps --status running -q reverse-proxy"
    copies = calls.lines.grep(/ compose cp /)
    assert_equal 1, copies.size
    assert_match(%r{compose cp reverse-proxy:/data/caddy/pki/authorities/local/root\.crt .*[/\\]nosia-caddy\.[^/\\]+[/\\]root\.crt}, copies.first)
    assert_operator calls.index("CONFIRM"), :<, calls.index("IMPORT")
    assert_includes output, fingerprint
    assert_includes output, thumbprint
    assert_match(/Subject:.*CA:TRUE/, output)
    assert_includes output, "Issuer:"
    assert_includes output, "UTC"
    assert_includes output, "beyond nosia.localhost"
    assert_match(/Protect.*Docker.*CA volume/, output)
    assert_includes output, "System trust import succeeded"
    assert_includes output, "curl.exe --fail https://nosia.localhost/up"
    assert_includes output, GUIDE
    refute_match(/all browsers|application is healthy/i, output)
    refute_match(/root\.key|intermediate\.key|compose (?:up|start)|\bvolume\b|\bcurl\b/, calls)
    assert_temp_clean
  end

  def test_child_embeds_confirmed_public_der_and_no_parent_path_or_docker_command
    output, status = run_helper(environment: { "REPLACE_ON_CONFIRM" => "1" })

    assert status.success?, output
    child = File.read(@payload)
    assert_includes child, Base64.strict_encode64(der)
    assert_includes child, fingerprint
    refute_includes child, @sandbox
    refute_match(/docker|trust-caddy|root\.key|PRIVATE KEY|Read-Host|Start-Process/i, child)
    copies = calls.lines.grep(/ compose cp /)
    assert_equal 1, copies.size
    exported_path = copies.first.match(/compose cp reverse-proxy:\/data\/caddy\/pki\/authorities\/local\/root\.crt (.+)\n/)[1]
    refute_equal @fixture, exported_path
    assert_includes calls, "REPLACED_EXPORTED_ROOT #{exported_path} changed after confirmation"
    assert_operator calls.index("CONFIRM"), :<, calls.index("REPLACED_EXPORTED_ROOT")
    assert_operator calls.index("REPLACED_EXPORTED_ROOT"), :<, calls.index("IMPORT")
    assert_equal certificate_fixture, File.read(@fixture)
    assert_temp_clean
  end

  def test_exact_machine_store_certificate_skips_confirmation_and_elevation
    output, status = run_helper(overrides: <<~'PS')
      function Get-CaddyRootCertificates { Get-CaddyCertificate $env:FIXTURE }
    PS

    assert status.success?, output
    assert_match(/exact root is already trusted/i, output)
    refute_match(/CONFIRM|IMPORT/, calls)
    assert_temp_clean
  end

  def test_same_subject_and_same_key_reissued_certificate_is_not_exact_trust
    File.write(File.join(@sandbox, "other.crt"), certificate_fixture(:reissued_root))
    output, status = run_helper(overrides: <<~'PS')
      function Get-CaddyRootCertificates { Get-CaddyCertificate (Join-Path $env:TEST_DIR 'other.crt') }
    PS

    assert status.success?, output
    assert_includes calls, "CONFIRM"
    assert_includes calls, "IMPORT"
    refute_match(/already trusted/i, output)
  end

  def test_native_store_adapter_queries_only_machine_root_and_user_only_does_not_deduplicate
    output, status = run_helper(boundaries: false, body: <<~'PS')
      function Get-ChildItem {
        param($LiteralPath, $ErrorAction)
        if ($LiteralPath -ceq 'Cert:\CurrentUser\Root') { return Get-CaddyCertificate $env:FIXTURE }
        if ($LiteralPath -cne 'Cert:\LocalMachine\Root') { throw "Wrong store: $LiteralPath" }
        Add-Call "STORE $LiteralPath"
      }
      $certificate = Get-CaddyCertificate $env:FIXTURE
      try { if (Test-CaddyTrusted $certificate) { throw 'User-only trust counted as machine trust' } }
      finally { $certificate.Dispose() }
    PS

    assert status.success?, output
    assert_equal "STORE Cert:\\LocalMachine\\Root\n", calls
  end

  def test_same_subject_with_a_different_key_is_not_trusted
    File.write(File.join(@sandbox, "other.crt"), certificate_fixture(:future))
    output, status = run_helper(overrides: <<~'PS')
      function Get-CaddyRootCertificates {
        [byte[]]$raw = Get-PemBytes (Join-Path $env:TEST_DIR 'other.crt')
        New-Object Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList (,$raw)
      }
      function Get-PemBytes($Path) {
        [Convert]::FromBase64String(([IO.File]::ReadAllText($Path) -replace '-----[^\r\n]+-----', ''))
      }
    PS

    assert status.success?, output
    assert_includes calls, "IMPORT"
  end

  %w[ version context empty_context ps stopped cp ].each do |failure|
    define_method("test_docker_#{failure}_fails_without_elevation_and_cleans_up") do
      output, status = run_helper(environment: { "DOCKER_FAILURE" => failure })

      refute status.success?, output
      assert_match(/Docker|Compose|reverse-proxy/, output)
      refute_match(/CONFIRM|IMPORT/, calls)
      assert_temp_clean
    end
  end

  def test_missing_docker_and_unsupported_os_fail_before_copy
    [ "function Get-Command { param($Name, $ErrorAction) $null }", "$env:OS = 'Linux'" ].each do |override|
      File.write(@log, "")
      output, status = run_helper(overrides: override)

      refute status.success?, output
      assert_match(/Docker|Windows/, output)
      refute_match(/compose cp|CONFIRM|IMPORT/, calls)
      assert_temp_clean
    end
  end

  %w[ missing directory nested_directory reparse ].each do |mode|
    define_method("test_rejects_#{mode}_copy_and_cleans_only_owned_temporary_directory") do
      outside = File.join(@sandbox, "outside")
      FileUtils.mkdir_p(outside)
      sentinel = File.join(outside, "keep.txt")
      File.write(sentinel, "caller data")
      output, status = run_helper(environment: { "COPY_MODE" => mode })

      refute status.success?, output
      assert_match(/regular|reparse|file|certificate/i, output)
      refute_match(/CONFIRM|IMPORT/, calls)
      assert_equal "caller data", File.read(sentinel)
      assert_equal certificate_fixture, File.read(@fixture)
      assert_temp_clean
    end
  end

  def test_cancellation_does_not_elevate
    output, status = run_helper(environment: { "CANCEL" => "1" })

    refute status.success?, output
    assert_match(/cancel/i, output)
    assert_includes calls, "CONFIRM"
    refute_includes calls, "IMPORT"
    assert_temp_clean
  end

  def test_real_confirmation_accepts_only_case_sensitive_literal_yes_with_test_ui_wrappers
    [ "yes", "no", "", "YES", " yes", "yes " ].each do |answer|
      output, status = run_helper(real_confirm: true, environment: { "ANSWER" => answer }, overrides: <<~'PS')
        function Test-CaddyInteractive { $true }
        function Read-Host { param($Prompt) $env:ANSWER }
      PS

      assert_equal answer == "yes", status.success?, output
      assert_temp_clean
      File.write(@log, "")
    end
  end

  def test_real_confirmation_refuses_eof
    output, status = run_helper(real_confirm: true, overrides: <<~'PS')
      function Test-CaddyInteractive { $true }
      function Read-Host { param($Prompt) $null }
    PS

    refute status.success?, output
    refute_includes calls, "IMPORT"
    assert_temp_clean
  end

  def test_actual_redirected_input_even_yes_is_refused_before_uac
    [ "yes\n", "\n", "" ].each do |input|
      output, status = run_helper(real_confirm: true, input: input)

      refute status.success?, output
      assert_match(/interactive|redirect/i, output)
      refute_includes calls, "IMPORT"
      assert_temp_clean
    end
  end

  def test_no_unattended_arguments_are_accepted
    [ "--yes", "-y", "anything" ].each do |argument|
      output, status = run_helper(body: "Invoke-CaddyTrust '#{argument}'")

      refute status.success?, output
      assert_match(/arguments|usage|flags/i, output)
      refute_match(/compose cp|IMPORT/, calls)
    end
  end

  def test_import_failure_reports_possible_partial_machine_change_and_removal_thumbprint
    output, status = run_helper(environment: { "IMPORT_FAILURE" => "1" })

    refute status.success?, output
    assert_match(/partial/i, output)
    assert_includes output, "Cert:\\LocalMachine\\Root"
    assert_includes output, thumbprint
    refute_match(/System trust import succeeded/, output)
    assert_temp_clean
  end

  def test_uac_denial_discloses_possible_partial_change_and_exact_removal_thumbprint
    output, status = run_helper(overrides: <<~'PS')
      function Invoke-CaddyElevatedImport { throw 'Mock UAC permission denied' }
    PS

    refute status.success?, output
    assert_match(/partial.*Cert:\\LocalMachine\\Root|Cert:\\LocalMachine\\Root.*partial/, output)
    assert_match(/permission denied/, output)
    assert_includes output, thumbprint
    refute_match(/System trust import succeeded/, output)
    assert_temp_clean
  end

  def test_native_temporary_directory_is_owned_by_the_user_with_protected_access_rules
    output, status = run_helper(boundaries: false, body: <<~'PS')
      $directory = New-CaddyTemporaryDirectory
      try {
        $security = Get-Acl -LiteralPath $directory -ErrorAction Stop
        $user = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        if ($security.GetOwner([Security.Principal.SecurityIdentifier]).Value -cne $user) { throw 'Wrong directory owner' }
        if (-not $security.AreAccessRulesProtected) { throw 'Directory inherits access rules' }
        $rules = @($security.Access)
        if ($rules.Count -ne 1 -or $rules[0].IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -cne $user -or
            $rules[0].AccessControlType -ne 'Allow' -or $rules[0].FileSystemRights -ne 'FullControl') { throw 'Unexpected directory access rules' }
        'ACL_OK'
      } finally { Remove-CaddyTemporaryItem $directory }
    PS

    assert status.success?, output
    assert_includes output, "ACL_OK"
    assert_temp_clean
  end

  def test_store_read_permission_failure_stops_before_confirmation
    output, status = run_helper(overrides: "function Get-CaddyRootCertificates { throw 'Store permission denied' }")

    refute status.success?, output
    assert_match(/permission denied/, output)
    refute_match(/CONFIRM|IMPORT/, calls)
    assert_temp_clean
  end

  def test_child_runs_with_mocked_import_and_holds_read_only_file_lock_until_import_finishes
    output, status = run_helper(boundaries: false, body: <<~'PS')
      function Import-Certificate {
        param($FilePath, $CertStoreLocation, $ErrorAction)
        if ($CertStoreLocation -cne 'Cert:\LocalMachine\Root' -or $ErrorAction -ne 'Stop') { throw 'Wrong import contract' }
        $bytes = [IO.File]::ReadAllBytes($FilePath)
        Add-Call ('IMPORTED ' + (Get-CaddyFingerprint $bytes))
        $blocked = $false
        try {
          $writer = [IO.File]::Open($FilePath, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
          $writer.Dispose()
        } catch [IO.IOException] { $blocked = $true }
        if (-not $blocked) { throw 'Certificate swap was not blocked during import' }
        $script:importedPath = $FilePath
      }
      $certificate = Get-CaddyCertificate $env:FIXTURE
      try { $child = New-CaddyImportScript $certificate.RawData (Get-CaddyFingerprint $certificate.RawData) }
      finally { $certificate.Dispose() }
      & ([scriptblock]::Create($child))
      if ([IO.File]::Exists($script:importedPath)) { throw 'Child left temporary public certificate' }
      'CHILD_OK'
    PS

    assert status.success?, output
    assert_includes output, "CHILD_OK"
    assert_equal "IMPORTED #{fingerprint}\n", calls
    assert_temp_clean
  end

  def test_child_rejects_modified_embedded_der_before_import
    output, status = run_helper(boundaries: false, body: <<~'PS')
      $certificate = Get-CaddyCertificate $env:FIXTURE
      try {
        $fingerprint = Get-CaddyFingerprint $certificate.RawData
        $publicDer = [Convert]::ToBase64String($certificate.RawData)
        $child = (New-CaddyImportScript $certificate.RawData $fingerprint).Replace($publicDer, [Convert]::ToBase64String([byte[]](1, 2, 3)))
      }
      finally { $certificate.Dispose() }
      & ([scriptblock]::Create($child))
    PS

    refute status.success?, output
    assert_match(/fingerprint/i, output)
    refute_match(/IMPORTED|FORBIDDEN/, output)
    assert_empty calls
    assert_temp_clean
  end

  def test_child_rechecks_the_locked_file_before_import
    output, status = run_helper(boundaries: false, body: <<~'PS')
      $certificate = Get-CaddyCertificate $env:FIXTURE
      try { $child = New-CaddyImportScript $certificate.RawData (Get-CaddyFingerprint $certificate.RawData) }
      finally { $certificate.Dispose() }
      $child = $child.Replace('    $lock = [IO.File]::Open(', "    [IO.File]::WriteAllBytes(`$temporaryFile, [byte[]](1, 2, 3))`n    `$lock = [IO.File]::Open(")
      & ([scriptblock]::Create($child))
    PS

    refute status.success?, output
    assert_match(/Locked certificate fingerprint mismatch/, output)
    refute_match(/FORBIDDEN/, output)
    assert_empty calls
    assert_temp_clean
  end

  def test_payload_builder_rejects_fingerprint_not_matching_the_actual_input
    output, status = run_helper(body: <<~'PS')
      $certificate = Get-CaddyCertificate $env:FIXTURE
      try { New-CaddyImportScript $certificate.RawData ('0' * 64) }
      finally { $certificate.Dispose() }
    PS

    refute status.success?, output
    assert_match(/fingerprint/i, output)
    refute_includes calls, "IMPORT"
  end

  def test_child_import_failure_exits_nonzero_and_removes_its_public_file
    output, status = run_helper(boundaries: false, body: <<~'PS')
      function Import-Certificate { throw 'Mock native import permission denied' }
      $certificate = Get-CaddyCertificate $env:FIXTURE
      try { $child = New-CaddyImportScript $certificate.RawData (Get-CaddyFingerprint $certificate.RawData) }
      finally { $certificate.Dispose() }
      & ([scriptblock]::Create($child))
    PS

    refute status.success?, output
    assert_match(/permission denied/, output)
    assert_temp_clean
  end

  def test_encoded_adapter_uses_only_system_windows_powershell_and_fixed_flags
    output, status = run_helper(boundaries: false, body: adapter_body)

    assert status.success?, output
    child = File.read(@payload)
    assert_includes child, Base64.strict_encode64(der)
    assert_includes child, fingerprint
    refute_match(/docker|trust-caddy|PRIVATE KEY/i, child)
    assert_empty calls
  end

  def test_encoded_adapter_rejects_nonzero_child_exit_and_uac_denial
    [ "7", "deny" ].each do |failure|
      output, status = run_helper(boundaries: false, environment: { "CHILD_FAILURE" => failure }, body: adapter_body)

      refute status.success?, output
      assert_match(/exit|denied|elevation/i, output)
      assert_temp_clean
    end
  end

  def test_entrypoint_catches_failure_and_prints_manual_guide_without_real_commands
    output, status = run_helper(boundaries: false, body: <<~'PS')
      $env:OS = 'Not-Windows'
      & $env:CADDY_TEST_HELPER
    PS

    refute status.success?, output
    assert_includes output, GUIDE
    refute_match(/System trust import succeeded/, output)
    assert_empty calls
  end

  private
    def der
      OpenSSL::X509::Certificate.new(certificate_fixture).to_der
    end

    def fingerprint
      OpenSSL::Digest::SHA256.hexdigest(der)
    end

    def thumbprint
      OpenSSL::Digest::SHA1.hexdigest(der).upcase
    end

    def calls
      File.read(@log).gsub("\r\n", "\n")
    end

    def assert_temp_clean
      assert_empty Dir.glob(File.join(@sandbox, "nosia-caddy.*")), "helper left temporary certificate material"
      assert_empty Dir.glob(File.join(@sandbox, "*.tmp")), "child left its temporary public certificate"
    end

    def run_helper(environment: {}, overrides: "", body: "Invoke-CaddyTrust", boundaries: true, real_confirm: false, input: "", source_helper: true)
      script = File.join(@sandbox, "harness.ps1")
      File.write(script, <<~PS)
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        try {
          function Add-Call($Message) { [IO.File]::AppendAllText($env:CALLS, $Message + "`n") }
          function Start-Process { throw 'FORBIDDEN real UAC/Start-Process' }
          function Import-Certificate { throw 'FORBIDDEN real native import' }
          function docker { throw 'FORBIDDEN real Docker' }
          #{source_helper ? '. $env:CADDY_TEST_HELPER' : ''}
          #{boundaries ? fake_boundaries : ''}
          #{real_confirm ? '' : fake_confirmation}
          #{overrides}
          #{body}
        } catch {
          [Console]::Error.WriteLine($_.ToString())
          exit 1
        }
      PS
      engine = ENV.fetch("CADDY_TEST_POWERSHELL", "pwsh")
      output, error, status = Open3.capture3(@environment.merge(environment), engine,
        "-NoLogo", "-NoProfile", "-NonInteractive", "-File", script, stdin_data: input)
      [ output + error, status ]
    end

    def fake_confirmation
      <<~'PS'
        function Confirm-CaddyTrust {
          Add-Call 'CONFIRM'
          if ($env:REPLACE_ON_CONFIRM -eq '1') {
            [IO.File]::WriteAllText($script:copiedRootPath, 'changed after confirmation')
            Add-Call "REPLACED_EXPORTED_ROOT $script:copiedRootPath $([IO.File]::ReadAllText($script:copiedRootPath))"
          }
          $env:CANCEL -ne '1'
        }
      PS
    end

    def fake_boundaries
      <<~'PS'
        function docker {
          $global:LASTEXITCODE = 0
          $command = $args -join ' '
          Add-Call "DOCKER $env:DOCKER_CONTEXT $env:COMPOSE_PROJECT_NAME $env:COMPOSE_FILE $command"
          switch ($command) {
            'compose version' { if ($env:DOCKER_FAILURE -eq 'version') { $global:LASTEXITCODE = 1 }; return }
            'context show' {
              if ($env:DOCKER_FAILURE -eq 'context') { $global:LASTEXITCODE = 1; return }
              if ($env:DOCKER_FAILURE -ne 'empty_context') { $env:DOCKER_CONTEXT }; return
            }
            'compose ps --status running -q reverse-proxy' {
              if ($env:DOCKER_FAILURE -eq 'ps') { $global:LASTEXITCODE = 1; return }
              if ($env:DOCKER_FAILURE -ne 'stopped') { 'container-id' }; return
            }
          }
          if ($args.Count -ne 4 -or $args[0] -ne 'compose' -or $args[1] -ne 'cp' -or
              $args[2] -cne 'reverse-proxy:/data/caddy/pki/authorities/local/root.crt') { throw "Unexpected Docker call: $command" }
          if ($env:DOCKER_FAILURE -eq 'cp') { $global:LASTEXITCODE = 1; return }
          $destination = $args[3]
          switch ($env:COPY_MODE) {
            'missing' { return }
            'directory' { [void][IO.Directory]::CreateDirectory($destination); return }
            'nested_directory' {
              [void][IO.Directory]::CreateDirectory((Join-Path $destination 'nested\inner'))
              [IO.File]::WriteAllText((Join-Path $destination 'nested\inner\unexpected.txt'), 'unexpected copy')
              New-Item -ItemType Junction -Path (Join-Path $destination 'external') -Target (Join-Path $env:TEST_DIR 'outside') | Out-Null
              return
            }
            'reparse' {
              New-Item -ItemType Junction -Path $destination -Target (Join-Path $env:TEST_DIR 'outside') | Out-Null
              return
            }
          }
          [IO.File]::Copy($env:FIXTURE, $destination)
          $script:copiedRootPath = $destination
        }
        function Get-CaddyRootCertificates { @() }
        function Invoke-CaddyElevatedImport {
          param([byte[]]$RawData, [string]$Fingerprint)
          Add-Call "IMPORT $Fingerprint"
          [IO.File]::WriteAllText($env:PAYLOAD, (New-CaddyImportScript $RawData $Fingerprint))
          if ($env:IMPORT_FAILURE -eq '1') { throw 'Native child import failed' }
        }
      PS
    end

    def adapter_body
      <<~'PS'
        function Start-Process {
          param($FilePath, $Verb, [switch]$Wait, [switch]$PassThru, $ArgumentList)
          if ($FilePath -cne (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')) { throw 'Wrong elevation engine' }
          if ($Verb -cne 'RunAs' -or -not $Wait -or -not $PassThru) { throw 'Wrong elevation flags' }
          if ($ArgumentList.Count -ne 4 -or $ArgumentList[0] -cne '-NoProfile' -or
              $ArgumentList[1] -cne '-NonInteractive' -or $ArgumentList[2] -cne '-EncodedCommand') { throw 'Wrong child arguments' }
          $child = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($ArgumentList[3]))
          [IO.File]::WriteAllText($env:PAYLOAD, $child)
          if ($env:CHILD_FAILURE -eq 'deny') { throw 'Mock UAC denied' }
          if ($env:CHILD_FAILURE -eq '7') { return [pscustomobject]@{ ExitCode = 7 } }
          [pscustomobject]@{ ExitCode = 0 }
        }
        $certificate = Get-CaddyCertificate $env:FIXTURE
        try { Invoke-CaddyElevatedImport $certificate.RawData (Get-CaddyFingerprint $certificate.RawData) }
        finally { $certificate.Dispose() }
      PS
    end
end
