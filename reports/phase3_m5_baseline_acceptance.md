# Phase 3 M5 Host Mapper Acceptance

Date: 2026-05-14
Agent: codex-orchestrator `1c005a25-956c-4b69-9b69-9bf3cd9a8d68`
Related tasks: `task-eb10e56f`, `task-394c8d95`, `task-631ec27e`, `task-6dcf07db`, `task-ec390fd2`, `task-f2d927fc`

## Verdict

Phase 3 M5 is accepted as the current host-side keyboard-to-UART mapper baseline.

This acceptance does not change the FPGA firmware/RTL baseline. M4 remains the accepted firmware and hardware baseline with `!N`, parameterized `!NLLLLVVVV`, and `!F` commands. M5 adds a host tool that maps playable piano-key inputs onto those accepted UART commands.

## Accepted Behavior

| Host input | UART command | Behavior |
| --- | --- | --- |
| `note 21` through `note 108` | `!NLLLLVVVV\r\n` | MIDI note number mapped to a clamped loop length and velocity |
| `name A0` through `name C8` | `!NLLLLVVVV\r\n` | Note-name alias for the same MIDI mapping |
| `note 69` or `name A4` | `!N006A7FFF\r\n` | Calibrated A4 reference mapping |
| `note <n> <velocity>` | `!NLLLLVVVV\r\n` | Optional velocity override, clamped to `0..32767` |
| `release`, `off`, `panic` | `!F\r\n` | All-active-voices release via the M4 note-off command |
| `bare` | `!N\r\n` | Backward-compatible fixed-note trigger |

All generated note commands use loop lengths in the RTL-supported `32..127` range and velocity values in `0..32767`.

## Accepted Evidence

| Item | Result |
| --- | --- |
| Final implementation head | `31c2a79` |
| Initial mapper commit | `d3d6a03` |
| Calibration fix commit | `26936fe` |
| Self-check fix commit | `31c2a79` |
| Final verifier task | `task-f2d927fc` |
| Validation report | `reports/phase3_m5_keyboard_mapper_validation.md` |
| Fresh UART capture | `reports/phase3_m5_fresh_hardware_uart.txt` |
| Self-check | PASS: all 88 notes, A4 exact, A0/C4/A4/C8 equivalence, release aliases |
| Representative commands | PASS: note/name pairs, velocity override, release/off/panic, bare |
| Firmware ROM | 931 / 1,024, unchanged from M4 |
| FPGA rebuild | Not required |
| Hardware health during M5 command run | `Q` increments, `K=0`; no new `X` from valid M5 commands |

## Scope Boundary

M5 is host-tool work only:

- no firmware parser changes
- no RTL changes
- no SDC, PLL, pin, or generated FPGA image changes
- no new per-note note-off identity
- no sustain or damper policy change

The fresh hardware capture inherits `X=00020002` from prior board state, but the verifier report records that the valid M5 command sequence did not introduce additional `X`. Firmware-level clean `X=0` acceptance remains covered by the M4 baseline evidence.

## Superseded Evidence

Earlier M5 validation artifacts from canceled or superseded tasks are not part of the accepted evidence set, especially stale captures or reports that used the old A4 mapping `!N006B7FFF`.

Only these M5 validation artifacts are accepted:

- `reports/phase3_m5_keyboard_mapper_validation.md`
- `reports/phase3_m5_fresh_hardware_uart.txt`

## Next Planning Boundary

M5 makes the current M4 firmware playable from a host-side keyboard mapper. The next boundary should be scoped deliberately before implementation: either a small host interaction wrapper around this mapper, or the first firmware feature that requires new state beyond all-notes release, such as note identity, sustain policy, or per-note note-off.
