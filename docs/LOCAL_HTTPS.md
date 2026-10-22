# Local HTTPS: trust, verify, and remove Caddy's CA

This is the canonical guide for the optional trust setup at `https://nosia.localhost` on Linux, macOS, and native Windows. Ordinary application startup, `bin/setup`, and the installers do not import a CA into your host's trust store.

## What you are trusting

The Compose path is **client HTTPS → Caddy → private HTTP `web:3000` (Puma)**. Only Caddy publishes ports 80/443; the web service does not publish Puma's port. There is no Thruster proxy.

For `.localhost`, Caddy creates a local certificate authority (CA): a **self-signed root** signs an intermediate, which signs the site's certificate. The site's certificate is **not a self-signed leaf**. Trust the public root, not the leaf or intermediate. Caddy running inside a container cannot automatically establish trust on your host.

For real public domains, Caddy's automatic public ACME certificate management remains available. Do not add `tls internal` unconditionally to the Caddyfile. Public domains using publicly trusted certificates require **no local CA import**; see [production deployment](DEPLOYMENT.md#4-configure-caddy-reverse-proxy).

> **Machine-wide authority extends beyond `nosia.localhost`.** This CA can issue certificates for other hostnames. Protect Docker access and the `caddy-data` volume: anyone with the CA's private key can mint certificates trusted by machines that imported its root. Import only the root from your intended Nosia instance, never an unknown remote Docker CA. Never copy private keys or the whole PKI directory to the host, browser, repository, or support ticket.

## 1. Start and identify the intended instance

From the Nosia installation directory containing your Compose file and `.env`:

```sh
docker compose up -d
docker context show
docker compose ps reverse-proxy
docker compose logs reverse-proxy
```

Use the **correct Compose project** for every step, including export and retry. Both helpers honor your selected Docker context/environment and current directory; they do not switch contexts or start containers. Review `DOCKER_CONTEXT`, `DOCKER_HOST`, `COMPOSE_FILE`, and `COMPOSE_PROJECT_NAME` if set. `docker context show` and the helper's `Docker context:` line are useful context, but environment overrides can affect the effective Docker endpoint too. Do not confirm unless that endpoint/project is the instance you control and intend to trust.

The only certificate source is:

```text
reverse-proxy:/data/caddy/pki/authorities/local/root.crt
```

The helpers copy only that public certificate into private temporary storage, validate it, and clean up their temporary copy on exit. They do not leave an exported root file in your installation directory. The deliberately installed public certificate remains in the selected machine store until you remove it.

## 2. Optional machine trust

### Linux and macOS

Prerequisites (install missing dependencies yourself; the helper does not install them):

- Docker CLI and Docker Compose, with access as your normal user to the intended running instance.
- A compatible modern **OpenSSL** on `PATH`, including `verify -check_ss_sig` and `x509 -ext basicConstraints`. Old OpenSSL/LibreSSL versions may lack these flags. On macOS, the bundled `openssl` may be insufficient: arrange an organization-approved compatible OpenSSL on `PATH` before running the helper.
- A POSIX shell and standard tools: `uname`, `awk`, `tr`, `cat`, `mktemp`, `rm`, `cmp`, plus `sudo`. Linux also needs `install` and the native trust updater below.
- **macOS 12+**, `/Library/Keychains/System.keychain`, `security`, and `plutil` with typed reads (`-extract ... raw -expect ...`). Earlier macOS versions are not supported by this helper. It uses the **System keychain and admin trust settings**, not just your login keychain or user trust.

Supported Linux machine-store layouts:

| Distribution | Anchor directory | Native updater |
| --- | --- | --- |
| Debian / Ubuntu | `/usr/local/share/ca-certificates` | `update-ca-certificates` |
| Fedora / RHEL | `/etc/pki/ca-trust/source/anchors` | `update-ca-trust` |
| Arch | `/etc/ca-certificates/trust-source/anchors` | `update-ca-trust` |

Review `bin/trust-caddy`, then run it as a **normal user**, not with `sudo` around the whole helper:

```sh
bin/trust-caddy
```

Before any import, the helper validates a single public CA certificate, its actual self-signature, and current validity. Review its subject, issuer, validity dates, and **SHA256** fingerprint against your intended instance. A matching subject/name alone is not sufficient. Save the exact printed `SHA256:`, `SHA1 removal identifier:`, and (on Linux) `Machine anchor/removal path:` and `Updater:` outputs for later removal. On macOS, also save the printed System keychain path.

At the interactive terminal, type literal `yes` only if you approve the displayed root's machine-wide authority. Anything else cancels. Do not pipe input, automate approval, or use an auto-yes wrapper; redirected input/output is refused. Only trust-store writes and the Linux updater use `sudo`; Docker and certificate inspection remain unelevated. An exact certificate already trusted by the selected machine store is reported without another import or duplicate. A similarly named or reissued certificate is not an exact match.

### Native Windows

Use **Windows PowerShell 5.1** or **PowerShell 7** on Windows, with Docker/Compose available to your normal user. Review `bin\trust-caddy.ps1`, then run in a normal, interactive PowerShell console from the installation directory:

```powershell
.\bin\trust-caddy.ps1
```

The helper validates the public CA, current validity, and actual self-signature through Windows certificate APIs. Review the subject, issuer, UTC validity dates, and strong **SHA256** fingerprint; type literal `yes` only for the intended root. No piping or unattended approval is supported. Save the exact `SHA256:` and `Windows SHA1 Thumbprint (removal identifier only):` outputs.

The import destination is `Cert:\LocalMachine\Root` (Local Computer → Trusted Root Certification Authorities), not Current User. The **SHA1 Thumbprint is only the Windows store/removal identifier**, not the strong SHA256 security fingerprint you review for trust. Exact certificate presence in this machine store avoids a duplicate import.

UAC elevates **only a fixed public-certificate import** with the confirmed certificate embedded. It does not elevate Docker or the whole helper. Approve the UAC prompt only after your review. If script execution policy blocks the helper, inspect the downloaded file and follow your **organization-approved** unblocking or signing procedure. Never globally disable execution policy or weaken it just to run this helper.

**WSL has a separate Linux trust store from the Windows machine store.** Running the Unix helper in WSL does not establish trust for a browser running on Windows; use the native Windows helper for that browser. Conversely, Windows trust does not automatically configure WSL applications.

## 3. Verify HTTPS and application health separately

On Linux/macOS:

```sh
curl --fail https://nosia.localhost/up
```

On Windows:

```powershell
curl.exe --fail https://nosia.localhost/up
```

Use `curl.exe` explicitly to avoid Windows PowerShell's `curl` alias. A successful OS import does not guarantee that every client uses that store, nor does it prove application health. Check the command's exit status and response; an HTTP failure is different from a certificate verification failure. `-k` / `--insecure` disables certificate verification and is not a normal verification or fix command.

If necessary, **restart the browser** after a trust change. Firefox and Chrome may use OS trust, a browser-specific authority store, or managed system-trust policy depending on platform, version, and organization. If the browser still rejects the chain, inspect its certificate-authority settings and policy. Where a separate authority import is required, use only the reviewed public root from the manual export below, compare its fingerprint, and authorize it for website identification according to the browser's instructions. Do not import a server leaf to bypass an error.

Ruby, Python, Java, and some curl builds use separate CA bundles or runtime stores (including custom `SSL_CERT_FILE`, `SSL_CERT_DIR`, or application settings). Configure the particular client's CA bundle/store using its documentation, or use a per-command CA file as below. This guide and the helpers do not automatically modify browser profiles or runtime stores. Track browser and runtime imports for separate removal later.

## Manual public-root export and client-specific trust

Use this when machine trust is unwanted, a platform/store layout is unsupported, or a dependency is missing. Follow the platform's native certificate-authority procedure or your administrator's policy rather than automatically installing dependencies. Work in a directory you control; choose a fresh export filename so you do not overwrite another certificate:

```sh
docker compose cp reverse-proxy:/data/caddy/pki/authorities/local/root.crt ./nosia-caddy-root.crt
```

The same `docker compose cp` command works in native PowerShell. Before importing anywhere, inspect the public root and compare its fingerprint with the intended instance's reviewed SHA256 value. If it changed, stop and investigate rather than importing on the strength of its name.

With compatible OpenSSL (the exported root is PEM):

```sh
openssl x509 -in ./nosia-caddy-root.crt -noout -subject -issuer -dates -fingerprint -sha256
openssl x509 -in ./nosia-caddy-root.crt -noout -ext basicConstraints
openssl verify -check_ss_sig -CAfile ./nosia-caddy-root.crt ./nosia-caddy-root.crt
```

Expect `CA:TRUE`, matching subject/issuer, and a currently valid self-signed root. OpenSSL prints colon-separated hexadecimal fingerprints; strip colons and normalize case to compare with the helper's lowercase SHA256.

Without OpenSSL, native Windows PowerShell 5.1/7 can inspect the exported certificate with the certificate API (this inspection does not import it):

```powershell
$pem = [IO.File]::ReadAllText((Join-Path (Get-Location).Path 'nosia-caddy-root.crt'))
$match = [regex]::Match($pem, '\A\s*-----BEGIN CERTIFICATE-----\r?\n(?<data>[A-Za-z0-9+/=\r\n]+)\r?\n-----END CERTIFICATE-----\s*\z')
if (-not $match.Success) { throw 'Expected one public certificate PEM block' }
$raw = [Convert]::FromBase64String($match.Groups['data'].Value)
$certificate = New-Object Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList (,$raw)
$hash = [Security.Cryptography.SHA256]::Create()
try {
    $certificate | Format-List Subject, Issuer, NotBefore, NotAfter, Thumbprint, HasPrivateKey
    $certificate.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.19' } | Format-List
    [BitConverter]::ToString($hash.ComputeHash($certificate.RawData)).Replace('-', '').ToLowerInvariant()
} finally {
    $hash.Dispose()
    $certificate.Dispose()
}
```

This displays identity, validity, CA constraints, and SHA256; it is not a replacement for the helper's full validation/self-signature checks. Review and compare before using the browser's authority-import UI or the platform's native procedure. Never trust an unfamiliar root because a download or copy succeeded.

For a single Unix curl request, without changing system trust:

```sh
curl --cacert ./nosia-caddy-root.crt --fail https://nosia.localhost/up
```

On Windows, use `curl.exe` with those same arguments. `--cacert` selects a specific trusted CA file and **still validates** the chain and hostname; it is not a bypass like `-k`. Keep a public export only as long as a client needs that CA file. Delete the export when finished and **never commit** it. A browser import stores its own copy, so deleting the exported file does not undo that import.

## Remove only the exact root you imported

Use the saved fingerprints and store/path from the original import. Never delete the whole CA store or all Caddy-named certificates. Other projects may have independent roots with the same display name. Browser and runtime imports require separate removal from each store/profile you changed.

### Linux: fingerprint-qualified anchor and matching updater

The helper uses a **lowercase, 64-hex SHA256** in the filename. The exact possible anchors are:

- Debian/Ubuntu: `/usr/local/share/ca-certificates/nosia-caddy-$fp.crt`
- Fedora/RHEL: `/etc/pki/ca-trust/source/anchors/nosia-caddy-$fp.crt`
- Arch: `/etc/ca-certificates/trust-source/anchors/nosia-caddy-$fp.crt`

The following prompts validate the saved fingerprint, normalize it to lowercase, select one native store, and compare the actual anchor's SHA256 before removing that one file and rebuilding trust. Choose the store matching the original printed path, not a different directory that happens to exist. No wildcard/name-based deletion is used:

```sh
(
  set -eu
  printf 'Saved old SHA256 (64 hex digits, no colons): '
  IFS= read -r fp
  printf '%s\n' "$fp" | LC_ALL=C awk 'length != 64 || /[^0-9A-Fa-f]/ { exit 1 }' || exit 1
  fp=$(printf '%s' "$fp" | tr '[:upper:]' '[:lower:]')
  printf 'Original store (debian, fedora, or arch): '
  IFS= read -r store
  case "$store" in
    debian) anchor="/usr/local/share/ca-certificates/nosia-caddy-$fp.crt"; updater=update-ca-certificates ;;
    fedora) anchor="/etc/pki/ca-trust/source/anchors/nosia-caddy-$fp.crt"; updater=update-ca-trust ;;
    arch) anchor="/etc/ca-certificates/trust-source/anchors/nosia-caddy-$fp.crt"; updater=update-ca-trust ;;
    *) printf 'Unknown store; nothing removed.\n' >&2; exit 1 ;;
  esac
  openssl x509 -in "$anchor" -noout -subject -issuer -dates -fingerprint -sha256
  actual=$(openssl x509 -in "$anchor" -noout -fingerprint -sha256)
  actual=$(printf '%s' "${actual#*=}" | tr -d ':' | tr '[:upper:]' '[:lower:]')
  [ "$actual" = "$fp" ] || { printf 'Fingerprint mismatch; nothing removed.\n' >&2; exit 1; }
  printf 'Type remove to delete only %s: ' "$anchor"
  IFS= read -r answer
  [ "$answer" = remove ] || exit 1
  sudo -- rm -- "$anchor"
  sudo -- "$updater"
)
```

Debian/Ubuntu's updater can also be run with `--fresh` if required by its native procedure. Fedora/RHEL and Arch use `update-ca-trust`. If the updater fails, trust may still contain the old root; fix that failure and rerun the matching updater, rather than deleting unrelated certificates.

### macOS: remove admin trust and the exact System certificate

Use the original **SHA1 removal identifier** (40 hex digits) to identify the old stored certificate. In **Keychain Access**, select the **System** keychain, inspect certificate details, and match that saved SHA1 identifier exactly. Export **only that public certificate** as `oldcert.cer` (DER certificate, not a private-key/P12 export). This works after Docker's CA has rotated: do not assume the current Docker `root.crt` is the old root.

Verify the old exported certificate against both saved fingerprints before removing its admin trust settings **and** its exact certificate from `/Library/Keychains/System.keychain`. The example uses DER; if your export is PEM, omit `-inform DER` from every OpenSSL command below. Case and colon normalization are deliberate:

```sh
(
  set -eu
  printf 'Saved old SHA1 removal identifier (40 hex digits, no colons): '
  IFS= read -r identifier
  printf '%s\n' "$identifier" | LC_ALL=C awk 'length != 40 || /[^0-9A-Fa-f]/ { exit 1 }' || exit 1
  identifier=$(printf '%s' "$identifier" | tr '[:upper:]' '[:lower:]')
  printf 'Saved old SHA256 (64 hex digits, no colons): '
  IFS= read -r fp
  printf '%s\n' "$fp" | LC_ALL=C awk 'length != 64 || /[^0-9A-Fa-f]/ { exit 1 }' || exit 1
  fp=$(printf '%s' "$fp" | tr '[:upper:]' '[:lower:]')
  openssl x509 -inform DER -in ./oldcert.cer -noout -subject -issuer -dates -fingerprint -sha256
  actual_sha1=$(openssl x509 -inform DER -in ./oldcert.cer -noout -fingerprint -sha1)
  actual_sha1=$(printf '%s' "${actual_sha1#*=}" | tr -d ':' | tr '[:upper:]' '[:lower:]')
  actual_sha256=$(openssl x509 -inform DER -in ./oldcert.cer -noout -fingerprint -sha256)
  actual_sha256=$(printf '%s' "${actual_sha256#*=}" | tr -d ':' | tr '[:upper:]' '[:lower:]')
  [ "$actual_sha1" = "$identifier" ] && [ "$actual_sha256" = "$fp" ] || exit 1
  printf 'Type remove to remove this exact root and its admin trust: '
  IFS= read -r answer
  [ "$answer" = remove ] || exit 1
  sudo security remove-trusted-cert -d ./oldcert.cer
  sudo security delete-certificate -Z "$identifier" /Library/Keychains/System.keychain
)
```

SHA1 here is a native removal identifier, not the security hash used to approve trust. Do not delete by a broad common name. If a command fails or a previous attempt already removed one part, inspect the exact certificate and admin trust settings before finishing the remaining step. Delete the public export when no longer needed; never commit it.

### Windows: exact LocalMachine Root Thumbprint

For removal, explicitly open an **administrator PowerShell** console. Use the saved old SHA1 Thumbprint, not a search for certificates named Caddy. The 40-hex Thumbprint identifies the store item; compare its SHA256 with your saved strong fingerprint too:

```powershell
$thumbprint = Read-Host 'Saved old SHA1 Thumbprint (40 hex digits, no spaces)'
if ($thumbprint -notmatch '\A[0-9A-Fa-f]{40}\z') { throw 'Invalid Thumbprint; nothing removed' }
$thumbprint = $thumbprint.ToUpperInvariant()
$expected = Read-Host 'Saved old SHA256 (64 hex digits, no colons)'
if ($expected -notmatch '\A[0-9A-Fa-f]{64}\z') { throw 'Invalid SHA256; nothing removed' }
$expected = $expected.ToLowerInvariant()
$storePath = 'Cert:\LocalMachine\Root\' + $thumbprint
$certificate = Get-Item -LiteralPath $storePath -ErrorAction Stop
$hash = [Security.Cryptography.SHA256]::Create()
try {
    $certificate | Format-List Subject, Issuer, NotBefore, NotAfter, Thumbprint
    $actual = [BitConverter]::ToString($hash.ComputeHash($certificate.RawData)).Replace('-', '').ToLowerInvariant()
    Write-Host "SHA256: $actual"
    if ($actual -cne $expected) { throw 'Fingerprint mismatch; nothing removed' }
    Remove-Item -LiteralPath $storePath -Confirm -ErrorAction Stop
} finally {
    $hash.Dispose()
    $certificate.Dispose()
}
```

Confirm only the displayed exact item. Removing Windows machine trust does not remove a separate WSL, browser, Java, or other runtime import.

## Persistence, replacement, and troubleshooting

- **`caddy-data` preserves the CA across container recreation.** Protect this volume and any backups as key-bearing sensitive data. Do not delete the volume as a routine certificate-warning fix.
- Deleting/replacing the CA volume creates a **new CA**, requiring a new review and trust decision. This **does not revoke** the old root already trusted by your host, browser, or runtime. Remove the old root explicitly using the saved old fingerprint/identifier and the old stored/exported certificate, not the new Docker root. A new trust import does not clean up an old one.
- If `reverse-proxy` is missing/stopped or the public root is not ready, check `docker compose logs reverse-proxy`, the correct Docker context/environment and Compose project, and retry after Caddy has initialized. A public-domain deployment may have no local root to import; it does not need one.
- A failed native import/updater can leave a **partial trust change**. Inspect the exact printed Linux anchor path, macOS SHA1 identifier/System keychain/admin trust, or Windows SHA1 Thumbprint in `Cert:\LocalMachine\Root` before retrying. Use the targeted removal steps to recover; do not assume failure means nothing changed.
- The installers **download but never execute** the optional helper and print a separate post-start command. Existing helpers are preserved rather than overwritten: review and replace them explicitly when updating. POSIX publication needs the standard `link` utility; if missing, the installer warns and points here rather than installing it. It publishes a complete download with owner execute permission, not a partially downloaded executable.
- If the helper download fails, application startup remains usable; use the manual guide/export or obtain and review the matching helper from a trusted release. Missing dependencies and unsupported layouts fail with guidance, not automatic dependency installation or silent privileged actions.
- Native macOS and Windows trust-store/browser behavior still requires verification on those platforms. Portable packaging tests do not establish that every native client trusts the root.
