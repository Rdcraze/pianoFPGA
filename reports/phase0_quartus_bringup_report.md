# Phase 0 Quartus Bring-Up Report

Date: `2026-04-24`

Update for `task-241de457`:

- the packaged Phase 0 timing collateral now includes a board-facing I/O model where local collateral is defensible, instead of stopping at internal clock-domain closure
- the updated `quartus/phase0/piano_phase0_top.sdc` now adds:
  - source-synchronous WM8978 input timing for `audio_lrc` and `audio_adcdat` at `10 ns` max from `audio_bclk` falling edge, with explicit `0 ns` min-arrival assumptions because no local min propagation / board skew number exists
  - source-synchronous WM8978 output timing for `audio_dacdat` at `10 ns` setup and `10 ns` hold around `audio_bclk` rising edge
  - explicit false-path exclusions for `audio_mclk` as a forwarded clock pin, `sys_rst_n` as asynchronous reset, `uart1_rx` / `uart1_tx` as asynchronous serial debug, and `i2c_scl` / `i2c_sda` as open-drain 2-wire control without defensible board-delay numbers
- revalidation after the final SDC pass is clean:
  - firmware build succeeded and regenerated `phase0_fw.mif`
  - ModelSim happy-path passed with `TB_PASS fabric_status=8019077f soc_status=037f write_count=18 dac_toggle_count=1668 uart_capture_count=36`
  - ModelSim targeted-NACK path passed with `TB_NACK_PASS fabric_status=6019073f soc_status=033f nack_count=1 stop_count=1`
  - Quartus full compile succeeded with `0` errors and `8` warnings and regenerated `output_files/piano_phase0_top.sof`
- current fitted resource summary from the board-I/O-modeled build:
  - `4796 / 10320` logic elements
  - `1520` registers
  - `262144 / 423936` memory bits
  - `1 / 2` PLLs
  - `2 / 46` embedded `9-bit` multipliers
- current timing summary from `output_files/piano_phase0_top.sta.summary`:
  - slow-`85C` setup slack:
    - `sys_clk_50m`: `0.357 ns`
    - `i2c_clk`: `17.508 ns`
    - `audio_bclk`: `316.385 ns`
  - slow-`85C` hold slack:
    - `sys_clk_50m`: `0.433 ns`
    - `i2c_clk`: `0.403 ns`
    - `audio_bclk`: `0.453 ns`
  - slow-`85C` setup TNS is `0.000` for all three modeled clocks
- TimeQuest now reports the design fully constrained for setup and hold; `report_ucp` shows `0` unconstrained setup paths and `0` unconstrained hold paths after the explicit exclusions are applied
- the remaining compile warnings are not new timing-model defects:
  - synthesis-only unused `data_a`, `clkena`, and `extclkena` warnings from vendor/generated RAM/PLL wrappers
  - the expected playback-only `audio_adcdat` unused-input warning
  - the expected PLL/output-pin caveats for forwarding `audio_mclk` off-chip
- the remaining board-signoff caveat is precise:
  - WM8978 audio data timing is now modeled at the FPGA boundary
  - `audio_mclk`, `i2c_*`, `uart1_*`, and `sys_rst_n` are explicit exclusions because the local manuals/schematic/datasheet set does not provide a defendable point-to-point timing aperture or board-delay number for them

Update for `task-f925ff80`:

- the integrated RV32I build is now timing-closed at the modeled internal `50 MHz` fabric target
- the closure change is intentionally narrow and local to `rtl/control/phase0_rv32i_core.v`:
  - execute-stage results now land in staged `wb_*` registers
  - load results also land in the same staged `wb_*` registers
  - the architectural register file is written only in `STATE_WRITEBACK`, which removes the old direct mixed execute/load fan-in from the register-file write edge
  - the asynchronous register-file reset is now written explicitly instead of via a procedural loop variable, which removes the transient Quartus latch warning seen during closure work
- revalidation after the final core change is clean:
  - firmware build succeeded and regenerated `phase0_fw.mif`
  - ModelSim happy-path passed with `TB_PASS fabric_status=8019077f soc_status=037f write_count=18 dac_toggle_count=1668 uart_capture_count=36`
  - ModelSim targeted-NACK path passed with `TB_NACK_PASS fabric_status=6019073f soc_status=033f nack_count=1 stop_count=1`
  - Quartus full compile succeeded and regenerated `output_files/piano_phase0_top.sof`
- current fitted resource summary from the timing-closed integrated RV32I build:
  - `4809 / 10320` logic elements
  - `1520` registers
  - `262144 / 423936` memory bits
  - `1 / 2` PLLs
  - `2 / 46` embedded `9-bit` multipliers
- current timing summary from `output_files/piano_phase0_top.sta.summary`:
  - slow-`85C` setup slack:
    - `sys_clk_50m`: `1.120 ns`
    - `i2c_clk`: `17.868 ns`
    - `audio_bclk`: `328.252 ns`
  - slow-`85C` hold slack:
    - `sys_clk_50m`: `0.433 ns`
    - `i2c_clk`: `0.444 ns`
    - `audio_bclk`: `0.453 ns`
  - slow-`85C` setup TNS is `0.000` for all three modeled clocks
- focused post-fit timing confirms the intended structural change:
  - the former failing `instr_reg[*] -> regs[*]` register-file writeback family is no longer the worst edge
  - the new slow-`85C` worst `sys_clk_50m` path is inside the staged writeback datapath (`regs[26][1] -> wb_writeback_data_q[29]`) with `19.252 ns` data delay and `1.120 ns` slack
- the remaining Quartus caveats at that handoff point were unchanged and understood:
  - playback-only `audio_adcdat` was still unused
  - PLL warnings remained about exporting `audio_mclk` off-chip through non-zero-delay routing
  - board-level I/O timing had not yet been modeled or explicitly excluded coherently; that was later tightened by `task-241de457`

Update for `task-9d00cc2f`:

- the packaged Phase 0 project now integrates the real minimal RV32I firmware-owned control plane instead of the earlier deterministic stub
- the active packaged RTL path now includes:
  - `rtl/control/phase0_rv32i_core.v`
  - `rtl/control/phase0_boot_rom.v`
  - `rtl/control/phase0_data_ram.v`
  - `rtl/control/phase0_rv32i_soc.v`
  - `rtl/peripherals/phase0_uart_mmio.v`
- `quartus/phase0/build.ps1` now rebuilds `fw/phase0`, regenerates `phase0_fw.mif`, and then runs the full FPGA flow against the same firmware image used by ModelSim
- current integrated validation on `2026-04-23` is:
  - firmware build succeeded
  - ModelSim happy-path passed with `TB_PASS fabric_status=8019077f soc_status=037f write_count=18 dac_toggle_count=1668 uart_capture_count=36`
  - ModelSim targeted-NACK path passed with `TB_NACK_PASS fabric_status=6019073f soc_status=033f nack_count=1 stop_count=1`
  - Quartus full compile succeeded and regenerated `output_files/piano_phase0_top.sof`
- current fitted resource summary from the integrated RV32I build:
  - `4696 / 10320` logic elements
  - `1520` registers
  - `262144 / 423936` memory bits
  - `1 / 2` PLLs
  - `2 / 46` embedded `9-bit` multipliers
- at the `task-9d00cc2f` handoff point, the remaining hardware issue was no longer license or packaging related:
  - TimeQuest then reported slow-`85C` setup slack of `-0.881 ns` on `sys_clk_50m`
  - `i2c_clk` and `audio_bclk` were already clean at `17.766 ns` and `328.040 ns`
  - the dominant failing paths were inside `phase0_rv32i_core.v`, primarily from `instr_reg[*]` into the register-file writeback path
  - that timing gap was later closed by `task-f925ff80`

Update for `task-e5e0096b`:

- the shipped Phase 0 default-tone contract is now aligned with the intended continuous baseline behavior instead of the earlier burst-and-retrigger bring-up behavior
- `phase0_soc_stub.v` now programs `DECAY_STEP = 0`, keeps the one post-init trigger for deterministic phase start, and stops issuing periodic trigger strobes during the runtime reporting loop
- board bring-up should therefore expect a continuous baseline tone once codec clocks and DAC data are active; recurring `R=XXXXXXXX` UART frames remain, but they are now status reports only and no longer imply periodic retrigger pulses
- the updated scripted full compile on `2026-04-23 15:27` local time completed successfully with `Quartus II 64-Bit Shell`, regenerated `output_files/piano_phase0_top.sof`, and reported slow-`85C` setup slack of `7.325 ns` on `sys_clk_50m`, `18.225 ns` on `i2c_clk`, and `328.130 ns` on `audio_bclk`

Update for `task-09810cec`:

- the packaged Phase 0 build now includes a dedicated PLL-backed `audio_mclk` generator at `12.000 MHz` instead of the older accidental `12.5 MHz` divider
- the SDC now models four clocks explicitly: `sys_clk_50m`, derived PLL `audio_mclk`, internal `i2c_clk`, and the codec-driven `audio_bclk` island at `1.500 MHz`
- the latest full compile on `2026-04-22 22:09` local time completed successfully with `0` errors and `7` warnings, regenerated `output_files/piano_phase0_top.sof`, and removed the previous PLL cross-check / TimeQuest warning noise
- the remaining warnings are now specific and understood:
  - unused `audio_adcdat` in the current playback-only RTL
  - synthesis-only `clkena` / `extclkena` unused warnings inside the small hand-written PLL wrapper
  - the expected fitter warnings about `audio_mclk` being an off-chip PLL output rather than a zero-delay internal clock

## Package Contents

Quartus project package:

- `quartus/phase0/piano_phase0_top.qpf`
- `quartus/phase0/piano_phase0_top.qsf`
- `quartus/phase0/piano_phase0_top.sdc`
- `quartus/phase0/build.ps1`

The package targets `EP4CE10F17C8` and binds only the current Phase 0 board interfaces:

- `sys_clk_50m` -> `PIN_E1`
- `sys_rst_n` -> `PIN_M15`
- `audio_mclk` -> `PIN_D14`
- `audio_bclk` -> `PIN_D12`
- `audio_lrc` -> `PIN_E9`
- `audio_dacdat` -> `PIN_D11`
- `audio_adcdat` -> `PIN_C14`
- `i2c_scl` -> `PIN_P15`
- `i2c_sda` -> `PIN_N14`
- `uart1_rx` -> `PIN_N6`
- `uart1_tx` -> `PIN_N5`

The current SDC models four clocks explicitly:

- `sys_clk_50m`: `50 MHz` board clock on `PIN_E1`
- derived `audio_mclk`: internal PLL clock at `12.000 MHz`, exported to `PIN_D14`
- `i2c_clk`: internal generated clock in `wm8978_i2c_ctrl`, modeled as `sys_clk_50m / 50 = 1 MHz`
- `audio_bclk`: external codec-driven Phase 0 audio clock, modeled as a `666.667 ns` period (`1.500 MHz`) bring-up clock

The packaged project also now depends on the generated firmware MIF:

- `quartus/phase0/phase0_fw.mif`
- this file is regenerated by `fw/phase0/build.ps1`, which `quartus/phase0/build.ps1` runs automatically before Quartus stages

The Phase 0 timing decision for the external audio domain is deliberate:

- `audio_bclk` is treated as an explicit external timing island for the current WM8978 codec-master bring-up path
- crossings between `{sys_clk_50m, i2c_clk}` and `audio_bclk` are declared asynchronous
- the current package now includes explicit source-synchronous timing on the WM8978 audio data pins and explicit exclusions for the remaining off-chip interfaces that do not have a defensible board-delay model from local collateral

## Exact Commands Run

Project directory:

- `E:\projects\piano-agents\quartus\phase0`

Commands executed against the packaged project:

1. `powershell -ExecutionPolicy Bypass -File E:\projects\piano-agents\quartus\phase0\build.ps1 -Stage map`
   Underlying Quartus command:
   `quartus_map --read_settings_files=on --write_settings_files=off piano_phase0_top`
2. `powershell -ExecutionPolicy Bypass -File E:\projects\piano-agents\quartus\phase0\build.ps1 -Stage fit`
   Underlying Quartus command:
   `quartus_fit --read_settings_files=on --write_settings_files=off piano_phase0_top`
3. `powershell -ExecutionPolicy Bypass -File E:\projects\piano-agents\quartus\phase0\build.ps1 -Stage compile`
   Verified after updating `build.ps1` to prefer `D:\quartus\quartus\bin64\quartus_*.exe` when both `bin` and `bin64` are installed.
4. Quartus GUI full compile for the same packaged project
   Underlying flow recorded in `output_files/piano_phase0_top.flow.rpt`:
   `quartus_map`, `quartus_fit`, `quartus_asm`, `quartus_sta`, `quartus_eda`

## Results

Initial scripted `quartus_map` succeeded on `2026-04-21 11:29:57` local time.

- status: `0` errors, `2` warnings
- warning kept intentionally: `audio_adcdat` is pinned for interface completeness but does not drive logic in the current playback-only Phase 0 RTL
- resource summary from `output_files/piano_phase0_top.map.summary`:
  - `868` logic elements
  - `471` registers
  - `11` pins
  - `0` memory bits
  - `2` embedded `9-bit` multipliers
  - `0` PLLs

The first scripted `quartus_fit` then failed on `2026-04-21 11:30:12` local time with:

- `Warning (292000): FLEXlm software error: Invalid (inconsistent) license key`
- `Error (119013): Current license file does not support the EP4CE10F17C8 device`

That failure turned out to be a tool-path and license-resolution mismatch, not a real project or device-support problem:

- the failing scripted run identified itself as `Quartus II 32-bit`
- the PowerShell-resolved CLI tools on `PATH` came from `D:\quartus\quartus\bin\quartus_*.exe`
- the successful GUI run identified itself as `Quartus II 64-Bit`
- the successful installation also contains `D:\quartus\quartus\bin64\quartus_*.exe`

The later GUI full compile for the same revision succeeded on `2026-04-21 11:37:02` local time and produced:

- `output_files/piano_phase0_top.sof`
- `output_files/piano_phase0_top.fit.summary`
- `output_files/piano_phase0_top.sta.summary`
- `output_files/piano_phase0_top.asm.rpt`

The successful GUI flow shows:

- `Quartus II 64-Bit Version 13.0.1 Build 232 06/12/2013 SP 1 SJ Full Version`
- total elapsed time `00:00:13`
- fitted resources:
  - `845 / 10,320` logic elements
  - `471` registers
  - `11 / 180` pins
  - `2 / 46` embedded `9-bit` multipliers
  - `0 / 2` PLLs
- constrained-clock timing from `piano_phase0_top.sta.summary`:
  - setup slack on `sys_clk_50m`: `7.030 ns`
  - hold slack on `sys_clk_50m`: `0.452 ns`

Conclusion:

- the packaged Quartus project is valid
- the board target `EP4CE10F17C8` is supported by the working installation path used by the GUI
- the original CLI license error came from invoking the `32-bit` `bin` executables instead of the working `64-bit` toolchain path
- `quartus/phase0/build.ps1` now prefers `bin64` executables when both are installed

That scripted `bin64` preference has now been verified directly. An initial full scripted run completed successfully on `2026-04-21 12:12:03` local time:

- command:
  `powershell -ExecutionPolicy Bypass -File E:\projects\piano-agents\quartus\phase0\build.ps1 -Stage compile`
- tool banner:
  `Quartus II 64-Bit Shell`
- end result:
  `Quartus II Full Compilation was successful. 0 errors, 23 warnings`
- outputs refreshed:
  - `output_files/piano_phase0_top.sof`
  - `output_files/piano_phase0_top.sta.summary`
  - `simulation/modelsim/*.vo`
  - `simulation/modelsim/*.sdo`

That first successful scripted run still left the design only partially constrained.

- `audio_bclk` and `wm8978_i2c_ctrl.i2c_clk` were detected as clocks with no explicit clock assignments
- TimeQuest reported the design was not fully constrained for setup or hold requirements
- the positive timing result still only covered the constrained `sys_clk_50m` domain

Timing collateral was then tightened in `quartus/phase0/piano_phase0_top.sdc` and revalidated with:

- `powershell -ExecutionPolicy Bypass -File E:\projects\piano-agents\quartus\phase0\build.ps1 -Stage compile`

The updated scripted run completed successfully on `2026-04-21 12:26:38` local time with:

- `Quartus II Full Compilation was successful. 0 errors, 3 warnings`
- `Quartus II 64-Bit Shell`
- flow elapsed time from `output_files/piano_phase0_top.flow.rpt`: `00:00:12`

The tightened timing package now covers:

- `sys_clk_50m`
- derived PLL `audio_mclk`
- internal generated `i2c_clk`
- external `audio_bclk`
- asynchronous separation between the sys/i2c fabric clocks and the codec-driven audio-bit-clock island
- PLL-clock derivation plus clock-uncertainty derivation for the modeled clocks

Updated TimeQuest summary from `output_files/piano_phase0_top.sta.summary`:

- slow `85C` setup slack:
  - `sys_clk_50m`: `6.834 ns`
  - `i2c_clk`: `18.238 ns`
  - `audio_bclk`: `327.968 ns`
- slow `85C` hold slack:
  - `sys_clk_50m`: `0.433 ns`
  - `audio_bclk`: `0.453 ns`
  - `i2c_clk`: `0.453 ns`
- slow `85C` removal slack:
  - `sys_clk_50m`: `3.777 ns`
  - `i2c_clk`: `1.029 ns`

The verifier-facing improvement is concrete:

- the previous unconstrained-clock warnings for `audio_bclk` and `wm8978_i2c_ctrl_inst|i2c_clk` are gone
- the previous clock-uncertainty warnings are gone
- the earlier PLL cross-check warning is gone after switching the package to `derive_pll_clocks`
- the current full-compile warnings are all specific implementation caveats rather than missing-clock collateral gaps

What remains explicitly excluded rather than point-to-point timed in this Phase 0 package:

- `sys_rst_n`
  - asynchronous board reset into `phase0_reset_sync`
- `audio_mclk`
  - forwarded codec clock output rather than a data pin with a local output-delay aperture
- `i2c_scl` and `i2c_sda`
  - open-drain 2-wire control with no local board capacitance or skew numbers for defensible setup/hold signoff
- `uart1_rx` and `uart1_tx`
  - asynchronous serial debug I/O rather than source-synchronous interfaces

The important change is that these are no longer accidental unconstrained paths. Phase 0 now times the defendable WM8978 audio data boundary and excludes the remaining board interfaces on purpose, with a stated reason for each exclusion.

## Board Bring-Up Checklist

1. Use the packaged script or GUI path that resolves to `D:\quartus\quartus\bin64\quartus_*.exe`, not the `32-bit` `bin` executables.
2. Confirm `E:\projects\piano-agents\quartus\phase0\output_files\piano_phase0_top.sof` exists before attempting programming.
3. Route the board jumpers so `UART1` is connected to the on-board `CH340` USB-UART path, per the board manual.
4. Open a serial console on `UART1` at `115200 8N1`.
5. After reset release, probe `audio_mclk` first. The current RTL should drive a continuous `12.000 MHz` clock from the dedicated PLL.
6. Probe `i2c_scl` and `i2c_sda` next. A codec configuration burst should appear shortly after reset.
7. Probe `audio_bclk` and `audio_lrc` only after I2C activity. Those are codec-driven clocks and should appear only if WM8978 initialization succeeds; under the current explicit Phase 0 contract, expect roughly `1.500 MHz` `audio_bclk` and `46.875 kHz` `audio_lrc`.
8. Probe `audio_dacdat` after `audio_bclk`/`audio_lrc` are active. The Phase 0 stub should produce a continuous baseline tone after its one deterministic post-init trigger.
9. On `UART1`, expect compact ASCII status frames from the executing `fw/phase0` image:
   - `I=50303031` for the control block identity word
   - `S=XXXXXXXX` for boot status
   - recurring `R=XXXXXXXX` runtime status frames once the continuous baseline tone is running
10. If boot status shows `init_failed`, inspect the shared I2C bus first. The current design depends on WM8978 accepting the bring-up sequence and then providing codec-master `audio_bclk`/`audio_lrc`.
11. Treat the current timing sign-off honestly: the package is now fully constrained for setup and hold in TimeQuest, with explicit source-synchronous timing on `audio_lrc`, `audio_adcdat`, and `audio_dacdat`, plus deliberate exclusions for `audio_mclk`, `i2c_*`, `uart1_*`, and `sys_rst_n`. The current slow-`85C` worst setup slack is `0.357 ns` on `sys_clk_50m`.
