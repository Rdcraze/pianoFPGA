# Phase 1C UART RX Host Smoke Tooling Report

Date: 2026-04-29
Agent: Codex implementer
Task: `task-c9de1991`

## Summary

Added host-only UART RX baseline smoke tooling for the accepted Phase 1C UART RX command-ingress baseline.

No RTL, firmware, constraints, clocking, register maps, UART semantics, or resource-affecting files were changed.

## Files Changed

- `scripts/phase1c_uart_rx_baseline_smoke.py`
- `scripts/test_phase1c_uart_rx_baseline_smoke.py`
- `reports/phase1c_uart_rx_host_smoke_tooling_report.md`
- evidence logs under `reports/phase1c_uart_rx_host_smoke_tooling_*`

## Tooling Behavior

The new script reuses `scripts/phase1c_uart_telemetry.py` parsing helpers and adds accepted-baseline smoke checks:

- validates frozen startup/cycle order: `I/S/R/V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E/G/H/J/L/N/P/Q/X`;
- supports `no-command` latest-value profile: `G=6`, `T/U/O=2`, `J/L/N=2`, `Q=0`, `X=0`, `K=0`;
- supports `commanded` latest-value profile for six `!N\r\n` commands: `G=12`, `T/U/O=4`, `J/L/N=4`, `Q=6`, `X=0`, `K=0`;
- checks nonzero voice health tags `V/Y/Z/M`;
- detects command echo regressions by rejecting raw `!N` in device telemetry;
- detects standalone `ACK` or `OK` lines;
- tolerates LF-normalized text captures while preserving raw CRLF parsing for UART captures;
- emits concise PASS/FAIL output for verifier logs;
- optionally captures from a serial port and sends only the accepted `!N\r\n` command in commanded mode.

## Usage

Check an existing no-command capture:

```powershell
python scripts\phase1c_uart_rx_baseline_smoke.py check reports\phase1c_uart_rx_command_ingress_boundary_uart_capture.txt --mode no-command
```

Check an existing commanded capture:

```powershell
python scripts\phase1c_uart_rx_baseline_smoke.py check reports\phase1c_uart_rx_boundary_audio_rerun_uart_capture.txt --mode commanded
```

Optional operator capture without programming hardware:

```powershell
python scripts\phase1c_uart_rx_baseline_smoke.py capture --port COM5 --mode commanded --output reports\capture.txt --duration 12 --check
```

The `capture` subcommand requires `pyserial`. It does not program the FPGA or rebuild anything.

## Evidence

Self-test:

- Command: `python scripts\test_phase1c_uart_rx_baseline_smoke.py`
- Log: `reports/phase1c_uart_rx_host_smoke_tooling_selftest.log`
- Result: PASS, `Ran 9 tests`

Parser regression:

- Command: `python scripts\test_phase1c_uart_telemetry.py`
- Log: `reports/phase1c_uart_rx_host_smoke_tooling_parser_regression.log`
- Result: PASS, `Ran 10 tests`

No-command accepted capture check:

- Capture: `reports/phase1c_uart_rx_command_ingress_boundary_uart_capture.txt`
- Log: `reports/phase1c_uart_rx_host_smoke_tooling_no_command_check.log`
- Result: `UART_RX_BASELINE_SMOKE_PASS mode=no-command frames=170 cycles=7 G=00000006 Q=00000000 X=00000000 K=00000000`

Commanded accepted capture check:

- Capture: `reports/phase1c_uart_rx_boundary_audio_rerun_uart_capture.txt`
- Log: `reports/phase1c_uart_rx_host_smoke_tooling_commanded_check.log`
- Result: `UART_RX_BASELINE_SMOKE_PASS mode=commanded frames=266 cycles=10 G=0000000C Q=00000006 X=00000000 K=00000000`

No hardware rebuild or reprogramming was needed for this task. The checks reused accepted baseline captures from the promoted build.

## Limitations

- The tool validates the accepted narrow UART RX baseline only.
- It does not expand command grammar beyond `!N\r\n`.
- It does not validate analog audio waveform content; that remains covered by the separate audio evidence workflow.
- It is not a replacement for Quartus, ModelSim, or firmware-build gates.
- For operator serial capture, hardware must already be programmed with the accepted SOF identity before running the script.
