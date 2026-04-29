# Phase 1 Observability Acceptance Decision

Date: `2026-04-24`  
Task: `task-a8271316`  
Role: orchestrator

## Decision

Accept the Phase 1 observability build as the current measurement baseline.

Authorize the next controlled step as timing/resource margin hardening, not a second voice and not richer physics.

Reason: observability is now good enough to support scaling decisions, but the build used `6515 / 10320` LEs and reduced slow-85C `sys_clk_50m` setup margin to `+0.889 ns`. That is a valid pass, but it is not the right state from which to add another synthesis voice or a larger kernel.

## Accepted Measurement Baseline

Reference artifacts:

- Freeze decision: `reports/phase1_reference_baseline_decision.md`
- Observability implementation: `reports/phase1_observability_impl_report.md`
- Observability validation: `reports/phase1_observability_validation.md`

Validated observability build:

- SOF checksum: `0x004DD5CF`
- SOF SHA-256: `FD95A04309291AD7E5EF1F1B26BFC1677053238CEBE9EBB3E474B6B19EC586D7`
- UART frames now include:
  - `V=` `VOICE_STATUS`
  - `F=` sample/frame counter
  - `T=` accepted trigger counter
  - `A=` active-valid sample counter
  - `W=` valid-sample counter
- Diagnostic registers are `0x40..0x50`.
- Frozen Phase 1 voice registers through `0x3C` are preserved.
- CPU remains out of the per-sample loop.
- Delay line remains synchronous M9K-backed.
- Voice multiplier remains DSP-backed.

Resource delta versus frozen Phase 1 reduced-voice baseline:

| Metric | Frozen Phase 1 | Observability | Delta |
| --- | ---: | ---: | ---: |
| Logic elements | `6308` | `6515` | `+207` |
| Registers | `2394` | `2523` | `+129` |
| Memory bits | `266752` | `266752` | `0` |
| M9Ks | `33` | `33` | `0` |
| DSP9 elements | `2` | `2` | `0` |
| PLLs | `1` | `1` | `0` |

Timing delta:

| Metric | Frozen Phase 1 | Observability | Delta |
| --- | ---: | ---: | ---: |
| `sys_clk_50m` setup slack | `+1.234 ns` | `+0.889 ns` | `-0.345 ns` |
| `sys_clk_50m` Fmax | `53.29 MHz` | `52.33 MHz` | `-0.96 MHz` |
| `sys_clk_50m` hold slack | `+0.429 ns` | `+0.432 ns` | `+0.003 ns` |

Hardware validation:

- COM4 UART reported `I/S/R` plus `V/F/T/A/W` frames.
- `V=08220010` decoded as peak `0x0822` / `2082`, voice enabled, inactive after decay, no clip.
- External audio capture showed a decaying non-square tone near `436.1 Hz` on both channels with zero clipped samples.

## Next Controlled Step

Create one implementer task: Phase 1 timing/resource margin hardening.

Allowed changes:

- Retiming, staging, register fanout reduction, mux/data-path cleanup, or other localized implementation changes that improve timing/resource margin.
- Diagnostic-path cleanup only if it reduces fanout or area without removing the accepted `V/F/T/A/W` visibility.
- Documentation/report updates.

Not allowed:

- second voice
- polyphony
- richer body/string physics
- SDRAM
- UI/TFT/touch
- sample playback
- exact-48-kHz clocking rework
- larger CPU or new software stack
- changed sound model or changed default note behavior
- register incompatibility through `0x50`

Target criteria:

- Preserve the accepted Phase 1 audio behavior and observability output.
- Keep all existing registers through `0x50` compatible.
- Keep CPU out of the per-sample synthesis loop.
- Keep delay lines M9K-backed and multiplier DSP-backed.
- Keep memory/M9K/DSP/PLL counts unchanged unless a clearly justified timing improvement requires otherwise.
- Stay below `7000` LEs.
- Improve or at least not materially worsen the current `+0.889 ns` slow-85C `sys_clk_50m` setup margin.
- Prefer recovering margin toward or above the frozen pre-observability `+1.234 ns` level.
- Maintain fully constrained TimeQuest setup/hold with zero TNS.
- Reproduce firmware, ModelSim, Quartus/TimeQuest, UART, and hardware audio smoke evidence.

## Go/No-Go For Later Two-Voice Or Richer-Kernel Work

A later scaling task may be considered only after timing/resource hardening is independently validated.

Minimum go criteria before attempting a second voice or richer kernel:

- `sys_clk_50m` setup slack remains comfortably positive after diagnostics.
- Resource trend is understood and documented against both frozen Phase 1 and observability baselines.
- UART `V/F/T/A/W` counters remain usable during hardware runs.
- Audio capture remains non-clipping and decaying, not a regression to square-wave behavior.
- The next experiment changes only one dimension.

If margin cannot be improved or materially worsens, the next task should be an architectural review of the worst path and resource/fanout pressure, not feature expansion.

## Bottom Line

The project has earned a controlled next step, but the next step is margin recovery. Two voices or richer physics are still gated by timing and resource evidence.
