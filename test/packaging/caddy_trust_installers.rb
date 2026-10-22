require "minitest/autorun"
require "open3"
require "fileutils"
require "tmpdir"

module CaddyTrustInstallerFixtures
  ROOT = File.expand_path("../..", __dir__)
  GUIDE = "https://github.com/dilolabs/nosia/blob/main/docs/LOCAL_HTTPS.md"
  UPSTREAM = "https://raw.githubusercontent.com/dilolabs/nosia/main/bin/"

  def setup
    @sandbox = Dir.mktmpdir("caddy installer test ")
    @project = File.join(@sandbox, "project with spaces")
    @log = File.join(@sandbox, "requests.log")
    @payload = File.join(@sandbox, "fake helper")
    @executed = File.join(@sandbox, "EXECUTED")
    FileUtils.mkdir_p(@project)
    File.write(@log, "")
    @environment = {
      "PROJECT" => @project, "CALLS" => @log, "PAYLOAD" => @payload,
      "EXECUTED" => @executed, "MODE" => "success", "FAIL_TOOL" => "",
      "TMPDIR" => @sandbox, "TEMP" => @sandbox, "TMP" => @sandbox
    }
  end

  def teardown
    FileUtils.remove_entry(@sandbox) if @sandbox
  end

  private
    def source(path)
      File.read(File.join(ROOT, path))
    end

    # Extract only this anchored definition, never source an installer or main.
    def shell_definition
      definition = source("install.sh")[/^download_caddy_trust_helper\(\) \{\n.*?^\}/m]
      refute_nil definition, "missing download_caddy_trust_helper definition"
      definition
    end

    def powershell_definition
      definition = source("install.ps1")[/^function Download-CaddyTrustHelper \{\n.*?^\}/m]
      refute_nil definition, "missing Download-CaddyTrustHelper definition"
      definition
    end

    def calls
      File.read(@log).gsub("\r\n", "\n")
    end

    def keep_unrelated_stage
      FileUtils.mkdir_p(File.dirname(@target))
      @unrelated = File.join(File.dirname(@target), ".trust-caddy.caller-owned")
      File.write(@unrelated, "caller data")
    end

    def assert_clean
      stages = Dir.glob(File.join(@project, "bin/.trust-caddy.*"))
      assert_equal @unrelated ? [ @unrelated ] : [], stages, "left an owned staging file"
      assert_equal "caller data", File.read(@unrelated) if @unrelated
      refute File.exist?(@executed), "downloaded helper was automatically EXECUTED"
    end

    def assert_usable(output, status)
      assert status.success?, output
      assert_includes output, "INSTALLER_USABLE"
      refute_includes output, "FORBIDDEN"
      assert_clean
    end

    def assert_warning(output, status)
      assert_usable(output, status)
      assert_match(/warning/i, output)
      assert_includes output, GUIDE
    end
end

class CaddyTrustInstallerPackagingTest < Minitest::Test
  include CaddyTrustInstallerFixtures

  def test_shell_distributes_only_its_helper_after_pull_and_before_final_guidance
    installer = source("install.sh")
    definition = shell_definition
    assert_operator installer.index(definition), :<, installer.index("# Main installation")
    assert_includes definition, UPSTREAM + "trust-caddy"
    refute_includes installer, UPSTREAM + "trust-caddy.ps1"
    assert_match(/docker compose pull.*?^  download_caddy_trust_helper\s*\n.*?Setup complete\. Start with: docker compose up -d/m, installer)
    assert_match(/if \[ -f ["']?bin\/trust-caddy["']? \]; then\s+echo "After startup, optionally run: bin\/trust-caddy"\s+else\s+echo "[^"]*#{Regexp.escape(GUIDE)}"/m, installer)
    assert_distribution_only(definition, installer)
  end

  def test_powershell_distributes_only_its_helper_after_pull_and_before_final_guidance
    installer = source("install.ps1")
    definition = powershell_definition
    assert_operator installer.index(definition), :<, installer.index("# Main installation")
    assert_includes definition, UPSTREAM + "trust-caddy.ps1"
    refute_match(%r{#{Regexp.escape(UPSTREAM)}trust-caddy["']}, installer)
    assert_match(/docker compose pull.*?^    Download-CaddyTrustHelper\s*\n.*?Setup complete\. Start with: docker compose up -d/m, installer)
    assert_match(/if \(Test-Path -LiteralPath ["']\.\\bin\\trust-caddy\.ps1["'] -PathType Leaf\) \{\s+Write-Host ["']After startup, optionally run: \.\\bin\\trust-caddy\.ps1["']\s+\} else \{\s+Write-Host "[^"]*#{Regexp.escape(GUIDE)}"/m, installer)
    assert_match(/\[IO\.File\]::Move\(\$\w+,\s*\$\w+\)/, definition)
    assert_distribution_only(definition, installer)
  end

  private
    def assert_distribution_only(definition, installer)
      refute_match(/\b(?:sudo|docker|Import-Certificate|Start-Process|Set-ExecutionPolicy|Invoke-Expression|certutil|security|update-ca-certificates|update-ca-trust)\b/i, definition)
      commands = installer.lines.reject { |line| line.match?(/^\s*(?:#|echo |Write-Host )/) }.join
      refute_match(/^\s*(?:[.&]\s*|(?:sh|bash|pwsh|powershell)\s+)?["']?(?:\.?[\/\\])?bin[\/\\]trust-caddy(?:\.ps1)?\b/i, commands)
      refute_match(/\b(?:Invoke-CaddyTrust|Import-Certificate|Set-ExecutionPolicy)\b|docker compose (?:up|start|run|exec)\b/i, commands)
    end
end

class CaddyTrustShellDownloaderTest < Minitest::Test
  include CaddyTrustInstallerFixtures

  def setup
    skip "POSIX shell downloader requires Linux or macOS" unless RUBY_PLATFORM.match?(/linux|darwin/)
    super
    @target = File.join(@project, "bin/trust-caddy")
    File.write(@payload, "#!/bin/sh\nprintf 'EXECUTED\\n' >> \"$EXECUTED\"\n# complete helper payload\n")
    prepare_tools
  end

  def test_complete_download_is_published_executable_without_execution
    output, status = run_downloader

    assert_usable(output, status)
    assert File.file?(@target), output
    assert_equal File.read(@payload), File.read(@target)
    assert File.executable?(@target)
    refute File.exist?(File.join(@project, "bin/trust-caddy.ps1"))
    assert_equal 1, calls.lines.grep(/^REQUEST /).size
    assert_includes calls, "REQUEST #{UPSTREAM}trust-caddy\n"
    assert_match(%r{^STAGED bin/\.trust-caddy\.[^/\n]+$}, calls)
    assert_operator calls.index("REQUEST"), :<, calls.index("CHMOD")
    assert_operator calls.index("CHMOD"), :<, calls.index("PUBLISH")
  end

  %w[ file empty_file directory symlink broken_symlink ].each do |kind|
    define_method("test_existing_#{kind}_is_preserved_without_a_request") do
      FileUtils.mkdir_p(File.dirname(@target))
      case kind
      when "file" then File.write(@target, "user modifications")
      when "empty_file" then File.write(@target, "")
      when "directory" then FileUtils.mkdir_p(@target)
      when "symlink" then File.symlink(@payload, @target)
      when "broken_symlink" then File.symlink("missing user helper", @target)
      end
      before = File.lstat(@target)
      output, status = run_downloader

      assert_usable(output, status)
      assert_empty calls
      assert_equal before.ino, File.lstat(@target).ino
      assert_equal "user modifications", File.read(@target) if kind == "file"
      assert_equal "missing user helper", File.readlink(@target) if kind == "broken_symlink"
    end
  end

  %w[ failure empty partial ].each do |mode|
    define_method("test_#{mode}_download_warns_and_leaves_no_partial_executable") do
      keep_unrelated_stage
      output, status = run_downloader("MODE" => mode)

      assert_warning(output, status)
      refute File.exist?(@target)
      refute_match(/CHMOD|PUBLISH/, calls)
    end
  end

  %w[ mkdir mktemp chmod ln ].each do |tool|
    define_method("test_#{tool}_failure_is_nonfatal_and_cleans_only_its_stage") do
      keep_unrelated_stage
      output, status = run_downloader("FAIL_TOOL" => tool)

      assert_warning(output, status)
      refute File.exist?(@target)
      assert_empty calls if %w[ mkdir mktemp ].include?(tool)
    end
  end

  def test_bin_file_prevents_staging_without_being_replaced
    File.write(File.join(@project, "bin"), "caller bin file")
    output, status = run_downloader

    assert_warning(output, status)
    assert_equal "caller bin file", File.read(File.join(@project, "bin"))
    assert_empty calls
  end

  %w[ race race_symlink ].each do |mode|
    define_method("test_#{mode}_publication_never_overwrites_the_racing_creator") do
      keep_unrelated_stage
      output, status = run_downloader("MODE" => mode)

      assert_warning(output, status)
      if mode == "race"
        assert_equal "racing user file", File.read(@target)
        refute File.executable?(@target)
      else
        assert_equal "missing racing helper", File.readlink(@target)
      end
    end
  end

  def test_fake_payload_really_records_execution_if_invoked
    _, _, status = Open3.capture3(@environment, "/bin/sh", @payload)

    assert status.success?
    assert_equal "EXECUTED\n", File.read(@executed)
  end

  private
    def prepare_tools
      tools = File.join(@sandbox, "guard tools")
      FileUtils.mkdir_p(tools)
      # An allowlisted PATH prevents network/dependency/Docker/trust commands escaping.
      %w[ mkdir mktemp chmod ln rm cat cp ].each do |name|
        executable = ENV.fetch("PATH").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, name) }.find { |path| File.executable?(path) && !File.directory?(path) }
        refute_nil executable, "missing sandbox tool #{name}"
        path = File.join(tools, name)
        File.write(path, <<~SH)
          #!/bin/sh
          [ "$FAIL_TOOL" != '#{name}' ] || exit 1
          #{name == 'chmod' ? 'printf "CHMOD\\n" >> "$CALLS"' : ''}
          #{name == 'ln' ? '[ "$1" = -s ] || printf "PUBLISH\\n" >> "$CALLS"' : ''}
          exec '#{executable}' "$@"
        SH
        FileUtils.chmod(0755, path)
      end
      File.write(File.join(tools, "curl"), <<~'SH')
        #!/bin/sh
        [ "$#" = 4 ] && [ "$1" = -fsSL ] && [ "$2" = -o ] &&
          [ "$4" = https://raw.githubusercontent.com/dilolabs/nosia/main/bin/trust-caddy ] || exit 97
        printf 'REQUEST %s\nSTAGED %s\n' "$4" "$3" >> "$CALLS"
        [ -f "$3" ] && [ ! -x "$3" ] || exit 97
        [ ! -e bin/trust-caddy ] && [ ! -L bin/trust-caddy ] || exit 97
        case "$MODE" in
          failure) exit 22 ;;
          empty) : > "$3"; exit 0 ;;
          partial)
            printf '%s\n' '#!/bin/sh' 'printf "EXECUTED\n" >> "$EXECUTED"' > "$3"
            exit 18 ;;
        esac
        cp "$PAYLOAD" "$3" || exit 1
        case "$MODE" in
          race) printf 'racing user file' > bin/trust-caddy ;;
          race_symlink) ln -s 'missing racing helper' bin/trust-caddy ;;
        esac
      SH
      FileUtils.chmod(0755, File.join(tools, "curl"))
      @environment["PATH"] = tools
    end

    def run_downloader(environment = {})
      script = shell_definition + "\ndownload_caddy_trust_helper\nprintf 'INSTALLER_USABLE\\n'\n"
      output, error, status = Open3.capture3(@environment.merge(environment), "/bin/sh", "-e", "-c", script, chdir: @project)
      [ output + error, status ]
    end
end

# Shared pure filesystem/HTTP-mock checks, not native certificate verification.
module CaddyTrustPowerShellDownloaderChecks
  def test_full_installer_parses_without_running_its_entrypoint
    output, status = run_powershell(<<~'PS', definition: false)
      $tokens = $null
      $errors = $null
      [void][Management.Automation.Language.Parser]::ParseFile($env:INSTALLER, [ref]$tokens, [ref]$errors)
      if ($errors.Count) { throw ($errors | Out-String) }
      'INSTALLER_USABLE'
    PS

    assert_usable(output, status)
    assert_empty calls
  end

  def test_complete_download_publishes_only_the_matching_payload_without_execution
    output, status = run_downloader

    assert_usable(output, status)
    assert File.file?(@target), output
    assert_equal File.read(@payload), File.read(@target)
    refute File.exist?(File.join(@project, "bin/trust-caddy"))
    assert_equal 1, calls.lines.grep(/^REQUEST /).size
    assert_includes calls, "REQUEST #{CaddyTrustInstallerFixtures::UPSTREAM}trust-caddy.ps1\n"
    assert_match(%r{^STAGED .*[/\\]bin[/\\]\.trust-caddy\.[\da-f-]+$}i, calls)
  end

  %w[ file empty_file directory symlink broken_symlink ].each do |kind|
    define_method("test_existing_#{kind}_is_preserved_without_a_request") do
      FileUtils.mkdir_p(File.dirname(@target))
      case kind
      when "file" then File.write(@target, "user modifications")
      when "empty_file" then File.write(@target, "")
      when "directory" then FileUtils.mkdir_p(@target)
      when "symlink", "broken_symlink"
        begin
          File.symlink(kind == "symlink" ? @payload : "missing user helper", @target)
        rescue NotImplementedError, Errno::EACCES, Errno::EPERM
          skip "Creating Windows symlinks requires developer mode or permission"
        end
      end
      before = File.lstat(@target)
      output, status = run_downloader

      assert_usable(output, status)
      assert_empty calls
      assert_equal before.ino, File.lstat(@target).ino
      assert_equal "user modifications", File.read(@target) if kind == "file"
      assert_equal "missing user helper", File.readlink(@target) if kind == "broken_symlink"
    end
  end

  %w[ failure empty partial missing write_failure publication_failure ].each do |mode|
    define_method("test_#{mode}_warns_nonfatally_and_cleans_only_its_stage") do
      keep_unrelated_stage
      output, status = run_downloader("MODE" => mode)

      assert_warning(output, status)
      if mode == "publication_failure"
        assert File.directory?(@target)
        assert_equal "caller data", File.read(File.join(@target, "keep.txt"))
      else
        refute File.exist?(@target)
      end
    end
  end

  def test_bin_file_prevents_staging_without_being_replaced
    File.write(File.join(@project, "bin"), "caller bin file")
    output, status = run_downloader

    assert_warning(output, status)
    assert_equal "caller bin file", File.read(File.join(@project, "bin"))
    assert_empty calls
  end

  def test_racing_creator_is_never_overwritten
    keep_unrelated_stage
    output, status = run_downloader("MODE" => "race")

    assert_warning(output, status)
    assert_equal "racing user file", File.read(@target)
  end

  def test_fake_payload_really_records_execution_if_invoked
    output, status = run_powershell("& $env:PAYLOAD", definition: false)

    assert status.success?, output
    assert_equal "EXECUTED\n", File.read(@executed)
  end

  private
    def setup_powershell
      @engine = ENV.fetch("CADDY_TEST_POWERSHELL", "pwsh")
      begin
        _, _, status = Open3.capture3(@engine, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", "exit 0")
        skip "PowerShell unavailable: #{@engine}" unless status.success?
      rescue Errno::ENOENT
        skip "PowerShell unavailable: set CADDY_TEST_POWERSHELL to run parser/pure mocks"
      end
      @target = File.join(@project, "bin/trust-caddy.ps1")
      @payload += ".ps1"
      File.write(@payload, "[IO.File]::AppendAllText($env:EXECUTED, \"EXECUTED`n\")\n# complete helper payload\n")
      @environment.merge!("PAYLOAD" => @payload, "INSTALLER" => File.join(CaddyTrustInstallerFixtures::ROOT, "install.ps1"))
    end

    def run_downloader(environment = {})
      run_powershell("Download-CaddyTrustHelper\n'INSTALLER_USABLE'", environment: environment)
    end

    def run_powershell(body, environment: {}, definition: true)
      fragment = File.join(@sandbox, "downloader.ps1")
      File.write(fragment, definition ? powershell_definition : "")
      harness = File.join(@sandbox, "mock harness.ps1")
      File.write(harness, <<~PS)
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        Set-Location -LiteralPath $env:PROJECT
        #{powershell_boundaries}
        #{definition ? '. $env:FRAGMENT' : ''}
        #{body}
      PS
      runner = <<~'PS'
        $ErrorActionPreference = 'Stop'
        foreach ($path in @($env:FRAGMENT, $env:HARNESS)) {
          $tokens = $null
          $errors = $null
          $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
          if ($errors.Count) { throw ($errors | Out-String) }
          if ($path -eq $env:FRAGMENT -and $env:HAS_DEFINITION -eq '1') {
            $statements = @($ast.EndBlock.Statements)
            if ($statements.Count -ne 1 -or $statements[0] -isnot [Management.Automation.Language.FunctionDefinitionAst] -or
                $statements[0].Name -cne 'Download-CaddyTrustHelper') { throw 'Not an isolated function definition' }
          }
        }
        & $env:HARNESS
      PS
      env = @environment.merge(environment).merge("FRAGMENT" => fragment, "HARNESS" => harness, "HAS_DEFINITION" => definition ? "1" : "0")
      output, error, status = Open3.capture3(env, @engine, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", runner)
      [ output + error, status ]
    end

    def powershell_boundaries
      <<~'PS'
        function docker { throw 'FORBIDDEN real Docker' }
        function Start-Process { throw 'FORBIDDEN process/elevation' }
        function Import-Certificate { throw 'FORBIDDEN native trust import' }
        function Set-ExecutionPolicy { throw 'FORBIDDEN execution policy change' }
        function Invoke-RestMethod { throw 'FORBIDDEN real HTTP' }
        function Invoke-WebRequest {
          param($Uri, $OutFile, $ErrorAction)
          if ($Uri -cne 'https://raw.githubusercontent.com/dilolabs/nosia/main/bin/trust-caddy.ps1' -or $ErrorAction -ne 'Stop') {
            throw 'Unexpected download contract'
          }
          [IO.File]::AppendAllText($env:CALLS, "REQUEST $Uri`nSTAGED $OutFile`n")
          $bin = Join-Path $env:PROJECT 'bin'
          if ([IO.Path]::GetDirectoryName($OutFile) -cne $bin) { throw 'Staging outside bin' }
          $target = Join-Path $bin 'trust-caddy.ps1'
          switch ($env:MODE) {
            'failure' { throw 'Mock HTTP failure' }
            'write_failure' { throw 'Mock OutFile creation denied' }
            'missing' { return }
            'empty' { [IO.File]::WriteAllText($OutFile, ''); return }
          }
          [IO.File]::WriteAllText($OutFile, [IO.File]::ReadAllText($env:PAYLOAD))
          switch ($env:MODE) {
            'partial' {
              [IO.File]::WriteAllText($OutFile, ([IO.File]::ReadAllText($env:PAYLOAD) -split '# complete')[0])
              throw 'Mock interrupted download'
            }
            'race' { [IO.File]::WriteAllText($target, 'racing user file') }
            'publication_failure' {
              [void][IO.Directory]::CreateDirectory($target)
              [IO.File]::WriteAllText((Join-Path $target 'keep.txt'), 'caller data')
            }
          }
        }
      PS
    end
end

class CaddyTrustInstallerPowerShellNativeTest < Minitest::Test
  include CaddyTrustInstallerFixtures
  include CaddyTrustPowerShellDownloaderChecks

  def setup
    skip "Native Windows installer checks require Windows PowerShell 5.1 and PowerShell 7" unless Gem.win_platform?
    super
    setup_powershell
  end
end

class CaddyTrustInstallerPowerShellPortableTest < Minitest::Test
  include CaddyTrustInstallerFixtures
  include CaddyTrustPowerShellDownloaderChecks

  def setup
    skip "Portable parser/pure mocks are separate from native Windows checks" if Gem.win_platform?
    super
    setup_powershell
  end
end
