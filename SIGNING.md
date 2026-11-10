# Verify a download

The installer and uninstaller use the JZB Apps self-signed Authenticode key. Windows may show an unknown-publisher warning. Checksums are calculated after signing, and `SHA256SUMS.sig` authenticates the release checksum manifest.

Public certificate SHA-256:

```text
776d8337e24c2f2d0c5b60d8e3778f34a636c0f8de8e1b54e68d081d4a4f6e90
```

Compare this fingerprint through a source you trust before using the certificate. A checksum alone does not authenticate the publisher.

Download the verification tools, public certificate and checksum files from the [release page](https://github.com/jb14813/Radeon-Memory-Guard/releases/tag/v0.5.1).

```powershell
.\Verify-Release.ps1 -Path .\RadeonMemoryGuard-Setup-0.5.1.exe -CertificatePath .\JZBApps-RadeonMemoryGuard.cer -ExpectedSha256 '<hash from SHA256SUMS>'
.\Verify-ReleaseManifest.ps1 -Manifest .\SHA256SUMS -CertificatePath .\JZBApps-RadeonMemoryGuard.cer -CheckFiles
```

The EXE check validates the signed image and pins its signer to the supplied certificate. The manifest check validates its signature and, with `-CheckFiles`, each listed download.

## Maintainer signing

The project key is nonexportable and retained in the Windows user certificate store. Reuse it for releases and keep the public certificate and fingerprint available with the downloads. Announce key changes before distributing a replacement identity.

```powershell
.\tools\New-ReleaseIdentity.ps1
.\tools\Build-Installer.ps1 -SelfSign
.\tools\Sign-ReleaseManifest.ps1 -Directory '<release directory>'
```

Authenticode signing uses an RFC3161 timestamp. The original vendor/Microsoft storage-driver signatures remain intact. Portable scripts are covered by the signed ZIP checksum in the release manifest.
