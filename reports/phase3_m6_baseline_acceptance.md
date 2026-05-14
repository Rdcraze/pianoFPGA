# Phase 3 M6 Host Live-Play Acceptance

Date: 2026-05-14
Agent: codex-orchestrator `1c005a25-956c-4b69-9b69-9bf3cd9a8d68`
Related tasks: `task-e24182ea`, `task-b5662601`, `task-5fd89e12`, `task-59f4d01f`

## Verdict

Phase 3 M6 is accepted as the current host live-play wrapper baseline.

This acceptance is host-tool-only. It does not change the accepted M4 firmware baseline, the accepted M5 mapper baseline, RTL, constraints, PLL settings, or generated FPGA images.

## Accepted Behavior

| Host input | Wrapper behavior |
| --- | --- |
| `A4`, `C5`, `69` | Uses the accepted M5 mapper to emit CRLF-terminated `!NLLLLVVVV` commands |
| `A4:4000`, `69:0x0FA0` | Applies a velocity override and emits the corresponding mapped command |
| `release`, `off`, `panic`, `!F` | Emits `!F\r\n` |
| `bare`, `!N` | Emits `!N\r\n` |
| raw `!NLLLLVVVV` | Normalizes documented raw command passthrough to CRLF framing |
| out-of-range notes | Rejects the input instead of silently mapping outside MIDI 21..108 |

Dry-run output prints `repr()`-style command strings so `\r\n` framing is visible.

## Accepted Evidence

| Item | Result |
| --- | --- |
| Initial wrapper commit | `c70e82d` |
| Wrapper rewrite/fix commit | `07e60a3` |
| Report update commit | `8054447` |
| Final verifier task | `task-59f4d01f` |
| Implementation report | `reports/phase3_m6_live_play_impl.md` |
| Validation report | `reports/phase3_m6_live_play_validation.md` |
| Before UART capture | `reports/phase3_m6_before.txt` |
| After UART capture | `reports/phase3_m6_fresh_hardware_uart.txt` |
| Self-check | PASS: notes, velocity override, aliases, raw passthrough, out-of-range rejection, CRLF |
| Dry-run | PASS: visible `\r\n` framing and expected M5 outputs |
| Hardware send smoke | PASS: `Q` +5 for five valid commands |
| Hardware error delta | PASS: `X` unchanged at `0x00020002` |
| Hardware clipping | PASS: `K=0` before and after |
| Firmware ROM | 931 / 1,024, unchanged from M4 |
| FPGA rebuild | Not required |

## Hardware Result

The final verifier used COM5 at 115200 baud and sent:

```
A4,C5,off,C4,panic
```

Observed counters:

| Metric | Before | After | Delta |
| --- | --- | --- | --- |
| `Q` | `0x13` | `0x18` | +5 |
| `X` | `0x00020002` | `0x00020002` | 0 |
| `K` | 0 | 0 | 0 |

The nonzero `X` value is inherited board state from earlier tests. M6 acceptance relies on the delta: valid M6 wrapper commands introduced no new `X`.

## Superseded Evidence

The following M6 verifier tasks are superseded and are not part of the accepted evidence set:

- `task-4127411e`
- `task-1782a971`
- `task-0164d90a`

Do not use stale `reports/phase3_m6_hardware_uart.txt` as final M6 evidence. The accepted hardware captures are:

- `reports/phase3_m6_before.txt`
- `reports/phase3_m6_fresh_hardware_uart.txt`

## Next Planning Boundary

M6 gives the prototype a repeatable host-side path from note sequences to live UART commands. The next boundary should be scoped before implementation: either a small operator-facing host interaction layer, or the first firmware feature that requires new musical state, such as note identity, per-note note-off, or sustain policy.
