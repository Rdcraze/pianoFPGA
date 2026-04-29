# Phase 0 RV32I Control-Plane Report

Task: `task-9d00cc2f`  
Date: `2026-04-23`

## Scope

Replace the interim Phase 0 stub control path with the smallest useful real RV32I firmware-owned subsystem, while preserving the already documented ROM/RAM/MMIO contract.

## Implemented

- Replaced the live top-level stub path with:
  - `rtl/control/phase0_rv32i_core.v`
  - `rtl/control/phase0_boot_rom.v`
  - `rtl/control/phase0_data_ram.v`
  - `rtl/control/phase0_rv32i_soc.v`
  - `rtl/peripherals/phase0_uart_mmio.v`
- Updated `rtl/top/piano_phase0_top.v` to instantiate `phase0_rv32i_soc` instead of `phase0_soc_stub`
- Kept the documented Phase 0 address map intact:
  - ROM `0x0000_0000`
  - RAM `0x0001_0000`
  - control block `0x4000_0000`
  - UART aperture `0x4000_1000`
- Updated `fw/phase0/build.ps1` so the firmware build emits `phase0.mif`, repo-root `phase0_fw.mif`, and `quartus/phase0/phase0_fw.mif`
- Updated `quartus/phase0/build.ps1` so Quartus always rebuilds the firmware image before FPGA stages

## Design Notes

- The integrated CPU is intentionally multi-cycle and throughput-light:
  - explicit fetch request/capture handling for the synchronous boot ROM
  - explicit load stage for the synchronous data RAM
  - explicit commit staging for non-load instructions
- This is deliberate Phase 0 engineering rather than a performance target. The goal is to execute `fw/phase0` correctly and predictably on-chip, not to produce a general-purpose SoC.
- ModelSim currently expects `phase0_fw.mif` to be visible from the simulator working directory. The validated flow runs simulation from the repo root.

## Verification

- Firmware:
  - `powershell -ExecutionPolicy Bypass -File fw/phase0/build.ps1`
  - passed and regenerated ELF/bin/disassembly/map plus `phase0_fw.mif`
- ModelSim compile:
  - `vlog` with Quartus `220model.v` and `altera_mf.v`
  - passed with `0` errors and `0` warnings
- ModelSim happy path:
  - `vsim -voptargs=+acc -c work.piano_phase0_top_tb -do "run 12 ms; quit -f"`
  - passed with `TB_PASS fabric_status=8019077f soc_status=037f write_count=18 dac_toggle_count=1668 uart_capture_count=36`
- ModelSim targeted NACK path:
  - `vsim -voptargs=+acc -c work.piano_phase0_top_nack_tb -do "run 12 ms; quit -f"`
  - passed with `TB_NACK_PASS fabric_status=6019073f soc_status=033f nack_count=1 stop_count=1`
- Quartus full compile:
  - `powershell -ExecutionPolicy Bypass -File quartus/phase0/build.ps1 -Stage compile`
  - passed and regenerated `quartus/phase0/output_files/piano_phase0_top.sof`

## Current FPGA Result

- Fitted resource summary:
  - `4696 / 10320` logic elements
  - `1520` registers
  - `262144 / 423936` memory bits
  - `1 / 2` PLLs
  - `2 / 46` DSP9s
- TimeQuest summary:
  - slow-`85C` setup slack:
    - `sys_clk_50m`: `-0.881 ns`
    - `i2c_clk`: `17.766 ns`
    - `audio_bclk`: `328.040 ns`
  - slow-`85C` hold slack:
    - `sys_clk_50m`: `0.433 ns`
    - `i2c_clk`: `0.453 ns`
    - `audio_bclk`: `0.454 ns`

## Remaining Risk

- Functional integration is complete for Phase 0 bring-up.
- The remaining open issue is slow-`85C` timing closure in `phase0_rv32i_core.v`.
- The dominant failing setup paths are inside the RV32I register-file writeback path, especially from `instr_reg[*]` into destination `regs[*]`.
- Board-level I/O delay constraints are still intentionally excluded in this Phase 0 package.
