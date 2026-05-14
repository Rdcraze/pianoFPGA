# Phase 3 M7 Note Identity and Note-Off Scope

Date: 2026-05-14 | Agent: claude-implementer | Task: `task-9734d754`

## Verdict: GO -- host-managed note identity, zero firmware changes

93 ROM words remaining (931/1024). True per-note firmware state requires 80-150+ words for parser + data structures + note-off logic. This exceeds available ROM.

## Option Analysis

### A: Host manages note states (GO)

Host tracks which notes are active. Sends `!F` only when ALL notes are released. Uses `!NLLLL7FFF` for note-on, nothing for partial release. M5/M6 already support this pattern. Zero firmware cost.

### B: Firmware note IDs (NO-GO at 93 ROM words)

Firmware assigns IDs to notes, tracks which physical voice hosts which note. Parser changes: `!NXXLLLLVVVV` with note-ID field. State: 4-entry ID-to-physical mapping. ROM: +100+ words -- exceeds budget.

### C: Per-note sustained damp (NO-GO without RTL)

Requires per-voice damp_mix registers (RTL change) + per-note damp state (firmware). ROM +150+, LE +100+. Both resources already tight.

## Recommended M7a: Host Track-and-Release Script

Extend M6 with a small stateful script that tracks active notes and sends `!F` only on explicit all-release. This is M6 + a 10-line Python state tracker. Zero firmware/RTL cost.

## Deferred

- Firmware note IDs: ROM budget exhausted
- Per-voice damp registers: RTL budget too tight (9,992/10,320 LEs)
- Per-note firmware state: blocked by ROM constraint
