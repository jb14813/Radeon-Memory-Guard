# Code signing policy

Radeon Memory Guard's experimental offline EXE and uninstaller carry a dedicated
**JZB Apps self-signed Authenticode signature**. This provides release-integrity
verification against our published public key. It does not establish a publicly
trusted Windows publisher. Windows may warn or block execution under its policy.

## Project policy

Keep and reuse the dedicated JZB Apps key. Publish SHA-256 checksums computed after
final Authenticode signing, together with the public certificate and the signed
checksum manifest. This project is not pursuing a third-party signing subscription
or certificate application. The private key is never distributed. If key rotation
becomes necessary, announce the change and publish the new certificate fingerprint.

The key is generated and retained nonexportably in the maintainer's Windows user
certificate store. It is reused for subsequent releases. Only the public .cer and
its SHA-256 fingerprint are distributed. No private key, PFX, personal certificate,
or credentials are included. Certificates belonging to other organizations are
never used. Public installers do not import certificates into any trust store.

The official AMD driver and bundled RAM-storage dependencies retain their original
vendor/Microsoft signatures. They are not modified or signed with the JZB Apps key.
The PowerShell scripts are not separately Authenticode-signed: the installer image
covers their embedded bytes, and the signed release manifest covers the portable ZIP.

## Verify a release

Obtain the certificate fingerprint from a channel you independently trust, such as
the project website and repository. Replacing both an EXE and its public key defeats
verification if you have no independently trusted fingerprint. A checksum supplied
beside a download alone is not publisher authentication.

1. Check the public certificate's SHA-256 against `signing/identity.json`.
2. Verify the signed EXE and its complete-file checksum, without importing trust:

```powershell
.\Verify-Release.ps1 -Path .\RadeonMemoryGuard-OfflineSetup-0.4.0.exe -CertificatePath .\JZBApps-RadeonMemoryGuard.cer -ExpectedSha256 '<hash from SHA256SUMS>'
```

The verifier checks PKCS#7 signature mathematics, asks Windows to verify the PE
image digest in cache-only mode, pins the signer to the supplied certificate, and
optionally compares complete-file SHA-256. Altering the EXE is rejected. This is
integrity verification, not a stability, safety, or public-trust certification.

`SHA256SUMS` is generated after every final asset is written. `SHA256SUMS.sig` is a
detached RSA/SHA-256 signature over its exact bytes. To verify it and local assets:

```powershell
.\Verify-ReleaseManifest.ps1 -Manifest .\SHA256SUMS -CertificatePath .\JZBApps-RadeonMemoryGuard.cer -CheckFiles
```

Build-time Authenticode signing requests an RFC3161 timestamp. Installation and
our cache-only verifier do not require that timestamp service. Signature checks
performed by Windows or vendor installers can use Windows certificate infrastructure;
normal trust and driver-signing requirements still apply while offline.

## Building and retaining the identity

Use Windows PowerShell 5.1:

```powershell
# Creates the dedicated nonexportable project key once, or reuses it.
.\tools\New-ReleaseIdentity.ps1
.\tools\Build-Installer.ps1 -SelfSign
```

An unsigned CI build requires no signing identity; `Build-Installer.ps1` defaults
to unsigned. `-SelfSign` selects only the exact dedicated certificate matching the
public file. Windows SDK SignTool is a build-time tool; users do not need it.

The default identity command does not install local trust. An owner can explicitly
choose `-TrustForCurrentUser`; that affects only their user stores and is never run
by Setup. No machine-wide root trust, kernel-signing policy, or Test Mode is changed.

See [Microsoft's SmartScreen guidance](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation).
A trusted signature identifies a publisher and detects changes; it does not prove
that this experimental workaround is safe or compatible with every system.
