# Minimal RAM backend implementation

Goal: provide a headless controller using the original signed Arsenal miniport and AWEAlloc, with only required runtime dependencies.

Constraints: no automatic Windows/GPU restart, no signing-policy changes, preserve original AMD files/settings and shared drivers, fixed 64 MiB locked physical memory, no temporary backend migration code.

- [x] Validate scoped PnP controller installation/removal and physical RAM readback.
- [x] Journal controller/package ownership and interrupted-operation recovery.
- [x] Integrate direct Windows setup/storage APIs and offline driver payloads.
- [x] Verify both PowerShell engines, self-sign with the existing project key, and independently review failure paths.
- [x] Validate the installed redirect, restoration, lost-device recovery, simulated update repairs, graphics APIs and file/disk writes.
- [x] Remove unused previous software and its driver through normal live device/package removal.

The runtime remains a hidden SYSTEM scheduled task; converting it to a permanent Windows service is a separate change. Current coverage and limits are recorded in ../../../VALIDATION.md.
