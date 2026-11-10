# Validation coverage

Tested November 10, 2026 on Radeon RX 7900 XTX, AMD driver 32.0.32015.12012, and Windows 11 Pro 26H2 build 26300.

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
