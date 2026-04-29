# Phase 1C UART RX Command-Ingress Contract Acceptance Decision

Date: 2026-04-28
Orchestrator: Codex orchestrator agent `1c005a25-956c-4b69-9b69-9bf3cd9a8d68`
Task: `task-e6c7bc2a`

## Decision

ACCEPTED AS IMPLEMENTATION GATE.

The revised Phase 1C UART RX command-ingress contract in `reports/phase1c_uart_rx_command_ingress_contract.md` is accepted as the controlling specification for any later UART RX command-ingress implementation.

This decision accepts the contract only. It does not itself implement or validate RTL, firmware, constraints, MIF/build outputs, Quartus project edits, host command tools, generated bitstreams, or hardware behavior. Any UART RX implementation must be assigned as a separate scoped task and must follow this contract exactly or stop for a new decision.

## Validation History

Initial validation artifact `c2e0d19a-049c-46b6-bdcf-d1be747e7a7e` in `reports/phase1c_uart_rx_command_ingress_contract_validation.md` returned FAIL for contract precision issues:

- missing `H=2` in no-command and commanded acceptance profiles;
- inconsistent overlong threshold wording;
- weaker partial reset/flush `X` behavior;
- ACK wording that could be read as implying an immediate response.

Revision artifact `7e6588a5-06d5-4a99-a34f-5f982ee57d4e` updated the same memo as a documentation-only change.

Revalidation artifact `3af2cab0-c5d4-460f-9fe8-8456fdf14848` in `reports/phase1c_uart_rx_command_ingress_contract_revalidation.md` returned PASS. The verifier confirmed the prior blockers are resolved and that the revision remained documentation-only.

## Accepted Contract Points

The accepted first UART RX slice is limited to one command:

```text
!N\r\n
```

Accepted behavior:

- `!N\r\n` enqueues exactly one default note event into the existing firmware-owned three-voice round-robin policy.
- The firmware selects the next voice; the host cannot select voice, pitch, velocity, duration, parameters, codec configuration, diagnostics clear, sample content, or synthesis behavior.
- CPU work remains in the low-rate control path and outside the audio sample loop.
- There is no byte-level echo, command echo, or standalone immediate ACK frame.
- `Q` telemetry after `P` is the ACK mechanism; it increments only after a valid command schedules a note event.

Accepted UART MMIO additions for a later implementation:

- Existing TX data remains `0x40001000 + 0x00`.
- Existing TX status remains `0x40001000 + 0x04`.
- RX data is reserved at `0x40001000 + 0x08`.
- RX status is reserved at `0x40001000 + 0x0C`.
- RX control is reserved at `0x40001000 + 0x10`.
- Control-register offsets through `0x80` remain frozen.

Accepted telemetry order with RX enabled:

```text
I/S/R
V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E/G/H/J/L/N/P/Q/X
```

Accepted health profiles:

- No-command compatibility remains `G=6`, `H=2`, `J/L/N=2`, `T/U/O=2`, `P=0`, `K=0`, with `Q=0`, `X=0` when RX telemetry is present.
- After six valid `!N\r\n` commands after boot, cumulative expected totals are `G=12`, `H=2`, `J/L/N=4`, `T/U/O=4`, `Q=6`, `P=0`, `K=0`.

Accepted parser/error details:

- Maximum command line length is exactly 16 total bytes including CRLF.
- At most 14 bytes may appear before CRLF.
- The 15th pre-CRLF byte makes the line overlong immediately and creates exactly one error.
- Reset clears partial command state and clears `Q/X`.
- `FLUSH_RX_FIFO` while a partial command is buffered reports `X` error code `4` exactly once and sets `RX_DROPPED_STICKY`.

## Implementation Gates

Any later UART RX implementation must meet the contract gates:

- Full Quartus compile passes.
- TimeQuest setup and hold are fully constrained.
- Listed TNS remains `0.000`.
- Total LEs remain at or below `8,200 / 10,320`.
- Slow-85C `sys_clk_50m` setup slack remains at or above `+1.0 ns`.
- Slow-85C `sys_clk_50m` hold slack remains nonnegative.
- Firmware ROM remains within `1024` words.
- DSP9 usage remains `6 / 46`.
- M9K usage remains `14 / 46` unless a later decision explicitly authorizes one additional memory block for RX buffering.
- No-command, commanded, malformed-input, backpressure, parser-regression, Quartus, UART, and audio smoke evidence must be reported.

## Still Blocked

This decision does not authorize:

- SDRAM;
- fourth voice or broader polyphony;
- richer physics;
- exact-48 kHz PLL/sample-rate work;
- larger CPU or ISA changes;
- hardware note dispatcher;
- voice stealing;
- per-note state;
- per-voice parameter banks;
- sample playback;
- UI/TFT/touch work;
- CPU participation in the audio sample loop;
- non-prefix-compatible UART telemetry changes;
- register changes before the accepted frozen ranges.

## Next Action

Create a separate, narrow UART RX implementation task using this accepted contract as the required specification. The implementation must stop and report rather than broadening scope if any contract gate cannot be met.
