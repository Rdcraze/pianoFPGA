# Phase 1C-B Body-Pipe Optimization Authorization Decision

Date: 2026-04-28
Orchestrator: codex-orchestrator
Task: `task-aa107598`

## Decision

Authorize a strictly narrow Phase 1C-B body-pipe/tap-storage optimization.

The goal is to reduce per-voice register/LE pressure inside the current reduced voice while preserving the accepted two-voice behavior.

This is not authorization for third voice, scheduler work, SDRAM, richer physics, UI, sample playback, larger CPU, clock work, or unrelated cleanup.

## Current Baseline

The active accepted baseline is the Phase 1C-A ROM/RAM right-sized build:

- SOF: `quartus/phase0/output_files/piano_phase0_top.sof`
- SHA-256: `D5D2A283CCF37795CEED9BD79C754003E184AE6927842F4E0112AE6D866FF3EA`
- checksum: `0x0055BA0E`

Accepted resources:

| Metric | Baseline |
| --- | ---: |
| Logic elements | 7,382 / 10,320 |
| Dedicated registers | 3,580 |
| Memory bits | 74,752 / 423,936 |
| M9Ks | 10 / 46 |
| DSP9 elements | 4 / 46 |
| PLLs | 1 / 2 |
| Slow-85C `sys_clk_50m` setup slack | +3.214 ns |
| Slow-85C `sys_clk_50m` hold slack | +0.433 ns |
| Slow-85C `sys_clk_50m` Fmax | 59.57 MHz |

## Rationale

The Phase 1C attribution report identified each `phase1_reduced_voice` as about 1,316 logic cells and 843 registers. The current voice body coloration path keeps a 32-entry signed body pipe per voice while only a few taps are used.

Now that ROM/RAM right-sizing recovered M9K headroom, it is reasonable to test whether that body-pipe state can be represented more efficiently without changing behavior.

This is the right next hardening target because it attacks per-voice register/LE pressure. It is more relevant to future voice scaling than additional memory cleanup, but it must be treated as behavior-sensitive audio work.

## Authorized Scope

Allowed:

- modify only the current reduced-voice body-pipe/tap-storage implementation and directly necessary testbench/report collateral;
- preserve the current two voice count;
- preserve the current firmware-visible register map and UART frame set;
- preserve current coefficients, defaults, sample-rate contract, clocking, ROM/RAM sizes, CPU, codec path, and mixer behavior;
- use M9K-backed, distributed, circular, or vendor-supported tap storage only if it preserves the current tap timing and improves or plausibly improves area;
- add a stronger standalone voice golden/signature test if needed.

Required behavior:

- body bypass behavior unchanged;
- body mix arithmetic order unchanged unless proven bit-exact at output;
- taps corresponding to current delays 6, 16, and 30 preserved;
- sample-valid cadence unchanged;
- per-voice peak/clip/active behavior unchanged;
- top-level two-voice peak and mix peak signatures preserved;
- no new runtime CPU dependency.

Not allowed:

- third voice or any voice-count increase;
- scheduler or independent note-event work;
- SDRAM;
- richer or changed physical model;
- coefficient/default changes;
- new sample playback or UI;
- larger CPU or ISA changes;
- clock/PLL/sample-rate changes;
- register-map expansion;
- UART diagnostic expansion;
- broad diagnostic removal;
- ROM/RAM resizing changes beyond the accepted Phase 1C-A baseline.

## Stop Criteria

Stop and report instead of forcing a fit if any of these occur:

- standalone voice signature changes without a clear intentional and approved reason;
- mix peak/clip behavior changes in the top happy-path test;
- delay-line M9K or voice multiplier DSP mapping regresses;
- TimeQuest setup slack drops below +1.0 ns;
- LE use increases materially instead of decreasing;
- implementation requires unrelated register, firmware, clock, or scheduler changes.

## Required Validation

Implementation must provide:

- changed-file list;
- exact explanation of old body-pipe state and new tap-storage state;
- standalone voice regression with unchanged signature, preferably including sample-by-sample comparison over the note onset/decay window;
- top happy/NACK simulations preserving two-voice counters and mix signature;
- firmware build;
- Quartus full compile and TimeQuest;
- hierarchy/resource delta versus the Phase 1C-A right-sized baseline;
- confirmation that voice delay lines remain synchronous M9K-backed and multipliers remain DSP-backed;
- hardware UART/audio smoke if the build is promoted for acceptance.

Verifier must independently check:

- scope discipline;
- behavior/signature preservation;
- resource/timing delta;
- M9K/DSP mapping;
- hardware smoke before any replacement-baseline decision.

## Expected Outcome

Success means reduced per-voice register and/or LE pressure while preserving the current hardware-accepted two-voice behavior.

Failure is acceptable if the report proves the optimization is not worthwhile. In that case, the project should retain the Phase 1C-A ROM/RAM right-sized baseline and avoid spending more time on this path.

