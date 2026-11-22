# Radeon Memory Guard

[Published v0.6.0 release guide](https://github.com/jb14813/Radeon-Memory-Guard/blob/main/docs/releases/v0.6.0.md)

Radeon Memory Guard maintains workarounds for identified AMD memory and cache-write issues, and retires them when a verified native driver fix is available. AMD External Events Utility stays available.

**Experimental.** May cause instability, application crashes or loss of AMD features. Driver and Windows updates may break protection. Restore saved settings or uninstall if problems appear.

Tested on **Radeon RX 7900 XTX** and **Windows 11 Pro 26H2, build 26300**. Native operation was validated on **Adrenalin 26.11.2 / driver 32.0.32029.2010**; workaround coverage was validated on **32.0.32015.12012**. See [exact identities and limits](VALIDATION.md).

## Install

1. Download `RadeonMemoryGuard-Setup-0.6.0.exe` from [GitHub Releases](https://github.com/jb14813/Radeon-Memory-Guard/releases/tag/v0.6.0).
2. Run Setup as administrator. Complete setup checks native fixes and enables needed protection; Custom offers memory maintenance only. Verified native fixes skip the corresponding workaround and RAM dependency installation.
3. [Check Status](#status) after installation and after updating your Radeon driver.

Requires 64-bit Windows and an official AMD Radeon driver. Setup includes the signed Arsenal/AWEAlloc storage drivers used by RAM mode.

The installer is self-signed, so Windows may display an unknown-publisher warning. [Verify its signature and SHA-256 checksum](SIGNING.md).

## Operation

A hidden SYSTEM task runs at startup and every five minutes. It checks the active driver and native-fix identities, maintains `Gmx_MgpuProcessWatcherSupport=0` where the memory workaround is needed, and repairs opted-in RAM redirection where applicable. It has no window or tray icon.

For the exact validated 26.11.2 images, maintenance restores its owned memory override and SSD redirection to their saved original state. Status reports `NativeMemoryFix=true`, `MemoryWorkaroundRequired=false`, and SSD `Mode=Native`. No 64 MiB RAM disk is allocated. A matching version label alone does not establish that an image is fixed.

Unknown images retain the previous compatibility behavior; they are not declared natively fixed. After a driver downgrade or unfamiliar update, review Status and rerun Setup if SSD protection is needed. Native retirement disables the previous SSD opt-in rather than silently enabling it again later.

When needed, RAM mode uses 64 MiB of locked physical memory, plus filesystem and driver overhead. It redirects the SYSTEM-profile `atieclxx.exe` cache; ordinary AMD logs and shader caches remain on disk. Native retirement releases the owned RAM volume; existing storage drivers are retained for normal uninstall/shared-use handling.

A driver update can load before maintenance applies the setting. `AppliedNeedsReload` means activation needs a later driver reload or Windows restart. The guard does not restart either automatically, and it cannot reclaim memory already leaked in the current session.

## Status

Open Windows PowerShell as administrator:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:ProgramFiles\JZB Apps\Radeon Memory Guard\RadeonMemoryGuard.ps1" -Action Status -Json
```

## Repair or uninstall

Run Setup again to repair the installation. To remove it, choose **Restore and uninstall** from the Start menu or uninstall through Windows Settings.

Removal restores saved AMD settings and the original cache file, releases the RAM disk, and removes unused components installed by the guard. Shared drivers and recovery records are preserved. If restoration encounters a conflict, recovery files remain available.

## Portable use

Extract the ZIP and open Windows PowerShell 5.1 as administrator in that folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\RadeonMemoryGuard.ps1" -Action Install
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\RadeonMemoryGuard.ps1" -Action InstallRamBackend
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\RadeonMemoryGuard.ps1" -Action ProtectSsdRam
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\RadeonMemoryGuard.ps1" -Action Status -Json
```

Use `-Action RestoreSsd` to restore the cache and service settings, or `-Action Uninstall` to restore and remove the guard. Recovery records are stored in `C:\ProgramData\JZBApps-RadeonMemoryGuard`.

## Build

Requires Windows PowerShell 5.1 and Inno Setup 6. Signing also requires Windows SDK SignTool and the [project signing identity](SIGNING.md).

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tools\Build-Release.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tools\Build-Installer.ps1" -SelfSign
```

## Privacy

Guard state and recovery files stay local; there is no automatic diagnostic upload. Manual RAM-backend installation can download its pinned package from GitHub. Review support reports before sharing; AMD software has its own privacy settings.

## Support and license

[JZB Apps](https://jzbapps.com) - [support@jzbapps.com](mailto:support@jzbapps.com)

Include your GPU, Windows build, Radeon driver version and a description of the problem.

JZB Apps code is [MIT licensed](LICENSE). Bundled components retain their [third-party licenses](THIRD-PARTY-NOTICES.txt). This project is independent of AMD and Microsoft.
