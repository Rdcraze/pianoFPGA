# Phase 1C UART RX Parser Boundary Fix Validation

Verifier: Codex verifier agent `e9722d83-b000-4165-a5a7-36b758c2e8d8`  
Task: `task-c54a3f54`  
Implementation artifact: `6a528047-15bd-44a5-87d4-1de1f663dee2`  
Fix report: `reports/phase1c_uart_rx_command_ingress_boundary_fix_report.md`

## Verdict

FAIL, because the required audio smoke evidence is anomalous and does not resemble the accepted three-voice baseline.

The parser boundary fix itself validates cleanly. The 14-byte pre-CRLF case now follows normal malformed classification, the 15th pre-CRLF byte is overlong exactly once, and no-command/six-command/malformed UART profiles remain correct. Resource, timing, ROM, and bitstream gates remain in bounds. However, the boundary-fix audio capture is a steady low-amplitude waveform with a different dominant frequency and envelope shape from the accepted three-voice captures, so I do not consider the audio smoke evidence acceptable for final promotion.

## Parser Boundary Result

PASS.

Source review of `fw/phase0/phase0_main.c` shows:

- `PHASE0_RX_MAX_LINE_BYTES` remains `16`.
- `phase0_rx_process_byte()` now detects LF following a buffered CR and allows that LF to terminate the line at the 16-byte total boundary.
- `phase0_rx_enter_discard()` records the overlong error and enters discard mode without flushing the hardware FIFO from firmware, preventing the discarded CRLF from being reprocessed as a second line.

Independent mirror check of the firmware conditions:

```text
valid_!N: errors=[0]
unsupported_11_pre: errors=[7]
max_14_pre_expected_malformed: errors=[1]
overlong_15_pre_once: errors=[3]
combined_boundary_sequence: errors=[2, 7, 1, 3]
```

This matches the contract: 14 pre-CRLF bytes are not overlong, 15 pre-CRLF bytes are overlong exactly once, and the combined malformed sequence ends with `X=00030004`.

## Simulation And UART Evidence

PASS.

ModelSim:

- `reports/phase1c_uart_rx_command_ingress_boundary_msim_malformed.log`: `TB_UART_RX_PASS`, `expected_X=00030004`
- `reports/phase1c_uart_rx_command_ingress_boundary_msim_no_command.log`: no-command pass, `G=6`, `Q=0`, `X=0`
- `reports/phase1c_uart_rx_command_ingress_boundary_msim_commanded.log`: commanded pass, `G=12`, `Q=6`, `X=0`
- `reports/phase1c_uart_rx_command_ingress_boundary_msim_backpressure.log`: `TB_UART_RX_BACKPRESSURE_PASS`, `preserve_oldest=1`
- NACK regression and parser selftests report PASS

Independent UART capture checks:

- No-command capture: 170 frames, latest `G=6`, `H=2`, `J/L/N=2`, `T/U/O=2`, `P=0`, `K=0`, `Q=0`, `X=0`
- Commanded capture: 266 frames, latest `G=12`, `H=2`, `J/L/N=4`, `T/U/O=4`, `P=0`, `K=0`, `Q=6`, `X=0`; no `!N` echo bytes found
- Malformed capture: 386 frames, latest `G=6`, `H=2`, `J/L/N=2`, `T/U/O=2`, `P=0`, `K=0`, `Q=0`, `X=00030004`; malformed input strings absent from telemetry

## Resource, Timing, ROM, Bitstream

PASS.

- Quartus full compile: PASS, 0 errors, 14 warnings
- LEs: `7,963 / 10,320`, within `8,200`
- M9Ks: `14 / 46`
- Memory bits: `80,896 / 423,936`
- DSP9: `6 / 46`
- PLLs: `1 / 2`
- Firmware ROM: `507 / 1024`
- Slow-85C `sys_clk_50m` setup slack: `+2.438 ns`, TNS `0.000`
- Slow-85C `sys_clk_50m` hold slack: `+0.406 ns`, TNS `0.000`
- Setup and hold fully constrained
- SOF SHA-256: `CAB259BC697ABB5F76AD48120AE4CD65AB1FD4311FC9AEA59F620868E3F3D7F5`
- Programmer checksum in report: `0x005F102E`

## Scope Check

PASS.

The fix is limited to firmware parser boundary handling, the RX testbench, and generated evidence. I found no scope drift into SDRAM, fourth voice, richer physics, exact-48k PLL work, larger CPU/ISA, hardware dispatcher, voice stealing, per-note state, per-voice parameter banks, UI, sample playback, or audio-loop CPU work.

## Audio Waveform Finding

FAIL for audio-smoke evidence quality.

The submitted boundary-fix audio capture has no clipped samples, no flat clipping plateau, near-zero DC offset, and no internal silent/dropout gaps after onset. Those are good signs. But the waveform does not resemble the accepted three-voice baseline:

| Capture | RMS | Peak | Dominant peak | Envelope shape |
| --- | ---: | ---: | ---: | --- |
| accepted round-robin verifier capture | `-44.05 dBFS` | `-13.12 dBFS` | `~436 Hz` | pluck-like, uneven decay/envelope |
| previous UART RX capture | `-42.55 dBFS` | `-13.14 dBFS` | `~436 Hz` | broadly similar to accepted baseline |
| boundary-fix capture | `-39.19 dBFS` | `-31.82 dBFS` | `~250 Hz` | nearly constant low-amplitude envelope |

Additional boundary-fix observations:

- min/max sample: `-838 / +840`
- DC offset: about `-0.16` samples, not concerning
- positive/negative peak asymmetry: about `0.24%`, not concerning
- no clipped samples at full scale
- 20 ms envelope had no internal silent gaps, but after initial onset it stayed near constant level for the whole capture
- normalized 100 ms envelope correlation with the accepted round-robin capture was only `0.136`

Per-second RMS for the boundary capture stayed almost flat around `-39.1 dBFS` from 1 s through 11 s, while the accepted capture shows a much more uneven pluck/decay profile and a strong peak around the main note event. This looks like an audio-capture/setup anomaly or an audio behavior regression that the current UART counters do not expose. Either way, the audio smoke evidence should not be accepted as proving baseline audio continuity.

## Git Tracking

At the user's request point, `git status --short --untracked-files=normal` was clean. This verifier task added only this validation report.

## Recommendation

Do not accept the boundary fix for final promotion yet.

Request a narrow follow-up that preserves the parser fix and re-runs audio smoke with a waveform check against the accepted three-voice baseline. The follow-up should either produce a baseline-like capture or explain and correct the capture-path anomaly. Existing parser, UART, simulation, Quartus, ROM, and timing evidence can be reused if source and bitstream identity remain unchanged, but the audio smoke should be repeated and compared explicitly.
