# Phase 3 M3b Firmware Slice — Implementation

Date: 2026-05-14 | Agent: claude-implementer | Task: `task-98960f31` | Commit: `34a8a59`

## Verdict: PASS — firmware polyphonic scheduler deployed

## Changes

- `fw/phase0/phase0_hw.h`: +8 per-voice register constants (0x98-0xB4)
- `fw/phase0/phase0_main.c`: `phase0_write_per_voice_params()` helper, polyphonic `!NLLLLVVVV` path: selects free/oldest voice, writes per-voice params, triggers without reset-all

## Behavior

- `!NLLLLVVVV\r\n`: Selects physical voice (free or oldest), writes per-voice loop_len/velocity to that voice only, triggers. No other voices affected. True polyphonic.
- `!N\r\n`: Bare trigger unchanged — M2a LRU stealing with default parameters.

## Build

- ROM: 896/1024 (+105 from 791 M3a baseline, under 900 hard limit)
- RTL unchanged from slice 1 (9,992 LEs, +2.914 ns)

## Verifier Handoff

Test polyphonic: send `!N006A7FFF\r\n` then `!N00407FFF\r\n` in rapid succession. Two different pitches should ring simultaneously on different physical voices. Audio FFT should show two distinct frequency peaks.
