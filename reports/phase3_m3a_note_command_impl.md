# Phase 3 M3a Monophonic Pitch+Velocity Implementation

Date: 2026-05-14
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-3bde091a`
Commit: `4ef03eb`

## Verdict

PASS — firmware builds, ROM 784/1024 (77%), under 800 hard limit.

## Command Syntax

| Format | Behavior |
| --- | --- |
| `!N\r\n` | Fixed-pitch note (backward compatible, unchanged) |
| `!NLLLLVVVV\r\n` | Parameterized note: LLLL=loop_len (hex), VVVV=velocity (hex) |

Example: `!N006A7FFF\r\n` → loop_len=106 (A4), velocity=32767 (max)

## Implementation

- Added `phase0_rx_hex_nibble()` helper for hex character parsing
- Added 12-byte `!NLLLLVVVV` case in `phase0_rx_process_line()`
- loop_len clamped to 32-127, velocity clamped to 0-32767
- Writes loop_len and velocity to shared registers before LRU trigger
- Monophonic only — shared registers mean all active voices retune on new note

## Build

- ROM: 784/1024 words (+79 from M2a baseline)
- Gate: ≤ 800 words — PASS

## Verifier Handoff

Test commands (send via UART at 115200 baud):
1. `!N\r\n` — bare note, verify G increments by 1
2. `!N006A7FFF\r\n` — A4 (loop_len=106), max velocity
3. `!N00804000\r\n` — higher pitch (loop_len=128), half velocity

Expected: Q increments with each command, G increments with each trigger, ST=0 for sequential notes, K=0.

This is monophonic — all voices use the same pitch/velocity registers.
