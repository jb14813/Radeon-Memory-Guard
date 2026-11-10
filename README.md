# Radeon Memory Guard

Radeon Memory Guard maintains a workaround for an identified AMD Radeon memory leak and redirects repeated executable-cache writes to a 64 MiB RAM disk. AMD External Events Utility stays running.

**Experimental.** May cause instability, application crashes or loss of AMD features. Driver and Windows updates may break protection. Restore saved settings or uninstall if problems appear.

Tested on **Radeon RX 7900 XTX**, AMD driver **32.0.32015.12012**, and **Windows 11 Pro 26H2, build 26300**. See [validation and compatibility limits](VALIDATION.md).

## Install

1. Download `RadeonMemoryGuard-Setup-0.5.1.exe` from [GitHub Releases](https://github.com/jb14813/Radeon-Memory-Guard/releases/tag/v0.5.1).
2. Run Setup as administrator. Complete setup enables memory maintenance and RAM redirection; Custom offers memory maintenance only.
3. [Check Status](#status) after installation and after updating your Radeon driver.

Requires 64-bit Windows and an official AMD Radeon driver. Setup includes the signed Arsenal/AWEAlloc storage drivers used by RAM mode.

The installer is self-signed, so Windows may display an unknown-publisher warning. [Verify its signature and SHA-256 checksum](SIGNING.md).

## Operation

A hidden SYSTEM task runs at startup and every five minutes. It maintains `Gmx_MgpuProcessWatcherSupport=0` for the active supported AMD display service and repairs the RAM-cache link when needed. It has no window or tray icon.

RAM mode uses 64 MiB of locked physical memory, plus filesystem and driver overhead. It redirects the SYSTEM-profile `atieclxx.exe` cache; ordinary AMD logs and shader caches remain on disk.

A driver update can load before maintenance applies the setting. `AppliedNeedsReload` means activation needs a later driver reload or Windows restart. The guard does not restart either automatically, and it cannot reclaim memory already leaked in the current session.

## Status

Open Windows PowerShell as administrator:

```powershell
& "$env:ProgramFiles\JZB Apps\Radeon Memory Guard\RadeonMemoryGuard.ps1" -Action Status -Json
```

## Repair or uninstall

Run Setup again to repair the installation. To remove it, choose **Restore and uninstall** from the Start menu or uninstall through Windows Settings.

Removal restores saved AMD settings and the original cache file, releases the RAM disk, and removes unused components installed by the guard. Shared drivers and recovery records are preserved. If restoration encounters a conflict, recovery files remain available.

## Portable use

Extract the ZIP and open Windows PowerShell 5.1 as administrator in that folder:

```powershell
.\RadeonMemoryGuard.ps1 -Action Install
.\RadeonMemoryGuard.ps1 -Action InstallRamBackend
.\RadeonMemoryGuard.ps1 -Action ProtectSsdRam
.\RadeonMemoryGuard.ps1 -Action Status -Json
```

Use `-Action RestoreSsd` to restore the cache and service settings, or `-Action Uninstall` to restore and remove the guard. Recovery records are stored in `C:\ProgramData\JZBApps-RadeonMemoryGuard`.

## Build

Requires Windows PowerShell 5.1 and Inno Setup 6. Signing also requires Windows SDK SignTool and the [project signing identity](SIGNING.md).

```powershell
.\tools\Build-Release.ps1
.\tools\Build-Installer.ps1 -SelfSign
```

## Support and license

[JZB Apps](https://jzbapps.com) - [support@jzbapps.com](mailto:support@jzbapps.com)

Include your GPU, Windows build, Radeon driver version and a description of the problem.

JZB Apps code is [MIT licensed](LICENSE). Bundled components retain their [third-party licenses](THIRD-PARTY-NOTICES.txt). This project is independent of AMD and Microsoft.
