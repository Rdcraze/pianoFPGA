# Phase 3 M3b Per-Voice Polyphonic Hardware Validation (Final)

Verifier: claude-verifier `e8db32f8-3c5f-4a11-bf2d-8f6e3ad76c4c`
Task: `task-e5da9090` (final acceptance)
Commit: `d3d9662` (parser line-reset fix) on `03be78b` (report)
SOF checksum: `0x007795FA`

## Verdict

**PASS — all valid-command captures end with X=0, K=0.**

The parser line-reset bug (parameterized !N path not clearing `phase0_rx_line_len` on return) was the root cause of all prior X errors. With this fix, valid commands produce clean telemetry across all test scenarios. Malformed input is correctly rejected (Q unchanged, X incremented). Stealing, bare compatibility, and polyphonic parameterized scheduling are all confirmed.

## Test Results

| Test | Q | X | K | Notes |
| --- | --- | --- | --- | --- |
| Baseline | 0 | **0** | 0 | Clean |
| Bare after param | 3 | **0** | 0 | 1 param + 2 bare accepted |
| Polyphonic | 6 | **0** | 0 | 3 more params accepted |
| Steal burst | 14 | **0** | 0 | 8 burst accepted, ST>0 |
| Malformed | 14 | 0x00070001 | 0 | Q unchanged, X incremented |

All valid-command captures end with X=0, K=0. Malformed command is the only X increment.

## Root Cause of Prior X Errors

The parameterized !N parser path (`!NLLLLVVVV\r\n`) called `phase0_rx_record_error()` or `return` without first clearing `phase0_rx_line_len = 0`. Stale bytes from the previous command's line buffer leaked into the next command's processing, causing spurious OVERLONG (error 3) and UNSUPPORTED_ARG (error 7) errors.

Fix: clear `phase0_rx_line_len = 0` before every return path in the parser, including error paths and the parameterized command path.

## What Changed (This Run vs Prior Attempts)

| Attempt | Fix | Result |
| --- | --- | --- |
| task-6a3a7645 | M3b base | X>0 (UART contention suspected) |
| task-a4198c78 | Clean board state | X>0 (UART contention suspected) |
| task-7dc6b8b8 | Quiet path v1 | X>0 (TX FIFO suspected) |
| task-2f127ad5 | Quiet path v2 + holdoff | Canceled before acceptance after parser bug found |
| **task-e5da9090** | **Parser line-reset fix** | **X=0** |

The true root cause was the parser bug in firmware — all prior hardware/UART theories were wrong.

## Polyphonic Evidence

Parameterized commands demonstrate true polyphonic behavior:

- `!N006A7FFF` (loop 106, max velocity) — LRU-assigned to physical voice
- `!N00407FFF` (loop 64, higher pitch) — LRU-assigned to different voice
- `!N007F4000` (loop 127, half velocity) — LRU-assigned to third voice

Per-voice trigger counts (VT/VV for voice3, T/U/O for voices 0-2) increment coherently across the parameterized command sequence. ST (steal count) increases when all 4 voices are active and additional commands arrive. The polyphonic architecture correctly dispatches different pitches/velocities to different physical voices.

## Bare !N Compatibility

Bare `!N\r\n` after parameterized retune increments Q and triggers a note using default loop_len/velocity — confirming the bare-compat default-write path works. The per-voice params from a previous retune do NOT persist into the bare command.

## Stealing with Per-Voice Parameters

ST>0 confirmed under burst load (8 parameterized commands on 4 physical voices). P/ST coherent.

## ROM Exceptions

| Exception | Gate | Actual | Delta | Reason |
| --- | --- | --- | --- | --- |
| M3b ROM | <= 900 | 912 | +12 | Bare compat + quiet path + parser fix |

## Resource/Timing

| Metric | Value |
| --- | --- |
| Quartus errors | 0 |
| Warnings | 16 |
| LEs | 9,938 |
| Setup slack | +2.948 ns |

## Recommendation

**PASS — promote Phase 3 M3b per-voice polyphonic pitch+velocity to accepted baseline.**

All hardware validation gates are satisfied. The parser line-reset fix resolves the month-long X=0 blocker. Polyphonic parameterized commands, voice stealing, bare !N backward compatibility, and malformed rejection are all confirmed on hardware with clean telemetry.
