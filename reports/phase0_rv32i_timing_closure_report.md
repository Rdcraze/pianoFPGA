# Phase 0 RV32I Timing Closure Report

Date: `2026-04-23`
Task: `task-f925ff80`

## Goal

Close the integrated RV32I slow-`85C` `sys_clk_50m` setup gap without changing the validated Phase 0 firmware-visible behavior.

## Baseline

At the start of this task, the integrated RV32I Phase 0 build was functionally correct but missed the internal fabric target:

- slow-`85C` `sys_clk_50m` setup slack: `-0.881 ns`
- slow-`85C` `sys_clk_50m` setup TNS: `-20.190`
- `i2c_clk` setup slack: `17.766 ns`
- `audio_bclk` setup slack: `328.040 ns`

Focused TimeQuest inspection showed the dominant failing family inside `rtl/control/phase0_rv32i_core.v`, centered on the old register-file writeback edge from decoded instruction / execute logic directly into `regs[*]`.

## RTL Change

The implemented closure change is intentionally narrow and local to `rtl/control/phase0_rv32i_core.v`.

- non-load instructions now capture `next_pc`, destination register, and writeback data into staged `wb_*` registers during `STATE_EXEC`
- load instructions capture their metadata in `STATE_EXEC`, then capture resolved load data into the same staged `wb_*` registers during `STATE_LOAD`
- the architectural register file is now written only in `STATE_WRITEBACK`
- the asynchronous register-file clear now uses explicit assignments instead of a procedural loop variable, removing the transient Quartus latch warning that appeared during closure work

This preserves the tiny multi-cycle core contract while moving the critical edge off the direct `instr_reg/execute -> regs[*]` path.

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
- result: full compile success, `0` errors, `8` warnings, regenerated `quartus/phase0/output_files/piano_phase0_top.sof`

## Timing Result

Latest TimeQuest summary from `quartus/phase0/output_files/piano_phase0_top.sta.summary`:

- slow-`85C` setup slack:
  - `sys_clk_50m`: `1.120 ns`
  - `i2c_clk`: `17.868 ns`
  - `audio_bclk`: `328.252 ns`
- slow-`85C` hold slack:
  - `sys_clk_50m`: `0.433 ns`
  - `i2c_clk`: `0.444 ns`
  - `audio_bclk`: `0.453 ns`
- slow-`85C` setup TNS:
  - `sys_clk_50m`: `0.000`
  - `i2c_clk`: `0.000`
  - `audio_bclk`: `0.000`

The integrated RV32I `sys_clk_50m` gap is therefore closed.

Focused post-fit timing now shows the worst `sys_clk_50m` path inside the staged writeback datapath rather than the old register-file write edge:

- from: `phase0_rv32i_core|regs[26][1]`
- to: `phase0_rv32i_core|wb_writeback_data_q[29]`
- data delay: `19.252 ns`
- slack: `1.120 ns`

The previous `instr_reg[*] -> regs[*]` family is no longer the limiting edge.

## Resource Summary

Latest fitted resource summary from `quartus/phase0/output_files/piano_phase0_top.fit.summary`:

- `4809 / 10320` logic elements
- `1520` registers
- `262144 / 423936` memory bits
- `1 / 2` PLLs
- `2 / 46` embedded `9-bit` multipliers

## Remaining Caveats

- TimeQuest still reports the design is not fully constrained for setup/hold because Phase 0 intentionally omits board-level I/O delays for off-chip `WM8978` and `UART1`
- Quartus still reports the known non-closure warnings:
  - unused playback-only `audio_adcdat`
  - PLL output compensation / routing caveats for exported `audio_mclk`
- no functional regression was observed in firmware, happy-path codec simulation, or targeted-NACK simulation after the timing-closure change
