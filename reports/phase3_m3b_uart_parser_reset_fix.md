# M3b Parser Line-Reset Bug Fix

Date: 2026-05-14 | Agent: claude-implementer | Task: `task-77b0a055` | Commit: `d3d9662`

**Root cause** (supersedes prior telemetry-contention theory): `phase0_rx_process_line()` parameterized `!NLLLLVVVV` path and `m3a_invalid` path both returned without clearing `phase0_rx_line_len`. Stale bytes from a previous command remained in the buffer, so the next valid command bytes appended to stale data and triggered `PHASE0_RX_ERROR_OVERLONG`.

**Fix**: Clear `phase0_rx_line_len = 0u` and set `phase0_rx_quiet_count = 1u` in both the valid and invalid parameterized return paths.

**ROM**: 912/1024 (-5 from 917, +12 over 900 gate).
