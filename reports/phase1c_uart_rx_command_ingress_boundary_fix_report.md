# Phase 1C UART RX Parser Boundary Fix Report

Date: 2026-04-29
Agent: Codex implementer
Task: `task-b5a6977e`

## Summary

Fixed the UART RX firmware parser boundary classification for the accepted 16-byte command line buffer contract:

- a line with 14 pre-CRLF bytes plus CRLF is accepted into normal line classification, not overlong;
- the 15th pre-CRLF byte is classified as overlong;
- overlong discard consumes bytes until CRLF and does not double-count the trailing CRLF;
- the existing no-echo, no-ACK, and narrow `!N\r\n` command-ingress behavior is preserved.

The fix is in firmware only. The RTL RX FIFO, MMIO decode, and telemetry wiring from Phase 1C remain unchanged.

## Files Changed

- `fw/phase0/phase0_main.c`
- `phase1c_uartrx_work/phase1c_uart_rx_top_tb.v`
- generated firmware, simulation, Quartus, UART, audio, and Git tracking evidence under `reports/`

## Firmware Fix

`phase0_rx_process_byte()` now treats LF after a buffered CR as line termination even when the buffer is at the 16-byte total boundary. That allows 14 payload bytes plus CRLF to reach `phase0_rx_process_line()` and be classified normally.

`phase0_rx_enter_discard()` no longer flushes the hardware FIFO on parser overlong. It records the overlong error once, enters discard mode, and lets the parser consume bytes until CRLF. This prevents the trailing CRLF from becoming a second malformed/partial line when the overlong byte and terminator are already in the RX FIFO.

## Firmware And ROM

- Build log: `reports/phase1c_uart_rx_command_ingress_boundary_fw_build.log`, PASS
- Canonical build log restored/copied: `reports/phase1c_uart_rx_command_ingress_fw_build.log`
- ROM words: `507 / 1024`

## ModelSim Evidence

- Compile: `reports/phase1c_uart_rx_command_ingress_boundary_msim_compile.log`, PASS, `0 errors, 0 warnings`
- Backpressure: `reports/phase1c_uart_rx_command_ingress_boundary_msim_backpressure.log`, PASS, `TB_UART_RX_BACKPRESSURE_PASS rdata=00000007 final_status=00000004 status_word=0023 preserve_oldest=1`
- No-command: `reports/phase1c_uart_rx_command_ingress_boundary_msim_no_command.log`, PASS, `G=6`, `Q=0`, `X=0`
- Commanded: `reports/phase1c_uart_rx_command_ingress_boundary_msim_commanded.log`, PASS, `G=12`, `Q=6`, `X=0`
- Malformed/boundary: `reports/phase1c_uart_rx_command_ingress_boundary_msim_malformed.log`, PASS, `expected_X=00030004`
- NACK regression: `reports/phase1c_uart_rx_command_ingress_boundary_msim_nack.log`, PASS, `TB_NACK_PASS`
- Parser selftests: `reports/phase1c_uart_rx_command_ingress_boundary_parser_selftest.log`, PASS, `Ran 10 tests`

The malformed simulation sends `!X\r\n`, `!N=00000001\r\n`, 14 `B` bytes plus CRLF, 15 `A` bytes plus CRLF, and a partial `!`. The final `X=00030004` proves the 14-byte line is classified as normal malformed input and the 15-byte line is one overlong error.

## Quartus Evidence

- Full compile log: `reports/phase1c_uart_rx_command_ingress_boundary_quartus_compile.log`
- Result: PASS, `0 errors, 14 warnings`
- Tool route: `D:\quartus\quartus\bin64\quartus_sh.exe --flow compile`

Resources:

- LEs: `7,963 / 10,320`
- M9Ks: `14 / 46`
- Memory bits: `80,896 / 423,936`
- DSP9: `6 / 46`
- PLLs: `1 / 2`
- RX FIFO remains explicit logic; no RX FIFO entry appears in the Fitter RAM Summary.

TimeQuest:

- Design-wide TNS: `0.000`
- Slow 85C `sys_clk_50m` setup slack: `+2.438 ns`
- Slow 85C `sys_clk_50m` hold slack: `+0.406 ns`
- Fast 0C `sys_clk_50m` hold slack: `+0.137 ns`
- Fully constrained setup/hold: PASS

Bitstream:

- SOF SHA-256: `CAB259BC697ABB5F76AD48120AE4CD65AB1FD4311FC9AEA59F620868E3F3D7F5`
- Programmer checksum: `0x005F102E`

## Hardware Evidence

Programmer:

- Cable list: `reports/phase1c_uart_rx_command_ingress_boundary_quartus_pgm_list.log`, `USB-Blaster [USB-0]`
- No-command program log: `reports/phase1c_uart_rx_command_ingress_boundary_quartus_pgm.log`, PASS
- Commanded program log: `reports/phase1c_uart_rx_command_ingress_boundary_quartus_pgm_command.log`, PASS
- Malformed program log: `reports/phase1c_uart_rx_command_ingress_boundary_quartus_pgm_malformed.log`, PASS

UART no-command:

- Capture: `reports/phase1c_uart_rx_command_ingress_boundary_uart_capture.txt`
- Parser log: `reports/phase1c_uart_rx_command_ingress_boundary_parser_no_command.log`
- Result: PASS, latest post-reset profile `G=6`, `H=2`, `J/L/N=2`, `T/U/O=2`, `P=0`, `K=0`, `Q=0`, `X=0`

UART commanded:

- Capture: `reports/phase1c_uart_rx_command_ingress_boundary_command_uart_capture.txt`
- Parser log: `reports/phase1c_uart_rx_command_ingress_boundary_parser_commanded.log`
- Result: PASS, six `!N\r\n` commands at 100 ms spacing
- Latest profile: `G=12`, `H=2`, `J/L/N=4`, `T/U/O=4`, `P=0`, `K=0`, `Q=6`, `X=0`
- Echo check: PASS, no `!N` bytes observed in device telemetry capture

UART malformed:

- Capture: `reports/phase1c_uart_rx_command_ingress_boundary_malformed_uart_capture.txt`
- Parser log: `reports/phase1c_uart_rx_command_ingress_boundary_parser_malformed.log`
- Sent `!X\r\n`, `!N=00000001\r\n`, `BBBBBBBBBBBBBB\r\n`, `AAAAAAAAAAAAAAA\r\n`, and a partial `!`
- Result: PASS, latest profile `G=6`, `H=2`, `J/L/N=2`, `T/U/O=2`, `P=0`, `K=0`, `Q=0`, `X=00030004`
- Echo check: PASS, malformed input bytes absent from device telemetry capture

Audio:

- Capture: `reports/phase1c_uart_rx_command_ingress_boundary_audio_capture.wav`
- FFmpeg log: `reports/phase1c_uart_rx_command_ingress_boundary_audio_ffmpeg.log`
- Analysis: `reports/phase1c_uart_rx_command_ingress_boundary_audio_analysis.txt`
- Duration: `11.99 s`
- Peak level: `-31.823148 dB`
- RMS level: `-39.187848 dB`
- Min/max sample: `-838 / 840`
- Hardware mix clip telemetry: `K=0`

## Git Tracking

The workspace contains a large untracked tree relative to `HEAD`, so I did not stage broad paths. I recorded the task source baseline at the user request point in `reports/phase1c_uart_rx_command_ingress_boundary_git_baseline.log`:

- `HEAD=ecbeb30cb64fb86f63dbca599c9651e80a49432a`
- `fw/phase0/phase0_main.c` blob `85975eb97a5a0c18561f52d6576bcd1bf54ee6f4`
- `phase1c_uartrx_work/phase1c_uart_rx_top_tb.v` blob `6ad0f929b6ab6c06fb7f42df4f0e3417af3db2d8`

I will stage only task-owned source/report/evidence paths if a commit is made.

## Notes

UART capture scripts open COM5 before JTAG programming to catch reset telemetry. Some raw captures can include stale pre-reset reports from the previously programmed image; all checks use the latest post-reset telemetry after `I/S`.

One transient JTAG scan-chain error occurred after the Quartus compile. A cable-list check immediately found `USB-Blaster [USB-0]`, and the subsequent programming and hardware smoke runs passed.
