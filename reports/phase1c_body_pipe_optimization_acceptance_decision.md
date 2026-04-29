# Phase 1C-B Body-Pipe Optimization Acceptance Decision

Date: 2026-04-28
Orchestrator: codex-orchestrator
Task: `task-b04a4c02`

## Decision

Promote the Phase 1C-B body-pipe/tap-storage optimized build to the current accepted baseline.

This acceptance is narrow: the same two-voice reduced model is accepted with lower LE/register use and an explicit +2 M9K tradeoff.

This decision does not authorize third voice, scheduler work, SDRAM, richer physics, UI, sample playback, larger CPU, clock work, register expansion, UART expansion, diagnostic removal, or unrelated feature expansion.

## References

- `reports/phase1c_body_pipe_optimization_impl_report.md`
- `reports/phase1c_body_pipe_optimization_validation.md`
- `reports/phase1c_body_pipe_optimization_authorization_decision.md`
- `reports/phase1c_rom_ram_rightsizing_acceptance_decision.md`

Verifier result for `task-0d8a2558`: PASS.

## Accepted Build Identity

Current accepted SOF:

- SOF: `quartus/phase0/output_files/piano_phase0_top.sof`
- SHA-256: `48BAB4ACBAD44899E5FB8E25B89496B4E4A8C1AFEF0CF110178EB8C481849510`
- Programmer checksum: `0x0050ADE7`

Fallback baseline:

- Phase 1C-A ROM/RAM right-sized SHA-256: `D5D2A283CCF37795CEED9BD79C754003E184AE6927842F4E0112AE6D866FF3EA`
- Phase 1C-A checksum: `0x0055BA0E`

## Accepted Change

The reduced voice body-history path now uses synchronous circular tap storage instead of a 32-entry shifting register pipe.

Accepted behavior constraints:

- two voice count unchanged;
- register map unchanged;
- UART frame set unchanged;
- coefficients/defaults unchanged;
- sample-rate and clocking unchanged;
- ROM/RAM sizing unchanged from Phase 1C-A;
- codec path and mixer behavior unchanged;
- CPU remains outside the per-sample synthesis loop.

The implementation preserves the active voice behavior with a 4,096-sample golden comparison against the Phase 1C-A reference trace.

## Resource And Timing Delta

Compared with the Phase 1C-A accepted baseline:

| Metric | Phase 1C-A | Phase 1C-B Accepted | Delta |
| --- | ---: | ---: | ---: |
| Logic elements | 7,382 / 10,320 | 6,474 / 10,320 | -908 |
| Dedicated registers | 3,580 | 2,748 | -832 |
| Memory bits | 74,752 / 423,936 | 75,776 / 423,936 | +1,024 |
| M9Ks | 10 / 46 | 12 / 46 | +2 |
| DSP9 elements | 4 / 46 | 4 / 46 | 0 |
| PLLs | 1 / 2 | 1 / 2 | 0 |
| Slow-85C `sys_clk_50m` setup slack | +3.214 ns | +3.907 ns | +0.693 ns |
| Slow-85C `sys_clk_50m` hold slack | +0.433 ns | +0.432 ns | -0.001 ns |
| Slow-85C `sys_clk_50m` Fmax | 59.57 MHz | 62.14 MHz | +2.57 MHz |

TimeQuest remains fully constrained with all listed TNS values at `0.000`.

## Mapping Notes

Preserved:

- boot ROM remains 1,024 x 32 using 4 M9Ks;
- data RAM remains 1,024 x 32 using 4 M9Ks;
- each voice delay line remains synchronous M9K-backed;
- each voice multiplier remains DSP-backed;
- total DSP9 use remains 4 / 46.

New accepted tradeoff:

- each voice now has one additional body-history M9K;
- total M9K use rises from 10 / 46 to 12 / 46.

This tradeoff is acceptable because Phase 1C-A recovered substantial M9K headroom, and Phase 1C-B materially reduces the current LE/register bottleneck.

## Hardware Evidence

Verifier hardware smoke passed:

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

This is the first hardening pass that materially improves the real future-scaling bottleneck.

The current accepted resource posture is now:

- logic: about 63% used;
- M9Ks: about 26% used;
- DSP9s: about 9% used;
- timing: comfortably positive at 50 MHz.

That is materially healthier than the pre-Phase-1C two-voice state, where logic was about 71% and M9Ks were about 74%.

This still does not make aggressive scaling safe. It makes a next controlled experiment more plausible.

## Still Gated

The following remain gated pending separate orchestrator decisions:

- third voice or broader polyphony;
- scheduler or independent note-event work;
- SDRAM feasibility;
- richer piano model;
- exact-48-kHz clock/PLL work;
- larger CPU or ISA changes;
- UI/TFT/touch work;
- sample playback;
- register-map expansion;
- UART diagnostic expansion;
- broad diagnostic removal.

## Next Recommendation

The next reasonable controlled experiment is a narrow third-voice fit and behavior slice, but only with explicit stop criteria and rollback to this Phase 1C-B baseline.

If authorized, that experiment should:

- duplicate only the optimized reduced voice;
- preserve current coefficients/defaults and clocking;
- avoid scheduler and richer physics;
- keep register/UART growth minimal;
- require simulation, Quartus/TimeQuest, resource mapping, and hardware smoke;
- stop if LE use exceeds a defined cap or slack drops below +1.0 ns.

