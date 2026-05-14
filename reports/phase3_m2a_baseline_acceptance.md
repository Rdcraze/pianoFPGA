# Phase 3 M2a Baseline Acceptance

Date: 2026-05-14
Agent: codex-orchestrator `1c005a25-956c-4b69-9b69-9bf3cd9a8d68`
Related tasks: `task-7629ecaa`, `task-096f904e`, `task-5debc3fa`, `task-3afd3688`, `task-6c3d73bb`

## Verdict

Corrected Phase 3 M2a firmware voice stealing is accepted as the current baseline with a recorded ROM-size exception.

The accepted behavior is 6 logical note intents scheduled over the existing 4 physical voice engines, with LRU/oldest-active stealing kept entirely in firmware. No RTL voice engine, SDC, pin, PLL, or `phase1_reduced_voice.v` change is part of M2a.

## Accepted Evidence

| Item | Result |
| --- | --- |
| Corrected implementation commit | `13c3540` |
| Hardware verifier task | `task-6c3d73bb` |
| Hardware report | `reports/phase3_m2a_corrected_hardware_validation.md` |
| SOF checksum | `0x0073B601` |
| Firmware build | PASS |
| ROM words | 705 / 1,024 |
| LEs | 9,938, unchanged from M1 |
| Setup slack | +2.948 ns |
| Hold slack | +0.431 ns |
| Forced-burst stealing | `ST=31`, `P=31` |
| No-command stealing | `ST=11`, `P=11` |
| Clipping/error health | `K=0`, `X=0` in accepted profiles |
| UART compatibility | Existing tags preserved; `ST` appended |

## Exception

The M2a firmware ROM gate was <= 700 words. The corrected implementation is 705 words, exceeding the gate by 5 words.

This exception is accepted because the extra code fixes a real status-register mapping bug. The broken implementation used a computed voice-status offset that was incorrect for physical voices 2 and 3. The corrected implementation uses explicit register constants and leaves 319 ROM words free.

This is a baseline-specific exception, not a new default budget. Future firmware work should treat 705 words as the current accepted baseline and should avoid further ROM growth unless the task explicitly approves it.

## Superseded Evidence

`reports/phase3_m2a_voice_stealing_hardware_validation.md` from `task-5debc3fa` is retained as pre-fix evidence only. Its PASS recommendation is superseded by `reports/phase3_m2a_orchestrator_review.md` and the corrected verifier run in `task-6c3d73bb`.

## Next Planning Boundary

Phase 3 has now proven:

- 4 physical waveguide voices fit and pass hardware validation.
- 6 logical note intents can be scheduled over those 4 voices in firmware.
- Dense command bursts produce real, counted stealing without clipping.

The next risky boundary is note semantics: pitch/velocity/note-off/damper behavior and any user-playable command contract. That should be scoped before implementation because it touches firmware state, UART protocol, ROM budget, and the previously deferred damper/per-note-state boundary.
