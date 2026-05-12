# Phase 2 Dirty Firmware Diff Resolution

Date: 2026-05-12
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-218221e2`

## Finding

`fw/phase0/phase0_main.c` had an uncommitted dirty diff containing three out-of-scope changes:

1. **GAIN default reduced**: `PHASE0_REG_GAIN` default changed `16384u` → `4096u` (-12 dB, reverts the gain calibration from `647edee` and `c25d1a7`)
2. **Speaker enable removed**: R49 write (`PHASE0_WM8978_WORD(49u, 0x0106u)`) removed — would disable speaker output (reverts `6149c59`)
3. **Speaker volume removed**: R54/R55 writes removed — would lose +20 dB volume boost (reverts `6934692`)
4. **Headphone volume changed**: R52/R53 values changed `0x0194` → `0x019E` (from speaker volume fix `6934692`)

These changes are NOT part of any pianoagent task executed in this session:
- `task-68752505` (measurement-hook contract) — design-only, no file edits
- `task-f9ffb452` (contract revision) — design-only, edited `reports/` only
- `task-b391edf5` (CC counter implementation) — added CC counter variable and tag, did not touch gain/codec writes
- `task-ad94d1d9` (hammer excitation scoping) — design-only, no firmware edits

The dirty diff would have broken the validated speaker enable, speaker volume, and gain calibration from the Phase 1C baseline.

## Action

Restored `fw/phase0/phase0_main.c` to HEAD baseline:

```
git checkout HEAD -- fw/phase0/phase0_main.c
```

## Verification

```
$ git diff -- fw/phase0/phase0_main.c
(no output — file is clean)
```

The file now matches the validated baseline at commit `7ed2c62` (Phase 1C CC counter implementation) with all speaker enable (`6149c59`), speaker volume (`6934692`), velocity (`647edee`), excitation guard (`c25d1a7`), and body filter (`ad94631`) fixes intact.

## Impact on Phase 2 Hammer Implementation

No blocker. The firmware baseline is clean. Phase 2 hammer excitation implementation can proceed without contamination. The hammer excitation change only touches `excitation_rom` constants inside `rtl/audio/phase1_reduced_voice.v` — firmware is not in scope.
