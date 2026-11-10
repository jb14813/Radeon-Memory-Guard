# Radeon Memory Guard

Free, open-source maintenance for AMD's process-watcher memory-leak workaround on
64-bit Windows. It keeps `Gmx_MgpuProcessWatcherSupport=0` applied when a driver
update changes the active AMD display service name.
Optional RAM redirection protects the SSD while keeping AMD External Events Utility running.

**Experimental workaround, version 0.5.0.** Tested on an RX 7900 XTX with AMD driver
32.0.32015.12012 and Windows 11 Pro 26H2, build 26300. It preserves AMD's official signed driver and normal Windows
driver-signing policy. RAM mode uses existing signed storage drivers, while the
memory workaround itself requires no companion driver.

**May cause instability, application crashes, or loss of AMD features. Driver or
Windows updates may break the workaround or leave protection temporarily inactive.**
Testing on this PC does not establish compatibility with other GPUs, drivers,
Windows builds, or every game and feature. Use at your own risk, keep important
data backed up, and check Status after updates. If problems appear, restore the
saved settings or uninstall. No stability, compatibility, or continuous-protection
guarantee is provided; see the MIT license.

By [JZB Apps](https://jzbapps.com). Support: [support@jzbapps.com](mailto:support@jzbapps.com).
Independent of AMD and Microsoft; not endorsed by either company.

## Requirements

No separate app framework needs to be installed. The guard uses Windows' built-in
Windows PowerShell 5.1, .NET Framework, PnP, scheduled-task, and storage components.
It does not require PowerShell 7, a modern .NET Desktop Runtime or SDK, Visual C++
Redistributable, Python, Node.js, or Inno Setup on the target PC.

Use 64-bit Windows with an official AMD Radeon driver, administrator access, and
the standard Windows management components enabled. Only the configuration listed
above has been hardware-validated. RAM mode additionally requires the signed Arsenal miniport and
AWEAlloc drivers: the offline EXE includes their original packages, verifies them,
and installs them if missing. No dependency download is needed during Setup.
Standard Windows trust roots and driver-signing policy must already permit the
vendor drivers to load; the installer does not bypass Windows security policy.

## Use

Run **RadeonMemoryGuard-OfflineSetup-0.5.0.exe**, accept the administrator prompt, and
leave the complete setup selected. It installs memory maintenance and any missing
verified RAM-storage dependencies from the bundled payload, and enables the fixed
64 MiB RAM redirect while keeping AMD External Events Utility running. Windows
and the GPU are not restarted.
Choose Custom to install only memory maintenance. Deselecting RAM during a later
repair does not remove an existing RAM setup; use RestoreSsd or uninstall to restore it.

The release EXE and uninstaller are self-signed with the dedicated JZB Apps
experimental key. This is integrity signing, not publicly trusted Windows publisher
verification. Windows or organization policy may warn or block execution. Vendor
storage drivers retain their original signatures. Setup never imports a trust
certificate or changes signing policy. A SHA-256 checksum is computed after signing.
See [code signing policy](https://github.com/jb14813/Radeon-Memory-Guard/blob/main/SIGNING.md)
for the public certificate fingerprint and verification commands.
Remove it through **Windows Settings > Apps > Installed apps**, or use
**Radeon Memory Guard > Restore and uninstall** in the Start menu. Removal restores
saved settings and releases RAM before deleting recovery scripts. If restoration
fails, removal stops and retains the files for recovery. Shared dependencies and
backup ledgers remain installed. Run the EXE again to repair or update the guard.

For advanced use, extract the portable release ZIP to a local folder. If Windows marks the download as blocked,
unblock the ZIP in its Properties before extraction. Open **Windows PowerShell
5.1 as Administrator** in the extracted folder:

```powershell
# Inspect the adapter and setting without changing them.
.\RadeonMemoryGuard.ps1 -Action Status -Json

# Apply once, install to Program Files, and enable automatic maintenance.
.\RadeonMemoryGuard.ps1 -Action Install
```

Installation creates one SYSTEM scheduled task, `JZBApps-RadeonMemoryGuard`, which
runs at startup and every five minutes. It uses Windows PowerShell and requires no
paid certificate, cloud account, Python, or background application.

The task selects PowerShell's `RemoteSigned` policy for its own process so it can
run the protected local scripts under SYSTEM. Machine-wide policy is unchanged,
and enforced Group Policy still takes precedence.

Maintenance dynamically resolves present AMD PCI display adapters to their current
service. It checks for the official Microsoft hardware signature and the setting
name in `amdkmdag.sys` before writing. Each service's original value or absence is
saved before the first change. Unsupported drivers and unexpected value types are
left unchanged. A valid signature and setting-name match are compatibility checks;
they do not establish effectiveness on every driver version.

## What happens after a driver update?

The next maintenance run rediscovers the active service and reapplies the setting
if necessary. It never changes the INF, catalog, driver binary, Secure Boot, HVCI,
or Windows signing policy. It never restarts the GPU or Windows automatically.

**Reapplication is not immediate activation.** A new driver may read its settings
before the maintenance task gets to run. If the task reports `AppliedNeedsReload`,
the setting is saved for the next driver reload or Windows restart. A five-minute
check cannot guarantee uninterrupted protection during installation. Check Status
after updating, then reload the driver or restart Windows when convenient. The
tool reports configuration separately from actual leak validation.

## Optional SSD write-loop protection with AMD kept running

On the tested PC, AMD External Events Client Module repeatedly copied the same
677,392-byte executable to the SYSTEM profile's `AppData\Local\AMD\atieclxx.exe`.
File and disk tracing confirmed writes reaching the system SSD. Stopping External
Events Utility stopped the loop; starting it reproduced the loop immediately.
This is a separate issue from the process-watcher memory leak.

The complete EXE setup enables RAM mode. For a portable installation, opt in from
an administrator Windows PowerShell:

```powershell
# Download the pinned original signed storage-driver package.
.\RadeonMemoryGuard.ps1 -Action InstallRamBackend
# Redirect the repeatedly overwritten cache executable into locked physical memory.
.\RadeonMemoryGuard.ps1 -Action ProtectSsdRam
.\RadeonMemoryGuard.ps1 -Action Status -Json
# Restore the original cache file and service settings, and release the RAM disk.
.\RadeonMemoryGuard.ps1 -Action RestoreSsd
```

RAM mode uses a fixed **64 MiB RAM disk**, plus filesystem and driver overhead.
AWEAlloc backs it with physical pages that are released when its backing handle
closes. It does not use a persistent disk image or a pageable RAM-disk allocation.
Repeated copies overwrite the same file, so the number of writes does not cause
the memory allocation to grow. The surrounding AMD shader-cache folders stay in place.

Only the identified SYSTEM-profile `atieclxx.exe` cache file is redirected through
an absolute file link. The valid AMD executable remains readable at its expected
path. The original cache file and service configuration are backed up first.
After redirecting, the guard starts External Events Utility and sets its startup
type to Manual: the SYSTEM task prepares RAM and starts AMD at Windows startup,
then checks the binding every five minutes. A healthy check does not restart AMD.
If the RAM volume disappears, maintenance stops this service, rebuilds the volume,
repairs its link, and starts it again. Windows and the display device stay running.

The offline EXE bundles the pinned, unmodified Arsenal driver package and its
source archive. Our own controller calls Windows setup and storage APIs; no
third-party desktop app or command-line tool is installed or launched. Only the
Arsenal miniport and AWEAlloc are used. Unneeded auxiliary service registrations
introduced by the original INF are removed before they can start. Windows keeps
the original complete signed package in its Driver Store.

Driver hashes and Microsoft hardware signatures are checked. No certificates
are created or imported, and Secure Boot, HVCI, signing policy and Test Mode are
unchanged. Setup never reboots Windows or restarts the display device. If Windows
defers activation, Setup reports the condition instead of requesting a restart.

Uninstall releases the RAM disk first. It removes the controller it created when
unused, preserves pre-existing/shared drivers, and records anything Windows keeps
loaded. A live driver is never force-unloaded or marked for deletion. Recovery and
ownership ledgers remain available under ProgramData.

Upgrading from another RAM backend requires using that installed version's restore
and uninstall first, then archiving its inactive `ram-cache.json` ledger. Keep the
saved service/memory backups. Setup refuses to overwrite an incompatible backend;
there is no automatic backend migration.

The replacement backend passed isolated physical-memory creation, eight 4 MiB
write/readback cycles, LUN removal, and scoped PnP controller installation/removal
without a reboot. A 72.52-second trace recorded 35,928,064 bytes of repeated executable-cache disk
writes reaching the RAM device only, with zero associated cache writes to the SSD
and zero events lost. Free RAM-disk space stayed constant. After cleanup and a
simulated update repair, a separate 30.13-second trace recorded another 14,913,536
bytes reaching RAM only, also with zero events lost. Ordinary logs, shader caches
and one-time backup writes remain on disk.

Restore/re-enable, recovery after RAM-device loss, replacement-cache repair and
startup-type reset recovery passed without an additional Windows reboot. A
250-process launch workload retained no AMD File/IoNm allocations in strict pool
tracing. Offscreen D3D11 readback and D3D12 allocation/queue checks passed; actual
games, new driver installations, sleep/resume and cold startup of this release
have not been comprehensively tested. See [validation coverage](VALIDATION.md).
Administrative Status is needed to inspect the protected link and storage backend.

After a driver update, writes can recur before the next five-minute check repairs
a replaced link or service configuration. Recheck with tracing when changing AMD
versions. RAM mode is an I/O mitigation; AMD's original retry loop still runs.

### Alternative: stop the service

The earlier service-disabling option is still available:

```powershell
.\RadeonMemoryGuard.ps1 -Action ProtectSsd
# Undo only SSD protection; memory maintenance keeps running.
.\RadeonMemoryGuard.ps1 -Action RestoreSsd
```

`ProtectSsd` backs up the original startup, running, and delayed-start settings,
then disables and stops **AMD External Events Utility**. It takes effect immediately
without restarting Windows or the GPU. **AMD hotkeys and some event-driven display
or profile features may be unavailable while this service is disabled.** Graphics
features require testing for your own workload. This is a service workaround,
not an AMD driver repair; restore the service and retest after an official fix.

The portable memory-only installation leaves both SSD modes off. The EXE's
complete setup selects RAM redirection. With explicit service-disabling opt-in, the maintenance
task checks the validated AMD service at startup and every five minutes and
disables it again if an update re-enables it. Writes may recur before that check.
It retains the original backup rather than replacing it with an update's defaults.
It refuses an unexpected executable or signature and never replaces AMD files.
Status reports the opt-in and current service state; tracing is needed to verify
write behavior. Logical write counters do not establish NAND wear or SSD health loss.

AMD has acknowledged an interaction involving External Events Utility and the
Microsoft PCIe filter in [this discussion](https://www.reddit.com/r/buildapc/comments/1x4153i/problem_with_amd_external_events_client_module/).

## Remove or restore

```powershell
# Stop maintenance and restore saved memory settings and opted-in SSD settings.
.\RadeonMemoryGuard.ps1 -Action Restore

# Restore settings, remove the task, and remove the installed program files.
.\RadeonMemoryGuard.ps1 -Action Uninstall

# Remove maintenance while keeping the current memory and SSD workarounds in place.
.\RadeonMemoryGuard.ps1 -Action Uninstall -KeepSetting
```

Restoration preserves a setting subsequently changed by an administrator and
reports `RestoreConflict`. Backups remain in
`C:\ProgramData\JZBApps-RadeonMemoryGuard` for inspection. If a value was already 0
when this utility first saw it, its original state is 0; uninstall keeps that prior
workaround. Restored settings also take effect after a driver reload.
`-KeepSetting` is refused while RAM mode is active because RAM must be recreated
at startup. Normal uninstall restores the original file and service settings and
releases the owned RAM disk. Backup ledgers remain for inspection.

`-WhatIf` previews administrator actions. Read-only Status also supports
PowerShell 7; administrator actions use Windows PowerShell 5.1.

## Scope and evidence

The identified AMD path acquires a file-object reference and a DOS-name buffer
without releasing them during detailed process inspection. Setting 0 selects its
basic process-event path. This may affect features that depend on detailed process
inspection; gaming, multiple GPUs, and debugger integrations need broader testing.

On the tested PC, strict WPR traces showed one retained `File` and `IoNm` allocation
per process start before the workaround. Follow-up traces after application,
after reboot, after 2.5 hours, and after 38.5 hours showed zero retained allocations
on that AMD path. The latest trace captured 571 process starts. This is evidence
for the tested configuration, not certification of all AMD hardware or releases.

This utility prevents recurrence of the observed path. It cannot reclaim kernel
allocations already orphaned in the running Windows session.

Related independent report:
[Windows-Containers issue 623](https://github.com/microsoft/Windows-Containers/issues/623#issuecomment-5688123405).
The project is independent of AMD and Microsoft.

## Development

```powershell
powershell -NoProfile -File tests\Test-Core.ps1
pwsh -NoProfile -File tests\Test-Core.ps1
powershell -NoProfile -File tests\Test-Ssd.ps1
pwsh -NoProfile -File tests\Test-Ssd.ps1
powershell -NoProfile -File tests\Test-Ram.ps1
pwsh -NoProfile -File tests\Test-Ram.ps1
powershell -NoProfile -File tests\Test-Storage.ps1
pwsh -NoProfile -File tests\Test-Storage.ps1
powershell -NoProfile -File tests\Test-StorageInventory.ps1
pwsh -NoProfile -File tests\Test-StorageInventory.ps1
powershell -NoProfile -File tests\Test-Backend.ps1
pwsh -NoProfile -File tests\Test-Backend.ps1
powershell -NoProfile -File tools\Build-Release.ps1
# Requires free Inno Setup 6; produces the local unsigned EXE and checksum.
powershell -NoProfile -File tests\Test-Installer.ps1
```

Tests use synthetic driver discovery, registry operations, and a service backend,
including update resets, rollback conflicts, failed writes, and delayed startup.
No real service or machine registry setting is modified. No proprietary driver or trace is needed. The release
package contains only the utility, README, license, and version. Raw ETL traces,
machine logs, certificates, and experimental driver patches are excluded.

There is no telemetry or upload service. Offline Setup uses bundled dependencies.
Portable online dependency setup downloads from GitHub. Windows
signature verification can use Windows' certificate trust/revocation infrastructure.
Licensed under MIT; see [LICENSE](LICENSE).
