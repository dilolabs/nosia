# Trusted Caddy Local HTTPS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Obtain the user's execution-method choice before dispatching implementation agents.

**Goal:** Run Caddy → Puma without Thruster and provide explicit, safe host trust helpers for Linux, macOS, and Windows.

**Architecture:** Caddy continues managing local/public HTTPS and forwarding to Puma on internal port 3000. Small host scripts export and validate only Caddy's public root, show its fingerprint, require interactive confirmation, and elevate only native trust-store writes. Existing installers distribute—but never execute—the helpers.

**Tech Stack:** Existing Rails/Puma/Docker Compose/Caddy; POSIX shell plus OpenSSL; Windows PowerShell 5.1/7 plus Windows certificate APIs; standalone Minitest packaging/subprocess tests.

---

## Authority, context, and safety

- Approved specification: `docs/superpowers/specs/2026-10-22-caddy-puma-local-https-design.md`. The user approved its written form with “Go”. This document is a plan, not evidence that any proposed command or test has already passed.
- Before implementation, create an isolated worktree from the committed plan. Do not copy, edit, stage, or discard the existing unrelated `Procfile.dev` change, untracked upgrade/composer plans, or `test/packaging/embedding_dimensions.rb`.
- Actual repository files take precedence over the generic stack description: `.ruby-version` is `4`; packaging tests already run without booting Rails; CI is `.github/workflows/ci.yml`. There is no `bin/ci` or `config/ci.rb`.
- Never run these new helpers against the working host during automated verification. Stub all privileged writes; do native import/removal smoke checks only in disposable machines.
- Every implementation task follows RED → GREEN. Run the exact new test first and confirm a missing behavior—not a syntax or harness error—causes failure. If a proposed command/API differs on a target OS, preserve the approved behavior, correct the plan inline, and test that target rather than relaxing validation.
- **Execution note:** The code blocks below preserve the original proposed implementation. Reviewed source files are now authoritative: review-driven corrections and native verification gaps are recorded in the execution notes below. Do not copy superseded snippets over the committed implementation.

## File map

### Execution progress

Worktree: `.worktrees/caddy-puma-local-https`, branch `feat/caddy-puma-local-https`.

Baseline: dependency check and database test preparation succeeded. Existing packaging tests: 2 runs, 8 assertions, no failures. With disposable encryption/model/chunk settings matching the checked-in 4096-dimensional schema, the application baseline has 626 runs, 3405 assertions, 0 failures, 1 error: `Website::CrawlableTest#test_crawl_url!_still_crawls_public_hosts` requires an unavailable embedding provider. The user explicitly approved proceeding with that baseline limitation. No development secrets were copied.

- [x] Task 1: Remove Thruster — committed `1148fc3`; spec and quality reviews approved; 17 packaging tests / 36 assertions pass.
- [x] Task 2: Unix helper — through `0c57572`; spec and quality reviews approved; 82 tests / 1,105 assertions pass. macOS admin-domain dedup uses typed `plutil` reads (macOS 12+); native macOS verification remains unavailable here.
- [x] Task 3: Windows helper — through `5caf65c`; spec and quality reviews approved; portable contracts 3 tests / 53 assertions pass, 48 native Windows tests skipped. Portable PowerShell 7.4.6 parses the helper/child/test fragments; native Windows 5.1/7 verification remains pending.
- [x] Task 4: Installer distribution — through `5490bd7`; spec and quality reviews approved; 63 tests / 762 assertions pass with 20 native Windows skips. Directory publication races, restrictive Unix umasks, and optional Windows guidance lookup errors have regression coverage.
- [x] Task 5: Documentation — through `fc4dfe0`; spec and quality reviews approved; 28 packaging/documentation contracts / 261 assertions pass. Guide reflects the actual helper outputs, platform prerequisites, exact removal, and client trust boundaries.
- [x] Task 6: Cross-platform CI — committed `3a6f3cf`; spec and quality reviews approved; all packaging 231 runs / 2,238 assertions pass, with 68 expected native Windows skips. Native macOS/Windows GitHub Actions execution has not been triggered.
- [x] Task 7: Available final verification and all-task review recorded in `d488c9a`; final code/spec/security review approved with no fixes requested, conditioned on remaining native/disposable acceptance evidence. No merge or push performed.

### Review-driven implementation corrections and remaining gates

- Unix validation compares decoded input bytes with the OpenSSL-exported certificate to reject concatenated/trailing objects inside a single PEM block. It does not implement a general ASN.1 encoding linter.
- Unix cleanup is confined to its uniquely created private directory, including unexpected nested copies, without following copied symlinks.
- macOS deduplication requires exact certificate presence and unrestricted admin-domain trust, not merely `verify-cert` success that could inherit user trust. Typed `plutil` reads require macOS 12+. Ordinary missing admin settings remain eligible for a confirmed first import; actual export errors are reported.
- Tests use portable Ruby permission checks, not GNU-only `stat` syntax.
- Windows snapshot tests mutate the exported root during confirmation and prove the child retains the confirmed DER. Native crypt32, stores, locks, and UAC remain unverified on this Linux host.
- Installer publication uses exact-path POSIX `link`, not the proposed `ln` command that could descend into a racing directory. Explicit `chmod u+x` handles restrictive umasks. PowerShell optional-guidance lookup errors fall back to the manual guide without failing installation.
- All implementation tasks passed separate spec and quality reviews; the final overall reviewer found no remaining source-code issues. Automated tests never changed real host trust.
- Parent independently reran all packaging tests: **231 runs, 2,238 assertions, 0 failures/errors, 68 native Windows skips**. Focused streaming/composer regressions: **12 runs, 120 assertions, no failures/errors**. New Ruby files: **5 files, no lint offenses**.
- Parent independently reran the full Rails suite: **626 runs, 3,405 assertions, 0 failures, 1 error**, exactly the approved unavailable embedding-provider baseline. Repository-wide lint and offline security warnings are pre-existing and recorded in `docs/LOCAL_HTTPS.md`.
- **Still pending:** native macOS and Windows PowerShell 5.1/7 CI, disposable-machine image/HTTPS/assets/streaming checks, real trust import/repeat/removal, and browser/runtime checks. No suitable disposable machine was provided. Do not treat these checks as passed or merge readiness as unconditional.
- Branch and worktree are preserved as-is. No application settings/secrets were copied from the main worktree; its pre-existing local changes remain untouched.

| File | Responsibility |
| --- | --- |
| `Gemfile`, `Gemfile.lock`, `Procfile`, `Dockerfile`, `config/dockerfile.yml` | Remove Thruster; describe Puma's internal port correctly. |
| `bin/thrust` | Delete the obsolete Thruster binstub. |
| `bin/trust-caddy` | Public-root acquisition, validation, confirmation, and Linux/macOS native trust operations. |
| `bin/trust-caddy.ps1` | Equivalent Windows workflow; certificate-only elevated import. |
| `install.sh`, `install.ps1` | Download matching helper safely; print its optional command without running it. |
| `test/support/caddy_certificate_fixtures.rb` | Generate ephemeral public test certificates; never write a private key or install a root. |
| `test/packaging/caddy_puma.rb` | Dependency, startup, port, and unchanged proxy/worker/migration contract tests. |
| `test/packaging/caddy_trust_posix.rb` | Real certificate validation and mocked native shell workflow tests. |
| `test/packaging/caddy_trust_windows.rb` | Native PowerShell 5.1/7 subprocess tests with mocked import/elevation. |
| `test/packaging/caddy_trust_installers.rb` | Helper-download behavior, preservation, failures, and no automatic trust. |
| `docs/LOCAL_HTTPS.md` | Canonical setup, verification, browser, CA lifecycle, and exact-removal guide. |
| `README.md`, `CONTRIBUTING.md`, `docs/DEPLOYMENT.md` | Entry points linking to the local HTTPS guide. |
| `docs/ARCHITECTURE.md`, `docs/DIAGRAMS.md` | Remove the two current architecture claims that Rails still runs a Thruster proxy. |
| `.github/workflows/ci.yml` | Isolated trust-helper tests on Linux, macOS, and both Windows PowerShell editions. |

`Caddyfile`, `docker-compose.yml`, `config/puma.rb`, `bin/start-app`, `bin/boot`, and worker configuration should need no implementation edits. Characterize them rather than doing unrelated cleanup. Do not force `tls internal` globally or newly publish port 3000 to the host.

## Task 1: Remove the bypassed Thruster proxy

**Files:** Create `test/packaging/caddy_puma.rb`; modify `Gemfile`, `Gemfile.lock`, `Procfile`, `Dockerfile`, `config/dockerfile.yml`; delete `bin/thrust`.

- [x] **Step 1: Add the regression contract.** Create this complete test file:

```ruby
require "minitest/autorun"
require "yaml"

class CaddyPumaPackagingTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_thruster_is_not_a_dependency_or_startup_wrapper
    refute_match(/^gem ["']thruster["']/, read("Gemfile"))
    refute_match(/^    thruster \(/, read("Gemfile.lock"))
    refute File.exist?(File.join(ROOT, "bin/thrust"))
    assert_equal "web: bin/start-app\nworker: bundle exec rake solid_queue:start\n", read("Procfile")
  end

  def test_app_image_exposes_puma_without_thruster_settings
    dockerfile = read("Dockerfile")
    assert_match(/^EXPOSE 3000$/, dockerfile)
    refute_match(/^EXPOSE .*\b(?:80|443)\b/, dockerfile)
    refute_match(/^ENV HTTP_(?:IDLE|READ|WRITE)_TIMEOUT=/, dockerfile)
    assert_includes dockerfile, 'CMD ["bin/boot"]'
    assert_equal false, YAML.safe_load(read("config/dockerfile.yml")).fetch("options").fetch("thruster")
  end

  def test_caddy_keeps_its_ca_and_internal_puma_upstream
    services = YAML.safe_load(read("docker-compose.yml")).fetch("services")
    proxy = services.fetch("reverse-proxy")
    assert_equal ["80:80", "443:443"], proxy.fetch("ports")
    assert_includes proxy.fetch("volumes"), "caddy-data:/data"
    refute services.fetch("web").key?("ports")
    assert_includes read("Caddyfile"), "reverse_proxy web:3000"
    refute_includes read("Caddyfile"), "tls internal"
    assert_includes read("config/puma.rb"), 'ENV.fetch("PORT", 3000)'
    assert_equal ["CMD", "curl", "-f", "http://localhost:3000/up"],
      services.fetch("web").fetch("healthcheck").fetch("test")
  end

  def test_startup_still_prepares_the_database_and_starts_rails
    assert_equal "#!/bin/bash -e\n\nrm -f tmp/pids/server.pid\n./bin/rails db:prepare\n./bin/rails server\n",
      read("bin/start-app")
    assert_includes read("bin/boot"), 'ProcessMonitor.new("Procfile")'
    services = YAML.safe_load(read("docker-compose.yml")).fetch("services")
    assert_equal "bundle exec rails db:prepare", services.fetch("db-migrate").fetch("command")
    assert_equal "bundle exec rake solid_queue:start", services.fetch("solidq").fetch("command")
  end

  private
    def read(path)
      File.read(File.join(ROOT, path))
    end
end
```

- [x] **Step 2: Run RED.** Run `ruby test/packaging/caddy_puma.rb`. Expect failures identifying the existing Thruster dependency/wrapper and `EXPOSE 80 443`; preservation tests should pass.
- [x] **Step 3: Make only these implementation edits.** Delete the `gem "thruster"` line and `bin/thrust`. Replace `Procfile` with:

```procfile
web: bin/start-app
worker: bundle exec rake solid_queue:start
```

Delete the Dockerfile's `# Configure environment defaults` block containing the three `HTTP_*_TIMEOUT` variables. Replace its port comment and instruction with:

```dockerfile
# Caddy forwards HTTP to Puma on the internal application port.
EXPOSE 3000
```

In `config/dockerfile.yml` retain every other option and change:

```yaml
  thruster: false
```

- [x] **Step 4: Update the lockfile without upgrading other gems.** Run `bundle install`, inspect `git diff -- Gemfile.lock`, and require the diff to remove only Thruster's dependency/platform entries and any genuinely orphaned dependency. Do not run `bundle update`.
- [x] **Step 5: Run GREEN and commit.** Run `ruby test/packaging/caddy_puma.rb` and `git diff --check`. Expect all packaging tests passing, with no worker or migration edits. Stage only Task 1 paths and commit `refactor: run Puma directly behind Caddy`.

## Task 2: Add the Unix trust helper and isolated tests

**Files:** Create `test/support/caddy_certificate_fixtures.rb`, `test/packaging/caddy_trust_posix.rb`, and `bin/trust-caddy`.

- [x] **Step 1: Add ephemeral certificate fixtures.** Create this support file; it writes no private keys:

```ruby
require "openssl"

module CaddyCertificateFixtures
  def certificate_fixture(kind = :root)
    return "not a certificate\n" if kind == :malformed

    key = OpenSSL::PKey::EC.generate("prime256v1")
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = OpenSSL::X509::Name.parse("/CN=Nosia disposable test CA")
    cert.issuer = cert.subject
    cert.public_key = key
    cert.not_before = kind == :future ? Time.now + 3600 : Time.now - 3600
    cert.not_after = kind == :expired ? Time.now - 60 : Time.now + 86400
    factory = OpenSSL::X509::ExtensionFactory.new
    factory.subject_certificate = cert
    factory.issuer_certificate = cert
    ca = kind == :leaf ? "CA:FALSE" : "CA:TRUE"
    cert.add_extension(factory.create_extension("basicConstraints", ca, true))
    cert.add_extension(factory.create_extension("keyUsage", "keyCertSign,cRLSign", true))
    signer = kind == :bad_signature ? OpenSSL::PKey::EC.generate("prime256v1") : key
    cert.sign(signer, OpenSSL::Digest::SHA256.new)
    pem = cert.to_pem
    return pem + pem if kind == :multiple
    return pem + "-----BEGIN PRIVATE KEY-----\nrejected\n-----END PRIVATE KEY-----\n" if kind == :private_key
    pem
  end
end
```

- [x] **Step 2: Add the failing subprocess tests.** Create this test file. The harness loads definitions without the script's final entry call, then replaces OS boundaries—not validation—with shell functions. There is no production test-mode flag or confirmation bypass.

```ruby
require "minitest/autorun"
require "open3"
require "tmpdir"
require "fileutils"
require "pty"
require_relative "../support/caddy_certificate_fixtures"

class CaddyTrustPosixTest < Minitest::Test
  include CaddyCertificateFixtures
  ROOT = File.expand_path("../..", __dir__)
  SCRIPT = File.join(ROOT, "bin/trust-caddy")
  BOUNDARIES = <<~'SH'
    platform_name() { printf '%s\n' "${FAKE_OS:-Linux}"; }
    directory_exists() { [ "$1" = "${EXPECTED_DIR:-/usr/local/share/ca-certificates}" ]; }
    require_command() { [ "$1" != "${MISSING_TOOL:-}" ] || fail "Missing required command: $1"; }
    docker() {
      printf 'DOCKER:%s\n' "$*" >> "$LOG"
      [ "${DOCKER_FAILURE:-}" != "$*" ] || return 1
      case "$*" in
        'compose version') return 0 ;;
        'context show') printf 'default\n' ;;
        'compose ps --status running -q reverse-proxy') printf '%s' "${CONTAINER_ID-container-id}" ;;
        'compose cp '*) cp "$CERTIFICATE" "$4" ;;
        *) return 90 ;;
      esac
    }
    admin() {
      printf 'ADMIN:%s\n' "$*" >> "$LOG"
      [ "${ADMIN_FAILURE:-}" != "$1" ] || return 1
      case "$1" in
        install) cp "$4" "$INSTALLED" ;;
        security) for last do :; done; cp "$last" "$INSTALLED" ;;
        update-ca-certificates|update-ca-trust) : ;;
        *) return 91 ;;
      esac
    }
  SH
  MAIN_BOUNDARIES = <<~'SH'
    root_trusted() { return "${TRUSTED:-1}"; }
    confirm() {
      printf 'CONFIRM\n' >> "$LOG"
      [ "${ANSWER:-yes}" = yes ] || fail 'Cancelled; no trust changes.'
    }
  SH

  def setup
    @dir = Dir.mktmpdir("nosia-trust-test-")
    @fixture = File.join(@dir, "fixture.crt")
    @log = File.join(@dir, "calls.log")
    @installed = File.join(@dir, "installed.crt")
    File.write(@fixture, certificate_fixture)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_helper_exists_and_is_executable
    assert File.file?(SCRIPT), "missing Unix trust helper"
    assert File.executable?(SCRIPT)
  end

  def test_validates_a_real_self_signed_ca_and_rejects_invalid_inputs
    [:root, :leaf, :expired, :future, :bad_signature, :multiple, :private_key, :malformed].each do |kind|
      File.write(@fixture, certificate_fixture(kind))
      output, status = shell('work="$WORK"; validate_root "$CERTIFICATE"')
      assert_equal kind == :root, status.success?, "#{kind}: #{output}"
      assert_empty admin_calls
    end
  end

  def test_all_native_store_mappings
    [
      ["Linux", "/usr/local/share/ca-certificates", "update-ca-certificates"],
      ["Linux", "/etc/pki/ca-trust/source/anchors", "update-ca-trust"],
      ["Linux", "/etc/ca-certificates/trust-source/anchors", "update-ca-trust"],
      ["Darwin", "/Library/Keychains/System.keychain", "security"]
    ].each do |os, directory, tool|
      File.write(@log, "")
      output, status = shell(MAIN_BOUNDARIES + "main", "FAKE_OS" => os, "EXPECTED_DIR" => directory)
      assert status.success?, output
      assert_includes admin_calls, tool
      assert_equal OpenSSL::X509::Certificate.new(File.read(@fixture)).to_der,
        OpenSSL::X509::Certificate.new(File.read(@installed)).to_der
      calls = File.read(@log)
      assert_operator calls.index("CONFIRM"), :<, calls.index("ADMIN:")
      assert_equal 1, calls.scan("compose cp ").length
      assert_includes calls, "reverse-proxy:/data/caddy/pki/authorities/local/root.crt"
      refute_match(/root\.key|intermediate\.key/, calls)
      assert_includes output, "SHA-256"
      assert_includes output, "curl --fail https://nosia.localhost/up"
    end
  end

  def test_already_trusted_root_does_not_prompt_or_write
    output, status = shell(MAIN_BOUNDARIES + "main", "TRUSTED" => "0")
    assert status.success?, output
    assert_includes output, "already trusted"
    assert_empty admin_calls
    refute_includes File.read(@log), "CONFIRM"
  end

  def test_preflight_failures_never_write
    [
      { "MISSING_TOOL" => "docker" }, { "MISSING_TOOL" => "openssl" },
      { "MISSING_TOOL" => "update-ca-certificates" }, { "MISSING_TOOL" => "sudo" },
      { "FAKE_OS" => "Darwin", "MISSING_TOOL" => "security" }, { "FAKE_OS" => "Unsupported" },
      { "EXPECTED_DIR" => "/unsupported" }, { "CONTAINER_ID" => "" },
      { "DOCKER_FAILURE" => "compose version" }, { "DOCKER_FAILURE" => "context show" },
      { "DOCKER_FAILURE" => "compose ps --status running -q reverse-proxy" },
      { "ANSWER" => "no" }
    ].each do |environment|
      File.write(@log, "")
      output, status = shell(MAIN_BOUNDARIES + "main", environment)
      refute status.success?, "#{environment}: #{output}"
      assert_empty admin_calls
    end
    File.unlink(@fixture)
    output, status = shell(MAIN_BOUNDARIES + "main")
    refute status.success?, output
    assert_empty admin_calls
    assert_includes output, "root.crt"
  end

  def test_install_and_refresh_failures_are_reported_truthfully
    output, status = shell(MAIN_BOUNDARIES + "main", "ADMIN_FAILURE" => "install")
    refute status.success?, output
    assert_includes output, "Inspect"
    File.write(@log, "")
    output, status = shell(MAIN_BOUNDARIES + "main", "ADMIN_FAILURE" => "update-ca-certificates")
    refute status.success?, output
    assert_includes output, "anchor was written"
    refute_includes output, "System trust installed"
  end

  def test_real_confirmation_refuses_redirected_yes_blank_and_eof
    ["yes\n", "\n", ""].each do |input|
      output, status = shell("confirm", {}, input: input)
      refute status.success?, output
      assert_empty admin_calls
    end
  end

  def test_real_confirmation_accepts_only_an_interactive_yes
    ["yes\n", "no\n", "\n"].each do |input|
      output = +""
      process_status = nil
      PTY.spawn("/bin/sh", "-c", definitions + "\nconfirm") do |reader, writer, pid|
        writer.write(input)
        writer.flush
        begin
          output << reader.read
        rescue Errno::EIO
        end
        Process.wait(pid)
        process_status = $?
      end
      assert_equal input == "yes\n", process_status.success?, output
    end
  end

  def test_native_linux_trust_reads_only_the_selected_bundle
    output, status = shell('work="$WORK"; validate_root "$CERTIFICATE"; store=linux; bundle="$CERTIFICATE"; root_trusted')
    assert status.success?, output
    output, status = shell('work="$WORK"; validate_root "$CERTIFICATE"; store=linux; bundle="$WORK/absent"; root_trusted')
    refute status.success?, output
    assert_empty admin_calls
  end

  def test_native_macos_trust_requires_presence_and_native_trust
    code = <<~'SH'
      security() {
        case "$1" in
          find-certificate) cat "$CERTIFICATE" ;;
          verify-cert) return "${NATIVE_TRUST_STATUS:-0}" ;;
          *) return 92 ;;
        esac
      }
      work="$WORK"; validate_root "$CERTIFICATE"; store=macos; root_trusted
    SH
    output, status = shell(code)
    assert status.success?, output
    output, status = shell(code, "NATIVE_TRUST_STATUS" => "1")
    refute status.success?, output
    assert_empty admin_calls
  end

  private
    def definitions
      assert File.file?(SCRIPT), "missing Unix trust helper"
      source = File.read(SCRIPT)
      assert_match(/\nmain "\$@"\s*\z/, source)
      source.sub(/\nmain "\$@"\s*\z/, "\n")
    end

    def shell(body, environment = {}, input: "")
      defaults = { "WORK" => @dir, "CERTIFICATE" => @fixture, "LOG" => @log,
        "INSTALLED" => @installed, "TMPDIR" => @dir }
      stdout, stderr, status = Open3.capture3(defaults.merge(environment), "/bin/sh", "-c",
        definitions + "\n" + BOUNDARIES + "\n" + body, stdin_data: input)
      [stdout + stderr, status]
    end

    def admin_calls
      File.exist?(@log) ? File.read(@log).lines.grep(/^ADMIN:/).join : ""
    end
end
```

- [x] **Step 3: Run RED.** Run `ruby test/packaging/caddy_trust_posix.rb`. Expect “missing Unix trust helper” assertions. Fix harness syntax errors before continuing; do not create production code to mask them.
- [x] **Step 4: Create the helper's validation and store boundaries.** Write this first part of `bin/trust-caddy`; Task 2 Step 5 appends its workflow in the same task:

```sh
#!/bin/sh
set -eu

GUIDE=https://github.com/dilolabs/nosia/blob/main/docs/LOCAL_HTTPS.md
work=

fail() { printf '%s\nGuide: %s\n' "$1" "$GUIDE" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"; }
platform_name() { uname -s; }
directory_exists() { [ -d "$1" ]; }
admin() { sudo -- "$@"; }

select_store() {
  case "$(platform_name)" in
    Darwin)
      store=macos
      anchor=/Library/Keychains/System.keychain
      require_command security
      ;;
    Linux)
      store=linux
      if directory_exists /usr/local/share/ca-certificates; then
        anchor_dir=/usr/local/share/ca-certificates
        updater=update-ca-certificates
        bundle=/etc/ssl/certs/ca-certificates.crt
      elif directory_exists /etc/pki/ca-trust/source/anchors; then
        anchor_dir=/etc/pki/ca-trust/source/anchors
        updater=update-ca-trust
        bundle=/etc/pki/tls/certs/ca-bundle.crt
      elif directory_exists /etc/ca-certificates/trust-source/anchors; then
        anchor_dir=/etc/ca-certificates/trust-source/anchors
        updater=update-ca-trust
        bundle=/etc/ssl/certs/ca-certificates.crt
      else
        fail 'Unsupported Linux trust store; use the manual export/import guide.'
      fi
      require_command install
      require_command "$updater"
      ;;
    *) fail 'Unsupported host; use the platform-specific or manual trust guide.' ;;
  esac
}

validate_root() {
  source_root=$1
  public="$work/public.crt"
  [ -f "$source_root" ] && [ ! -L "$source_root" ] || fail 'Missing regular root.crt file.'
  awk '
    /^-----BEGIN CERTIFICATE-----\r?$/ { if (++starts != 1 || inside || ended) exit 1; inside=1; next }
    /^-----END CERTIFICATE-----\r?$/ { if (!inside || ++ends != 1) exit 1; inside=0; ended=1; next }
    { if (inside) { if ($0 !~ /^[A-Za-z0-9+\/=\r]+$/) exit 1 }
      else if ($0 !~ /^[[:space:]]*$/) exit 1 }
    END { if (starts != 1 || ends != 1 || inside) exit 1 }
  ' "$source_root" || fail 'Expected one public CA certificate, without private keys or other material.'
  openssl x509 -in "$source_root" -out "$public" || fail 'Malformed root certificate.'
  openssl x509 -in "$public" -noout -text > "$work/details"
  awk '/X509v3 Basic Constraints:/ { getline; if ($0 ~ /CA:TRUE/) ca=1 } END { exit !ca }' \
    "$work/details" || fail 'Certificate is not a CA.'
  subject=$(openssl x509 -in "$public" -noout -subject -nameopt RFC2253 | sed 's/^[^=]*= *//')
  issuer=$(openssl x509 -in "$public" -noout -issuer -nameopt RFC2253 | sed 's/^[^=]*= *//')
  [ "$subject" = "$issuer" ] || fail 'Certificate is not self-issued.'
  openssl verify -check_ss_sig -CAfile "$public" "$public" > "$work/verification" 2>&1 ||
    fail 'Expected a currently valid self-signed CA; check its dates/signature and OpenSSL compatibility.'
  fingerprint=$(openssl x509 -in "$public" -noout -sha256 -fingerprint | sed 's/^[^=]*=//' | tr -d ':')
  sha1=$(openssl x509 -in "$public" -noout -sha1 -fingerprint | sed 's/^[^=]*=//' | tr -d ':')
  case "$fingerprint" in ''|*[!0-9A-Fa-f]*) fail 'Invalid certificate fingerprint.' ;; esac
  [ "${#fingerprint}" -eq 64 ] || fail 'Invalid SHA-256 fingerprint length.'
  snapshot=$(cat "$public")
}

root_trusted() {
  if [ "$store" = macos ]; then
    security find-certificate -a -p /Library/Keychains/System.keychain > "$work/store.pem" 2>/dev/null || return 1
    openssl verify -CAfile "$work/store.pem" "$public" >/dev/null 2>&1 || return 1
    security verify-cert -c "$public" -p basic -l -L -k /Library/Keychains/System.keychain >/dev/null 2>&1
  else
    [ -f "$bundle" ] && openssl verify -CAfile "$bundle" "$public" >/dev/null 2>&1
  fi
}

confirm() {
  [ -t 0 ] || fail 'Interactive confirmation is required; do not pipe input into this helper.'
  printf 'Trust this CA machine-wide? Type yes to continue: '
  answer=
  IFS= read -r answer || fail 'Cancelled; no trust changes.'
  [ "$answer" = yes ] || fail 'Cancelled; no trust changes.'
}

cleanup() {
  if [ -n "$work" ]; then
    rm -f "$work/root.crt" "$work/public.crt" "$work/details" "$work/verification" "$work/store.pem"
    rmdir "$work" 2>/dev/null || :
  fi
}
```

- [x] **Step 5: Append the entry workflow.** These functions are not a new service layer; they keep source acquisition, inspection, confirmation, and native writes separately testable.

```sh
install_root() {
  # Recreate the public file from the validated in-memory snapshot, not Docker.
  printf '%s\n' "$snapshot" > "$public"
  if [ "$store" = macos ]; then
    admin security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$public" ||
      fail "Trust import failed. Inspect System Keychain and admin trust settings for SHA-1 identifier $sha1; import may have partially changed trust."
  else
    anchor="$anchor_dir/nosia-caddy-$fingerprint.crt"
    admin install -m 0644 "$public" "$anchor" ||
      fail "Anchor installation failed. Inspect $anchor before retrying; no trust refresh was attempted."
    admin "$updater" ||
      fail "The anchor was written to $anchor, but $updater failed. Remove that exact file and rerun $updater, or repair the refresh and retry."
  fi
}

main() {
  [ "$#" -eq 0 ] || fail 'Usage: bin/trust-caddy (no unattended confirmation flag).'
  for tool in docker openssl awk sed tr cat mktemp rm rmdir sudo; do require_command "$tool"; done
  select_store
  docker compose version >/dev/null 2>&1 || fail 'Docker Compose is unavailable; check Docker installation/access.'
  context=$(docker context show) || fail 'Cannot read the selected Docker context.'
  printf 'Docker context: %s\nCertificate source: reverse-proxy\n' "$context"
  printf 'Proceed only if this is your intended Caddy instance.\n'
  running=$(docker compose ps --status running -q reverse-proxy) || fail 'Cannot inspect reverse-proxy; check Docker and this Compose project.'
  [ -n "$running" ] || fail 'reverse-proxy is not running. Start Compose, inspect its logs, and retry.'
  umask 077
  work=$(mktemp -d "${TMPDIR:-/tmp}/nosia-caddy.XXXXXXXX") || fail 'Cannot create a private temporary directory.'
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  docker compose cp reverse-proxy:/data/caddy/pki/authorities/local/root.crt "$work/root.crt" ||
    fail 'Cannot copy root.crt. Check reverse-proxy logs; Caddy may not have generated its local CA yet.'
  validate_root "$work/root.crt"
  openssl x509 -in "$public" -noout -subject -issuer -dates
  printf 'SHA-256 fingerprint: %s\n' "$fingerprint"
  printf 'Removal identifier (macOS SHA-1): %s\n' "$sha1"
  printf 'This root can authorize other hostnames, not only nosia.localhost. Protect Caddy data and Docker access.\n'
  if root_trusted; then
    printf 'This exact root is already trusted; no changes made.\n'
  else
    confirm
    install_root
    printf 'System trust installed for SHA-256 %s.\n' "$fingerprint"
    if [ "$store" = linux ]; then printf 'Installed anchor: %s\n' "$anchor"; fi
  fi
  printf 'Verify separately: curl --fail https://nosia.localhost/up\n'
  printf 'Browsers/runtimes may need a separate import. Guide: %s\n' "$GUIDE"
}

main "$@"
```

- [x] **Step 6: Set mode and run GREEN.** Run `chmod +x bin/trust-caddy`, `sh -n bin/trust-caddy`, and `ruby test/packaging/caddy_trust_posix.rb`. Expect passing real-certificate validation, all three Linux mappings, macOS routing, cancellation, repeat-run, and partial-failure tests. No real `sudo`, trust import, Docker daemon, or CA-store write may occur in the tests.
- [x] **Step 7: Check cleanup explicitly.** Extend `test_all_native_store_mappings` with the assertion below and repeat the test. The expected set contains fixture, log, and fake installed certificate only:

```ruby
assert_equal %w[ calls.log fixture.crt installed.crt ], Dir.children(@dir).sort
```

- [x] **Step 8: Commit.** Stage only Task 2 files and commit `feat: add opt-in Linux and macOS Caddy trust helper`.

## Task 3: Add the native Windows helper without elevating Docker

**Files:** Create `test/packaging/caddy_trust_windows.rb` and `bin/trust-caddy.ps1`.

The root's self-signature must be verified, not inferred from equal subject/issuer names. Use `CryptVerifyCertificateSignatureEx` from Windows' built-in `crypt32.dll`; it supports the ECDSA certificates Caddy actually generates. An `X509Chain` with unknown-root errors ignored is not a substitute for checking the root signature.

- [x] **Step 1: Add the native subprocess tests.** Created, including portable missing-feature RED assertions. Native execution under both Windows editions remains pending. The `Start-Process` tripwire prevents unintended UAC elevation even if another mock is omitted.

```ruby
require "minitest/autorun"
require "open3"
require "tmpdir"
require "fileutils"
require_relative "../support/caddy_certificate_fixtures"

class CaddyTrustWindowsTest < Minitest::Test
  include CaddyCertificateFixtures
  ROOT = File.expand_path("../..", __dir__)
  SCRIPT = File.join(ROOT, "bin/trust-caddy.ps1")
  MOCKS = <<~'PS'
    function docker { throw 'Use the mocked Docker boundary.' }
    function Invoke-CaddyDocker {
      param([string[]]$Arguments)
      $call = $Arguments -join ' '
      Add-Content -LiteralPath $env:LOG -Value "DOCKER:$call"
      if ($env:DOCKER_FAILURE -eq $call) { throw "Docker failed: $call" }
      switch ($call) {
        'compose version' { return 'test compose' }
        'context show' { return 'desktop-linux' }
        'compose ps --status running -q reverse-proxy' {
          if ($env:NO_CONTAINER -eq '1') { return '' }
          return 'container-id'
        }
        default {
          if ($Arguments[0] -ne 'compose' -or $Arguments[1] -ne 'cp') { throw 'Unexpected Docker call' }
          [IO.File]::Copy($env:FIXTURE, $Arguments[-1])
        }
      }
    }
    function Test-CaddyTrusted { param($Certificate) return $env:ALREADY_TRUSTED -eq '1' }
    function Confirm-CaddyTrust {
      Add-Content -LiteralPath $env:LOG -Value 'CONFIRM'
      if ($env:ANSWER -eq 'no') { throw 'Cancelled; no trust changes.' }
    }
    function Invoke-CaddyElevatedImport {
      param([string]$ScriptText)
      Add-Content -LiteralPath $env:LOG -Value 'IMPORT'
      [IO.File]::WriteAllText($env:IMPORT_SCRIPT, $ScriptText)
      if ($env:IMPORT_FAILURE -eq '1') { throw 'Import failed; inspect LocalMachine\Root for partial changes.' }
    }
  PS

  def setup
    skip "native Windows only" unless Gem.win_platform?
    @dir = Dir.mktmpdir("nosia-trust-tests-")
    @fixture = File.join(@dir, "fixture.crt")
    @log = File.join(@dir, "calls.log")
    @import_script = File.join(@dir, "import.ps1")
    File.write(@fixture, certificate_fixture)
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir
  end

  def test_validates_real_ecdsa_ca_and_rejects_invalid_inputs
    [:root, :leaf, :expired, :future, :bad_signature, :multiple, :private_key, :malformed].each do |kind|
      File.write(@fixture, certificate_fixture(kind))
      output, status = windows('Get-CaddyCertificate -Path $env:FIXTURE | Out-Null')
      assert_equal kind == :root, status.success?, "#{kind}: #{output}"
      assert_empty calls
    end
  end

  def test_workflow_confirms_once_and_passes_only_immutable_public_data_to_elevation
    output, status = windows(MOCKS + "\nInvoke-CaddyTrust")
    assert status.success?, output
    assert_operator calls.index("CONFIRM"), :<, calls.index("IMPORT")
    assert_equal 1, calls.scan("compose cp ").length
    assert_includes calls, "reverse-proxy:/data/caddy/pki/authorities/local/root.crt"
    cert = OpenSSL::X509::Certificate.new(File.read(@fixture))
    child = File.read(@import_script)
    assert_includes child, [cert.to_der].pack("m0")
    assert_includes child, "Cert:\\LocalMachine\\Root"
    refute_match(/docker|Invoke-CaddyTrust|PRIVATE KEY/i, child)
    assert_includes output, OpenSSL::Digest::SHA256.hexdigest(cert.to_der).upcase
    assert_includes output, "curl.exe --fail https://nosia.localhost/up"
    assert_empty Dir.glob(File.join(@dir, "nosia-caddy-*"))
  end

  def test_duplicate_does_not_prompt_or_import
    output, status = windows(MOCKS + "\nInvoke-CaddyTrust", "ALREADY_TRUSTED" => "1")
    assert status.success?, output
    assert_includes output, "already trusted"
    refute_match(/CONFIRM|IMPORT/, calls)
  end

  def test_docker_missing_root_cancellation_and_import_failures
    [
      { "DOCKER_FAILURE" => "compose version" }, { "DOCKER_FAILURE" => "context show" },
      { "DOCKER_FAILURE" => "compose ps --status running -q reverse-proxy" },
      { "DOCKER_FAILURE" => "compose cp reverse-proxy:/data/caddy/pki/authorities/local/root.crt" },
      { "NO_CONTAINER" => "1" }, { "ANSWER" => "no" }, { "IMPORT_FAILURE" => "1" }
    ].each do |environment|
      File.write(@log, "")
      # cp includes a random destination; use the explicit override for that failure.
      overrides = environment.values.any? { |value| value.start_with?("compose cp ") } ?
        "function Invoke-CaddyDocker { param([string[]]$Arguments) if ($Arguments[1] -eq 'cp') { throw 'root.crt unavailable' }; return 'available' }" : ""
      output, status = windows(MOCKS + "\n" + overrides + "\nInvoke-CaddyTrust", environment)
      refute status.success?, "#{environment}: #{output}"
      refute_includes calls, "IMPORT" unless environment.key?("IMPORT_FAILURE")
      refute_includes output, "System trust installed"
      assert_empty Dir.glob(File.join(@dir, "nosia-caddy-*"))
    end
    File.write(@log, "")
    File.unlink(@fixture)
    output, status = windows(MOCKS + "\nInvoke-CaddyTrust")
    refute status.success?, output
    refute_includes calls, "IMPORT"
  end

  def test_missing_docker_and_unsupported_host_fail_before_import
    code = "function Get-Command { throw 'Missing docker' }; Invoke-CaddyTrust"
    output, status = windows(code)
    refute status.success?, output
    output, status = windows("Invoke-CaddyTrust", "OS" => "NotWindows")
    refute status.success?, output
    assert_empty calls
  end

  def test_real_confirmation_refuses_redirected_input
    output, status = windows("Confirm-CaddyTrust")
    refute status.success?, output
    assert_includes output, "Interactive"
    assert_empty calls
  end

  def test_confirmation_only_accepts_yes_from_interactive_ui
    ["yes", "no", ""].each do |answer|
      body = <<~'PS'
        function Test-CaddyInteractive { return $true }
        function Read-Host { return $env:ANSWER }
        Confirm-CaddyTrust
      PS
      output, status = windows(body, "ANSWER" => answer)
      assert_equal answer == "yes", status.success?, output
    end
  end

  def test_native_duplicate_lookup_compares_certificate_bytes_not_subject
    code = <<~'PS'
      $cert = Get-CaddyCertificate -Path $env:FIXTURE
      function Get-CaddyRootCertificates { return $cert }
      if (-not (Test-CaddyTrusted -Certificate $cert)) { throw 'Expected exact root match' }
      function Get-CaddyRootCertificates { return @() }
      if (Test-CaddyTrusted -Certificate $cert) { throw 'Unexpected root match' }
    PS
    output, status = windows(code)
    assert status.success?, output
  end

  def test_encoded_import_child_is_testable_without_real_trust_writes
    code = <<~'PS'
      function Import-Certificate {
        param($FilePath, $CertStoreLocation, $ErrorAction)
        if ($CertStoreLocation -ne 'Cert:\LocalMachine\Root') { throw 'Wrong store' }
        $cert = [Security.Cryptography.X509Certificates.X509Certificate2]::new([IO.File]::ReadAllBytes($FilePath))
        [IO.File]::WriteAllText($env:LOG, [Convert]::ToBase64String($cert.RawData))
      }
      $cert = Get-CaddyCertificate -Path $env:FIXTURE
      & ([scriptblock]::Create((New-CaddyImportScript -Certificate $cert)))
    PS
    output, status = windows(code)
    assert status.success?, output
    assert_equal [OpenSSL::X509::Certificate.new(File.read(@fixture)).to_der].pack("m0"), File.read(@log)
  end

  def test_elevation_adapter_only_runs_the_encoded_import_and_checks_exit_status
    code = <<~'PS'
      function Start-Process {
        param($FilePath, $ArgumentList, $Verb, [switch]$Wait, [switch]$PassThru, $ErrorAction)
        if ($Verb -ne 'RunAs' -or -not $Wait -or -not $PassThru) { throw 'Unsafe elevation adapter' }
        if ($ArgumentList -notcontains '-EncodedCommand') { throw 'Missing encoded import' }
        $decoded = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($ArgumentList[-1]))
        if ($decoded -ne 'certificate-only') { throw 'Unexpected child payload' }
        return [pscustomobject]@{ ExitCode = [int]$env:CHILD_EXIT }
      }
      Invoke-CaddyElevatedImport -ScriptText 'certificate-only'
    PS
    output, status = windows(code, "CHILD_EXIT" => "0")
    assert status.success?, output
    output, status = windows(code, "CHILD_EXIT" => "1")
    refute status.success?, output
  end

  private
    def windows(body, environment = {})
      assert File.file?(SCRIPT), "missing Windows trust helper"
      harness = File.join(@dir, "harness.ps1")
      quoted_script = SCRIPT.tr("\\", "/").gsub("'", "''")
      File.write(harness, <<~PS)
        $ErrorActionPreference = 'Stop'
        . '#{quoted_script}'
        function Start-Process { throw 'Tests must never elevate' }
        try {
          #{body}
        } catch {
          [Console]::Error.WriteLine($_.Exception.Message)
          exit 1
        }
      PS
      defaults = { "FIXTURE" => @fixture, "LOG" => @log, "IMPORT_SCRIPT" => @import_script,
        "TEMP" => @dir, "TMP" => @dir }
      engine = ENV.fetch("CADDY_TEST_POWERSHELL", "pwsh")
      stdout, stderr, status = Open3.capture3(defaults.merge(environment), engine, "-NoProfile", "-File", harness)
      [stdout + stderr, status]
    end

    def calls
      File.exist?(@log) ? File.read(@log) : ""
    end
end
```

- [ ] **Step 2: Run RED on Windows.** In PowerShell run `$env:CADDY_TEST_POWERSHELL='powershell'; ruby test/packaging/caddy_trust_windows.rb`, then repeat with `'pwsh'`. Expect “missing Windows trust helper”, not an OpenSSL or Ruby setup error. On Linux the file should report native-Windows skips; that is not Windows verification.
- [x] **Step 3: Write validation and native read boundaries.** Create the first part of `bin/trust-caddy.ps1`:

```powershell
# Opt-in host trust for the current Compose project's Caddy local CA.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:CaddyGuide = 'https://github.com/dilolabs/nosia/blob/main/docs/LOCAL_HTTPS.md'

function Get-CaddyFingerprint {
    param([Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Certificate.RawData)).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Test-CaddyRootSignature {
    param([Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)
    if (-not ('Nosia.CaddySignature' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Nosia {
    public static class CaddySignature {
        [DllImport("crypt32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CryptVerifyCertificateSignatureEx(
            IntPtr provider, uint encoding, uint subjectType, IntPtr subject,
            uint issuerType, IntPtr issuer, uint flags, IntPtr extra);
    }
}
'@
    }
    return [Nosia.CaddySignature]::CryptVerifyCertificateSignatureEx(
        [IntPtr]::Zero, 1, 2, $Certificate.Handle, 2, $Certificate.Handle, 0, [IntPtr]::Zero)
}

function Get-CaddyCertificate {
    param([string]$Path)
    $pem = [IO.File]::ReadAllText($Path)
    $match = [regex]::Match($pem, '\A\s*-----BEGIN CERTIFICATE-----\s*(?<data>[A-Za-z0-9+/=\r\n]+)\s*-----END CERTIFICATE-----\s*\z')
    if (-not $match.Success) { throw 'Expected one public CA certificate, without private keys or other material.' }
    $der = [Convert]::FromBase64String($match.Groups['data'].Value)
    $cert = [Security.Cryptography.X509Certificates.X509Certificate2]::new($der)
    try {
        if ([Convert]::ToBase64String($der) -ne [Convert]::ToBase64String($cert.RawData)) { throw 'Unexpected trailing certificate data.' }
        $extension = $cert.Extensions['2.5.29.19']
        if ($null -eq $extension) { throw 'Certificate lacks CA basic constraints.' }
        $constraints = [Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($extension, $extension.Critical)
        if (-not $constraints.CertificateAuthority -or $cert.HasPrivateKey) { throw 'Expected a public CA certificate.' }
        $now = [DateTime]::UtcNow
        if ($now -lt $cert.NotBefore.ToUniversalTime() -or $now -gt $cert.NotAfter.ToUniversalTime()) { throw 'Certificate is not currently valid.' }
        if ([Convert]::ToBase64String($cert.SubjectName.RawData) -ne [Convert]::ToBase64String($cert.IssuerName.RawData)) { throw 'Certificate is not self-issued.' }
        if (-not (Test-CaddyRootSignature -Certificate $cert)) { throw 'Certificate self-signature is invalid.' }
        return $cert
    } catch {
        $cert.Dispose()
        throw
    }
}

function Invoke-CaddyDocker {
    param([string[]]$Arguments)
    & docker @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Docker failed: $($Arguments -join ' '). Check Docker access, reverse-proxy logs, and root.crt availability." }
}

function Get-CaddyRootCertificates {
    Get-ChildItem -Path 'Cert:\LocalMachine\Root' -ErrorAction Stop
}

function Test-CaddyTrusted {
    param([Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)
    $fingerprint = Get-CaddyFingerprint -Certificate $Certificate
    $matches = @(Get-CaddyRootCertificates | Where-Object { (Get-CaddyFingerprint -Certificate $_) -eq $fingerprint })
    return $matches.Count -gt 0
}

function Test-CaddyInteractive {
    return [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
}

function Confirm-CaddyTrust {
    if (-not (Test-CaddyInteractive)) { throw 'Interactive confirmation is required; do not pipe input into this helper.' }
    if ((Read-Host 'Trust this CA machine-wide? Type yes to continue') -cne 'yes') { throw 'Cancelled; no trust changes.' }
}
```

- [x] **Step 4: Append the certificate-only elevation adapter and workflow.** The immutable DER bytes and their confirmed SHA-256 are embedded as base64/hex, never shell-interpolated file paths. Only this import runs as administrator:

```powershell
function New-CaddyImportScript {
    param([Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)
    $template = @'
$ErrorActionPreference = 'Stop'
$path = $null
$locked = $null
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $bytes = [Convert]::FromBase64String('__DER__')
    $fingerprint = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '')
    if ($fingerprint -ne '__SHA256__') { throw 'Confirmed certificate fingerprint mismatch.' }
    $path = Join-Path ([IO.Path]::GetTempPath()) ('nosia-caddy-' + [Guid]::NewGuid().ToString('N') + '.cer')
    [IO.File]::WriteAllBytes($path, $bytes)
    # Lock against modification/deletion, then verify the locked file itself.
    $locked = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $lockedFingerprint = [BitConverter]::ToString($sha.ComputeHash($locked)).Replace('-', '')
    if ($lockedFingerprint -ne '__SHA256__') { throw 'Import file does not match the confirmed certificate.' }
    Import-Certificate -FilePath $path -CertStoreLocation 'Cert:\LocalMachine\Root' -ErrorAction Stop | Out-Null
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
} finally {
    $sha.Dispose()
    if ($null -ne $locked) { $locked.Dispose() }
    if ($null -ne $path -and [IO.File]::Exists($path)) { Remove-Item -LiteralPath $path -Force }
}
exit 0
'@
    return $template.Replace('__DER__', [Convert]::ToBase64String($Certificate.RawData)).Replace('__SHA256__', (Get-CaddyFingerprint -Certificate $Certificate))
}

function Invoke-CaddyElevatedImport {
    param([string]$ScriptText)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ScriptText))
    $engine = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $process = Start-Process -FilePath $engine -Verb RunAs -Wait -PassThru -ErrorAction Stop -ArgumentList @(
        '-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded
    )
    if ($process.ExitCode -ne 0) { throw 'Import failed or partially completed; inspect the exact thumbprint in LocalMachine\Root before retrying.' }
}

function Invoke-CaddyTrust {
    if ($env:OS -ne 'Windows_NT') { throw 'Use bin/trust-caddy on Linux/macOS.' }
    Get-Command docker -ErrorAction Stop | Out-Null
    $directory = $null
    $certificate = $null
    try {
        Invoke-CaddyDocker -Arguments @('compose', 'version') | Out-Null
        $context = (Invoke-CaddyDocker -Arguments @('context', 'show')) -join ''
        Write-Host "Docker context: $context`nCertificate source: reverse-proxy"
        Write-Host 'Proceed only if this is your intended Caddy instance.'
        $running = (Invoke-CaddyDocker -Arguments @('compose', 'ps', '--status', 'running', '-q', 'reverse-proxy')) -join ''
        if ([string]::IsNullOrWhiteSpace($running)) { throw 'reverse-proxy is not running. Start Compose, check its logs, and retry.' }
        $directory = Join-Path ([IO.Path]::GetTempPath()) ('nosia-caddy-' + [Guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($directory) | Out-Null
        $path = Join-Path $directory 'root.crt'
        Invoke-CaddyDocker -Arguments @('compose', 'cp', 'reverse-proxy:/data/caddy/pki/authorities/local/root.crt', $path) | Out-Null
        $certificate = Get-CaddyCertificate -Path $path
        $fingerprint = Get-CaddyFingerprint -Certificate $certificate
        Write-Host "Subject: $($certificate.Subject)`nIssuer: $($certificate.Issuer)"
        Write-Host "Valid: $($certificate.NotBefore.ToUniversalTime().ToString('o')) through $($certificate.NotAfter.ToUniversalTime().ToString('o'))"
        Write-Host "SHA-256 fingerprint: $fingerprint"
        Write-Host "Windows removal thumbprint (SHA-1 identifier): $($certificate.Thumbprint)"
        Write-Host 'This root can authorize other hostnames, not only nosia.localhost. Protect Caddy data and Docker access.'
        if (Test-CaddyTrusted -Certificate $certificate) {
            Write-Host 'This exact root is already trusted; no changes made.'
        } else {
            Confirm-CaddyTrust
            try {
                Invoke-CaddyElevatedImport -ScriptText (New-CaddyImportScript -Certificate $certificate)
            } catch {
                throw "Elevation/import failed: $($_.Exception.Message) Inspect LocalMachine\Root for exact thumbprint $($certificate.Thumbprint); trust may have partially changed."
            }
            Write-Host "System trust installed for SHA-256 $fingerprint."
        }
        Write-Host "Verify separately: curl.exe --fail https://nosia.localhost/up"
        Write-Host "Browsers/runtimes may need a separate import. Guide: $script:CaddyGuide"
    } finally {
        if ($null -ne $certificate) { $certificate.Dispose() }
        if ($null -ne $directory -and [IO.Directory]::Exists($directory)) { Remove-Item -LiteralPath $directory -Recurse -Force }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try { Invoke-CaddyTrust; exit 0 }
    catch { [Console]::Error.WriteLine("$($_.Exception.Message)`nGuide: $script:CaddyGuide"); exit 1 }
}
```

- [ ] **Step 5: Run GREEN in both editions.** Run the two Task 3 Step 2 commands again. Expect actual ECDSA signature validation and all mocked workflow/import/elevation tests to pass without a UAC dialog or trust-store modification. If Windows is unavailable, record it as unverified and require the native CI job in Task 6 before release.
- [x] **Step 6: Commit.** Stage the two Task 3 paths and commit `feat: add opt-in Windows Caddy trust helper`.

## Task 4: Distribute helpers through the existing installers

**Files:** Create `test/packaging/caddy_trust_installers.rb`; modify only helper-download and final-guidance portions of `install.sh` and `install.ps1`.

- [x] **Step 1: Add isolated downloader tests.** Create this file; it extracts only the new downloader function, so testing never runs Docker installation, model selection, or the existing installer entry point.

```ruby
require "minitest/autorun"
require "open3"
require "tmpdir"
require "fileutils"

class CaddyTrustInstallersTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def setup
    @dir = Dir.mktmpdir("nosia installer tests ")
    @log = File.join(@dir, "calls.log")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_shell_downloader_preserves_existing_files_and_publishes_only_complete_helpers
    skip "POSIX host only" if Gem.win_platform?
    target = File.join(@dir, "bin/trust-caddy")
    output, status = run_shell("success")
    assert status.success?, output
    assert File.executable?(target)
    assert_equal "#!/bin/sh\nprintf 'EXECUTED\\n' >> \"$LOG\"\n", File.read(target)
    assert_empty Dir.glob(File.join(@dir, "bin/.trust-caddy.*"))
    refute_includes File.read(@log), "EXECUTED"
    File.write(target, "user-owned helper\n")
    File.write(@log, "")
    output, status = run_shell("success")
    assert status.success?, output
    assert_equal "user-owned helper\n", File.read(target)
    assert_equal "", File.read(@log)
    File.unlink(target)
    %w[ failure empty ].each do |mode|
      output, status = run_shell(mode)
      assert status.success?, output
      assert_includes output, "Warning"
      refute File.exist?(target)
      assert_empty Dir.glob(File.join(@dir, "bin/.trust-caddy.*"))
    end
  end

  def test_windows_downloader_preserves_existing_files_and_publishes_only_complete_helpers
    skip "native Windows only" unless Gem.win_platform?
    target = File.join(@dir, "bin/trust-caddy.ps1")
    output, status = run_windows("success")
    assert status.success?, output
    assert_equal "Add-Content -LiteralPath $env:LOG -Value 'EXECUTED'", File.read(target)
    refute_includes File.read(@log), "EXECUTED"
    assert_empty Dir.glob(File.join(@dir, "bin/.trust-caddy.*"))
    File.write(target, "user-owned helper")
    File.write(@log, "")
    output, status = run_windows("success")
    assert status.success?, output
    assert_equal "user-owned helper", File.read(target)
    assert_equal "", File.read(@log)
    File.unlink(target)
    %w[ failure empty ].each do |mode|
      output, status = run_windows(mode)
      assert status.success?, output
      assert_includes output, "Warning"
      refute File.exist?(target)
      assert_empty Dir.glob(File.join(@dir, "bin/.trust-caddy.*"))
    end
  end

  def test_installers_distribute_but_never_execute_trust_helpers
    shell = File.read(File.join(ROOT, "install.sh"))
    ps = File.read(File.join(ROOT, "install.ps1"))
    assert_match(/^  download_caddy_trust_helper$/, shell)
    assert_match(/^    Download-CaddyTrustHelper$/, ps)
    assert_includes shell, "After startup, optionally run: bin/trust-caddy"
    assert_includes ps, 'After startup, optionally run: .\bin\trust-caddy.ps1'
    refute_match(/^\s*(?:\.\/)?bin\/trust-caddy\s*$/, shell)
    refute_match(/^\s*(?:&\s*)?\.\\bin\\trust-caddy\.ps1\s*$/, ps)
    refute_match(/add-trusted-cert|Import-Certificate|update-ca-certificates|Invoke-CaddyTrust/, shell + ps)
  end

  private
    def definition(file, pattern)
      match = File.read(File.join(ROOT, file)).match(pattern)
      refute_nil match, "missing helper downloader in #{file}"
      match[0]
    end

    def run_shell(mode)
      function = definition("install.sh", /^download_caddy_trust_helper\(\) \{\n.*?^\}/m)
      fake = <<~'SH'
        curl() {
          printf 'REQUEST\n' >> "$LOG"
          case "$MODE" in
            failure) printf partial > "$4"; return 1 ;;
            empty) : > "$4" ;;
            success) printf '%s\n' '#!/bin/sh' 'printf '\''EXECUTED\n'\'' >> "$LOG"' > "$4" ;;
          esac
        }
      SH
      stdout, stderr, status = Open3.capture3({ "MODE" => mode, "LOG" => @log }, "/bin/sh", "-c",
        "set -eu\n" + function + "\n" + fake + "\ndownload_caddy_trust_helper", chdir: @dir)
      [stdout + stderr, status]
    end

    def run_windows(mode)
      function = definition("install.ps1", /^function Download-CaddyTrustHelper \{\n.*?^\}/m)
      path = File.join(@dir, "downloader-test.ps1")
      File.write(path, function + "\n" + <<~'PS')
        $ErrorActionPreference = 'Stop'
        function Invoke-WebRequest {
          param($Uri, $OutFile, $ErrorAction)
          Add-Content -LiteralPath $env:LOG -Value 'REQUEST'
          switch ($env:MODE) {
            failure { [IO.File]::WriteAllText($OutFile, 'partial'); throw 'download failed' }
            empty { [IO.File]::WriteAllText($OutFile, '') }
            success { [IO.File]::WriteAllText($OutFile, 'Add-Content -LiteralPath $env:LOG -Value ''EXECUTED''') }
          }
        }
        Download-CaddyTrustHelper
      PS
      engine = ENV.fetch("CADDY_TEST_POWERSHELL", "pwsh")
      stdout, stderr, status = Open3.capture3({ "MODE" => mode, "LOG" => @log }, engine,
        "-NoProfile", "-File", path, chdir: @dir)
      [stdout + stderr, status]
    end
end
```

- [x] **Step 2: Run RED.** Run `ruby test/packaging/caddy_trust_installers.rb`. Expect missing-downloader failures, with the other platform's behavior test skipped. Native Windows repeats remain pending.
- [x] **Step 3: Add the complete POSIX downloader before `# Main installation` in `install.sh`.** The hard-link publication is atomic and refuses to overwrite an existing destination, including a concurrently created file. The committed version uses `link`, not the superseded `ln` example below:

```sh
download_caddy_trust_helper() {
  helper=bin/trust-caddy
  guide=https://github.com/dilolabs/nosia/blob/main/docs/LOCAL_HTTPS.md
  if [ -e "$helper" ] || [ -L "$helper" ]; then
    echo "Keeping existing $helper"
    return 0
  fi
  if ! mkdir -p bin; then
    echo "Warning: Cannot create bin for the optional trust helper. Guide: $guide" >&2
    return 0
  fi
  staged=$(mktemp bin/.trust-caddy.XXXXXXXX) || {
    echo "Warning: Cannot stage optional trust helper. Guide: $guide" >&2
    return 0
  }
  if curl -fsSL https://raw.githubusercontent.com/dilolabs/nosia/main/bin/trust-caddy -o "$staged" &&
      [ -s "$staged" ] && chmod +x "$staged" && ln "$staged" "$helper"; then
    echo "Downloaded optional $helper; it has not been run."
  else
    echo "Warning: Optional trust helper was not installed; existing files were preserved. Guide: $guide" >&2
  fi
  rm -f "$staged"
}
```

Replace only the final `echo "Setup complete..."` inside `do_install` with:

```sh
  download_caddy_trust_helper
  echo "Setup complete. Start with: docker compose up -d"
  if [ -f bin/trust-caddy ]; then
    echo "After startup, optionally run: bin/trust-caddy"
  else
    echo "Optional local HTTPS trust guide: https://github.com/dilolabs/nosia/blob/main/docs/LOCAL_HTTPS.md"
  fi
```

- [x] **Step 4: Add the complete Windows downloader before `# Main installation` in `install.ps1`.** `File.Move` with two arguments refuses to overwrite an existing target on PowerShell 5.1 and 7:

```powershell
function Download-CaddyTrustHelper {
    $target = Join-Path (Get-Location).Path 'bin\trust-caddy.ps1'
    $guide = 'https://github.com/dilolabs/nosia/blob/main/docs/LOCAL_HTTPS.md'
    if (Test-Path -LiteralPath $target) {
        Write-Host "Keeping existing $target"
        return
    }
    $staged = $null
    try {
        $directory = Split-Path -Parent $target
        [IO.Directory]::CreateDirectory($directory) | Out-Null
        $staged = Join-Path $directory ('.trust-caddy.' + [Guid]::NewGuid().ToString('N'))
        Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/dilolabs/nosia/main/bin/trust-caddy.ps1' -OutFile $staged -ErrorAction Stop
        if (([IO.FileInfo]::new($staged)).Length -eq 0) { throw 'Empty helper download' }
        [IO.File]::Move($staged, $target)
        Write-Host "Downloaded optional $target; it has not been run."
    } catch {
        Write-Host "Warning: Optional trust helper was not installed; existing files were preserved. $($_.Exception.Message) Guide: $guide"
    } finally {
        if ($null -ne $staged -and [IO.File]::Exists($staged)) { Remove-Item -LiteralPath $staged -Force }
    }
}
```

Replace only the final `Write-Host "Setup complete..."` inside `Do-Install` with:

```powershell
    Download-CaddyTrustHelper
    Write-Host "Setup complete. Start with: docker compose up -d"
    if (Test-Path -LiteralPath '.\bin\trust-caddy.ps1') {
        Write-Host 'After startup, optionally run: .\bin\trust-caddy.ps1'
    } else {
        Write-Host 'Optional local HTTPS trust guide: https://github.com/dilolabs/nosia/blob/main/docs/LOCAL_HTTPS.md'
    }
```

- [x] **Step 5: Run available GREEN checks and commit.** Shell, portable PowerShell mocks, packaging, and syntax checks passed; native Windows runs remain pending. No network, Docker installation, or real helper execution occurred in the tests. Committed only Task 4 paths.

## Task 5: Document local trust, verification, and exact removal

**Files:** Create `docs/LOCAL_HTTPS.md`; modify `README.md:142-150`, `CONTRIBUTING.md:60-70`, `docs/DEPLOYMENT.md` before its Caddy production example, `docs/ARCHITECTURE.md:810-814`, and `docs/DIAGRAMS.md:40`; extend `test/packaging/caddy_puma.rb`.

- [x] **Step 1: Add the documentation contract before writing the guide.** Add this public test method inside `CaddyPumaPackagingTest`:

```ruby
def test_local_https_documentation_covers_all_platforms_without_normalizing_insecure_requests
  path = File.join(ROOT, "docs/LOCAL_HTTPS.md")
  assert File.file?(path), "missing local HTTPS guide"
  guide = File.read(path)
  ["bin/trust-caddy", "trust-caddy.ps1", "LocalMachine", "System Keychain",
   "update-ca-certificates", "update-ca-trust", "Firefox", "Chrome", "WSL",
   "caddy-data", "root.crt", "SHA-256", "SHA-1", "Remove-Item",
   "remove-trusted-cert", "curl.exe --fail", "curl --fail"].each do |term|
    assert_includes guide, term
  end
  %w[ README.md CONTRIBUTING.md docs/DEPLOYMENT.md ].each do |path|
    assert_includes read(path), "LOCAL_HTTPS.md"
  end
  refute_includes read("docs/ARCHITECTURE.md"), "- Thruster HTTP/2 proxy"
  refute_includes read("docs/DIAGRAMS.md"), "Puma + Thruster"
end
```

- [x] **Step 2: Run RED.** Run `ruby test/packaging/caddy_puma.rb`. Expect only the missing guide/link test to fail; preserve the earlier proxy/startup contract.
- [x] **Step 3: Write the complete local guide below.** Shell variables asking the reader for an actual fingerprint/path are interactive inputs, not unresolved plan details. Do not replace them with broad certificate-subject deletion commands.

````markdown
# Trusted local HTTPS

Nosia uses Caddy → Puma. Caddy terminates HTTPS and forwards HTTP to Puma on the private Compose network at `web:3000`. Thruster is not required.

For `nosia.localhost`, Caddy creates its own local certificate authority (CA). Its root is self-signed; the server certificate is signed by that CA. The root must be trusted by each client that connects. Docker cannot install host trust by installing trust inside a container.

## Before installing trust

Start Nosia from its Compose project directory:

```sh
docker compose up -d
docker compose logs reverse-proxy
docker context show
```

Confirm this is your intended Docker engine and Caddy instance. Do not install a root obtained from an unfamiliar Docker context. The helpers use the current Compose configuration, including its normal environment/project selection.

Trusting a root CA grants it authority for hostnames beyond `nosia.localhost`. Protect Docker access and the `caddy-data` volume: it contains the private CA keys. Export only `root.crt`, never a private key or the whole PKI directory.

## Linux and macOS

Prerequisites: Docker Compose, a compatible OpenSSL command supporting `verify -check_ss_sig`, standard Unix tools, `sudo`, and the native trust-store tool. Debian/Ubuntu use `update-ca-certificates`; Fedora/RHEL and Arch use `update-ca-trust`; macOS uses `security` and System Keychain. Install missing dependencies through your normal package manager; the helper does not install them.

Run as your normal user, not with `sudo` around the whole command:

```sh
bin/trust-caddy
```

Review the Docker context, certificate identity, validity dates, and SHA-256 fingerprint. Type `yes` only if you intend to trust this CA. The helper requests administrator privileges only for trust-store writes. Blank input, refusal, and redirected input do not install trust.

Save the printed SHA-256 fingerprint, Linux anchor path, and (on macOS) SHA-1 removal identifier. The SHA-1 value identifies an existing certificate for native removal; it is not the security fingerprint used for confirmation.

## Windows

Use native Windows PowerShell 5.1 or PowerShell 7 with Docker Desktop/Compose available:

```powershell
.\bin\trust-caddy.ps1
```

Run in a normal PowerShell session. Review the identity and SHA-256 fingerprint, then type `yes`. Only the certificate import prompts for UAC; Docker is not rerun as administrator. The destination is `Cert:\LocalMachine\Root`. Save the printed Windows certificate thumbprint (SHA-1 identifier) for exact removal later.

If local script policy blocks a downloaded file, inspect it first and follow your organization's script-signing/unblocking policy. Do not disable execution policy globally. The helper does not change it.

Windows and WSL have separate stores. Running the Linux helper in WSL does not configure Windows browsers; running the Windows helper does not configure Linux clients in WSL.

## Verify separately

On Linux/macOS:

```sh
curl --fail https://nosia.localhost/up
```

On Windows:

```powershell
curl.exe --fail https://nosia.localhost/up
```

Use `curl.exe`, not PowerShell's possible `curl` alias. Do not add `-k`: that disables the verification being tested. An HTTP error from the app is different from a certificate-verification failure.

Some curl builds, browsers, or language runtimes use their own CA bundle instead of the OS store. A successful system import does not promise that every client trusts the root. Restart the browser if needed. Firefox and Chrome may require importing the public `root.crt` into their certificate-authority settings or enabling an organization-approved system-trust policy. Python, Ruby, Java, and other runtimes may also need their documented CA configuration.

## Export the public root manually

For separate browser/runtime stores or unsupported Linux distributions:

```sh
docker compose cp reverse-proxy:/data/caddy/pki/authorities/local/root.crt ./nosia-caddy-root.crt
openssl x509 -in ./nosia-caddy-root.crt -noout -subject -issuer -dates -sha256 -fingerprint
```

The `docker compose cp` command also works in PowerShell; use the helper's native certificate inspection there if OpenSSL is unavailable. Compare the exported certificate's SHA-256 to the helper's output before importing it. To check HTTPS without changing system trust, a curl build supporting a custom CA file can use:

```sh
curl --cacert ./nosia-caddy-root.crt --fail https://nosia.localhost/up
```

This still verifies the chain and hostname; it does not disable TLS verification. Import this public certificate using the unsupported platform's documented CA procedure. Delete the local export when no longer needed; do not commit it to the repository.

## Remove exactly this CA

Removing host trust does not remove Caddy's CA from Docker. Browser/runtime stores configured separately must also be cleaned up separately.

### Debian/Ubuntu

Enter the exact SHA-256 printed during installation. The following validates its format and targets only its fingerprint-qualified Nosia anchor:

```sh
printf 'Installed SHA-256 fingerprint (64 hex digits): '
IFS= read -r fingerprint
case "$fingerprint" in ''|*[!0-9A-Fa-f]*) exit 1 ;; esac
[ "${#fingerprint}" -eq 64 ] || exit 1
sudo rm -f "/usr/local/share/ca-certificates/nosia-caddy-$fingerprint.crt"
sudo update-ca-certificates --fresh
```

For Fedora/RHEL use the same validated fingerprint and `/etc/pki/ca-trust/source/anchors/nosia-caddy-$fingerprint.crt`, followed by `sudo update-ca-trust`. For Arch use `/etc/ca-certificates/trust-source/anchors/nosia-caddy-$fingerprint.crt`, followed by `sudo update-ca-trust`. Use the exact case/path printed by the helper. Do not remove other Caddy roots based on name.

### macOS

Use the SHA-1 removal identifier printed by the helper to select the exact existing certificate from System Keychain. This also works after the Docker CA has changed:

```sh
printf 'Installed macOS SHA-1 removal identifier (40 hex digits): '
IFS= read -r identifier
case "$identifier" in ''|*[!0-9A-Fa-f]*) exit 1 ;; esac
[ "${#identifier}" -eq 40 ] || exit 1
```

In Keychain Access, open **System**, inspect the intended certificate's fingerprint, and export just that certificate as `nosia-caddy-remove.cer`. Confirm its SHA-1 equals the saved identifier:

```sh
actual=$(openssl x509 -inform DER -in ./nosia-caddy-remove.cer -noout -sha1 -fingerprint | sed 's/^[^=]*=//' | tr -d ':')
[ "$actual" = "$identifier" ] || exit 1
sudo security remove-trusted-cert -d ./nosia-caddy-remove.cer
sudo security delete-certificate -Z "$identifier" /Library/Keychains/System.keychain
rm -f ./nosia-caddy-remove.cer
```

If exporting PEM instead, omit `-inform DER`. Do not use a subject-name deletion command: several unrelated local CAs can all be named Caddy.

### Windows

In an administrator PowerShell session, enter the saved Windows removal thumbprint (SHA-1 identifier), inspect the exact certificate, and confirm removal:

```powershell
$thumbprint = (Read-Host 'Installed Windows removal thumbprint').Replace(' ', '').ToUpperInvariant()
if ($thumbprint -notmatch '\A[0-9A-F]{40}\z') { throw 'Invalid thumbprint' }
$path = "Cert:\LocalMachine\Root\$thumbprint"
Get-Item -LiteralPath $path | Format-List Subject, Issuer, Thumbprint, NotBefore, NotAfter
Remove-Item -LiteralPath $path -Confirm
```

## CA persistence and troubleshooting

- Ordinary Caddy container recreation preserves the CA in `caddy-data`; repeat helper runs should report the exact root already trusted.
- Deleting that volume creates a new CA. Trusting the new root does not revoke old trusted roots: remove obsolete roots explicitly using their saved fingerprints/paths.
- A missing `root.crt` usually means the proxy is not running, local HTTPS has not initialized, or the selected Docker context/project is wrong. Inspect `docker compose logs reverse-proxy` and retry; do not import another certificate to work around it.
- If Linux writes an anchor but fails to refresh trust, the helper prints that exact anchor path and updater command. Repair the refresh or remove that anchor and rerun the updater. On macOS/Windows a failed import can also partially change trust; inspect only the printed exact certificate identifier before retrying.
- Public-domain deployments continue using Caddy's publicly trusted ACME certificates. They do not require host trust in the local CA; do not add `tls internal` to the shared production Caddyfile.
- The installers download helpers but never run them. If the helper download fails, use this manual guide. Existing helper files are preserved; review upstream changes and replace an old helper deliberately when upgrading.
````

- [x] **Step 4: Update the three entry points.** Replaced the README's current certificate-warning note and linked the reviewed canonical guide:

```markdown
> **Local HTTPS:** Caddy signs `nosia.localhost` with its local CA. After starting Compose, optionally run `bin/trust-caddy` (Linux/macOS) or `.\bin\trust-caddy.ps1` (Windows) to review and trust its public root. See [Trusted local HTTPS](docs/LOCAL_HTTPS.md) for prerequisites, browser imports, verification, and removal. Public-domain deployment remains automatic; see the [Deployment Guide](docs/DEPLOYMENT.md).
```

After the Docker setup instructions in `CONTRIBUTING.md`, add:

```markdown
For trusted `https://nosia.localhost`, run the explicit host helper after Compose starts: `bin/trust-caddy` on Linux/macOS or `.\bin\trust-caddy.ps1` on Windows. Review the fingerprint and confirmation prompt. See [Trusted local HTTPS](docs/LOCAL_HTTPS.md); this is not part of `bin/setup` and does not happen automatically.
```

Before the production Caddy example in `docs/DEPLOYMENT.md`, add:

```markdown
For the default `nosia.localhost` address, keep the repository's automatic local HTTPS configuration and follow [Trusted local HTTPS](LOCAL_HTTPS.md) to trust its public root explicitly. The example below is for public-domain deployment. Do not force `tls internal` on public domains or export private Caddy CA keys.
```

Remove the single `- Thruster HTTP/2 proxy` bullet from the `web` service in `docs/ARCHITECTURE.md`. In `docs/DIAGRAMS.md`, replace only its existing application-server row with this width-preserving row:

```text
│ Puma (port 3000) │                        │ • AddText        │
```

- [x] **Step 5: Run GREEN and commit.** Run `ruby test/packaging/caddy_puma.rb` and `git diff --check`. Review each command for exact-certificate targeting, no blanket deletion, and no normal use of insecure TLS bypass. Commit Task 5 files as `docs: explain local Caddy trust verification and removal`.

## Task 6: Make cross-platform verification a CI gate

**Files:** Extend `test/packaging/caddy_puma.rb` and `test/packaging/caddy_trust_windows.rb`; add one job to `.github/workflows/ci.yml` without replacing existing jobs.

- [x] **Step 1: Add the CI contract and PowerShell parse checks.** Add this method to `CaddyPumaPackagingTest`:

```ruby
def test_ci_runs_isolated_helper_tests_on_all_host_platforms
  workflow = YAML.safe_load(read(".github/workflows/ci.yml"))
  job = workflow.fetch("jobs").fetch("trust_helpers")
  rows = job.fetch("strategy").fetch("matrix").fetch("include")
  assert_includes rows, { "os" => "ubuntu-latest", "engine" => "posix" }
  assert_includes rows, { "os" => "macos-latest", "engine" => "posix" }
  assert_includes rows, { "os" => "windows-latest", "engine" => "powershell" }
  assert_includes rows, { "os" => "windows-latest", "engine" => "pwsh" }
  scripts = job.fetch("steps").filter_map { |step| step["run"] }.join("\n")
  assert_includes scripts, "ruby test/packaging/caddy_trust_posix.rb"
  assert_includes scripts, "ruby test/packaging/caddy_trust_windows.rb"
  assert_includes scripts, "ruby test/packaging/caddy_trust_installers.rb"
  refute_match(/sudo|Import-Certificate|(?:^|\s)bin\/trust-caddy(?:\s|$)/, scripts)
end
```

Add this method inside `CaddyTrustWindowsTest`; `windows` is the harness defined in Task 3:

```ruby
def test_both_powershell_files_parse_in_this_native_engine
  installer = File.join(ROOT, "install.ps1").tr("\\", "/").gsub("'", "''")
  helper = SCRIPT.tr("\\", "/").gsub("'", "''")
  body = <<~PS
    foreach ($path in @('#{installer}', '#{helper}')) {
      $tokens = $null
      $parseErrors = $null
      [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors) | Out-Null
      if ($parseErrors.Count -gt 0) { throw ($parseErrors -join "`n") }
    }
  PS
  output, status = windows(body)
  assert status.success?, output
end
```

- [x] **Step 2: Run RED.** Run `ruby test/packaging/caddy_puma.rb`. Expect the missing `trust_helpers` job to fail. The new Windows parse test runs under the already configured Task 3 engine commands on Windows.
- [x] **Step 3: Add the job under `jobs:` in `.github/workflows/ci.yml`.** It installs only the minimal test dependencies, not the application's native Rails bundle on Windows; the committed version also selects compatible Homebrew OpenSSL on macOS:

```yaml
  trust_helpers:
    name: Caddy trust helpers (${{ matrix.os }}, ${{ matrix.engine }})
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        include:
          - os: ubuntu-latest
            engine: posix
          - os: macos-latest
            engine: posix
          - os: windows-latest
            engine: powershell
          - os: windows-latest
            engine: pwsh
    steps:
      - uses: actions/checkout@v6
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: .ruby-version
          bundler-cache: false
      - name: Install standalone test dependencies
        run: gem install minitest openssl --no-document
      - name: Unix helper contracts (no real trust writes)
        if: runner.os != 'Windows'
        shell: bash
        run: |
          set -e
          sh -n bin/trust-caddy
          sh -n install.sh
          ruby test/packaging/caddy_puma.rb
          ruby test/packaging/caddy_trust_posix.rb
          ruby test/packaging/caddy_trust_installers.rb
      - name: Native PowerShell contracts (no real elevation or trust writes)
        if: runner.os == 'Windows'
        shell: pwsh
        env:
          CADDY_TEST_POWERSHELL: ${{ matrix.engine }}
        run: |
          ruby test/packaging/caddy_trust_windows.rb
          if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
          ruby test/packaging/caddy_trust_installers.rb
          if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
```

- [x] **Step 4: Run GREEN and commit.** Run `ruby test/packaging/caddy_puma.rb` and `git diff --check`. Check the GitHub Actions expression syntax without evaluating CI commands against the local machine. Commit Task 6 files as `ci: verify Caddy trust helpers across host platforms`.

## Task 7: Final regression, security review, and disposable smoke checks

**Files:** No production code by default. Record observed results and platform limitations in `docs/LOCAL_HTTPS.md` under a short `## Maintainer verification` section.

- [x] **Step 1: Run all available isolated tests in the implementation worktree.** Native Windows tests remain explicitly skipped on this Unix host:

```sh
ruby test/packaging/caddy_puma.rb
ruby test/packaging/caddy_trust_posix.rb
ruby test/packaging/caddy_trust_installers.rb
sh -n bin/trust-caddy
sh -n install.sh
```

Expected: all applicable tests pass; no real Docker, elevation, or trust-store writes. On native Windows use each Task 3 engine setting to run both `caddy_trust_windows.rb` and `caddy_trust_installers.rb`. A skipped Windows test on Linux does not satisfy the native platform gate.

- [x] **Step 2: Run available application regressions and static checks.** Recorded the approved provider baseline error and pre-existing lint/security findings. The installed offline Brakeman scanner was used instead of the network freshness-enforcing binstub; that exact binstub invocation was not run. Original command list:

```sh
bin/rails test test/models/message/stream_buffer_test.rb test/integration/chat_composer_ui_test.rb
bin/rails test
bin/rubocop
bin/brakeman --no-pager
git diff --check
```

Expected: existing streaming/composer behavior, the application suite, lint, and security checks remain green. If setup or a pre-existing failure blocks a command, record the exact failure separately; do not edit unrelated tests or call it passing. Use the repository's actual PostgreSQL setup rather than the generic SQLite description in global agent guidance.

- [x] **Step 3: Review privileged boundaries manually.** Checked independently during implementation, per-task reviews, and final overall review:

  - Source is one public root copied over Docker, not a download from unverified HTTPS.
  - Certificate data is validated before inspection/confirmation and held as a canonical snapshot; no second Docker fetch occurs after confirmation.
  - Subject equality alone never substitutes for a valid self-signature or CA basic constraints.
  - Unix requires a TTY and literal `yes`; Windows rejects redirected input and requires literal `yes`.
  - The parent Windows workflow never elevates; the child contains certificate bytes, fingerprint validation, and the fixed `LocalMachine\Root` import only.
  - Linux writes a fingerprint-qualified Nosia filename; macOS/Windows compare exact certificates rather than matching names.
  - Error output distinguishes no-write failures from potentially partial trust changes.
  - Installer downloads cannot overwrite existing helpers and never invoke a trust command.
  - Temporary cleanup is limited to directories/files created by this workflow.
  - Public HTTPS, Docker volumes, worker startup, migrations, and the user's local work remain intact.

- [ ] **Step 4: Build and validate the real proxy in a disposable Linux/macOS test environment only.** **NOT RUN: no disposable machine provided.** This step assumes an already configured disposable Nosia checkout/`.env`, Docker Model Runner, and free ports 80/443. Do not run it against an existing production project. Build the local image and use this temporary Compose overlay so all Rails services use the changed image:

```sh
docker build -t nosia:caddy-puma-smoke .
smoke_dir=$(mktemp -d)
cat > "$smoke_dir/image.yml" <<'YAML'
services:
  web:
    image: nosia:caddy-puma-smoke
  db-migrate:
    image: nosia:caddy-puma-smoke
  solidq:
    image: nosia:caddy-puma-smoke
YAML
docker compose -p nosia-caddy-smoke -f docker-compose.yml -f "$smoke_dir/image.yml" up -d
docker compose -p nosia-caddy-smoke -f docker-compose.yml -f "$smoke_dir/image.yml" exec -T reverse-proxy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker compose -p nosia-caddy-smoke -f docker-compose.yml -f "$smoke_dir/image.yml" logs reverse-proxy
docker compose -p nosia-caddy-smoke -f docker-compose.yml -f "$smoke_dir/image.yml" cp reverse-proxy:/data/caddy/pki/authorities/local/root.crt "$smoke_dir/root.crt"
curl --silent --show-error --dump-header - --output /dev/null http://nosia.localhost/up
curl --cacert "$smoke_dir/root.crt" --fail https://nosia.localhost/up
```

Expected: Caddy validation succeeds, HTTP responds with an HTTPS redirect (normally 308), and verified HTTPS reaches the app. This client-scoped `--cacert` does not modify host trust. If Caddy has not generated its root, wait for initialization by inspecting logs and retry the copy; do not bypass TLS.

Find and verify one real precompiled asset using the same disposable project:

```sh
asset=$(docker compose -p nosia-caddy-smoke -f docker-compose.yml -f "$smoke_dir/image.yml" exec -T web sh -c 'find public/assets -type f -name "*.css" -print -quit' | sed 's!^public!!')
test -n "$asset"
curl --cacert "$smoke_dir/root.crt" --fail --output /dev/null "https://nosia.localhost$asset"
```

Expected: an actual stylesheet is served successfully. Verify chat streaming in a browser in that disposable machine after the native trust check below: log in through the existing flow, create a chat using its configured test model, and confirm tokens arrive incrementally and the composer unlocks when the response finishes. A passing Ruby stream-buffer test alone does not prove proxy-level streaming.

- [ ] **Step 5: Perform native store checks only in disposable machines.** **NOT RUN: no disposable machine provided; working host trust left unchanged.** In the Step 4 Unix shell, select the same temporary project explicitly before running the helper:

```sh
export COMPOSE_PROJECT_NAME=nosia-caddy-smoke
export COMPOSE_FILE="$PWD/docker-compose.yml:$smoke_dir/image.yml"
bin/trust-caddy
curl --fail https://nosia.localhost/up
bin/trust-caddy
```

Expected: first run displays identity and requires confirmation/elevation; second run makes no duplicate write or prompt. Record the printed SHA-256, installed anchor, and removal identifier. Remove that exact trust entry using the guide, then confirm normal HTTPS verification fails while `curl --cacert "$smoke_dir/root.crt" ...` still succeeds. If a custom CA bundle or browser profile has separate trust, account for it rather than treating contradictory client results as universal success.

On disposable native Windows with an already configured test application project and free ports 80/443, build/use the local image and run:

```powershell
docker build -t nosia:caddy-puma-smoke .
$smokeDir = Join-Path $env:TEMP ('nosia-smoke-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($smokeDir) | Out-Null
$overlay = Join-Path $smokeDir 'image.yml'
@'
services:
  web:
    image: nosia:caddy-puma-smoke
  db-migrate:
    image: nosia:caddy-puma-smoke
  solidq:
    image: nosia:caddy-puma-smoke
'@ | Set-Content -LiteralPath $overlay
$env:COMPOSE_PROJECT_NAME = 'nosia-caddy-smoke'
$env:COMPOSE_FILE = (Join-Path $PWD 'docker-compose.yml') + ';' + $overlay
docker compose up -d
docker compose exec -T reverse-proxy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
.\bin\trust-caddy.ps1
curl.exe --fail https://nosia.localhost/up
.\bin\trust-caddy.ps1
```

Perform exact-thumbprint removal using Task 5's guide, then verify that normal certificate validation fails. Confirm Docker runs in the unelevated parent and only the import receives a UAC prompt. Exercise both Windows PowerShell 5.1 and PowerShell 7, preserving the same CA between repeat runs. Do not claim native verification from mock-only CI.

- [ ] **Step 6: Stop only the smoke project's containers; do not delete volumes.** **NOT APPLICABLE here: no smoke project was started.** On Unix:

```sh
docker compose -p nosia-caddy-smoke -f docker-compose.yml -f "$smoke_dir/image.yml" down
rm -f "$smoke_dir/root.crt" "$smoke_dir/image.yml"
rmdir "$smoke_dir"
unset COMPOSE_PROJECT_NAME COMPOSE_FILE
```

For the separate Windows smoke project, after removing its exact trusted root:

```powershell
docker compose down
Remove-Item -LiteralPath $overlay
[IO.Directory]::Delete($smokeDir)
Remove-Item Env:\COMPOSE_PROJECT_NAME
Remove-Item Env:\COMPOSE_FILE
```

Do not use `down -v`: preserving CA identity is a requirement and the database volume may contain test data worth retaining. Remove the exact host trust entry before removing the exported certificate. VM disposal is the final cleanup boundary for native smoke checks.

- [x] **Step 7: Record observed results, not anticipated ones.** Added the reviewed `## Maintainer verification` section to `docs/LOCAL_HTTPS.md` with results and explicit gaps, committed as `docs: record Caddy local HTTPS verification`.
- [x] **Step 8: Review the implementation against the approved spec.** Final overall code/spec/security review approved with no fixes requested, conditioned on pending acceptance checks. Preserved the branch/worktree without merging or pushing because full-suite/native acceptance is not green. No host CA imports or worktree removal performed.

## Spec coverage and execution handoff

| Approved requirement | Plan coverage |
| --- | --- |
| Caddy → Puma, remove Thruster, preserve jobs/migrations | Task 1 contract and minimal edits; Task 7 regressions. |
| Local/public automatic HTTPS and persisted CA | Task 1 preservation tests; Tasks 5 and 7 lifecycle/redirect checks. |
| Linux/macOS helper, exact native trust stores | Task 2 real-certificate and mocked OS tests. |
| Windows 5.1/7, public-data-only elevation | Task 3 signature validation, encoded child, and native subprocess tests. |
| Explicit interactive confirmation, no private keys, duplicate safety | Tasks 2 and 3 negative cases and snapshot assertions; Task 7 security review. |
| Missing prerequisites, invalid roots, permissions, partial failures | Tasks 2 and 3 failure matrices and diagnostics. |
| Installer download only, preservation, atomic publication | Task 4 isolated downloader tests and minimal installer edits. |
| Verification, browser/runtime stores, WSL, exact removal, CA replacement | Task 5 canonical guide and entry-point links. |
| No real trust changes during tests, cross-platform acceptance | Task 6 native test matrix; Task 7 explicitly disposable manual checks. |
| No unrelated refactoring or changes to user's local work | Scope notes and isolated-worktree execution prerequisite. |

Before execution, choose either **subagent-driven execution** (fresh task agents with review checkpoints) or **inline execution** using `executing-plans`. Preparing this plan does not choose either method or authorize implementation.

### Planning self-review

- Checked each approved spec requirement against the task map above; no implementation requirement is intentionally deferred outside these tasks.
- Scanned for unresolved planning placeholders and checked function names, fixture paths, and method signatures across the examples. The Windows template's `__DER__` and `__SHA256__` tokens are fully defined runtime substitutions in `New-CaddyImportScript`, not missing plan content.
- Syntax-checked the proposed Ruby and POSIX-shell code blocks, including shell heredocs inside the Ruby tests. This is syntax evidence only, not a red/green run of the proposed feature.
- PowerShell is not installed in the planning environment. Its proposed scripts and native trust operations require Task 3/6 Windows execution; do not report them as locally verified.

### API references for implementers

- Caddy Docker local HTTPS and root location: https://caddyserver.com/docs/running#local-https-with-docker
- Windows certificate import: https://learn.microsoft.com/en-us/powershell/module/pki/import-certificate
- Windows self-signature verification API and subject/issuer constants: https://learn.microsoft.com/en-us/windows/win32/api/wincrypt/nf-wincrypt-cryptverifycertificatesignatureex
- OpenSSL verification flags: https://docs.openssl.org/1.1.1/man1/verify/
