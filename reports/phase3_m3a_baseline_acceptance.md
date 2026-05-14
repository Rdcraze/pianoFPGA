# Phase 3 M3a Baseline Acceptance

Date: 2026-05-14
Agent: codex-orchestrator `1c005a25-956c-4b69-9b69-9bf3cd9a8d68`
Related tasks: `task-f92ef528`, `task-3bde091a`, `task-0c0c4c27`, `task-6aef4675`, `task-1177fbf8`

## Verdict

Phase 3 M3a is accepted as the current monophonic pitch+velocity command baseline.

This is a firmware-only command feature. It does not provide true polyphonic pitch because loop length and velocity are still shared registers. Parameterized commands intentionally reset the physical voices before retuning, then trigger a fresh monophonic note.

## Accepted Behavior

| Command | Behavior |
| --- | --- |
| `!N\r\n` | Backward-compatible fixed-note M2a trigger path |
| `!NLLLLVVVV\r\n` | Monophonic parameterized note; `LLLL` loop length, `VVVV` velocity |

Loop length is clamped to the RTL-supported `32..127` range. Velocity is clamped to `0..32767`. Malformed parameterized commands are rejected: `Q` does not increment and `X` records the parser error/count.

## Accepted Evidence

| Item | Result |
| --- | --- |
| Implementation/report head | `42b60e2` |
| Hardware verifier task | `task-1177fbf8` |
| Hardware report | `reports/phase3_m3a_hardware_validation.md` |
| SOF checksum | `0x00742CF6` |
| Firmware ROM | about 791 / 1,024 |
| Quartus errors | 0 |
| Warnings | 16 |
| Setup slack | +2.948 ns |
| LEs | 9,938 |
| Bare `!N` compatibility | PASS |
| Parameterized command acceptance | PASS |
| Malformed command rejection | PASS |
| Monophonic guard | PASS |
| Clipping | `K=0` in all reported tests |

## Limits

- M3a is monophonic for parameterized pitch/velocity commands.
- It is not a substitute for per-voice pitch registers.
- Existing M2a logical voice stealing remains available through the bare `!N` path.
- Future firmware work starts from a 791-word ROM baseline and should avoid growth without an explicit budget.

## Next Planning Boundary

The next step should not add damper or richer note semantics blindly. The next high-risk boundary is M3b: per-physical-voice loop length and velocity registers, with firmware writing parameters to the selected physical voice before trigger. That requires RTL register-map changes and must be planned against the tight 9,938-LE baseline before implementation.
