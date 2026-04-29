# Phase 0 Board-I/O Timing Validation

Date: `2026-04-24`  
Task: `task-9d4d5c1f`

## Findings

- No blocking verifier findings. The updated Phase 0 SDC and regenerated TimeQuest reports pass for the current board-I/O timing model scope.
- TimeQuest now reports zero unconstrained clocks, input ports, input-port paths, output ports, and output-port paths for setup and hold. It also emits `Design is fully constrained for setup requirements` and `Design is fully constrained for hold requirements`.
- Exact slow-85C internal/model-clock timing remains positive, but `sys_clk_50m` setup margin is tighter than the prior internal-only closure pass: `+0.357 ns` slack, `0.000 ns` TNS. This is still a pass.
- The new WM8978 audio I/O timing paths are present and positive. Worst slow-85C `audio_bclk` setup is the `audio_dacdat` output path at `+316.385 ns`; worst `audio_lrc` input setup path observed is `+320.666 ns`. Worst slow-85C `audio_bclk` hold is `+0.453 ns`, with `audio_dacdat` output hold at `+0.454 ns` and `audio_lrc` internal-capture hold paths starting at `+1.345 ns`.
- `audio_adcdat` is constrained in the SDC but remains playback-only unused in RTL, so it has no meaningful endpoint path. Quartus still reports `No output dependent on input pin "audio_adcdat"`; this is an intentional residual warning, not a timing miss.
- Scope caveat: this is not full PCB-level timing signoff. `audio_mclk`, `i2c_scl`, `i2c_sda`, `uart1_rx`, `uart1_tx`, and `sys_rst_n` are explicitly false-pathed with stated justifications because local collateral lacks defensible external timing apertures or PCB skew numbers.

Verdict: PASS for the current defensible Phase 0 board-I/O timing model, with residual exclusions explicitly documented.

## SDC And UCP Check

Reviewed `quartus/phase0/piano_phase0_top.sdc` and confirmed:

- `sys_clk_50m` is constrained at `20.000 ns`.
- `i2c_clk` is generated from `sys_clk_50m` with divide-by-50.
- PLL clocks are derived through `derive_pll_clocks`.
- `audio_bclk` is modeled as an external `666.667 ns` clock.
- `audio_lrc` and `audio_adcdat` have `set_input_delay` max `10.000 ns` and min `0.000 ns` relative to `audio_bclk` falling edge.
- `audio_dacdat` has `set_output_delay` max `10.000 ns` and min `-10.000 ns` relative to `audio_bclk`.
- `audio_mclk`, I2C, UART, and async reset are explicit timing exclusions rather than accidental unconstrained gaps.

TimeQuest unconstrained-path table after verifier rerun:

| Property | Setup | Hold |
| --- | ---: | ---: |
| Illegal clocks | `0` | `0` |
| Unconstrained clocks | `0` | `0` |
| Unconstrained input ports | `0` | `0` |
| Unconstrained input port paths | `0` | `0` |
| Unconstrained output ports | `0` | `0` |
| Unconstrained output port paths | `0` | `0` |

## Timing Evidence

Verifier reran:

- ModelSim compile and happy/NACK simulations.
- `quartus/phase0/build.ps1 -Stage compile`.
- Live programming and UART/audio smoke check on the regenerated SOF.

Quartus full compilation completed with `0 errors, 8 warnings`. TimeQuest completed with `0 errors, 0 warnings`.

Regenerated SOF:

- Before verifier compile: `2026-04-24T08:41:44+08:00`.
- After verifier compile: `2026-04-24T08:57:48+08:00`.
- Programmed checksum: `0x003F73CC`.

Slow 1200 mV 85C setup:

| Clock | Slack | TNS |
| --- | ---: | ---: |
| `sys_clk_50m` | `+0.357 ns` | `0.000 ns` |
| `i2c_clk` | `+17.508 ns` | `0.000 ns` |
| `audio_bclk` | `+316.385 ns` | `0.000 ns` |

Slow 1200 mV 85C hold:

| Clock | Slack | TNS |
| --- | ---: | ---: |
| `i2c_clk` | `+0.403 ns` | `0.000 ns` |
| `sys_clk_50m` | `+0.433 ns` | `0.000 ns` |
| `audio_bclk` | `+0.453 ns` | `0.000 ns` |

Representative slow-85C paths:

| Path | Slack | Notes |
| --- | ---: | --- |
| `instr_reg[17] -> wb_writeback_data_q[9]` | `+0.357 ns` | Current worst `sys_clk_50m` setup path. |
| `audio_dacdat reg -> audio_dacdat port` | `+316.385 ns` | Worst `audio_bclk` setup path and new output-delay path. |
| `audio_lrc port -> frame_sample[*]` | `+320.666 ns` | New input-delay path. |
| `audio_dacdat reg -> audio_dacdat reg` | `+0.454 ns` | Representative `audio_dacdat` hold path. |
| `audio_lrc_d1 -> bit_count[*]` | `+1.345 ns` | Representative `audio_lrc` capture hold path. |

## Functional Evidence

ModelSim:

- Compile: `0 errors, 0 warnings`.
- Happy path: `TB_PASS fabric_status=8019077f soc_status=037f write_count=18 dac_toggle_count=1668 uart_capture_count=36`.
- NACK path: `TB_NACK_PASS fabric_status=6019073f soc_status=033f nack_count=1 stop_count=1`.

Live board:

- JTAG cable visible as `USB-Blaster [USB-0]`.
- JTAG ID: `0x020F10DD`.
- Programmer configured one `EP4CE10F17` device successfully.
- UART on `COM4` at `115200 8N1` after programming:

```text
I=50303031
S=8019073F
R=8019077F
R=8019077F
R=8019077F
R=8019077F
R=8019077F
```

Audio smoke:

- External Realtek capture confirms the continuous default tone remains present on both channels.
- L channel: `440.001853 Hz`, RMS CV `0.0111%`.
- R channel: `440.001856 Hz`, RMS CV `0.0146%`.
- L/R amplitude imbalance remains about `9.30 dB`, consistent with the already-known wiring/capture issue rather than a timing-model regression.

## Residual Caveats

- `audio_mclk` is a forwarded codec clock output and remains excluded from data-style board I/O timing because no local board-skew or codec input-aperture value is available.
- I2C pins are excluded as open-drain protocol pins; the RTL controller remains functionally inside the WM8978 526 kHz maximum at the documented 250 kHz target, but SDC does not prove bus rise/fall on real PCB loading.
- UART pins are asynchronous serial debug I/O, so correctness is covered by baud tolerance and live UART smoke evidence rather than FPGA-to-external-clock setup/hold constraints.
- `sys_rst_n` is asynchronous reset into a synchronizer and is intentionally false-pathed.
- No local collateral provides measured PCB trace delay/skew, so the WM8978 audio data timing is device-aperture timing plus explicit assumptions, not final measured PCB timing signoff.

## Artifacts

- `reports/phase0_board_io_timing_model_report.md`
- `reports/phase0_board_io_timing_requirements.md`
- `reports/phase0_board_io_timing_msim_compile.log`
- `reports/phase0_board_io_timing_msim_happy.log`
- `reports/phase0_board_io_timing_msim_nack.log`
- `reports/phase0_board_io_timing_quartus_compile.log`
- `reports/phase0_board_io_timing_programmer.log`
- `reports/phase0_board_io_timing_uart.txt`
- `reports/phase0_board_io_timing_capture_external.wav`
- `reports/phase0_board_io_timing_audio_analysis_external.json`
- `reports/phase0_board_io_timing_audio_external.png`
