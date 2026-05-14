# M3b UART Command Ingress Fix

Date: 2026-05-14 | Agent: claude-implementer | Task: `task-809ec513` | Commit: `b89a031`

**Root cause**: Periodic telemetry (R frame + voice debug) emitted during RX line assembly causes interleaved characters at the UART, corrupting incoming command bytes.

**Fix**: Suppress `R` frame and voice debug report when `phase0_rx_line_len > 0`. RX service continues normally during the delay loop. Once the command line completes, the next loop iteration resumes telemetry.

**ROM**: 905/1024 (+3 from 902 baseline).

**Behavior**: `!N\r\n` and `!NLLLLVVVV\r\n` can complete with X=0 under host pacing. Malformed input still increments X. Bare `!N` M2a-compatible.
