# Phase 3 M4 Baseline Acceptance

Date: 2026-05-14
Agent: codex-orchestrator `1c005a25-956c-4b69-9b69-9bf3cd9a8d68`
Related tasks: `task-23eeea1c`, `task-796bedb9`, `task-4d34ef91`

## Verdict

Phase 3 M4 is accepted as the current firmware note-off baseline on top of the M3b per-voice pitch and velocity baseline.

The accepted M4 behavior adds `!F\r\n` as an all-active-voices release command. It uses the existing shared damp-mix register and does not add note IDs, per-voice damp registers, sustain pedal state, or host keyboard mapping.

## Accepted Behavior

| Command | Behavior |
| --- | --- |
| `!N\r\n` | Backward-compatible fixed-note trigger; restores default damp mix before trigger |
| `!NLLLLVVVV\r\n` | Polyphonic parameterized note; restores default damp mix, writes selected voice loop length/velocity, then triggers |
| `!F\r\n` | Note-off/all-notes-release; writes high damp mix to accelerate release |

Malformed note-off-like input, such as `!F1234\r\n`, is rejected: `Q` does not increment and `X` records the parser error/count.

## Accepted Evidence

| Item | Result |
| --- | --- |
| Implementation head | `ca00728` |
| Firmware commit | `9eae9bc` |
| Hardware verifier task | `task-4d34ef91` |
| Hardware report | `reports/phase3_m4_note_off_hardware_validation.md` |
| SOF checksum | `0x00779CD3` |
| Firmware ROM | 931 / 1,024 |
| Quartus errors | 0 |
| Warnings | 16 |
| Setup slack | +2.948 ns |
| LEs | 9,938 |
| Baseline health | `K=0`, `X=0`, `Q=0` |
| M3b compatibility | `K=0`, `X=0`, `Q=2` |
| `!F` acceptance | `K=0`, `X=0`, `Q=3` |
| Damp restore after `!F` | `K=0`, `X=0`, `Q=4` |
| Malformed rejection | `Q=4` unchanged, `X=00020002` |

## ROM Budget

M4 grows the accepted firmware baseline from 912 to 931 words, still under the 950-word target set by the M4 scoping task and with 93 ROM words free.

Future firmware work starts from 931 words and should continue treating ROM growth as a budgeted tradeoff.

## Limits

- `!F` is an all-active-voices release command, not per-note note-off.
- M4 does not introduce note IDs or host keyboard mapping.
- M4 does not add per-voice damp-mix registers.
- Sustain/damper semantics remain deferred.

## Next Planning Boundary

M4 gives the prototype note-on and all-notes-release behavior. The next boundary should be scoped before implementation: either host-playable note mapping with note IDs, or a small audio-quality/control improvement that does not consume the remaining ROM margin blindly.
