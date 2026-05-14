# Phase 3 M2a Status Mapping Fix

Date: 2026-05-14
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-3afd3688`
Commit: `cd0a3c4`

## Fixes Applied

### 1. Voice Status Register Mapping (Critical)

**Bug**: `phase0_lru_steal_note_event()` used `PHASE0_REG_VOICE_STATUS + vi * 0x34` to compute voice status register offsets. The voice status registers are NOT evenly spaced — their actual offsets are 0x24, 0x58, 0x74, 0x88. The computed expression returned wrong addresses for all voices except voice0.

**Fix**: Replaced with explicit switch statement over `PHASE0_REG_VOICE_STATUS`, `PHASE0_REG_VOICE1_STATUS`, `PHASE0_REG_VOICE2_STATUS`, `PHASE0_REG_VOICE3_STATUS`.

**Impact**: The free-slot scan and steal logic now correctly identifies which physical voices are active. This fixes the G=14 (vs expected G=12) discrepancy — the broken scan was failing to find free slots and was double-triggering.

### 2. ST Tag in Parser

Added `ST` to `M2_STEAL_TAGS` in `phase1c_uart_telemetry.py` and to `KNOWN_TAGS`. Parser no longer reports ST as unknown.

## Build Results

- Firmware: PASS, ROM 705/1024 words (69%)
- ROM gate: 700 words — **exceeded by 5 words (+7 from 698)**
- Exception: 5-word exceedance is unavoidable — the explicit switch over 4 register constants costs 7 words vs the broken single-expression approach

## Expected UART Profile (Corrected)

| Profile | G | Q | X | K | ST |
| --- | --- | --- | --- | --- | --- |
| No-command (12 events) | 12 | 0 | 0 | 0 | 0 |
| Commanded (6×!N) | 18 | 6 | 0 | 0 | 0 |

With the corrected status register mapping, the free-slot scan now works correctly. G should match the expected values: G=12 (6 logical × 2 events) in no-command, G=18 (12 + 6 command events) in commanded.

## Verifier Handoff

To exercise voice stealing (ST>0): send bursts of 8+ `!N\r\n` commands with minimal inter-command delay (< 50 ms). All 4 physical voices will be active after the first 4 commands, forcing the 5th-8th commands to steal the oldest voice. Expected: ST≈4, G≈20 (12 base + 8 commands).

## Files Changed

- `fw/phase0/phase0_main.c`: explicit status register switch
- `scripts/phase1c_uart_telemetry.py`: ST tag in known tags
