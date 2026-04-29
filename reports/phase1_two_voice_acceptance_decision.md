# Phase 1 Two-Voice Acceptance Decision

Date: 2026-04-25
Orchestrator: codex-orchestrator
Task: `task-46d60ffc`

## Decision

Accept and freeze the Phase 1 two-voice build as the current tool-validated baseline.

This is not yet a hardware-accepted baseline. The verifier could not run board smoke because `quartus_pgm -l` reported no JTAG hardware and Windows reported no serial COM ports. Hardware UART/audio validation remains a required deferred gate before any claim that this exact SOF is live-board accepted.

## Basis

References:

- `reports/phase1_two_voice_impl_report.md`
- `reports/phase1_two_voice_validation.md`
- `reports/phase1_timing_margin_acceptance_decision.md`

The implementation and verifier agree on the essential facts:

- The build duplicates the accepted reduced Phase 1 voice once.
- The CPU remains in the control/status/UART role and is not in the per-sample synthesis loop.
- Existing registers through `0x50` remain compatible.
- New diagnostics start at `0x54`.
- UART `I/S/R/V/F/T/A/W` is preserved and extended with `Y/U/B/C/M/K`.
- The two voices are mixed through signed 17-bit addition with signed 16-bit saturation.
- No SDRAM, sample playback, richer physics, larger CPU, UI/TFT/touch, exact-48-kHz PLL work, new bus fabric, or unrelated cleanup was added.
- Delay lines remain synchronous M9K-backed.
- Multipliers remain DSP-backed.

## Frozen Build Identity

- SOF: `quartus/phase0/output_files/piano_phase0_top.sof`
- SOF checksum: `0x00553670`
- SOF SHA-256: `274C3F3178A08E103B500E724ED15E5FDFF0E58D15DD0EFB94514BECC3523A78`

## Resource And Timing Snapshot

Compared with the accepted timing-margin baseline:

| Metric | Timing-Margin Baseline | Two-Voice Build | Delta |
| --- | ---: | ---: | ---: |
| Logic elements | 5,683 / 10,320 | 7,366 / 10,320 | +1,683 |
| Dedicated registers | 2,588 | 3,580 | +992 |
| Memory bits | 266,752 / 423,936 | 271,360 / 423,936 | +4,608 |
| M9Ks | 33 / 46 | 34 / 46 | +1 |
| DSP9 elements | 2 / 46 | 4 / 46 | +2 |
| PLLs | 1 / 2 | 1 / 2 | 0 |

Timing:

- TimeQuest setup and hold are fully constrained.
- All listed TNS values are `0.000`.
- Slow-85C `sys_clk_50m` setup slack is `+3.957 ns`.
- Slow-85C `sys_clk_50m` hold slack is `+0.432 ns`.
- Slow-85C `sys_clk_50m` Fmax is `62.33 MHz`.
- Worst slow-85C setup path remains in RV32I writeback, not the voice datapath.

The build remains under the `8000 / 10320` LE experiment limit by 634 LEs.

## Validation Status

Passed:

- firmware build
- fresh ModelSim compile
- standalone reduced-voice testbench
- top happy-path testbench
- top NACK-path testbench
- Quartus full compile
- TimeQuest fully constrained setup/hold checks
- M9K and DSP mapping checks

Deferred:

- board programming
- UART capture of baseline `I/S/R/V/F/T/A/W` plus new `Y/U/B/C/M/K`
- analog audio capture
- no-clipping/no-square-regression hardware confirmation

The missing hardware pass is an availability blocker, not a design failure.

## Register Additions

Existing registers through `0x50` remain frozen-compatible. New registers are:

| Offset | Register |
| --- | --- |
| `0x54` | `VOICE1_CONTROL` |
| `0x58` | `VOICE1_STATUS` |
| `0x5C` | `VOICE1_TRIGGER_COUNT` |
| `0x60` | `VOICE1_ACTIVE_COUNT` |
| `0x64` | `VOICE1_VALID_COUNT` |
| `0x68` | `VOICE_MIX_STATUS` |
| `0x6C` | `VOICE_MIX_CLIP_COUNT` |

Expected current firmware behavior for deferred hardware smoke:

- `T=1`
- `U=1`
- `K=0`
- voice0 and voice1 peaks roughly match the simulation signature
- mix peak reflects the two-voice overlap without saturation

## Orchestrator Interpretation

The two-voice experiment is successful, but it also confirms the resource warning.

The design is now around 71% LE utilization and 74% physical M9K utilization. That is acceptable for this controlled experiment, but it is not room for careless duplication. Further scaling must be an architecture decision, not a mechanical "add more voices" task.

DSP headroom remains comparatively strong. Future arithmetic growth should prefer DSP-backed datapaths over LE-heavy soft logic where practical.

SDRAM remains out of scope for the immediate baseline because it would add a separate timing, arbitration, latency, and verification axis. It should be considered only as a bounded memory-system experiment after the current hardware smoke is complete, or after measured on-chip memory pressure requires it.

## Next Work Authorized

Authorized now:

1. Run deferred hardware smoke for this exact SOF when JTAG/UART are visible.
2. Preserve the two-voice tool baseline and its logs/artifacts.
3. If hardware passes, produce a hardware-accepted freeze decision.

Not authorized without a new orchestrator decision:

- third voice or broader polyphony
- richer physics
- SDRAM integration
- sample playback
- larger CPU
- exact-48-kHz clock/PLL rework
- UI/TFT/touch work
- unrelated cleanup mixed with feature work

## Decision Gate

Do not start additional RTL feature expansion until one of the following happens:

- deferred hardware UART/audio smoke passes for this SOF; or
- an explicit architecture review decides to proceed despite missing board evidence.

