# Phase 3 M2a Voice Stealing Implementation

Date: 2026-05-14
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-096f904e`
Commit: `00816d8`

## Verdict

**PASS — firmware built, ROM 698/1024 words, under 700 gate.**

Firmware-only implementation. No RTL, SDC, pin, or PLL changes. M1 4-voice hardware baseline unchanged.

## Design

6 logical note slots mapped to 4 physical voice slots via LRU stealing:

1. On `!N` command: find first free physical voice (checking VOICE_STATUS ACTIVE bits).
2. If all 4 busy: find oldest physical voice by age counter, steal it. Reset stolen voice before re-trigger.
3. Trigger the selected physical voice, update age counter.
4. Advance logical slot index 0→1→...→5→0.

## Files Changed

- `fw/phase0/phase0_main.c`: Added M2 slot management structs, LRU steal function, PHASE0_RR_EVENT_COUNT 8→12, ST telemetry tag for steal count, M2 structure init

## Firmware Build

- Build: PASS (0 errors)
- ROM: 698/1024 words (68%)
- Gate: ROM ≤ 700 — PASS with 2 words margin

## Expected UART Profile

| Profile | G | Q | X | K | ST | CC |
| --- | --- | --- | --- | --- | --- | --- |
| No-command (12 events) | 12 | 0 | 0 | 0 | 0 | 0x003D0900 |
| Commanded (6×!N) | 18 | 6 | 0 | 0 | 0 | 0x003D0900 |

ST=0 in no-command (no stealing needed when sequential triggering fits within 4 physical slots). ST may be non-zero in rapid-command scenarios.

## UART Tag Order

I/S/.../X/CC/V3/VT/VA/VV/S3/**ST** — ST tag appended after S3 for M2 steal count.

## Residual Risk

- The LRU age counter wraps at 32 bits but wraps safely (at 50 MHz, overflow takes ~86 seconds of continuous triggering — not reachable in smoke).
- Voice status readback assumes REG_VOICE_STATUS + N*0x34 offset pattern for voice1-voice3. If register layout differs, the free-slot scan may misidentify active voices.
