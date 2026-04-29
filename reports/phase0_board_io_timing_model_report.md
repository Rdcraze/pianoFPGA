# Phase 0 Board I/O Timing Model Report

Date: `2026-04-24`
Task: `task-241de457`

## Goal

Refine the Phase 0 Quartus timing package from internal clock-domain closure to board-I/O timing signoff quality where the local board/manual/datasheet collateral actually supports it.

## Inputs

Primary source for the board-facing timing model:

- `reports/phase0_board_io_timing_requirements.md`

That report provides defensible device-side timing for the WM8978 audio boundary and 2-wire control bus, while also making clear that local collateral does not include PCB trace-delay/skew numbers or a CH340 UART timing aperture.

## SDC Change

Updated file:

- `quartus/phase0/piano_phase0_top.sdc`

The final constraint split is:

### Explicitly timed

- `sys_clk_50m`
  - `20.000 ns`
- `i2c_clk`
  - generated internal clock at `1 MHz`
- `audio_bclk`
  - external codec-master clock at `1.500 MHz` (`666.667 ns`) for the current direct-`MCLK` Phase 0 contract
- `audio_lrc`
  - `set_input_delay` relative to `audio_bclk` falling edge
  - max `10.000 ns`
  - min `0.000 ns` as an explicit assumption
- `audio_adcdat`
  - same timing model as `audio_lrc`
  - max `10.000 ns`
  - min `0.000 ns` as an explicit assumption
- `audio_dacdat`
  - `set_output_delay` relative to `audio_bclk` rising edge
  - setup requirement modeled as `10.000 ns`
  - hold requirement modeled as `10.000 ns`

### Explicitly excluded

- `audio_mclk`
  - forwarded codec clock output, not a data interface with a defensible local output-delay aperture
- `i2c_scl`
  - open-drain 2-wire protocol output
- `i2c_sda`
  - bidirectional open-drain 2-wire protocol signal
- `uart1_rx`
  - asynchronous serial debug input
- `uart1_tx`
  - asynchronous serial debug output
- `sys_rst_n`
  - asynchronous board reset into `phase0_reset_sync`

## Assumptions

The final board-I/O model uses two assumptions that are real assumptions rather than sourced board numbers:

1. `audio_lrc` / `audio_adcdat` minimum arrival is modeled as `0 ns`.
   The WM8978 timing table in the local collateral gives a max `10 ns` propagation delay from `BCLK` falling edge, but no min value.
2. No board trace-delay or skew number is applied at the WM8978 boundary.
   Local manuals, schematic, examples, and datasheets do not provide a defendable PCB number.

These assumptions are intentionally narrower than the earlier package-wide "board I/O not modeled" state, but they are not full PCB signoff.

## Validation

Firmware:

- `powershell -ExecutionPolicy Bypass -File E:\projects\piano-agents\fw\phase0\build.ps1`
- result: success

ModelSim:

- `vlog` with Quartus simulation libraries and the full Phase 0 RTL passed with `0` errors and `0` warnings
- happy-path:
  - `vsim -voptargs=+acc -c work.piano_phase0_top_tb -do "run 12 ms; quit -f"`
  - result: `TB_PASS fabric_status=8019077f soc_status=037f write_count=18 dac_toggle_count=1668 uart_capture_count=36`
- targeted-NACK path:
  - `vsim -voptargs=+acc -c work.piano_phase0_top_nack_tb -do "run 12 ms; quit -f"`
  - result: `TB_NACK_PASS fabric_status=6019073f soc_status=033f nack_count=1 stop_count=1`

Quartus:

- `powershell -ExecutionPolicy Bypass -File E:\projects\piano-agents\quartus\phase0\build.ps1 -Stage compile`
- result: full compile success, `0` errors, `8` warnings

## Final Timing Result

Latest TimeQuest summary from `quartus/phase0/output_files/piano_phase0_top.sta.summary`:

- slow-`85C` setup slack:
  - `sys_clk_50m`: `0.357 ns`
  - `i2c_clk`: `17.508 ns`
  - `audio_bclk`: `316.385 ns`
- slow-`85C` hold slack:
  - `sys_clk_50m`: `0.433 ns`
  - `i2c_clk`: `0.403 ns`
  - `audio_bclk`: `0.453 ns`
- slow-`85C` setup TNS:
  - `sys_clk_50m`: `0.000`
  - `i2c_clk`: `0.000`
  - `audio_bclk`: `0.000`

TimeQuest `report_ucp` now reports:

- fully constrained for setup requirements
- fully constrained for hold requirements
- unconstrained setup paths: `0`
- unconstrained hold paths: `0`

## Warning Delta

The first board-I/O pass temporarily introduced a new TimeQuest warning by trying to model `audio_mclk` as an explicit generated output clock. That warning was removed in the final pass by converting `audio_mclk` to an explicit forwarded-clock exclusion.

The final compile does not introduce new TimeQuest warnings.

Remaining Quartus warnings are the known non-signoff items:

- unused `data_a` in the auto-generated ROM wrapper
- unused `clkena` / `extclkena` in the small PLL wrapper
- playback-only unused `audio_adcdat`
- incomplete I/O assignments report
- fitter caveats about forwarding `audio_mclk` off-chip from the PLL output

## Resource Summary

Latest fitted resource summary from `quartus/phase0/output_files/piano_phase0_top.fit.summary`:

- `4796 / 10320` logic elements
- `1520` registers
- `262144 / 423936` memory bits
- `1 / 2` PLLs
- `2 / 46` embedded `9-bit` multipliers

## Residual Caveat

Phase 0 is now in a materially better state than before:

- the defendable WM8978 audio data boundary is timed
- the package is fully constrained in TimeQuest
- the remaining off-chip interfaces are excluded intentionally rather than left as accidental unconstrained gaps

But this is still not final board signoff in the strongest possible sense, because the local collateral still does not provide measured PCB delay/skew numbers or a point-to-point timing aperture for:

- `audio_mclk`
- `i2c_scl`
- `i2c_sda`
- `uart1_rx`
- `uart1_tx`
- `sys_rst_n`
