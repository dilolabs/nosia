# Caddy → Puma with trusted local HTTPS

## Goal

Keep Caddy in front of Puma and provide a way to trust Caddy's local root CA on the host for `https://nosia.localhost`.

Success means users on supported Linux, macOS, and Windows hosts can explicitly install trust in the correct Caddy CA and validate local HTTPS without disabling certificate verification. Ordinary app startup never changes host trust.

## Current context

- `Caddyfile` proxies to `web:3000`, where Puma listens. Caddy automatically uses its internal CA for `.localhost` names.
- `docker-compose.yml` runs Caddy as `reverse-proxy` and persists `/data` in the `caddy-data` volume.
- The public root certificate is `/data/caddy/pki/authorities/local/root.crt` inside that container. Installing trust inside the container does not install trust on the host.
- `Procfile` still wraps Rails with Thruster, even though Caddy bypasses Thruster's listener.
- `README.md` currently tells users to expect a browser certificate warning. It documents macOS/Linux and Windows installation workflows.
- `install.sh` and `install.ps1` generate a Compose project and download its Caddyfile, but currently do not distribute host trust helpers.
- The repository has unrelated local changes; they must remain untouched.

## Decisions

- **“Keep Caddy → Puma.”** Retain Caddy as the HTTPS endpoint and Puma as the Rails application server.
- **“Have a way to trust its root certificate on the host.”** Allow host clients to validate local HTTPS without bypassing certificate verification.
- **“Linux, macOS, Windows.”** Support all three host platforms already covered by the installation documentation.
- **“Helpers + docs (Recommended).”** Provide explicit host-side trust helpers alongside verification, removal, and browser guidance instead of requiring users to assemble manual commands.
- **“Remove it (Recommended).”** Remove Thruster and its startup wiring so Caddy is the only HTTP proxy and Puma remains the application server.
- **“Approve this section” — architecture and setup.** Keep Puma on internal port 3000, preserve Caddy's automatic local/public certificate selection and persisted CA, and provide explicit helpers that export only the public root, display identity and fingerprint, and require confirmation before trust installation.
- **“Approve this section” — platform, safety, installer, and testing scope.** Use native machine-level trust stores on supported Linux distributions, macOS, and Windows; distribute helpers without executing them; document verification and exact-certificate removal; test without altering real host trust stores.
- **“Go” after the written-spec review request.** Approve the committed written specification and proceed to implementation planning, not implementation.

## Approaches considered

1. **Opt-in helpers plus documentation (selected):** export Caddy's public root, display its fingerprint, ask for confirmation, and request OS privileges only to install trust. More code to test, but a repeatable setup experience on all three platforms. Does not require Caddy on the host.
2. **Manual documentation only:** document export and native OS commands. Less code to maintain, but more error-prone for users and less consistent across platforms.

## Architecture

- Caddy remains the only HTTPS endpoint and reverse proxy. Puma continues to bind internally to `0.0.0.0:3000`; it is not newly published to the host.
- Remove Thruster from `Gemfile` and `Gemfile.lock`, remove `bin/thrust`, and change `Procfile` so the existing Rails startup script runs without the Thruster wrapper. Keep migration and worker behavior otherwise unchanged.
- Align the application Dockerfile with port 3000, remove Thruster-only timeout variables, and disable Thruster in `config/dockerfile.yml`. External ports 80 and 443 remain published by Caddy.
- Keep Caddy's automatic local/public certificate selection. Do not unconditionally force `tls internal` for deployments using public domains.
- Preserve the `caddy-data` volume and its existing CA across normal container restarts and upgrades.

## Components and responsibilities

### Host helpers

Add `bin/trust-caddy` for POSIX-shell Linux/macOS use and `bin/trust-caddy.ps1` for native Windows PowerShell 5.1 and PowerShell 7. Neither helper depends on host Ruby, Rails, or Caddy.

Users invoke the matching helper explicitly from the directory containing their Compose project, after starting it. Helpers use that project's current Docker context and Compose configuration rather than guessing a Docker volume or container name.

The workflow is:

1. Check the platform and required commands, including Docker Compose and the platform's certificate/trust tools. Unix helpers use OpenSSL for certificate inspection; Windows uses native certificate APIs. Missing prerequisites are explained, never automatically installed.
2. Show the selected Docker context and identify `reverse-proxy` as the certificate source. Tell users to proceed only if this is their intended Caddy instance; do not fetch a root over unverified HTTPS.
3. Copy only `/data/caddy/pki/authorities/local/root.crt` from the running `reverse-proxy` container into a unique user-owned temporary directory. Do not read or export private CA keys or the entire PKI directory.
4. Parse and validate the certificate: require one currently valid, self-signed CA certificate and reject private-key material or malformed input.
5. Display subject, issuer, validity dates, and the SHA-256 certificate fingerprint. Explain that trusting this CA grants authority beyond `nosia.localhost`.
6. If the exact certificate is already trusted, report that and avoid duplicate writes. Otherwise, require an explicit affirmative interactive response; blank input, refusal, or EOF must not install trust. There is no unattended confirmation bypass in this change.
7. Request elevation only for trust-store writes, and install the certificate in the platform's native machine-level store. Docker and certificate-inspection operations run as the invoking user. On Windows an elevated trust-write operation receives only the validated public certificate, not a request to rerun the whole workflow as administrator.
8. Report the installed certificate's fingerprint and removal identity, along with verification and browser guidance. Clean up temporary exports on success, cancellation, or failure.

The certificate used for installation must be the same certificate whose fingerprint the user confirmed. Do not re-fetch it between confirmation and import.

### Platform trust stores

| Platform | Store and update mechanism |
| --- | --- |
| Debian/Ubuntu | Project-specific `.crt` anchor under `/usr/local/share/ca-certificates`, then `update-ca-certificates`. |
| Fedora/RHEL | Anchor under `/etc/pki/ca-trust/source/anchors`, then `update-ca-trust`. |
| Arch Linux | Anchor under `/etc/ca-certificates/trust-source/anchors`, then `update-ca-trust`. |
| macOS | System Keychain, using the native `security` tool to install trusted-root status. |
| Windows | `LocalMachine\Root`, using native Windows certificate-store tooling with elevation. |

Use a Nosia-specific, fingerprint-qualified anchor filename on Linux so installation never overwrites an unrelated certificate or silently replaces an old CA. On macOS and Windows, identify certificates by their exact certificate fingerprint/store identifier, never by subject name alone. Windows documentation distinguishes the displayed SHA-256 fingerprint from the certificate-store thumbprint used for removal.

Unsupported distributions or missing native tools fail safely with a link to manual export/trust documentation. WSL and Windows have distinct trust stores: a Linux helper does not promise to configure Windows browsers, or vice versa.

### Installer distribution

Update `install.sh` and `install.ps1` to download the corresponding helper into `bin/` alongside the generated Compose project, using the existing upstream source convention. Preserve an existing helper rather than overwriting potential user modifications. Publish a newly downloaded helper only after its download completes; make the Unix helper executable.

Installers print the separate optional trust command after the existing startup guidance. They never execute the helper, install a CA, or start containers to obtain one. A helper-download failure warns clearly and links to manual instructions; it does not invalidate an otherwise working Nosia installation or leave a partial executable.

### Documentation

Update `README.md`, `CONTRIBUTING.md`, and the relevant local HTTPS sections of `docs/DEPLOYMENT.md`:

- Explain that Caddy's local CA signs the server certificate; trusting its root is preferable to accepting browser warnings or using `curl -k`.
- Provide platform-specific helper commands and prerequisites, administrator prompts, and manual certificate export commands for browser imports or unsupported systems.
- Explain how to verify `https://nosia.localhost/up` using normal certificate verification. On Windows use `curl.exe` to avoid PowerShell alias ambiguity; account for curl builds with their own CA bundles.
- Document Firefox/Chrome and runtime-specific trust stores as possible additional steps. Do not promise every browser, Ruby, Python, Java, or other client will inherit OS trust.
- Include exact-certificate removal instructions for each platform; remove only the installed Nosia CA, not every certificate named Caddy.
- Explain that normal restarts preserve the root, whereas deleting `caddy-data` creates a new CA. Trusting a new root does not revoke an old one; remove obsolete trusted roots explicitly.
- Explain that public domains continue to use publicly trusted ACME certificates and need no local root installation.

## Security and error handling

- Trust installation is explicit and opt-in, not a side effect of starting Nosia.
- Caddy's private root and intermediate keys remain inside its persisted data volume. Explain the need to protect that volume and Docker access because a trusted CA can issue certificates for other names.
- Do not expose Caddy's administration endpoint, mount host trust stores into a container, disable TLS verification, or change browser security settings automatically.
- Before any privileged write, missing Docker access, an unavailable `reverse-proxy`, an absent root, invalid certificate input, or unsupported tooling exits with actionable diagnostics and no trust-store changes.
- Caddy creates the root during local HTTPS setup. If it is not ready, instruct users to check the proxy's logs and retry rather than silently importing another certificate.
- Permission denial or native tool failure produces a nonzero exit status and identifies the failed step. If a write succeeded before an update failed, report that partial modification and its exact cleanup path instead of claiming nothing changed.
- A successful OS import means the system trust operation succeeded, not that every browser/runtime trusts the CA or that the application health endpoint is healthy. Show the verification command separately.

## Testing and acceptance

- Use Minitest packaging/subprocess tests for the shell helpers and the dependency/startup changes. Stub Docker, certificate inputs, elevation, and native trust-store operations; never install test roots into a developer's or CI runner's real store.
- Cover valid public-root export, invalid/non-CA/expired certificate rejection, confirmation and cancellation, noninteractive refusal, duplicate trust, missing Docker/Compose/container/root, missing tools, unsupported platforms, permission failure, and truthful partial-failure reporting.
- Assert the exported path is only `root.crt`, no private key is read, no privileged operation precedes confirmation, and the confirmed fingerprint matches the installed certificate.
- Exercise each Linux trust-store mapping and macOS command routing with isolated fake commands/filesystems. Run Windows helper tests on a native Windows runner, mocking certificate-store and elevation operations; include PowerShell syntax/compatibility checks for 5.1 and 7.
- Test installer helper distribution, preservation of existing files, complete-download publication, failure reporting, and the absence of any automatic helper execution.
- Verify removal of the Thruster dependency and startup wrapper, Puma's internal port 3000, Caddy's `web:3000` upstream, unchanged health checks, and unchanged worker/migration behavior.
- Validate Caddy configuration and perform an opt-in, disposable-environment smoke check for HTTP-to-HTTPS redirects, normal HTTPS verification, a static asset, and streaming/chat responses after Thruster removal. Do not import a test CA on the working host as part of automated tests.
- Native OS-store import, duplicate-run, browser, and exact-removal smoke checks belong in disposable test machines. If a target platform is unavailable during implementation, record that limitation rather than claiming native verification.

## Boundaries and non-goals

- Keep the two host helpers small and platform-focused. Certificate acquisition, validation/confirmation, and privileged import are distinct steps, not a new Rails service or framework.
- No new proxy, private ACME server, mkcert dependency, host Caddy installation, web certificate-download endpoint, or automatic browser-profile modification.
- No automatic CA rotation, unattended trust bypass, or automatic removal of older roots. Removal is documented and explicit.
- Do not change unrelated process-monitor, background-job, database, or application behavior.
- Do not fix unrelated installer resource-detection or shell portability issues as part of this change.

## Brainstorming progress

- [x] Explore project context, documentation, and recent commits.
- [x] Assess visual companion: unnecessary for this command-line and certificate workflow.
- [x] Ask clarifying questions and establish scope.
- [x] Propose two or three approaches with trade-offs and a recommendation.
- [x] Present the design and obtain approval.
- [x] Finalize and commit the design document.
- [x] Self-review the written specification; fresh-context review also approved with no issues.
- [x] Obtain the user's review of the written specification.
- [x] Invoke writing-plans to prepare the implementation plan.

## References

- https://caddyserver.com/docs/running#local-https-with-docker
- https://caddyserver.com/docs/automatic-https#local-https
