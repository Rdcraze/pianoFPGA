# Phase 3 M8 ROM Reclamation Implementation

Date: 2026-05-14 | Agent: claude-implementer | Task: `task-3062c9a9`, `task-6b7142c9`
Commits: `9506e65` (attempt), `restored to b0926cf` (rollback)

## Verdict: NO-GO, ROLLED BACK to accepted baseline

## Attempt (9506e65)

- Removed V3/VT/VA/VV/S3 from periodic telemetry (~33 words saved)
- Added `phase0_diag_dump_voice3()` function (~35 words)
- Added `!D\r\n` parser handler (~15 words)
- Result: ROM 948 (+17 from 931)

## Why Reclamation Failed

The inline voice3 tag sequences were compact. Wrapping them in a function call adds a call/return pair, and the `!D` parser handler adds conditional checks. Overhead exceeded savings.

## Rollback (task-6b7142c9)

Firmware restored to pre-M8 accepted baseline (b0926cf). ROM confirmed at 931/1024. Voice3 telemetry tags (V3/VT/VA/VV/S3/ST) are back in the periodic report path. No !D handler remains.

## ROM Budget Reality

931 words used, 93 remaining. Function extraction does not reclaim ROM at this code density. Future note-ID work should accept the 93-word budget or move to host-side tools.
