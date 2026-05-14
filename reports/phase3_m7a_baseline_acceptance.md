# Phase 3 M7a Host Track-and-Release Acceptance

Date: 2026-05-14
Agent: codex-orchestrator `1c005a25-956c-4b69-9b69-9bf3cd9a8d68`
Related tasks: `task-9734d754`, `task-c8665fdb`, `task-4d649ee7`, `task-dc70eed8`, `task-add5b497`

## Verdict

Phase 3 M7a is accepted as the current host track-and-release wrapper baseline.

This is a host-side workaround for playable release behavior. It does not implement true per-note firmware note-off, note IDs, sustain state, per-voice damp registers, firmware parser changes, RTL changes, or FPGA image changes.

## Accepted Behavior

| Event | Behavior |
| --- | --- |
| `down:A4`, `down:69`, `d:C4` | Send a mapped `!NLLLLVVVV\r\n` command and mark the note active |
| `down:A4:4000`, `d:69:0x0FA0` | Send a mapped note command with velocity override |
| `up:A4`, `u:69` | Mark the note inactive; suppress UART while other notes remain active |
| final `up:<note>` that empties the active set | Send `!F\r\n` |
| `panic`, `release`, `off`, `all-off` | Clear the active set and send `!F\r\n` |

Dry-run output shows active-set transitions and `repr()` command framing without emitting raw CRLF command lines.

## Accepted Evidence

| Item | Result |
| --- | --- |
| Scope commit | `a5bfd80` |
| Initial implementation commit | `3a9e869` |
| Structured-action fix commit | `ef1cc5e` |
| Implementation report commit | `4790626` |
| Final verifier task | `task-dc70eed8` |
| Implementation report | `reports/phase3_m7a_track_release_impl.md` |
| Validation report | `reports/phase3_m7a_track_release_validation.md` |
| Before UART capture | `reports/phase3_m7a_before.txt` |
| After UART capture | `reports/phase3_m7a_hardware_uart.txt` |
| Self-check | PASS: overlap, command count, panic, repeated up, velocity, note number, invalid event, CRLF |
| Dry-run | PASS: `up:A4` suppressed while C5 remains active; send count 5 |
| Hardware send smoke | PASS: `Q` +5 for five valid commands |
| Hardware error delta | PASS: `X` unchanged at `0x00020002` |
| Hardware clipping | PASS: `K=0` before and after |
| Firmware ROM | 931 / 1,024, unchanged from M4 |
| FPGA rebuild | Not required |

## Hardware Result

Verifier sent:

```
down:A4,down:C5,up:A4,up:C5,down:C4,panic
```

Observed counters:

| Metric | Before | After | Delta |
| --- | --- | --- | --- |
| `Q` | `0x1D` | `0x22` | +5 |
| `X` | `0x00020002` | `0x00020002` | 0 |
| `K` | 0 | 0 | 0 |

The nonzero `X` value is inherited board state from earlier tests. M7a acceptance relies on the delta: valid M7a wrapper commands introduced no new `X`.

## Limits

- Releasing one note while other notes remain active does not damp that released note in firmware.
- M7a suppresses `!F` during partial release to avoid cutting off still-held notes, so previously released notes can continue until the active set empties or panic/all-off is sent.
- True per-note release remains deferred because the accepted M7 scope found the remaining 93 firmware ROM words insufficient for note IDs or per-note state.

## Next Planning Boundary

M7a is the practical zero-firmware playable-release workaround. The next boundary should be chosen deliberately: either improve host operator ergonomics around M7a, or reclaim firmware ROM before attempting true note IDs, sustain state, or per-note note-off.
