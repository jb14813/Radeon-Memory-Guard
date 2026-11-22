# Validation coverage

## Native fixes: Adrenalin 26.11.2

Tested November 22, 2026 on Radeon RX 7900 XTX and Windows 11 Pro 26H2 build 26300. The driver was already installed. Original driver settings were restored, the owned RAM cache was detached, and only the Radeon display device was reloaded. Windows remained in the same boot session.

| Image | Version label | SHA-256 |
| --- | --- | --- |
| amdkmdag.sys | 32.0.32029.2010 | `84BF65785C9D59206D9800915FDD4B4A5CF13A702836347124328E7A780F57CD` |
| atiesrxx.exe | 6.14.11.1290 | `220E65D90CCC546CB93C14B7469906B681F38B619A838129005F3B54583A5F30` |
| atieclxx.exe | 6.14.11.1290 | `BC31696C0CA9361C55BB5FF34BF28E327FEF1ECD4C22C87A0852E66BF4C0CD28` |

- With the process-watcher override absent, 250 controlled process launches retained zero AMD-associated File/IoNm allocations. Strict processing rejected lost events/time inversion, and outstanding tagged intervals had stack coverage.
- With External Events Utility running at its original Automatic startup and its client running, a 60.03-second native I/O trace recorded zero writes to the identified SYSTEM-profile cache. The trace included 15 seconds of warm-up and 45 seconds of steady state, with zero lost events. No RAM redirection was active.
- These image identities are the native-fix recognition contract in 0.6.0. Memory recognition requires the validated signed driver image; SSD recognition also requires the validated service/client pair. A matching version string alone is insufficient.
- Hardware graphics smoke checks passed: 96 D3D11 clear/copy/full-readback cycles, 96 D3D12 buffer allocation/release cycles, and 12 device lifetimes and queue/fence checks per applicable API.

[AMD's 26.11.2 notes](https://www.amd.com/en/resources/support-articles/release-notes/RN-RAD-WIN-26-11-2.html) describe a process-launch memory leak fix and an excessive-write fix scoped to RX 5000/6000 graphics on Windows 10. The RX 7900 XTX/Windows 11 SSD result above is a separate local observation, not an expansion of AMD's stated coverage.

The display reload interrupted other GPU applications on the test host. Visual sensor checks and full game benchmarks are outside this native-driver validation. These observations do not establish uninterrupted application recovery or comprehensive game compatibility.

## Workarounds: driver 32.0.32015.12012

Tested November 10, 2026 on Radeon RX 7900 XTX and Windows 11 Pro 26H2 build 26300.

| Check | Result |
| --- | --- |
| RAM storage | Arsenal 7.12.10.629 miniport and AWEAlloc |
| Isolated storage | Fixed 64 MiB physical RAM; eight 4 MiB write/readback cycles; scoped LUN and PnP cleanup |
| Healthy maintenance | AMD service PID and RAM volume unchanged |
| Restore and re-enable | Original service/file restored, owned RAM released, protection recreated |
| Lost RAM disk | Rebuilt before AMD service resumed |
| Simulated update | Replaced cache link and Automatic startup repaired; healthy RAM reused and original backup preserved |
| Primary write trace | 72.52 seconds; 35,928,064 cache bytes to RAM only; zero associated cache bytes to SSD; zero events lost; free space constant |
| Independent follow-up | 30.13 seconds; 14,913,536 cache bytes to RAM only; zero associated cache bytes to SSD; zero events lost |
| Process-start leak check | 250 controlled process launches; zero retained AMD File/IoNm allocations; strict processing rejected lost events/time inversion; outstanding tagged allocations had stack coverage |
| Graphics smoke check | 96 D3D11 clear/copy/full-readback cycles; 96 D3D12 buffer allocation/release cycles; 12 device lifetimes and queue/fence checks per applicable API; no display recovery events |
| Automated suites | 118 assertions in Windows PowerShell 5.1 and 118 in PowerShell 7; system mutations mocked in unit tests |
| Review | No unresolved Critical or Important findings |

These bounded checks do not establish universal gaming or stability compatibility. Full game benchmarks, FreeSync/HDR, recording, sleep/resume, a real newer AMD driver installation, cold startup of this release, and fresh-PC dependency installation remain unvalidated. Ordinary log/shader-cache writes and one-time recovery backup writes still reach disk. The AMD retry loop continues; its repeated cache writes are redirected.
