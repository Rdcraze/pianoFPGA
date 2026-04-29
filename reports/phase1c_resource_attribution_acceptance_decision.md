# Phase 1C Resource Attribution Acceptance Decision

Date: 2026-04-28
Orchestrator: codex-orchestrator
Task: `task-49380986`

## Decision

Accept the Phase 1C resource attribution findings.

Authorize only a narrow ROM/RAM right-sizing implementation slice as the next step.

This authorization is for memory-headroom cleanup only. It does not authorize third voice, SDRAM, scheduler work, body-pipe rewrite, richer physics, UI, sample playback, larger CPU, clock rework, or unrelated cleanup.

## References

- `reports/phase1c_resource_attribution_and_hardening_proposal.md`
- `reports/phase1c_resource_attribution_validation.md`
- `reports/phase1_two_voice_hardware_acceptance_decision.md`
- `reports/phase1_next_scaling_architecture_options.md`

Verifier result for `task-4b1885eb`: PASS.

## Accepted Findings

The current hardware-accepted two-voice baseline is:

| Metric | Value |
| --- | ---: |
| Logic elements | 7,366 / 10,320 |
| Dedicated registers | 3,580 |
| Memory bits | 271,360 / 423,936 |
| M9Ks | 34 / 46 |
| DSP9 elements | 4 / 46 |
| PLLs | 1 / 2 |
| `sys_clk_50m` setup slack | +3.957 ns |
| `sys_clk_50m` hold slack | +0.432 ns |
| `sys_clk_50m` Fmax | 62.33 MHz |

The hierarchy attribution is accepted:

- RV32I SoC: 3,586 logic cells, 1,278 registers, 262,144 memory bits, 32 M9Ks.
- RV32I core: 3,423 logic cells and 1,242 registers.
- Boot ROM: 4,096 x 32, 131,072 bits, 16 M9Ks.
- Data RAM: 4,096 x 32, 131,072 bits, 16 M9Ks.
- Audio path: 3,019 logic cells, 1,959 registers, 9,216 memory bits, 2 M9Ks, 4 DSP9s.
- Each reduced voice: 1,316 logic cells, 843 registers, 4,608 logical memory bits, 1 physical M9K, 2 DSP9s.

Interpretation:

- LE pressure is mainly RV32I core plus duplicated voice engines.
- M9K pressure is mainly oversized firmware ROM/RAM, not the reduced voice delay lines.
- DSP pressure is low.
- A naive third voice remains a poor default next step because it projects to roughly 9,049 / 10,320 LEs before added routing/control/debug effects.

## Authorized Slice

Authorize:

`Phase 1C-A: right-size firmware ROM/RAM`

Required scope:

- reduce avoidable boot ROM and data RAM M9K use;
- keep current two-voice behavior unchanged;
- keep CPU out of the sample loop;
- keep base MMIO/register behavior unchanged;
- keep UART and hardware smoke expectations unchanged;
- update linker, firmware build, boot ROM, data RAM, MIF generation, SoC decode, docs, and reports coherently;
- use conservative ROM/RAM depth with explicit margin and a bounds check;
- preserve the accepted two-voice SOF as the rollback baseline until the new build is validated and hardware-accepted.

Suggested target:

- reduce ROM and RAM from 4,096 x 32 each to a smaller measured depth, such as 1,024 x 32 each, only if firmware image and stack margin are documented.

Expected value:

- recover substantial M9K headroom;
- reduce memory-pressure risk for later work;
- not expected to materially reduce LE pressure.

## Required Validation

Implementation must provide:

- firmware build evidence;
- linker/MIF/depth consistency evidence;
- ROM/RAM size and stack-margin rationale;
- ModelSim happy/NACK/reduced-voice tests;
- Quartus full compile and TimeQuest;
- resource delta versus hardware-accepted two-voice baseline;
- confirmation that voice M9K/DSP mapping did not regress;
- hardware UART/audio smoke before promotion to a new accepted baseline.

Verifier must explicitly check:

- no behavioral or register-map drift;
- no accidental feature expansion;
- no SDRAM;
- no third voice or scheduler;
- no CPU, clock, or audio-model redesign;
- M9K reduction is real and does not trade into unacceptable LE/timing cost.

## Still Gated

The following remain gated pending later decisions:

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

## Next Tasks

Assign implementer:

- implement Phase 1C-A ROM/RAM right-sizing.

Assign verifier:

- validate Phase 1C-A and require hardware smoke before accepting a replacement baseline.

