# Phase 3 M5 Host-Playable Note Mapping Scope

Date: 2026-05-14 | Agent: claude-implementer | Task: `task-eb10e56f`

## Verdict: GO — host-side key-to-loop conversion, no firmware changes

M5 adds a host-side Python script that maps MIDI note numbers to `!NLLLLVVVV` commands via the existing UART protocol. Zero firmware ROM cost (93 words remain). Zero RTL cost.

## ROM Budget Reality

1024 - 931 = 93 words remaining. A new firmware parser case costs 20-40 words. A note-ID table or MIDI-to-freq lookup costs 50-100+ words as a lookup table. We MUST stay within 93 words for any firmware additions. The safest M5 is pure host-side with zero firmware changes.

## Proposed M5: Host-Side Key Mapper

A Python script (`scripts/phase3_m5_keyboard.py`) that:
1. Reads key presses from stdin or a serial key input
2. Converts MIDI note number → loop_len via a small lookup table
3. Sends `!NLLLL7FFF\r\n` to the FPGA UART
4. Sends `!F\r\n` on key release

All logic in Python. No firmware, RTL, or ROM changes.

## Deferred

- Firmware MIDI note parsing → out of ROM budget
- Per-note note-off by ID → needs RTL per-voice damp_mix, ROM for parser
- In-firmware key mapping → 93 words insufficient

## Acceptance Gates

| Gate | Threshold |
| --- | --- |
| Host script produces valid `!NLLLLVVVV` for all 88 keys | PASS |
| Key release sends `!F` | PASS |
| FPGA UART accepts commands with Q++, X=0 | PASS |
| ROM unchanged from 931 | PASS |

## Next Task

"Implement M5 host-side key-to-loop-len mapper script"
