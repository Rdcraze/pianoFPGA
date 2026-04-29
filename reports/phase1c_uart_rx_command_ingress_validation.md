# Phase 1C UART RX Command-Ingress Implementation Validation

Verifier: Codex verifier agent `e9722d83-b000-4165-a5a7-36b758c2e8d8`  
Task: `task-3a7c0518`  
Implementation artifact: `49616f66-9724-43eb-adc1-7d0574c5a936`  
Implementation report: `reports/phase1c_uart_rx_command_ingress_impl_report.md`  
Accepted contract: `reports/phase1c_uart_rx_command_ingress_contract.md`  
Acceptance decision: `reports/phase1c_uart_rx_command_ingress_contract_acceptance_decision.md`

## Verdict

FAIL. Revision required before acceptance.

The implementation passes the reported no-command, six-command, malformed, simulation, Quartus, and hardware smoke cases I checked. However, source inspection found an exact contract violation in the firmware command parser: a line with the maximum allowed 14 bytes before CRLF is classified as overlong when LF arrives. The accepted contract defines overlong as the 15th pre-CRLF byte, with 14 pre-CRLF bytes allowed.

## Passing Evidence

### Contract scope and MMIO

The implementation stays within the accepted UART RX slice:

- UART TX data/status remain at `0x40001000 + 0x00` and `0x40001000 + 0x04`.
- RX MMIO is implemented at `0x08` RXDATA, `0x0C` RXSTATUS, and `0x10` RXCONTROL.
- Control-register offsets through `0x80` are not moved.
- Firmware command grammar is limited to `!N\r\n` for accepted commands.
- `Q` and `X` telemetry are appended after `P` in `I/S/R/V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E/G/H/J/L/N/P/Q/X` order.
- Source and evidence do not show SDRAM, fourth voice, richer physics, exact-48k PLL, larger CPU/ISA, hardware dispatcher, voice stealing, per-note state, per-voice parameter banks, UI, sample playback, or CPU audio-loop work.

### Independent capture checks

I independently parsed the submitted hardware UART captures using the existing telemetry parser and direct expected-value checks.

No-command capture `reports/phase1c_uart_rx_command_ingress_uart_capture.txt`:

- PASS, 194 frames parsed
- latest `G=6`, `H=2`, `J/L/N=2`, `T/U/O=2`, `P=0`, `K=0`, `Q=0`, `X=0`

Commanded capture `reports/phase1c_uart_rx_command_ingress_command_uart_capture.txt`:

- PASS, 266 frames parsed
- latest `G=12`, `H=2`, `J/L/N=4`, `T/U/O=4`, `P=0`, `K=0`, `Q=6`, `X=0`
- no `!N` command bytes found in the telemetry capture

Malformed capture `reports/phase1c_uart_rx_command_ingress_malformed_uart_capture.txt`:

- PASS, 266 frames parsed
- latest `G=6`, `H=2`, `J/L/N=2`, `T/U/O=2`, `P=0`, `K=0`, `Q=0`, `X=00030003`
- malformed input byte strings were absent from device telemetry

Parser selftest:

```powershell
python scripts\test_phase1c_uart_telemetry.py -v
```

Result: PASS, 10 tests.

### Simulation evidence reviewed

Submitted ModelSim logs report PASS:

- `reports/phase1c_uart_rx_command_ingress_msim_compile.log`: 0 errors, 0 warnings
- `reports/phase1c_uart_rx_command_ingress_msim_no_command.log`: `TB_UART_RX_PASS mode=0`, `G=6`, `Q=0`, `X=0`
- `reports/phase1c_uart_rx_command_ingress_msim_commanded.log`: `TB_UART_RX_PASS mode=1`, `G=12`, `Q=6`, `X=0`
- `reports/phase1c_uart_rx_command_ingress_msim_malformed.log`: `TB_UART_RX_PASS mode=2`, `G=6`, `Q=0`, `X=00030003`
- `reports/phase1c_uart_rx_command_ingress_msim_backpressure.log`: `TB_UART_RX_BACKPRESSURE_PASS rdata=00000007 status_word=0033`
- voice and NACK regression logs report PASS

### Resource, timing, ROM, and bitstream evidence

Quartus full compile:

- `reports/phase1c_uart_rx_command_ingress_quartus_compile.log`: full compilation successful, 0 errors, 14 warnings
- LEs: `7,963 / 10,320`, within `8,200`
- M9Ks: `14 / 46`
- memory bits: `80,896 / 423,936`
- DSP9: `6 / 46`
- PLLs: `1 / 2`
- UART RX FIFO fitted as logic under `phase0_uart_mmio`, 0 memory bits and 0 M9Ks in that hierarchy

TimeQuest:

- `quartus/phase0/output_files/piano_phase0_top.sta.summary`
- slow-85C `sys_clk_50m` setup slack `+2.438 ns`, TNS `0.000`
- slow-85C `sys_clk_50m` hold slack `+0.406 ns`, TNS `0.000`
- setup and hold fully constrained in the compile log

Firmware:

- `fw/phase0/build/phase0.mem`: 500 words, within 1024
- the implementation report references `reports/phase1c_uart_rx_command_ingress_fw_build.log`, but that file was not present; ROM size was independently checked from current firmware build output

Bitstream/programming:

- SOF SHA-256 independently verified as `E53FC492C4720433AD301BBD0E328F950D16C22AD20D524191F220D9B50CB1D3`
- programmer logs show checksum `0x005EF7CF` and successful programming on USB-Blaster

Audio:

- `reports/phase1c_uart_rx_command_ingress_audio_analysis.txt` reports duration `11.99 s`, peak `-13.140396 dB`, RMS `-42.553396 dB`, sample min/max `-7218 / 2427`
- hardware UART telemetry reports `K=0`

## Blocking Finding

### Maximum-length pre-CRLF line is classified as overlong

Accepted contract rule:

- maximum command line is exactly 16 total bytes including CRLF
- at most 14 bytes may appear before CRLF
- the 15th pre-CRLF byte is overlong

Firmware source:

- `fw/phase0/phase0_main.c:20` defines `PHASE0_RX_MAX_LINE_BYTES 16u`
- `fw/phase0/phase0_main.c:376` rejects when `phase0_rx_line_len >= PHASE0_RX_MAX_LINE_BYTES - 2u` and current byte is not CR
- `fw/phase0/phase0_main.c:381` rejects when `phase0_rx_line_len >= PHASE0_RX_MAX_LINE_BYTES - 1u` and current byte is not LF

This rejects the LF of a 14-byte pre-CRLF line as overlong. A direct mirror of the firmware conditions produced:

```text
valid_!N: pre_crlf=2 total=4 errors=[0]
unsupported_11_pre: pre_crlf=11 total=13 errors=[7]
max_14_pre_should_not_overlong: pre_crlf=14 total=16 errors=[3]
overlong_15_pre: pre_crlf=15 total=17 errors=[3]
```

The 14-byte pre-CRLF case should not produce error code `3`. Depending on content, it should be processed as malformed, unknown opcode, or unsupported argument. This is an exact grammar/error contract failure, even though the tested 15-byte overlong case passes.

## Residual Risks

- The supplied backpressure test proves valid/full/overrun status, but does not directly read back all FIFO contents to prove oldest-byte preservation after overflow. Source logic appears intended to drop newest bytes, but this could use a stronger test in the fix.
- Hardware evidence covers the required no-command, six-command, and malformed smoke cases, but not the 14-byte boundary case above.
- The referenced firmware build log path is missing, although current build artifacts independently show the ROM bound is met.

## Recommendation

Do not accept the implementation yet.

Request a narrow fix to the firmware parser boundary check and tests:

1. Ensure 14 pre-CRLF bytes plus CRLF is not classified as overlong.
2. Ensure the 15th pre-CRLF byte is classified as overlong exactly once.
3. Add simulation and, if practical, hardware/parser evidence for the 14-byte boundary and 15-byte overlong cases.
4. Re-run the existing no-command, six-command, malformed, parser, Quartus, and UART/audio smoke checks after the fix.
