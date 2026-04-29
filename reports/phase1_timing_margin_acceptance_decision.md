# Phase 1 Timing Margin Acceptance Decision

Date: `2026-04-24`  
Task: `task-ee0187aa`  
Role: orchestrator

## Decision

Accept the Phase 1 timing/resource margin hardening build as the current implementation baseline.

Authorize the next controlled experiment as a narrow two-voice feasibility slice.

This is not a general polyphony milestone. It is a single-dimension experiment to measure whether the current reduced voice can be duplicated or otherwise scheduled as two simultaneous hardware-owned voices without breaking timing, memory, UART observability, or audio behavior.

## Accepted Baseline

Reference artifacts:

- Prior acceptance: `reports/phase1_observability_acceptance_decision.md`
- Implementation report: `reports/phase1_timing_margin_impl_report.md`
- Validation report: `reports/phase1_timing_margin_validation.md`

Accepted build identity:

- SOF checksum: `0x0047FF19`
- SOF SHA-256: `22ADDED0CF998F728B63CD94CE6493CEEC9B506E115C9680F11A6C3986E15626`

Resource baseline:

| Metric | Timing-Margin Baseline |
| --- | ---: |
| Logic elements | `5683 / 10320` |
| Registers | `2588` |
| Memory bits | `266752 / 423936` |
| M9Ks | `33 / 46` |
| DSP9 elements | `2 / 46` |
| PLLs | `1 / 2` |

Timing baseline:

| Clock | Slow-85C setup slack | Slow-85C hold slack |
| --- | ---: | ---: |
| `sys_clk_50m` | `+3.170 ns` | `+0.432 ns` |
| `i2c_clk` | `+18.167 ns` | `+0.453 ns` |
| `audio_bclk` | `+315.933 ns` | `+0.453 ns` |

Additional baseline facts:

- `sys_clk_50m` Fmax: `59.42 MHz`
- Worst current setup path remains RV32I writeback, not the voice datapath.
- CPU remains out of the per-sample audio loop.
- UART `I/S/R/V/F/T/A/W` observability is accepted.
- Registers through `0x50` are accepted and must remain compatible.
- Delay line remains synchronous M9K-backed.
- Voice multiplier remains DSP-backed.
- Hardware audio capture remains a decaying non-square tone near `436 Hz` with zero clipped samples.

## Why Two-Voice Is Now Allowed

The previous observability build was not a good starting point for voice scaling because `sys_clk_50m` setup slack had fallen to `+0.889 ns`.

The timing-margin pass changed the situation:

- `sys_clk_50m` setup slack improved to `+3.170 ns`.
- LE use dropped from `6515` to `5683`.
- M9K, memory-bit, DSP9, and PLL counts stayed flat.
- The sound model and observability behavior were preserved.

This creates enough headroom for one narrow measurement experiment.

## Two-Voice Experiment Scope

Allowed:

- A second instance of the current reduced Phase 1 voice, or a clearly documented minimal two-voice scheduling structure if that is more conservative.
- Two simultaneous or staggered note events sufficient to prove overlap.
- Reuse the current sample-rate contract and current single-voice numerical format.
- Keep the same reduced voice model and default coefficients unless a per-voice duplicate register is needed.
- Extend diagnostics only as needed to distinguish voice 0, voice 1, mix clip/peak, and counters.
- Saturating mix of two voices into the existing mono-to-dual-mono codec path.
- Documentation and reports.

Not allowed:

- richer string/body/hammer physics
- multi-note pitch system or keyboard scheduler
- pedal/damper behavior
- MIDI
- SDRAM
- sample playback
- UI/TFT/touch
- exact-48-kHz clock rework
- larger CPU or new bus fabric
- changing the accepted one-voice behavior as a side effect

Register policy:

- Existing registers through `0x50` must remain compatible.
- New two-voice diagnostic/control registers, if needed, must start after the current diagnostic range and be documented.
- Firmware may trigger/configure voices and report status, but must not service per-sample synthesis.

## Acceptance Targets

A two-voice slice is acceptable only if verifier confirms:

- Firmware build passes.
- ModelSim voice/top/NACK or equivalent two-voice regressions pass.
- Quartus full compile passes.
- TimeQuest remains fully constrained with nonnegative setup and hold slack and `0.000` TNS.
- `sys_clk_50m` setup slack remains comfortably positive; a drop below `+1.0 ns` should trigger review rather than automatic continuation.
- Total LE use remains below `8000 / 10320` for this experiment.
- M9K and memory use remain explicitly documented and justified.
- DSP use remains explicitly documented and justified.
- Delay lines remain M9K-backed; no async-read delay-line implementation is acceptable.
- Multipliers remain DSP-backed or any logic-multiplier mapping is called out as a finding.
- UART observability still reports the accepted baseline frames and enough two-voice state to diagnose active/clip/peak/counter behavior.
- Hardware audio capture shows overlapping or clearly two-trigger behavior, zero clipping or documented acceptable saturation behavior, and no regression to a continuous square baseline.

## Stop Conditions

Stop and report rather than pushing through if:

- timing becomes marginal or fails,
- the second voice forces broad CPU/bus restructuring,
- M9K packing fails in a way that substantially increases LE use,
- the implementation requires SDRAM or clocking changes,
- the sound model changes beyond duplicating/scheduling the current reduced voice,
- UART/debug visibility becomes weaker than the accepted timing-margin baseline.

## Bottom Line

Proceed with a narrow two-voice feasibility slice. Keep the experiment deliberately small and measurement-driven. The goal is not to build the final polyphonic instrument; it is to find the real cost of one additional reduced hardware voice.
