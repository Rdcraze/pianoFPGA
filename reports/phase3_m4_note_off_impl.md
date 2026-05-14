# Phase 3 M4 Note-Off Implementation

Date: 2026-05-14 | Agent: claude-implementer | Task: `task-796bedb9` | Commit: `9eae9bc`

**ROM: 931/1024 (under 950 target)**

## Commands

| Command | Behavior |
| --- | --- |
| `!F\r\n` | Release all: damp_mix = 32767 (max damping) |
| `!N\r\n` | Restore damp_mix default, trigger with default pitch |
| `!NLLLLVVVV\r\n` | Restore damp_mix default, write per-voice params, trigger |

## Implementation

- Added `!F\r\n` parser case (4 bytes) — writes `VOICE_DAMP_MIX = 32767`
- Added damp_mix restore (`PHASE0_VOICE_DEFAULT_DAMP_MIX = 16384`) to both bare `!N` and parameterized `!N` paths before trigger
- No RTL changes. Firmware only.

## Verifier

Send `!N006A7FFF\r\n` → audio plays → send `!F\r\n` → audio decays rapidly → send `!N00407FFF\r\n` → new note plays with normal sustain. Q=3, X=0.
