# Changelog

## 0.5.0 - 2026-11-10

- Use our headless Windows API controller and the original signed Arsenal miniport/AWEAlloc drivers.
- Keep runtime and offline payloads limited to the controller and required storage drivers; no third-party desktop app or command-line executable runs.
- Scope device installation/removal to owned controllers and journal ownership before installation completes.
- Preserve pre-existing/shared drivers and remove unused owned components after RAM restoration.
- Reject incompatible prior backend ledgers before replacing installed files; use the prior version's restore/uninstall when changing backends.
- Validate isolated physical RAM writes, readback, LUN cleanup and scoped PnP install/remove without a reboot.

## 0.4.0 - 2026-11-10

- Bundle the original verified RAM-storage packages for offline Setup, with no network fallback.
- Include third-party notices and the pinned Arsenal source archive without modifying vendor signatures.
- Add dedicated JZB Apps self-signed integrity signing for the EXE and uninstaller, public-certificate verification, and post-signing checksums.
- Reject altered release images and provide a separately signed checksum manifest.
- Add tests for missing and corrupted offline payloads and both dependencies absent with downloads blocked.

## 0.3.1 - 2026-11-10

- Brand the EXE, setup wizard, and uninstaller with the approved JZB monogram.
- Add website and support-email links in setup, Start menu, and Installed apps.
- Show experimental status, the tested GPU/driver/Windows configuration, and instability/update limitations before installation.
- Keep the installer unsigned; no certificate or Windows signing-policy change is made.

## 0.3.0 - 2026-11-10

- Add a local Windows EXE installer with elevation, complete setup, repair, and restoration before uninstall. No publication or company signing certificate is involved.
- Add ProtectSsdRam: keep AMD External Events Utility running and redirect its repeated executable writes into a fixed physical-memory volume.
- Prepare RAM at startup, recover missing RAM storage, and repair a cache link replaced by an update.
- Restore the original cache file and service configuration, then release only the owned RAM device.
- Add optional verified, pinned setup of free signed RAM-storage dependencies.
- Preserve shader caches and reject RAM uninstall configurations that would strand a link after startup maintenance is removed.

## 0.2.0 - 2026-11-10

- Add explicit ProtectSsd / RestoreSsd actions for the External Events executable rewrite loop.
- Preserve startup, running, and delayed-start configuration before disabling the validated AMD service.
- Maintain opted-in SSD protection after updates without overwriting the original backup.
- Include SSD service protection in Status, full restoration, and uninstall.
- Preserve later administrator changes and document unavailable service-dependent features.

## 0.1.0 - 2026-11-07

- Inspect active AMD display drivers and the process-watcher setting.
- Maintain the existing workaround at startup and every five minutes.
- Rediscover service names after driver updates; check signatures and the setting marker.
- Save original values before changing them, and restore without overwriting later changes.
- Report pending activation without automatically restarting Windows or the GPU.
- Provide portable release packaging and Windows PowerShell / PowerShell 7 checks.
