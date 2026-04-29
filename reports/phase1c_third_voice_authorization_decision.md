# Phase 1C Third-Voice Authorization Decision

Date: 2026-04-28
Orchestrator: codex-orchestrator
Task: `task-be235959`

## Decision

Authorize a narrow third-voice feasibility experiment from the accepted Phase 1C-B baseline.

This is a bounded fit and behavior experiment only. It is not authorization for scheduler work, richer physics, SDRAM, UI, sample playback, clock work, larger CPU, or broader polyphony architecture.

## Current Baseline

Accepted baseline:

- SOF: `quartus/phase0/output_files/piano_phase0_top.sof`
- SHA-256: `48BAB4ACBAD44899E5FB8E25B89496B4E4A8C1AFEF0CF110178EB8C481849510`
- checksum: `0x0050ADE7`

Accepted resources:

| Metric | Phase 1C-B Baseline |
| --- | ---: |
| Logic elements | 6,474 / 10,320 |
| Dedicated registers | 2,748 |
| Memory bits | 75,776 / 423,936 |
| M9Ks | 12 / 46 |
| DSP9 elements | 4 / 46 |
| PLLs | 1 / 2 |
| Slow-85C `sys_clk_50m` setup slack | +3.907 ns |
| Slow-85C `sys_clk_50m` hold slack | +0.432 ns |
| Slow-85C `sys_clk_50m` Fmax | 62.14 MHz |

## Rationale

Before Phase 1C hardening, a third duplicated voice was too close to the LE limit to be a sensible default next step.

After ROM/RAM right-sizing and body-pipe optimization, the two-voice design has materially better headroom:

- LE use fell to about 63%.
- M9K use is about 26%.
- DSP use is still about 9%.
- Timing remains comfortably positive.

This makes a narrow third-voice experiment reasonable, provided it is treated as a bounded feasibility slice and not as the start of uncontrolled feature expansion.

## Authorized Scope

Allowed:

- instantiate one additional copy of the current optimized reduced voice;
- trigger all three voices in a simple hardware-owned way sufficient to prove three simultaneous overlapping voices;
- extend the mix path to three voices with explicit signed saturation;
- add only minimal diagnostics needed to observe voice2 and final mix behavior;
- preserve existing registers through the current Phase 1C-B map;
- place any new registers after the existing map;
- preserve current sample rate, coefficients, defaults, clocking, ROM/RAM sizes, CPU, codec path, and UART baseline frames;
- preserve CPU-out-of-sample-loop architecture.

Not allowed:

- scheduler or note allocator;
- independent note-event architecture beyond minimal trigger wiring;
- fourth voice;
- SDRAM;
- richer or changed physical model;
- coefficient/default changes;
- sample playback;
- UI/TFT/touch;
- larger CPU or ISA changes;
- clock/PLL/sample-rate changes;
- register-map churn outside additive post-map diagnostics;
- broad UART expansion beyond the minimum needed to observe the third voice and mix;
- diagnostic removal;
- unrelated cleanup.

## Stop Criteria

Stop and report instead of forcing the result if any of these occur:

- LE use exceeds `8,200 / 10,320`;
- `sys_clk_50m` setup slack drops below `+1.0 ns`;
- setup/hold are not fully constrained;
- any listed TNS is nonzero;
- existing two-voice registers or UART frames become incompatible;
- voice delay-line M9K mapping regresses;
- voice multiplier DSP mapping regresses;
- mix clipping appears unexpectedly in the default smoke case;
- implementation requires scheduler, clock, CPU, SDRAM, or model changes.

## Required Validation

Implementation must provide:

- changed-file list;
- new register/UART additions, if any;
- explanation of three-voice trigger and mix behavior;
- standalone voice regression;
- top-level simulation showing three triggers, three active voices, expected peak/mix behavior, and no unexpected clipping;
- NACK path regression;
- firmware build;
- Quartus full compile and TimeQuest;
- resource/timing delta versus Phase 1C-B baseline;
- M9K/DSP mapping evidence;
- hardware UART/audio smoke if the result is to be considered for acceptance.

Verifier must independently check:

- strict scope;
- register/UART compatibility;
- three-voice behavior evidence;
- resource/timing stop criteria;
- M9K/DSP mapping;
- hardware smoke before recommending replacement-baseline acceptance.

## Acceptance Policy

A successful implementation does not automatically replace the Phase 1C-B baseline.

The orchestrator must publish a separate third-voice acceptance decision after verifier PASS and hardware smoke evidence.

