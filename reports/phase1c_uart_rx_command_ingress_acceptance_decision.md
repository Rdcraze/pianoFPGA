# Phase 1C UART RX Command-Ingress Acceptance Decision

Date: 2026-04-29
Orchestrator: Codex orchestrator agent `1c005a25-956c-4b69-9b69-9bf3cd9a8d68`
Task: `task-24b10dfc`

## Decision

ACCEPTED AND PROMOTED.

The Phase 1C UART RX command-ingress implementation is accepted as the current UART RX baseline. The accepted image is the boundary-fixed build with:

- SOF SHA-256: `CAB259BC697ABB5F76AD48120AE4CD65AB1FD4311FC9AEA59F620868E3F3D7F5`
- Programmer checksum: `0x005F102E`

This promotion is limited to the accepted `!N\r\n` command-ingress slice. It does not authorize broader command grammar, host-selected note parameters, hardware dispatch, additional voices, SDRAM, richer physics, UI work, sample playback, larger CPU/ISA work, or CPU participation in the audio sample loop.

## Accepted Behavior

Accepted UART RX behavior:

- UART TX data/status offsets remain `0x40001000 + 0x00` and `0x40001000 + 0x04`.
- RXDATA/RXSTATUS/RXCONTROL are added at UART-page offsets `0x08`, `0x0C`, and `0x10`.
- The only accepted command is `!N\r\n`.
- A valid command enqueues one default note into the existing firmware-owned three-voice round-robin scheduler.
- There is no byte echo, command echo, or standalone ACK frame.
- `Q` telemetry after `P` is the ACK count.
- `X` reports RX/parser error state.
- Telemetry order is `I/S/R/V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E/G/H/J/L/N/P/Q/X`.

Accepted parser boundary behavior:

- A line with 14 pre-CRLF bytes plus CRLF is not overlong and is classified normally.
- The 15th pre-CRLF byte is overlong exactly once.
- Overlong discard consumes through CRLF without double-counting the terminator.

## Evidence Summary

Implementation report:

- `reports/phase1c_uart_rx_command_ingress_impl_report.md`

Initial validation:

- `reports/phase1c_uart_rx_command_ingress_validation.md`
- Result: FAIL only for exact parser boundary handling.

Boundary fix report:

- `reports/phase1c_uart_rx_command_ingress_boundary_fix_report.md`

Boundary fix validation:

- `reports/phase1c_uart_rx_command_ingress_boundary_fix_validation.md`
- Result: parser/UART/simulation/resource/timing/ROM/scope PASS, audio smoke FAIL due anomalous capture.

Audio rerun report:

- `reports/phase1c_uart_rx_boundary_audio_rerun_report.md`
- Cause identified: prior anomalous capture used an unplugged external microphone.
- Same SOF/checksum used; no source or bitstream rebuild.

Audio rerun validation:

- `reports/phase1c_uart_rx_boundary_audio_rerun_validation.md`
- Result: PASS.
- Corrected rerun shows expected `~436 Hz` commanded note event, `872 Hz` harmonic content, peak near accepted captures, no clipping, no internal dropouts, low DC offset, `K=0`, `Q=6`, `X=0`, and no echo.

## Resource And Timing Baseline

Accepted resource/timing identity from the boundary-fixed build:

- LEs: `7,963 / 10,320`
- M9Ks: `14 / 46`
- Memory bits: `80,896 / 423,936`
- DSP9s: `6 / 46`
- PLLs: `1 / 2`
- Firmware ROM: `507 / 1024` words
- Slow-85C `sys_clk_50m` setup slack: `+2.438 ns`
- Slow-85C `sys_clk_50m` hold slack: `+0.406 ns`
- Fast-0C `sys_clk_50m` hold slack: `+0.137 ns`
- Listed TNS: `0.000`
- Setup and hold: fully constrained

This remains inside the accepted implementation gates.

## Accepted Test Profiles

No-command profile:

- `G=6`
- `H=2`
- `J/L/N=2`
- `T/U/O=2`
- `P=0`
- `K=0`
- `Q=0`
- `X=0`

Six-command profile:

- six `!N\r\n` commands at the accepted smoke cadence
- `G=12`
- `H=2`
- `J/L/N=4`
- `T/U/O=4`
- `P=0`
- `K=0`
- `Q=6`
- `X=0`
- no command echo observed

Malformed/boundary profile:

- `!X\r\n`, `!N=00000001\r\n`, 14-byte pre-CRLF malformed line, 15-byte pre-CRLF overlong line, and partial input do not trigger notes.
- Final parser status matches `X=00030004`.

## Still Blocked

The following remain explicitly blocked without a new contract and validation path:

- SDRAM;
- fourth voice or broader polyphony;
- richer physics;
- exact-48 kHz PLL/sample-rate work;
- larger CPU or ISA changes;
- hardware note dispatcher;
- voice stealing;
- per-note state;
- per-voice parameter banks;
- host-selected voice, pitch, velocity, duration, or synthesis parameters;
- codec configuration over RX;
- diagnostic clear commands over RX;
- sample playback;
- UI/TFT/touch work;
- CPU work in the audio sample loop;
- non-prefix-compatible UART telemetry changes;
- register changes outside the accepted UART RX offsets and frozen ABI.

## Next Direction

Treat this as the stable Phase 1C UART RX baseline. Further work should stay controlled: either add host/operator tooling around the accepted `!N\r\n` command and parser checks, or prepare a separate design-only memo for the next command/control extension. Do not expand command semantics directly from this acceptance decision.
