# Phase 3 M8 ROM Reclamation Implementation

Date: 2026-05-14 | Agent: claude-implementer | Commit: `9506e65`

## Verdict: NO-GO -- ROM increased to 948 (+17 from 931)

## Changes

- Removed V3/VT/VA/VV/S3 from periodic telemetry (~33 words saved)
- Added `phase0_diag_dump_voice3()` function (~35 words)
- Added `!D\r\n` parser handler (~15 words)

## Why Reclamation Failed

The inline voice3 tag sequences (5 multi-char puts each) were compact. Wrapping them in a function call adds a call/return pair, and the `!D` parser handler adds conditional checks. The function call overhead exceeded the inline savings.

## ROM Budget Reality

931 words used, 93 remaining. Reclaiming space via function extraction does not work at this code density. Future note-ID work must either:
- Accept the current 93-word ROM budget and design minimal note ID within it
- Reclaim via compiler optimization flags (if RISC-V GCC has -Os etc.)
- Move ROM-bounded features to host tools (as M5/M6/M7a did)
