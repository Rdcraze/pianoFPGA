# Phase 1C Third-Voice Acceptance Decision

Date: 2026-04-28
Orchestrator: codex-orchestrator
Task: `task-05c1d75d`

## Decision

Promote the Phase 1C third-voice build as a narrow three-voice feasibility baseline.

This acceptance means the platform has now demonstrated three simultaneous optimized reduced voices with clean simulation, Quartus/TimeQuest closure, and hardware UART/audio smoke.

This is not authorization for scheduler work, fourth voice, SDRAM, richer physics, UI, sample playback, larger CPU, clock work, or broader polyphony architecture.

## References

- `reports/phase1c_third_voice_impl_report.md`
- `reports/phase1c_third_voice_validation.md`
- `reports/phase1c_third_voice_authorization_decision.md`
- `reports/phase1c_body_pipe_optimization_acceptance_decision.md`

Verifier result for `task-f1a5b36e`: PASS.

## Accepted Build Identity

Current accepted SOF:

- SOF: `quartus/phase0/output_files/piano_phase0_top.sof`
- SHA-256: `91784AE1B85E69F989D4CD09273466E14A6FAB66A557AD8ACDA296F990A07A0E`
- Programmer checksum: `0x005B2137`

Rollback baseline:

- Phase 1C-B two-voice optimized SHA-256: `48BAB4ACBAD44899E5FB8E25B89496B4E4A8C1AFEF0CF110178EB8C481849510`
- Phase 1C-B checksum: `0x0050ADE7`

## Accepted Change

The build adds one optimized reduced voice instance, producing three simultaneous hardware-owned voices.

Accepted scope:

- one additional optimized reduced voice;
- no scheduler or note allocator;
- no fourth voice;
- same coefficients/defaults;
- same ROM/RAM sizing;
- same clocking/sample-rate contract;
- same CPU and firmware-owned control architecture;
- same codec/output path;
- additive post-map voice2 registers only;
- UART frames remain prefix-compatible through the existing sequence.

## Register And UART Additions

Existing registers remain unchanged through `0x6C`.

New registers:

| Offset | Name |
| --- | --- |
| `0x70` | `PHASE0_REG_VOICE2_CONTROL` |
| `0x74` | `PHASE0_REG_VOICE2_STATUS` |
| `0x78` | `PHASE0_REG_VOICE2_TRIGGER_COUNT` |
| `0x7C` | `PHASE0_REG_VOICE2_ACTIVE_COUNT` |
| `0x80` | `PHASE0_REG_VOICE2_VALID_COUNT` |

Existing UART frames remain in order through:

`V, F, T, A, W, Y, U, B, C, M, K`

New appended frames:

- `Z`: voice2 status
- `O`: voice2 trigger count
- `D`: voice2 active count
- `E`: voice2 valid count

## Resource And Timing Delta

Compared with the Phase 1C-B accepted baseline:

| Metric | Phase 1C-B Accepted | Three-Voice Accepted | Delta |
| --- | ---: | ---: | ---: |
| Logic elements | 6,474 / 10,320 | 7,548 / 10,320 | +1,074 |
| Dedicated registers | 2,748 | 3,275 | +527 |
| Memory bits | 75,776 / 423,936 | 80,896 / 423,936 | +5,120 |
| M9Ks | 12 / 46 | 14 / 46 | +2 |
| DSP9 elements | 4 / 46 | 6 / 46 | +2 |
| PLLs | 1 / 2 | 1 / 2 | 0 |
| Slow-85C `sys_clk_50m` setup slack | +3.907 ns | +3.675 ns | -0.232 ns |
| Slow-85C `sys_clk_50m` hold slack | +0.432 ns | +0.433 ns | +0.001 ns |
| Slow-85C `sys_clk_50m` Fmax | 62.14 MHz | 61.26 MHz | -0.88 MHz |

Stop criteria were met:

- LE use below `8,200 / 10,320`;
- `sys_clk_50m` setup slack above `+1.0 ns`;
- setup and hold fully constrained;
- all listed TNS values `0.000`;
- M9K and DSP mapping preserved as expected;
- default mix clip count remains `0`.

## Hardware Evidence

Verifier hardware smoke passed:

- USB-Blaster detected.
- Programming succeeded on `EP4CE10F17@1`.
- JTAG ID code observed: `0x020F10DD`.
- UART captured on `COM5`, `115200 8N1`.
- Existing frames through `K` were present.
- Appended `Z/O/D/E` frames were present.
- Steady UART signature included:
  - `V=08220010`
  - `Y=08220010`
  - `Z=08220010`
  - `T=00000001`
  - `U=00000001`
  - `O=00000001`
  - `M=18660010`
  - `K=00000000`
- Mix peak `0x1866` equals 6,246, matching three voices at peak 2,082.
- External audio capture passed.
- Audio showed 0 clipped PCM samples.
- Dominant spectral peak was around 435.9 Hz.
- Verifier measured the three-voice capture at about +3.37 dB RMS versus the Phase 1C-B two-voice capture.

## Interpretation

This is a significant feasibility result. The EP4CE10 platform can host:

- the minimal RV32I control plane;
- WM8978 output path;
- three optimized reduced physical-model voices;
- UART observability;
- clean timing at 50 MHz;
- hardware playback without clipping in the default smoke case.

The project now has a credible three-voice reduced-physics baseline.

It is still not a scalable instrument architecture. The current build proves a fixed simultaneous three-voice slice, not note allocation, voice stealing, velocity handling, pedal behavior, richer physical modeling, or general polyphony management.

## Still Gated

The following remain gated pending separate decisions:

- scheduler or note allocator;
- fourth voice;
- SDRAM feasibility;
- richer piano model;
- exact-48-kHz clock/PLL work;
- larger CPU or ISA changes;
- UI/TFT/touch work;
- sample playback;
- register-map expansion beyond controlled diagnostics;
- UART diagnostic expansion beyond controlled diagnostics;
- diagnostic removal or cleanup mixed with feature work.

## Next Recommendation

Do not proceed directly to a fourth voice.

The next useful milestone should be a design-only scheduler/control memo for the current three voices. It should define how note events would be assigned to the three existing voices without adding another voice or changing the sound kernel.

The memo should compare:

- firmware-triggered simple round-robin assignment;
- small hardware note-event dispatcher;
- keeping simultaneous fixed triggers and moving next to another optimization pass.

No scheduler implementation should start until that decision memo is reviewed.

