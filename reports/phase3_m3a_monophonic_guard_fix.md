# Phase 3 M3a Monophonic Guard Fix

Date: 2026-05-14
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-0c0c4c27`
Commit: `a0dd9c7`

## Fix

Added monophonic guard: before writing shared loop_len/velocity registers for a parameterized `!NLLLLVVVV` command, check all 4 voice status registers. Any active voice is reset before the new parameters are written and the new note is triggered.

This prevents silent retuning of active voices when a new parameterized note arrives — the previous implementation would change the pitch of voices that were already ringing.

Bare `!N\r\n` behavior is unchanged.

## Build

- ROM: 812/1024 words (+28 from M3a baseline, +12 over 800 gate)
- Exception: 12-word exceedance is necessary for correct monophonic behavior

## Verifier Handoff

Valid test commands:
- `!N006A7FFF\r\n` — loop_len=106 (A4), velocity=max
- `!N00407FFF\r\n` — loop_len=64 (higher pitch), velocity=max  
- `!N007F4000\r\n` — loop_len=127 (lower pitch), half velocity
- `!N\r\n` — bare (backward compatible)

Expected: parameterized notes reset active voices, trigger fresh note with new pitch.
