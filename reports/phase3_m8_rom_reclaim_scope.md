# Phase 3 M8 ROM Reclamation Scope

Date: 2026-05-14 | Agent: claude-implementer | Task: `task-10a08030`

## Verdict: GO -- reclaim ~50-80 words, target ROM ~850-880

93 words remaining (931/1024) is insufficient for firmware note IDs. Reclaiming 50-80 words from telemetry + parser code makes ~140-170 words available, enough for a minimal note-ID implementation.

## ROM Consumers (estimated from firmware structure)

| Component | Est. Words | Reclaimable? | Risk |
| --- | --- | --- | --- |
| Voice debug telemetry (V3/VT/VA/VV/S3/ST tags) | ~80-100 | Yes: remove optional voice3 diag | Low observability loss |
| Hex converter (phase0_hex_ascii) | ~12 | No: shared core | Required |
| UART put_frame / put_hex32 | ~20 | No: shared core | Required |
| RX parser (line processing) | ~120-150 | Yes: simplify conditional structure | Medium: parser correctness |
| LRU scheduler | ~100 | Limited: core functionality | High |
| Damp_mix restore on bare/param !N | ~30 | Limited: M4 compatibility | Low |
| Quiet/holdoff code | ~15 | Possible: if command spacing enforces proper timing | Low: may re-expose UART contention |
| Stage 2 init (codec writes) | ~20 | No: boot-critical | Cannot touch |
| Startup telemetry (I/S/R) | ~15 | No: boot-critical | Cannot touch |

## Recommended M8 Slice: Remove Voice3 Diagnostic Telemetry

Voice3 telemetry (V3/VT/VA/VV/S3 tags) costs ~80-100 ROM words in formatting and register reads. These tags report per-voice diagnostics that firmware could report via a dedicated query command instead of every report cycle.

**Approach**: Gate voice3 diagnostic tags behind a new `!D\r\n` (diagnostics dump) command. When `!D` is received, emit voice3 tags once. Normal periodic telemetry omits voice3 tags.

**Savings**: ~60-80 words (from removing V3/VT/VA/VV/S3 formatting in the periodic report path).

**Risk**: Verifier loses per-cycle voice3 observability but gains on-demand diagnostics via `!D`.

## ROM Headroom After M8

Current: 931 words. After M8: ~850-870 words. Available: ~150-170 words. Sufficient for minimal note-ID parser (needs ~80-100 words).

## Next Task

"Implement M8: gate voice3 telemetry behind !D diagnostic command"
