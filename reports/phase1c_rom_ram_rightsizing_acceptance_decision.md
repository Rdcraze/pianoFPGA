# Phase 1C-A ROM/RAM Right-Sizing Acceptance Decision

Date: 2026-04-28
Orchestrator: codex-orchestrator
Task: `task-c241c4b0`

## Decision

Promote the Phase 1C-A ROM/RAM right-sized build to the current accepted baseline.

This replaces the prior hardware-accepted two-voice SOF as the active baseline, while retaining the prior SOF identity as the rollback point.

This is a memory-headroom cleanup acceptance only. It does not authorize third voice, SDRAM, scheduler work, body-pipe rewrite, richer physics, UI, sample playback, larger CPU, clock work, or unrelated feature expansion.

## References

- `reports/phase1c_rom_ram_rightsizing_impl_report.md`
- `reports/phase1c_rom_ram_rightsizing_validation.md`
- `reports/phase1c_resource_attribution_acceptance_decision.md`
- `reports/phase1_two_voice_hardware_acceptance_decision.md`

Verifier result for `task-a03a1741`: PASS.

## Accepted Build Identity

Current accepted SOF:

- SOF: `quartus/phase0/output_files/piano_phase0_top.sof`
- SHA-256: `D5D2A283CCF37795CEED9BD79C754003E184AE6927842F4E0112AE6D866FF3EA`
- Programmer checksum: `0x0055BA0E`

Rollback SOF identity:

- prior hardware-accepted two-voice SHA-256: `274C3F3178A08E103B500E724ED15E5FDFF0E58D15DD0EFB94514BECC3523A78`
- prior checksum: `0x00553670`

## Accepted Change

The firmware memory envelope is now:

| Memory | Previous | Accepted Now |
| --- | ---: | ---: |
| Boot ROM | 4,096 x 32 | 1,024 x 32 |
| Data RAM | 4,096 x 32 | 1,024 x 32 |
| ROM bytes | 16 KiB | 4 KiB |
| RAM bytes | 16 KiB | 4 KiB |

Base addresses remain unchanged:

- ROM base: `0x0000_0000`
- RAM base: `0x0001_0000`
- control registers: `0x4000_0000`
- UART MMIO: `0x4000_1000`

Firmware bounds:

- `.text`: `0x37c` bytes
- `phase0.bin`: 892 bytes
- `.data`: empty
- `.bss`: empty
- stack top: `0x00011000`
- MIF depth: 1,024 words

## Resource And Timing Delta

Compared with the prior hardware-accepted two-voice baseline:

| Metric | Prior Two-Voice | Right-Sized Baseline | Delta |
| --- | ---: | ---: | ---: |
| Logic elements | 7,366 / 10,320 | 7,382 / 10,320 | +16 |
| Dedicated registers | 3,580 | 3,580 | 0 |
| Memory bits | 271,360 / 423,936 | 74,752 / 423,936 | -196,608 |
| M9Ks | 34 / 46 | 10 / 46 | -24 |
| DSP9 elements | 4 / 46 | 4 / 46 | 0 |
| PLLs | 1 / 2 | 1 / 2 | 0 |
| Slow-85C `sys_clk_50m` setup slack | +3.957 ns | +3.214 ns | -0.743 ns |
| Slow-85C `sys_clk_50m` hold slack | +0.432 ns | +0.433 ns | +0.001 ns |
| Slow-85C `sys_clk_50m` Fmax | 62.33 MHz | 59.57 MHz | -2.76 MHz |

TimeQuest remains fully constrained with all listed TNS values at `0.000`.

## Hardware Evidence

The right-sized build passed independent hardware smoke:

- USB-Blaster detected.
- Programming succeeded on `EP4CE10F17@1`.
- JTAG ID code observed: `0x020F10DD`.
- UART captured on `COM5`, `115200 8N1`.
- Startup and recurring diagnostics were present.
- Captured two-voice signature included:
  - `V=08220010`
  - `T=00000001`
  - `Y=08220010`
  - `U=00000001`
  - `M=10440010`
  - `K=00000000`
- External Realtek audio capture passed.
- Measured tone was about 435.5 Hz.
- Total clipped samples: `0`.
- No square-wave regression indicated.

## Interpretation

This slice achieved the intended result: it removed avoidable M9K pressure from oversized firmware ROM/RAM while preserving the accepted two-voice audio/control behavior.

The design is no longer M9K-tight in the same way:

- previous M9K use: 34 / 46
- current M9K use: 10 / 46

This does not materially improve the main future polyphony risk:

- LE use slightly increased to 7,382 / 10,320.
- The RV32I core and duplicated voice engines remain the dominant LE/register contributors.
- A third duplicated voice remains gated and should not be treated as safe just because M9Ks are now available.

## Still Gated

The following remain gated pending separate orchestrator decisions:

- third voice or broader polyphony;
- body-pipe/tap-storage rewrite;
- SDRAM feasibility;
- minimal scheduler;
- richer piano model;
- exact-48-kHz clock/PLL work;
- larger CPU or ISA changes;
- UI/TFT/touch work;
- sample playback;
- broad diagnostic removal.

## Next Recommendation

If continuing Phase 1C hardening, the next rational option is a separate decision on the body-pipe/tap-storage optimization, because it is the candidate that might reduce per-voice register/LE pressure.

That work must be isolated from voice-count, scheduler, SDRAM, clock, and model changes, and it should require bit-exact or signature-preserving simulation before hardware acceptance.

