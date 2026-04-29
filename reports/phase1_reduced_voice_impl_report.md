# Phase 1 Reduced Voice Implementation Report

Task: `task-9fb09496`  
Date: `2026-04-24`  
Role: `implementer`

## Summary

Implemented the Phase 1 single reduced piano voice on top of the validated Phase 0 RV32I/WM8978 baseline.

The live sample source is now `rtl/audio/phase1_reduced_voice.v`, a hardware-owned fixed-pitch reduced waveguide/Karplus-Strong-style voice:

- `128` entry Q1.17 delay line, mapped by Quartus into M9K-backed synchronous RAM
- one time-multiplexed signed `18 x 16` multiplier for allpass, damping, loop-gain, excitation, and body-mix arithmetic
- first-order allpass using default coefficient `9952`
- one-pole damping mix using default `16384`
- loop gain default `32640`
- 16-sample Q1.15 half-sine hammer burst scaled by `velocity_q15`, default `0x4000`
- optional tiny body coloration with default `body_mix_q15 = 8192`
- saturating Q1.17 feedback/write path and Q1.15 output conversion
- sticky `clip_seen` and peak-meter status

The CPU remains out of the per-sample loop. Firmware only writes parameters and triggers the voice through the new MMIO registers.

## Integration

Changed RTL/FW collateral:

- `rtl/audio/phase1_reduced_voice.v`: new Phase 1 voice engine
- `rtl/audio/phase1_reduced_voice_tb.v`: standalone objective voice regression
- `rtl/audio/phase0_audio_path.v`: now instantiates `phase1_reduced_voice` instead of the Phase 0 sample generator
- `rtl/control/phase0_control_regs.v`: preserves registers through `0x18` and adds voice registers at `0x20..0x3C`
- `rtl/top/piano_phase0_top.v`: wires voice controls/status between the RV32I-visible register bank and audio path
- `rtl/top/piano_phase0_top_tb.v`: keeps happy/NACK checks and adds nonzero voice peak / no-clip checks on the happy path
- `fw/phase0/phase0_hw.h`: adds voice register offsets, masks, and default constants
- `fw/phase0/phase0_main.c`: writes voice defaults, clears `clip_seen`, and triggers the voice after codec init
- `quartus/phase0/piano_phase0_top.qsf`: adds the new voice RTL source
- `docs/phase0_impl_notes.md`: documents the Phase 1 voice, register map, validation, and residual warnings

## Voice Register Map

Existing Phase 0 registers through `0x18` are preserved.

New registers:

- `0x20 VOICE_CONTROL`: reset `0x00000001`; bit `0` enable, bit `1` W1 trigger, bit `2` W1 reset, bit `3` body bypass, bit `4` allpass/dispersion bypass, bit `8` W1 clip clear
- `0x24 VOICE_STATUS`: bit `0` active, bit `1` excite busy, bit `2` clip seen, bit `3` sample valid, bit `4` voice enabled, bits `31:16` peak meter
- `0x28 VOICE_VELOCITY`: reset `0x4000`, unsigned Q1.15, clamped to `0x7FFF`
- `0x2C VOICE_LOOP_LEN`: reset `106`, clamped to `32..127`
- `0x30 VOICE_LOOP_GAIN`: reset `32640`, unsigned Q1.15, clamped to `0x7FFF`
- `0x34 VOICE_DAMP_MIX`: reset `16384`, unsigned Q1.15, clamped to `0x7FFF`
- `0x38 VOICE_DISP_COEFF`: reset `9952`, signed Q1.15
- `0x3C VOICE_BODY_MIX`: reset `8192`, unsigned Q1.15, clamped to `0x7FFF`

## Validation

Firmware:

- Command: `powershell -ExecutionPolicy Bypass -File fw/phase0/build.ps1`
- Result: PASS; regenerated `fw/phase0/build/phase0.elf`, `phase0.bin`, `phase0.mem`, and copied `phase0_fw.mif`

ModelSim compile:

- Command: `vlog D:\quartus\quartus\eda\sim_lib\altera_mf.v ... rtl\top\piano_phase0_top_tb.v`
- Result: PASS, `0` errors, `0` warnings

Standalone voice simulation:

- Command: `vsim -c work.phase1_reduced_voice_tb -do "run -all; quit -f"`
- Result: PASS
- Output: `VOICE_TB_PASS first_nonzero_sample=106 freq=438.084112 rms_100ms=292.703180 rms_500ms=35.578467 rms_3s=0.000000 peak=2082`

Phase 0/Phase 1 happy path:

- Command: `vsim -voptargs=+acc -c work.piano_phase0_top_tb -do "run 12 ms; quit -f"`
- Result: PASS
- Output: `TB_PASS fabric_status=8019077f soc_status=037f write_count=18 dac_toggle_count=1243 voice_peak_level=2082 uart_capture_count=36`

Targeted NACK path:

- Command: `vsim -voptargs=+acc -c work.piano_phase0_top_nack_tb -do "run 12 ms; quit -f"`
- Result: PASS
- Output: `TB_NACK_PASS fabric_status=6018073f soc_status=033f nack_count=1 stop_count=1`

Quartus full compile:

- Command: `powershell -ExecutionPolicy Bypass -File quartus\phase0\build.ps1 -Stage compile`
- Result: PASS, `0` errors, `10` warnings, regenerated `quartus/phase0/output_files/piano_phase0_top.sof`

Final fit:

- Logic elements: `6308 / 10320`
- Registers: `2394`
- Memory bits: `266752 / 423936`
- Embedded multiplier 9-bit elements: `2 / 46`
- PLLs: `1 / 2`

TimeQuest:

- Fully constrained for setup and hold
- Slow `85C` setup slack: `1.234 ns` on `sys_clk_50m`, `18.044 ns` on `i2c_clk`, `315.774 ns` on `audio_bclk`
- Slow `85C` hold slack: `0.429 ns` on `sys_clk_50m`, `0.452 ns` on `i2c_clk`, `0.451 ns` on `audio_bclk`
- All listed TNS values are `0.000`

## Findings

Initial Quartus synthesis passed functionally but did not infer RAM for the voice delay line because the first implementation used asynchronous delay-line reads. That produced a final fit of `8889` LEs, over the Phase 1 budget.

The fix was to add a registered delay-line read stage and mark the `128 x 18` state storage as `M9K`. Quartus then inferred synchronous RAM for the delay line and final fit dropped to `6308` LEs, under the `7000` LE budget.

Remaining warnings are understood and do not block Phase 1:

- `audio_adcdat` is intentionally unused in the current playback-only path
- existing PLL warnings remain for forwarded `audio_mclk` compensation/jitter caveats
- Quartus emits RAM pass-through warnings for the small inferred voice delay RAMs; the memories still map to M9K and the behavior is covered by RTL simulation

## Scope Held

No polyphony, pedal, SDRAM, SD, TFT/UI, exact-48-kHz rework, modal body bank, nonlinear hammer solver, MIDI, or CPU sample-loop work was added.
