# M3b UART Command Ingress Fix

Date: 2026-05-14 | Agent: claude-implementer | Task: `task-809ec513`, `task-64393328`
Commits: `b89a031`, `6497f12`

**Root cause**: Periodic telemetry (R frame + voice debug) interleaves with incoming UART command bytes, causing RX parse errors (overlong, unsupported arg). This affects X=0 gate for command validation.

**Fix 1** (`b89a031`): Suppress report while `phase0_rx_line_len > 0`. Insufficient — telemetry resumes immediately after line completion, before next command arrives.

**Fix 2** (`6497f12`): Add `phase0_rx_quiet_count` set to 1 after every line completion, decremented each report cycle. Telemetry suppressed during RX assembly AND for 1 cycle after command completion. This provides a ~95 ms quiet window at current report cadence.

**ROM**: 917/1024 (+17 over original 900 gate, +12 from 905 after fix 1).

**Verifier handoff**: After programming, send commands with ≥ 100ms spacing. Expected: `K=0, X=0` for valid `!N\r\n` and `!NLLLLVVVV\r\n`.
