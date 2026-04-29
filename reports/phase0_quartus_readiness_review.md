# Phase 0 Quartus Readiness Review

Date: `2026-04-21`

## Findings

### [P1] Timing coverage does not yet cover the full bring-up clocking scheme

`quartus/phase0/piano_phase0_top.sdc` constrains only `sys_clk_50m`:

- `create_clock -name {sys_clk_50m} -period 20.000 [get_ports {sys_clk_50m}]`

That is enough to show the core `50 MHz` fabric domain is healthy, but it is not enough for a stronger board-ready timing claim. TimeQuest still reports:

- `2` unconstrained clocks
- `4` unconstrained input ports
- `5` unconstrained output ports
- `Warning (332060)` on internal `wm8978_i2c_ctrl_inst|i2c_clk`
- `Warning (332060)` on external `audio_bclk`
- `Critical Warning (332168)` / `Critical Warning (332169)` for missing clock uncertainty assignments

The external `audio_bclk` gap is understandable for a first codec-master bring-up package, but the unconstrained internal `i2c_clk` means the codec-control path is also outside timing sign-off today. This does not invalidate the generated `.sof`, but it does limit the confidence level of the package to first non-destructive bring-up rather than full timing closure.

No additional pinout, device-selection, top-level, or source-set mismatches were found in this review.

## Package Validation

The Quartus package under `quartus/phase0/` is coherent:

- `piano_phase0_top.qsf` targets `Cyclone IV E`, device `EP4CE10F17C8`, top `piano_phase0_top`
- the source list is restricted to the current Phase 0 RTL
- the pin assignments bind only the intended board interfaces:
  - `sys_clk_50m` -> `PIN_E1`
  - `sys_rst_n` -> `PIN_M15`
  - `audio_bclk` -> `PIN_D12`
  - `audio_lrc` -> `PIN_E9`
  - `audio_adcdat` -> `PIN_C14`
  - `audio_mclk` -> `PIN_D14`
  - `audio_dacdat` -> `PIN_D11`
  - `i2c_scl` -> `PIN_P15`
  - `i2c_sda` -> `PIN_N14`
  - `uart1_rx` -> `PIN_N6`
  - `uart1_tx` -> `PIN_N5`

The fitted pin report keeps those interfaces at `2.5 V`, which is consistent with the current project/package.

## Board / Example Cross-Check

The Quartus pin assumptions match the project-local board evidence:

- `docs/board_capabilities_report.md` identifies the same `EP4CE10F17C8` board target and the same audio / I2C / UART pins
- `docs/manual_audio_example_report.md` matches the WM8978-facing pins and confirms the expected codec-master arrangement where `audio_bclk` and `audio_lrc` are inputs to the FPGA
- the bundled vendor example at `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/59_audio_sd_play/quartus_prj/audio_sd_play.qsf` uses the same WM8978 control and audio pins

I did not find a likely board-pin, bank, or I/O-standard mismatch from the available local evidence.

## Exact Commands / Outputs Inspected

This review independently inspected the saved Quartus package and outputs rather than rerunning the full compile. The exact commands used in this verification pass were:

1. `Get-Content quartus/phase0/piano_phase0_top.sdc`
2. `Select-String -Path 'quartus/phase0/piano_phase0_top.qsf' -Pattern 'TOP_LEVEL_ENTITY|FAMILY|DEVICE|set_location_assignment'`
3. `Select-String -Path 'quartus/phase0/output_files/piano_phase0_top.flow.rpt','quartus/phase0/output_files/piano_phase0_top.sta.summary','quartus/phase0/output_files/piano_phase0_top.sta.rpt' -Pattern 'Successful|Slack|Unconstrained|Warning \(332060\)|Critical Warning \(332168\)|Critical Warning \(332169\)'`
4. `Select-String -Path 'quartus/phase0/output_files/piano_phase0_top.pin' -Pattern 'audio_|sys_|uart1_|i2c_'`
5. `Select-String -Path 'quartus/phase0/build.ps1' -Pattern 'bin64|quartus_map|quartus_fit|quartus_asm|quartus_sta'`
6. `Select-String -Path 'docs/board_capabilities_report.md' -Pattern 'E1|D14|D12|E9|D11|C14|P15|N14|N6|N5'`
7. `Select-String -Path 'docs/manual_audio_example_report.md' -Pattern 'D14|D12|E9|D11|C14|P15|N14|N6|N5|BCLK|LRC|codec'`
8. `Select-String -Path 'Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/59_audio_sd_play/quartus_prj/audio_sd_play.qsf' -Pattern 'PIN_D14|PIN_D12|PIN_E9|PIN_D11|PIN_C14|PIN_P15|PIN_N14|PIN_N6|PIN_N5'`

## Quartus Output Review

Saved outputs show a successful full compile:

- `output_files/piano_phase0_top.flow.rpt`: `Flow Status ; Successful - Tue Apr 21 11:37:02 2026`
- `output_files/piano_phase0_top.sof` is present
- `output_files/piano_phase0_top.sta.summary` shows constrained `sys_clk_50m` timing is clean:
  - setup slack `7.030 ns`
  - hold slack `0.452 ns`
  - recovery slack `15.002 ns`
  - removal slack `3.565 ns`
  - minimum pulse-width slack `9.470 ns`

The project therefore compiles cleanly enough for programming and observation, but only for the constrained `50 MHz` domain.

I also verified that `quartus/phase0/build.ps1` already prefers `bin64` when available, so the older note in `reports/phase0_quartus_bringup_report.md` saying the script still needed that change is now stale.

## Bring-Up Collateral Review

`reports/phase0_quartus_bringup_report.md` is specific enough to be useful at first power-up. It gives a usable probe order and expected observables:

1. `audio_mclk`
2. `i2c_scl` / `i2c_sda`
3. codec-generated `audio_bclk` / `audio_lrc`
4. `audio_dacdat`
5. UART status frames on `UART1` at `115200 8N1`

That is a reasonable first non-destructive checklist for confirming clocking, codec init traffic, codec-master clock appearance, and basic firmware-visible status.

## Readiness Assessment

The current package appears suitable for a first non-destructive board bring-up session if the goal is to observe:

- reset release
- continuous `audio_mclk`
- WM8978 I2C initialization traffic
- codec-generated `audio_bclk` / `audio_lrc`
- `audio_dacdat` activity
- UART status output

Residual risks remain:

- no timing closure for the internal `i2c_clk` domain
- no timing closure for the external codec-driven `audio_bclk` domain
- no clock uncertainty derivation/assignment in the current SDC
- `reports/phase0_quartus_bringup_report.md` contains one stale note about `build.ps1` bin64 preference

Bottom line: the design looks board-ready for cautious first observation and signal-check bring-up, but not yet timing-ready for a stronger production-style or sign-off-style readiness claim.
