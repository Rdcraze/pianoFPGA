# Phase 1C UART RX Command Ingress Implementation Report

Date: 2026-04-28
Agent: Codex implementer
Task: `task-dcc92e91`

## Summary

Implemented the accepted narrow UART RX command-ingress slice:

- added 115200 8N1 UART RX sampling in `phase0_uart_mmio`;
- added UART RX MMIO offsets `RXDATA=0x08`, `RXSTATUS=0x0C`, `RXCONTROL=0x10`;
- implemented a minimum 16-byte RX FIFO as explicit logic registers, not M9K RAM;
- preserved TXDATA `0x00` and STATUS `0x04`;
- extended the SoC UART page decode to `data_addr[4:2]`;
- added firmware polling/parser support for exactly `!N\r\n`;
- valid commands enqueue one default note through the existing firmware-owned three-voice round-robin;
- appended `Q` and `X` telemetry after `P`;
- preserved no echo and no standalone ACK.

The first hardware commanded run exposed an RX overrun while firmware was in the report delay loop. The final implementation services RX periodically inside that low-rate delay loop (`8192`-cycle chunks), keeping the CPU out of the audio sample path while meeting the six-command hardware smoke.

## Files Changed

- `rtl/peripherals/phase0_uart_mmio.v`
- `rtl/control/phase0_rv32i_soc.v`
- `fw/phase0/phase0_hw.h`
- `fw/phase0/phase0_main.c`
- `phase1c_uartrx_work/phase1c_uart_rx_top_tb.v`
- generated firmware, simulation, Quartus, UART, and audio evidence under `reports/`

## Contract Behavior

Implemented command grammar:

```text
!N\r\n
```

Rejected in this slice:

- unknown opcodes, including `!X\r\n`;
- unsupported arguments, including `!N=00000001\r\n`;
- overlong lines with 15 bytes before CRLF;
- partial lines until CRLF or reset/flush;
- host-selected voice, pitch, velocity, duration, parameters, codec, diagnostic clear, or sample selection.

Telemetry order with RX enabled:

```text
I/S/R/V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E/G/H/J/L/N/P/Q/X
```

## Resource And Timing Evidence

Quartus full compile:

- Log: `reports/phase1c_uart_rx_command_ingress_quartus_compile.log`
- Result: PASS, `0 errors, 14 warnings`
- Tool route: `D:\quartus\quartus\bin64\quartus_sh.exe --flow compile`
- Note: the 32-bit fitter path hit a local license-file issue; the 64-bit full flow completed cleanly.

Final fitted resources:

- LEs: `7,963 / 10,320`, delta `+415` vs accepted `7,548`
- M9Ks: `14 / 46`
- Memory bits: `80,896 / 423,936`
- DSP9: `6 / 46`
- PLLs: `1 / 2`
- RX FIFO implementation: explicit logic registers, no M9K RX FIFO entry in Fitter RAM Summary

TimeQuest:

- Design-wide TNS: `0.0`
- Slow 85C `sys_clk_50m` setup slack: `+2.438 ns`
- Slow 85C `sys_clk_50m` hold slack: `+0.406 ns`
- Fast 0C `sys_clk_50m` hold slack: `+0.137 ns`
- Fully constrained setup/hold: PASS

Firmware:

- Log: `reports/phase1c_uart_rx_command_ingress_fw_build.log`
- ROM words: `500 / 1024`, delta `+182` vs accepted `318`

Bitstream:

- SOF SHA-256: `E53FC492C4720433AD301BBD0E328F950D16C22AD20D524191F220D9B50CB1D3`
- Programmer checksum: `0x005EF7CF`

## ModelSim Evidence

- Compile: `reports/phase1c_uart_rx_command_ingress_msim_compile.log`, PASS, `0 errors, 0 warnings`
- Backpressure: `reports/phase1c_uart_rx_command_ingress_msim_backpressure.log`, PASS, `TB_UART_RX_BACKPRESSURE_PASS rdata=00000007 status_word=0033`
- No-command: `reports/phase1c_uart_rx_command_ingress_msim_no_command.log`, PASS, `G=6`, `Q=0`, `X=0`
- Commanded: `reports/phase1c_uart_rx_command_ingress_msim_commanded.log`, PASS, `G=12`, `J/L/N=4`, `Q=6`, `X=0`
- Malformed/partial/overlong: `reports/phase1c_uart_rx_command_ingress_msim_malformed.log`, PASS, `G=6`, `Q=0`, `X=00030003`
- Voice regression: `reports/phase1c_uart_rx_command_ingress_msim_voice.log`, PASS, `VOICE_TB_PASS`
- NACK regression: `reports/phase1c_uart_rx_command_ingress_msim_nack.log`, PASS, `TB_NACK_PASS`
- Parser selftests: `reports/phase1c_uart_rx_command_ingress_parser_selftest.log`, PASS, `Ran 10 tests`

## Hardware Evidence

Programmer:

- Cable list: `reports/phase1c_uart_rx_command_ingress_quartus_pgm_list.log`, `USB-Blaster [USB-0]`
- No-command program log: `reports/phase1c_uart_rx_command_ingress_quartus_pgm.log`, PASS
- Commanded program log: `reports/phase1c_uart_rx_command_ingress_quartus_pgm_command.log`, PASS
- Malformed program log: `reports/phase1c_uart_rx_command_ingress_quartus_pgm_malformed.log`, PASS

UART no-command:

- Capture: `reports/phase1c_uart_rx_command_ingress_uart_capture.txt`
- Parser log: `reports/phase1c_uart_rx_command_ingress_parser_no_command.log`
- Result: PASS, latest post-reset profile `G=6`, `H=2`, `J/L/N=2`, `T/U/O=2`, `P=0`, `K=0`, `Q=0`, `X=0`

UART commanded:

- Capture: `reports/phase1c_uart_rx_command_ingress_command_uart_capture.txt`
- Check log: `reports/phase1c_uart_rx_command_ingress_parser_commanded.log`
- Result: PASS, six `!N\r\n` commands at 100 ms spacing
- Latest profile: `G=12`, `H=2`, `J/L/N=4`, `T/U/O=4`, `P=0`, `K=0`, `Q=6`, `X=0`
- Echo check: PASS, no `!N` bytes observed in device telemetry capture

UART malformed:

- Capture: `reports/phase1c_uart_rx_command_ingress_malformed_uart_capture.txt`
- Check log: `reports/phase1c_uart_rx_command_ingress_parser_malformed.log`
- Sent `!X\r\n`, `!N=00000001\r\n`, `AAAAAAAAAAAAAAA\r\n`, and a partial `!`
- Result: PASS, latest profile `G=6`, `H=2`, `J/L/N=2`, `T/U/O=2`, `P=0`, `K=0`, `Q=0`, `X=00030003`
- Echo check: PASS, malformed input bytes absent from device telemetry capture

Audio:

- Devices: `reports/phase1c_uart_rx_command_ingress_audio_devices.log`
- Capture: `reports/phase1c_uart_rx_command_ingress_audio_capture.wav`
- FFmpeg log: `reports/phase1c_uart_rx_command_ingress_audio_ffmpeg.log`
- Analysis: `reports/phase1c_uart_rx_command_ingress_audio_analysis.txt`
- Duration: `11.99 s`
- Peak level: `-13.140396 dB`
- RMS level: `-42.553396 dB`
- Min/max sample: `-7218 / 2427`
- Hardware mix clip telemetry: `K=0`

## Notes

Hardware UART capture scripts open COM5 before JTAG programming to catch reset telemetry. Some raw captures include one report from the previously programmed image before the `I/S` reset sequence; acceptance checks use the latest post-reset telemetry and all logged parser/check outputs PASS.

The implementation remains intentionally narrow. It does not implement host-selected note parameters, a hardware dispatcher, richer parser grammar, diagnostic clear commands, or audio-loop CPU work.
