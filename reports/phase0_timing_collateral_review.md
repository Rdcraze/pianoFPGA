# Phase 0 Timing Collateral Review

Date: `2026-04-21`

## Findings

### [P2] The timing package is materially stronger, but it is still not full board-level timing sign-off

The updated `quartus/phase0/piano_phase0_top.sdc` fixes the specific gaps called out in the prior review:

- `i2c_clk` is now modeled as a generated clock from `sys_clk_50m`
- `audio_bclk` is now modeled explicitly as an external codec-driven clock
- `{sys_clk_50m, i2c_clk}` and `audio_bclk` are separated with `set_clock_groups -asynchronous`
- `derive_clock_uncertainty` is now present

On a fresh verifier rerun of the packaged flow, the old warning classes are gone:

- no unconstrained-clock warning for internal `wm8978_i2c_ctrl_inst|i2c_clk`
- no unconstrained-clock warning for external `audio_bclk`
- no `Critical Warning (332168)` / `Critical Warning (332169)` clock-uncertainty warnings
- `Unconstrained Clocks: 0`
- TimeQuest completed with `0 errors, 0 warnings`

The residual limit is that the design is still not fully constrained for board I/O timing:

- `Unconstrained Input Ports: 4`
- `Unconstrained Output Ports: 5`
- TimeQuest still reports `Design is not fully constrained for setup requirements`
- TimeQuest still reports `Design is not fully constrained for hold requirements`

That remaining gap is consistent with the current bring-up-stage intent, but it means the new package should be described as stronger pre-board collateral, not final timing closure.

## Exact Verification Run

I reran the packaged compile from the current tree:

1. `powershell -ExecutionPolicy Bypass -File E:\projects\piano-agents\quartus\phase0\build.ps1 -Stage compile`

Observed result:

- `Quartus II 64-Bit Shell`
- `Quartus II Full Compilation was successful. 0 errors, 3 warnings`
- `quartus_sta` completed with `0 errors, 0 warnings`
- `quartus/phase0/output_files/piano_phase0_top.flow.rpt` reports:
  - `Flow Status ; Successful - Tue Apr 21 13:15:01 2026`

## Timing Review

Fresh TimeQuest output is materially better than the previous package:

- `Found 3 clocks`
  - `sys_clk_50m` at `20.000 ns`
  - `i2c_clk` at `1000.000 ns`
  - `audio_bclk` at `640.000 ns`
- worst-case setup slack:
  - `sys_clk_50m`: `7.334 ns`
  - `i2c_clk`: `18.209 ns`
  - `audio_bclk`: `314.898 ns`
- worst-case hold slack:
  - `sys_clk_50m`: `0.433 ns`
  - `i2c_clk`: `0.453 ns`
  - `audio_bclk`: `0.453 ns`

The key change is not just better numbers; it is that the previously missing clock intent is now explicit in the package.

What remains intentionally outside sign-off:

- off-chip input timing for `audio_lrc`, `audio_adcdat`, `uart1_rx`, and `sys_rst_n`
- off-chip output timing for `audio_mclk`, `audio_dacdat`, `i2c_scl`, `i2c_sda`, and `uart1_tx`

## Coherence Of The Audio Clock Treatment

The chosen treatment for the codec-driven clock domain is technically coherent for this bring-up-stage design.

Why:

- `rtl/peripherals/wm8978_codec_stub.v` uses `audio_bclk` as the actual audio-side event clock
- the `audio_bclk` domain is crossed back into `sys_clk` through toggle-style synchronization rather than being timed as a synchronous relation
- `rtl/peripherals/wm8978_dac_tx.v` does not use `audio_lrc` as a separate event clock; it samples `audio_lrc` inside the `audio_bclk` domain as a frame qualifier

That means `create_clock(audio_bclk)` plus asynchronous grouping against `{sys_clk_50m, i2c_clk}` matches the implemented architecture. The remaining missing piece is not clock declaration anymore; it is board-level I/O delay modeling for the off-chip codec-facing pins.

## Bring-Up Collateral Alignment

`reports/phase0_quartus_bringup_report.md` is now aligned with the packaged flow:

- it no longer carries the stale statement that `build.ps1` still needs a `bin64` preference
- it explicitly documents the three modeled clocks
- it states that the remaining unconstrained ports are intentional Phase 0 omissions rather than hidden timing debt

I independently verified that `quartus/phase0/build.ps1` now prefers `bin64` when present.

## Assessment

This package has progressed beyond the previous "first observation only" state. The timing collateral is now materially stronger for imminent board use because the major clock-intent gaps are explicit and the old unconstrained-clock warnings are removed in a fresh compile.

Residual limits still matter:

- this is not full board-level I/O timing sign-off
- the modeled `audio_bclk` island is coherent for the current fixed WM8978 bring-up contract, but it is still a bring-up abstraction rather than a complete codec-interface timing model
- future changes to the codec clocking contract would require the SDC assumptions to be revisited

Bottom line: the package is now reasonably stronger pre-board collateral and suitable for imminent cautious bring-up, but it still should not be represented as final timing closure for the off-chip WM8978/UART interfaces.
