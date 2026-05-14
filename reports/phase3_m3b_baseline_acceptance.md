# Phase 3 M3b Baseline Acceptance

Date: 2026-05-14
Agent: codex-orchestrator `1c005a25-956c-4b69-9b69-9bf3cd9a8d68`
Related tasks: `task-7c34223f`, `task-9723f616`, `task-98960f31`, `task-8b603dfd`, `task-809ec513`, `task-64393328`, `task-77b0a055`, `task-e5da9090`

## Verdict

Phase 3 M3b is accepted as the current per-physical-voice pitch and velocity baseline.

The accepted behavior is true polyphonic parameterized note dispatch over the existing 4 physical voices. Firmware selects a free or oldest physical voice, writes that voice's loop length and velocity registers, then triggers only that physical voice. Bare `!N\r\n` remains backward compatible by restoring default per-voice parameters before trigger.

## Accepted Behavior

| Command | Behavior |
| --- | --- |
| `!N\r\n` | Backward-compatible fixed-note trigger using default loop length and velocity |
| `!NLLLLVVVV\r\n` | Polyphonic parameterized note; writes `LLLL` and `VVVV` to the selected physical voice before trigger |

Loop length is clamped to the RTL-supported `32..127` range. Velocity is clamped to `0..32767`. Malformed parameterized commands are rejected: `Q` does not increment and `X` records the parser error/count.

## Accepted Evidence

| Item | Result |
| --- | --- |
| Final implementation head | `03be78b` |
| Parser fix commit | `d3d9662` |
| Hardware verifier task | `task-e5da9090` |
| Hardware report | `reports/phase3_m3b_hardware_validation.md` |
| SOF checksum | `0x007795FA` |
| Firmware ROM | 912 / 1,024 |
| Quartus errors | 0 |
| Warnings | 16 |
| Setup slack | +2.948 ns |
| LEs | 9,938 |
| Baseline valid health | `K=0`, `X=0`, `Q=0` |
| Bare after parameterized retune | `K=0`, `X=0`, `Q=3` |
| Polyphonic parameterized commands | `K=0`, `X=0`, `Q=6` |
| Steal burst | `K=0`, `X=0`, `Q=14`, `ST=18` |
| Malformed rejection | `Q=14` unchanged, `X=00070001` |

## Exceptions

The original M3b firmware hard gate was 900 ROM words. The accepted image uses 912 words.

This exception is accepted because the growth covers three correctness fixes needed for reliable hardware validation and compatibility:

- bare `!N` default per-voice parameter restore after retuned commands
- UART report quieting/holdoff while command lines are processed
- parameterized parser line-reset fix, which clears stale RX bytes on every completed-line exit

This is a baseline-specific exception, not a new default budget. Future firmware work starts from 912 words and should treat additional ROM growth as a deliberate tradeoff.

## Superseded Evidence

Earlier PASS recommendations from `task-6a3a7645`, `task-a4198c78`, and `task-7dc6b8b8` are superseded. Their valid-command captures had nonzero `X`, later traced to the parameterized parser returning without clearing `phase0_rx_line_len`.

Only these UART captures are part of the accepted evidence set:

- `reports/phase3_m3b_baseline_uart.txt`
- `reports/phase3_m3b_bare_after_param_uart.txt`
- `reports/phase3_m3b_polyphonic_uart.txt`
- `reports/phase3_m3b_steal_burst_uart.txt`
- `reports/phase3_m3b_malformed_uart.txt`

## Next Planning Boundary

M3b proves per-voice pitch and velocity dispatch on hardware. The next risky boundary is playable note semantics on top of that baseline: note-on/note-off or release behavior, sustain/damper policy, UART command shape, and the ROM impact of any additional per-note state.
