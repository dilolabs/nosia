# Opt-in Windows machine trust. Dot-source to load functions without running them.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CaddyFingerprint {
    param([byte[]]$RawData)
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($hash.ComputeHash($RawData)).Replace('-', '').ToLowerInvariant()
    } finally {
        $hash.Dispose()
    }
}

function Test-CaddyRootSignature {
    param([Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)
    if (-not ('Nosia.CaddyNativeSignature' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Nosia {
    public static class CaddyNativeSignature {
        [DllImport("crypt32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CryptVerifyCertificateSignatureEx(
            IntPtr provider, uint encoding, uint subjectType, IntPtr subject,
            uint issuerType, IntPtr issuer, uint flags, IntPtr extra);
    }
}
'@
    }
    # X509_ASN_ENCODING = 1; both subject and issuer are CERT_CONTEXT = 2.
    return [Nosia.CaddyNativeSignature]::CryptVerifyCertificateSignatureEx(
        [IntPtr]::Zero, 1, 2, $Certificate.Handle, 2, $Certificate.Handle, 0, [IntPtr]::Zero)
}

function Get-CaddyCertificate {
    param([string]$Path)
    $attributes = [IO.File]::GetAttributes($Path)
    if (($attributes -band [IO.FileAttributes]::Directory) -or ($attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Caddy root certificate must be a regular file, not a directory or reparse point.'
    }
    $pem = [IO.File]::ReadAllText($Path)
    $match = [regex]::Match($pem, '\A\s*-----BEGIN CERTIFICATE-----\r?\n(?<data>[A-Za-z0-9+/=\r\n]+)\r?\n-----END CERTIFICATE-----\s*\z')
    if (-not $match.Success) {
        throw 'Expected exactly one public CERTIFICATE PEM block and whitespace only; no keys or trailing text.'
    }
    $raw = [Convert]::FromBase64String($match.Groups['data'].Value)
    $certificate = New-Object Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList (,$raw)
    try {
        # Windows certificate parsers may silently ignore additional decoded DER.
        if ([Convert]::ToBase64String($raw) -cne [Convert]::ToBase64String($certificate.RawData)) {
            throw 'Certificate PEM contains extra DER data or multiple certificates.'
        }
        if ($certificate.HasPrivateKey) { throw 'Only a public certificate is allowed.' }
        $constraints = @($certificate.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.19' })
        if ($constraints.Count -ne 1 -or
            $constraints[0] -isnot [Security.Cryptography.X509Certificates.X509BasicConstraintsExtension] -or
            -not $constraints[0].CertificateAuthority) {
            throw 'Certificate must have X509 Basic Constraints CA:TRUE.'
        }
        $now = [DateTime]::UtcNow
        if ($now -lt $certificate.NotBefore.ToUniversalTime() -or $now -gt $certificate.NotAfter.ToUniversalTime()) {
            throw 'Root CA certificate is not currently valid.'
        }
        if ([Convert]::ToBase64String($certificate.SubjectName.RawData) -cne [Convert]::ToBase64String($certificate.IssuerName.RawData)) {
            throw 'Root CA certificate issuer must equal its subject.'
        }
        if (-not (Test-CaddyRootSignature $certificate)) { throw 'Root CA certificate self-signature is invalid.' }
        return $certificate
    } catch {
        $certificate.Dispose()
        throw
    }
}

function Invoke-CaddyDocker {
    # Use the caller's current directory, Docker context, Compose project and env.
    $result = & docker @args
    if ($LASTEXITCODE -ne 0) {
        throw "Docker/Compose failed: docker $($args -join ' '). Check Docker context and docker compose logs reverse-proxy."
    }
    return $result
}

function Get-CaddyRootCertificates {
    # Read only. CurrentUser trust is deliberately not consulted.
    Get-ChildItem -LiteralPath 'Cert:\LocalMachine\Root' -ErrorAction Stop
}

function Test-CaddyTrusted {
    param([Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)
    $expected = [Convert]::ToBase64String($Certificate.RawData)
    foreach ($existing in @(Get-CaddyRootCertificates)) {
        try {
            if ([Convert]::ToBase64String($existing.RawData) -ceq $expected) { return $true }
        } finally {
            $existing.Dispose()
        }
    }
    return $false
}

function Test-CaddyInteractive {
    return [Environment]::UserInteractive -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
}

function Confirm-CaddyTrust {
    if (-not (Test-CaddyInteractive)) {
        throw 'An interactive console is required; redirected input (even piped yes) is refused.'
    }
    $answer = Read-Host 'Type literal yes to trust this root system-wide (anything else cancels)'
    return $answer -ceq 'yes'
}

function New-CaddyImportScript {
    param([byte[]]$RawData, [string]$Fingerprint)
    if ($Fingerprint -cnotmatch '\A[0-9a-f]{64}\z' -or (Get-CaddyFingerprint $RawData) -cne $Fingerprint) {
        throw 'Confirmed fingerprint does not match the actual certificate input.'
    }
    $publicDer = [Convert]::ToBase64String($RawData)
    # Only base64 public DER and a checked hex fingerprint enter this static code.
    # No parent paths, commands, Docker context or helper invocation are elevated.
    $template = @'
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$publicDer = '__PUBLIC_DER__'
$expectedFingerprint = '__FINGERPRINT__'
$temporaryFile = $null
$lock = $null
$hash = $null
try {
    $raw = [Convert]::FromBase64String($publicDer)
    $hash = [Security.Cryptography.SHA256]::Create()
    $actual = [BitConverter]::ToString($hash.ComputeHash($raw)).Replace('-', '').ToLowerInvariant()
    if ($actual -cne $expectedFingerprint) { throw 'Embedded certificate fingerprint mismatch.' }
    # GetTempFileName creates a unique file owned by the elevated identity.
    $temporaryFile = [IO.Path]::GetTempFileName()
    [IO.File]::WriteAllBytes($temporaryFile, $raw)
    $attributes = [IO.File]::GetAttributes($temporaryFile)
    if (($attributes -band [IO.FileAttributes]::ReparsePoint) -or ($attributes -band [IO.FileAttributes]::Directory)) {
        throw 'Import certificate file must be a regular file without reparse points.'
    }
    # The importer can read but no writer/deleter can swap the checked file.
    $lock = [IO.File]::Open($temporaryFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $lockedFingerprint = [BitConverter]::ToString($hash.ComputeHash($lock)).Replace('-', '').ToLowerInvariant()
    if ($lockedFingerprint -cne $expectedFingerprint) { throw 'Locked certificate fingerprint mismatch.' }
    Import-Certificate -FilePath $temporaryFile -CertStoreLocation 'Cert:\LocalMachine\Root' -ErrorAction Stop | Out-Null
} catch {
    [Console]::Error.WriteLine('Certificate import failed; a partial machine root-store change is possible: ' + $_.ToString())
    exit 1
} finally {
    if ($null -ne $lock) { $lock.Dispose() }
    if ($null -ne $hash) { $hash.Dispose() }
    if ($null -ne $temporaryFile) { [IO.File]::Delete($temporaryFile) }
}
'@
    return $template.Replace('__PUBLIC_DER__', $publicDer).Replace('__FINGERPRINT__', $Fingerprint)
}

function Invoke-CaddyElevatedImport {
    param([byte[]]$RawData, [string]$Fingerprint)
    $script = New-CaddyImportScript $RawData $Fingerprint
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
    $engine = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $child = Start-Process -FilePath $engine -Verb RunAs -Wait -PassThru -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded)
    if ($null -eq $child -or $child.ExitCode -ne 0) {
        throw 'Elevated certificate import failed (nonzero child exit code); inspect the machine root store before retrying.'
    }
}

function New-CaddyTemporaryDirectory {
    $path = Join-Path ([IO.Path]::GetTempPath()) ('nosia-caddy.' + [Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($path)
    try {
        # Remove inherited access before copying anything, including on shared TEMP.
        $owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $security = New-Object Security.AccessControl.DirectorySecurity
        $security.SetOwner($owner)
        $security.SetAccessRuleProtection($true, $false)
        $rule = New-Object Security.AccessControl.FileSystemAccessRule -ArgumentList @(
            $owner, [Security.AccessControl.FileSystemRights]::FullControl,
            ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit),
            [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow)
        $security.AddAccessRule($rule)
        Set-Acl -LiteralPath $path -AclObject $security -ErrorAction Stop
        return $path
    } catch {
        Remove-CaddyTemporaryItem $path
        throw
    }
}

function Remove-CaddyTemporaryItem {
    param([string]$Path)
    # Recurse only within our exact directory, never through a copied junction.
    $attributes = [IO.File]::GetAttributes($Path)
    if ($attributes -band [IO.FileAttributes]::Directory) {
        if (-not ($attributes -band [IO.FileAttributes]::ReparsePoint)) {
            foreach ($item in [IO.Directory]::GetFileSystemEntries($Path)) { Remove-CaddyTemporaryItem $item }
        }
        [IO.Directory]::Delete($Path, $false)
    } else {
        if (-not ($attributes -band [IO.FileAttributes]::ReparsePoint)) {
            [IO.File]::SetAttributes($Path, ($attributes -band (-bnot [IO.FileAttributes]::ReadOnly)))
        }
        [IO.File]::Delete($Path)
    }
}

function Invoke-CaddyTrust {
    if ($args.Count -ne 0) { throw 'Usage: bin/trust-caddy.ps1 (no arguments or unattended flags).' }
    if ($env:OS -cne 'Windows_NT') { throw 'This helper requires native Windows.' }
    if ($null -eq (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Missing Docker command; install Docker and Compose manually.' }
    Invoke-CaddyDocker compose version | Out-Null
    $context = (Invoke-CaddyDocker context show | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($context)) { throw 'Docker returned an empty context; check Docker configuration.' }
    Write-Host "Docker context: $context"
    Write-Host 'Source: reverse-proxy:/data/caddy/pki/authorities/local/root.crt'
    $running = (Invoke-CaddyDocker compose ps --status running -q reverse-proxy | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($running)) {
        throw 'reverse-proxy is not running. Check docker compose logs reverse-proxy and retry.'
    }
    $temporaryDirectory = $null
    $certificate = $null
    try {
        $temporaryDirectory = New-CaddyTemporaryDirectory
        $path = Join-Path $temporaryDirectory 'root.crt'
        Invoke-CaddyDocker compose cp 'reverse-proxy:/data/caddy/pki/authorities/local/root.crt' $path | Out-Null
        $certificate = Get-CaddyCertificate $path
        $fingerprint = Get-CaddyFingerprint $certificate.RawData
        $thumbprint = $certificate.Thumbprint
        Write-Host "Subject: $($certificate.Subject)"
        Write-Host "Issuer: $($certificate.Issuer)"
        Write-Host "Valid from (UTC): $($certificate.NotBefore.ToUniversalTime().ToString('o'))"
        Write-Host "Valid until (UTC): $($certificate.NotAfter.ToUniversalTime().ToString('o'))"
        Write-Host "SHA256: $fingerprint"
        Write-Host "Windows SHA1 Thumbprint (removal identifier only): $thumbprint"
        Write-Host 'Machine store: Cert:\LocalMachine\Root'
        Write-Host 'WARNING: This root authority extends beyond nosia.localhost.'
        Write-Host 'Protect access to Docker and its Caddy CA volume; its private key can issue trusted certificates.'
        if (Test-CaddyTrusted $certificate) {
            Write-Host 'This exact root is already trusted by the machine store; no changes made.'
        } else {
            if (-not (Confirm-CaddyTrust)) { throw 'Cancelled; no system trust changes were requested.' }
            try {
                Invoke-CaddyElevatedImport $certificate.RawData $fingerprint
            } catch {
                throw "Elevation/import failed; a partial change in Cert:\LocalMachine\Root is possible. Inspect exact SHA1 Thumbprint $thumbprint before retrying/removing it. $($_.ToString())"
            }
            Write-Host 'System trust import succeeded.'
        }
        Write-Host 'Verify the application separately: curl.exe --fail https://nosia.localhost/up'
        Write-Host 'Browser/runtime-specific trust and removal instructions: https://github.com/dilolabs/nosia/blob/main/docs/LOCAL_HTTPS.md'
    } finally {
        if ($null -ne $certificate) { $certificate.Dispose() }
        if ($null -ne $temporaryDirectory) { Remove-CaddyTemporaryItem $temporaryDirectory }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-CaddyTrust @args
    } catch {
        [Console]::Error.WriteLine('Error: ' + $_.ToString())
        [Console]::Error.WriteLine('Manual instructions: https://github.com/dilolabs/nosia/blob/main/docs/LOCAL_HTTPS.md')
        exit 1
    }
}
