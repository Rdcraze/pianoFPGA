# Phase 3 M4 Playable Note Semantics Scope

Date: 2026-05-14 | Agent: claude-implementer | Task: `task-23eeea1c`

## Verdict: GO — firmware-only note-off command

M4 is the natural completion of M3b: add `!F\r\n` (note-off/release) to complement `!N` (note-on). Pure firmware, no RTL, ROM ~950 words.

## M3b Baseline

- 4 physical voices with per-voice loop_len/velocity via MMIO (0x98-0xB4)
- `!N\r\n` bare trigger (M2a-compatible, default pitch)
- `!NLLLLVVVV\r\n` parameterized polyphonic trigger
- LRU voice stealing with ST counter
- ROM 912/1024, LE 9,992, timing +2.914 ns

## Proposed M4: Note-Off

**Command**: `!F\r\n` — release all active voices by increasing damp_mix.

**Behavior**: Firmware writes `damp_mix = 32767` to shared damp_mix register, causing all active voices to decay rapidly. Damp_mix is restored to default on next `!N` trigger.

**RTL impact**: None. Uses existing shared `VOICE_DAMP_MIX` register.

**ROM estimate**: +30-40 words for parser case + damp_mix write/restore. Target ROM ≤ 950.

## Deferred

- Per-note ID tracking → Phase 4
- Per-voice damp_mix registers → only if polyphonic note-off is needed
- Host keyboard mapping → Phase 4
- Sustain pedal → Phase 4+

## Acceptance Gates

| Gate | Threshold |
| --- | --- |
| `!F` accepted with Q++, no X | PASS |
| `!N` restores default damp_mix | PASS |
| ROM ≤ 950 | Target |
| LE unchanged | 9,992 |

## Next Task

"Implement Phase 3 M4: firmware note-off command `!F\r\n`"
