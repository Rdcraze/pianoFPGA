# Phase 1 Two-Voice Hardware Acceptance Decision

Date: 2026-04-28
Orchestrator: codex-orchestrator
Task: `task-40708968`

## Decision

Promote the frozen Phase 1 two-voice build from tool-validated to hardware-accepted.

This closes the deferred hardware UART/audio smoke gate for the exact SOF accepted in `reports/phase1_two_voice_acceptance_decision.md`.

This decision does not authorize further feature expansion by itself.

## Evidence

References:

- `reports/phase1_two_voice_acceptance_decision.md`
- `reports/phase1_two_voice_hardware_smoke.md`
- `reports/phase1_two_voice_validation.md`
- `reports/phase1_two_voice_impl_report.md`

Verifier result for `task-691ac888`: PASS.

Hardware smoke confirmed:

- exact frozen SOF programmed successfully
- USB-Blaster JTAG path operational
- active UART path identified as `COM5`
- startup `I/S` frames captured
- recurring baseline `R/V/F/T/A/W` frames captured
- new two-voice `Y/U/B/C/M/K` frames captured
- voice0 trigger count `T=1`
- voice1 trigger count `U=1`
- mix clip count `K=0`
- voice0 peak `0x0822` = 2082
- voice1 peak `0x0822` = 2082
- mix peak `0x1044` = 4164
- external audio capture showed a non-clipped decaying tone around 435.5 Hz
- no square-wave regression was observed

## Accepted Build Identity

- SOF: `quartus/phase0/output_files/piano_phase0_top.sof`
- SOF checksum: `0x00553670`
- SHA-256: `274C3F3178A08E103B500E724ED15E5FDFF0E58D15DD0EFB94514BECC3523A78`
- Programmer target: `EP4CE10F17@1`
- JTAG ID code observed by verifier: `0x020F10DD`

## Accepted Resource Snapshot

The hardware-accepted two-voice build remains the same resource point as the tool-validated baseline:

| Metric | Two-Voice Build |
| --- | ---: |
| Logic elements | 7,366 / 10,320 |
| Dedicated registers | 3,580 |
| Memory bits | 271,360 / 423,936 |
| M9Ks | 34 / 46 |
| DSP9 elements | 4 / 46 |
| PLLs | 1 / 2 |

Timing remains accepted from the prior tool validation:

- fully constrained setup and hold
- all listed TNS values `0.000`
- slow-85C `sys_clk_50m` setup slack `+3.957 ns`
- slow-85C `sys_clk_50m` hold slack `+0.432 ns`
- slow-85C `sys_clk_50m` Fmax `62.33 MHz`

## Interpretation

The platform has now proven a live-board, two-voice, reduced-physics baseline with:

- hardware-owned synthesis
- CPU control/status only
- working WM8978 output path
- UART observability
- no runtime clipping in the smoke capture
- expected doubled mix peak for two simultaneous reduced voices

This is a real milestone. It confirms that the minimal hybrid architecture is viable on the EP4CE10 board for two reduced voices.

It also confirms that future scaling must stay disciplined. The design is already about 71% of available LEs and 74% of available M9Ks. Further naive voice duplication is likely to run into logic, routing, and memory-packing limits before the nominal FPGA totals are exhausted.

## Scope Limits

This decision accepts only the current simultaneous two-voice reduced model.

It does not validate or authorize:

- third voice or larger polyphony
- richer piano physics
- velocity layers or sample playback
- SDRAM integration
- exact-48-kHz clock/PLL rework
- larger CPU
- UI/TFT/touch work
- new bus fabric
- unrelated cleanup mixed with feature work

## Next Allowed Work

The next useful milestone should be an architecture review before another implementation slice.

That review should decide one controlled axis only:

1. reduce per-voice LE cost before adding more voices;
2. move more arithmetic into DSP-backed datapaths;
3. design a minimal scheduler while keeping the current two-voice kernel fixed;
4. perform a bounded SDRAM feasibility experiment only if a specific memory-pressure question justifies it;
5. attempt a third voice only with explicit resource/timing stop criteria.

Recommended immediate next task:

Create a short architecture options memo for the next controlled scaling step. It should compare "third voice by duplication" against "optimize two-voice kernel first" and "minimal scheduler without more voices", using the accepted resource and timing numbers above.

## Gate

No additional RTL feature expansion should start until the orchestrator publishes the next architecture decision.

