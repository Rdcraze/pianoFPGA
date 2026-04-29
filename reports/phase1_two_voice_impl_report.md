# Phase 1 Two-Voice Implementation Report

Task: `task-e4ded029`  
Date: `2026-04-25`  
Role: `implementer`

## Summary

Implemented the authorized narrow two-voice feasibility slice from `reports/phase1_timing_margin_acceptance_decision.md`.

The implementation duplicates the current reduced Phase 1 voice once, shares the accepted coefficients/defaults, triggers both voices from firmware after codec bring-up, and mixes the two hardware-owned voices with signed saturation into the existing mono-to-dual-mono WM8978 path.

Scope held:

- no richer physics
- no SDRAM
- no sample playback
- no UI/TFT/touch
- no exact-48-kHz or PLL rework
- no larger CPU or new bus fabric
- CPU remains outside the per-sample synthesis loop
- existing registers through `0x50` remain compatible

## Changed Files

- `rtl/audio/phase0_audio_path.v`
- `rtl/control/phase0_control_regs.v`
- `rtl/top/piano_phase0_top.v`
- `rtl/top/piano_phase0_top_tb.v`
- `fw/phase0/phase0_hw.h`
- `fw/phase0/phase0_main.c`
- `docs/phase0_impl_notes.md`
- `reports/phase1_two_voice_impl_report.md`

## Implementation

`rtl/audio/phase0_audio_path.v` now instantiates:

- `phase1_reduced_voice_inst` for voice0, preserving the accepted single-voice register/status behavior.
- `phase1_reduced_voice1_inst` for voice1, using the same reduced model and shared parameter wires.

The mix path is:

- signed 16-bit voice0 sample plus signed 16-bit voice1 sample into a 17-bit sum
- saturate to signed Q1.15 for `tx_sample`
- sticky mix clip flag
- mix clip event counter
- mix peak meter

Firmware triggers voice0 and voice1 as simultaneous note events after the two CPU-owned WM8978 volume writes. This proves overlapping hardware-owned voices without adding a scheduler or pitch system.

## Register Map Additions

Existing registers through `0x50` are preserved. New two-voice diagnostics start after the accepted observability range:

| Offset | Register | Purpose |
| --- | --- | --- |
| `0x54` | `VOICE1_CONTROL` | bit `0` enable, bit `1` W1 trigger, bit `2` W1 reset, bit `8` W1 clip clear |
| `0x58` | `VOICE1_STATUS` | same layout as `VOICE_STATUS`: bits `31:16` peak, bit `4` enabled, bit `3` sample valid, bit `2` clip, bit `1` excite busy, bit `0` active |
| `0x5C` | `VOICE1_TRIGGER_COUNT` | accepted voice1 trigger count |
| `0x60` | `VOICE1_ACTIVE_COUNT` | voice1 active-valid sample count |
| `0x64` | `VOICE1_VALID_COUNT` | voice1 valid sample count |
| `0x68` | `VOICE_MIX_STATUS` | bits `31:16` mix peak, bit `4` voice1 enabled, bit `3` mix valid, bit `2` mix clip, bit `1` any excite busy, bit `0` any active |
| `0x6C` | `VOICE_MIX_CLIP_COUNT` | output-mix saturation event count |

UART preserves `I/S/R/V/F/T/A/W` and appends:

- `Y=` `VOICE1_STATUS`
- `U=` `VOICE1_TRIGGER_COUNT`
- `B=` `VOICE1_ACTIVE_COUNT`
- `C=` `VOICE1_VALID_COUNT`
- `M=` `VOICE_MIX_STATUS`
- `K=` `VOICE_MIX_CLIP_COUNT`

## Validation

Firmware:

- Command: `powershell -ExecutionPolicy Bypass -File fw\phase0\build.ps1`
- Result: PASS

ModelSim:

- Full compile with Quartus `altera_mf.v` and the current RTL/testbench set: PASS, `0` errors, `0` warnings
- Standalone reduced voice TB: PASS
- Output: `VOICE_TB_PASS first_nonzero_sample=106 freq=438.084112 rms_100ms=292.703180 rms_500ms=35.578467 rms_3s=0.000000 peak=2082`
- Top happy path: PASS
- Output: `TB_PASS fabric_status=8019057f soc_status=037f write_count=18 dac_toggle_count=1304 voice_peak_level=2082 voice1_peak_level=2082 mix_peak_level=4164 voice_sample_count=517 voice_trigger_count=1 voice1_trigger_count=1 voice_active_count=358 voice1_active_count=358 voice_valid_count=516 voice1_valid_count=516 mix_clip_count=0 uart_capture_count=111`
- Top NACK path: PASS
- Output: `TB_NACK_PASS fabric_status=6018053f soc_status=033f nack_count=1 stop_count=1`

Quartus:

- Command: `powershell -ExecutionPolicy Bypass -File quartus\phase0\build.ps1 -Stage compile`
- Result: PASS, `0` errors, `12` warnings
- SOF SHA-256: `274C3F3178A08E103B500E724ED15E5FDFF0E58D15DD0EFB94514BECC3523A78`

TimeQuest:

- Fully constrained for setup and hold
- All listed TNS values are `0.000`
- Slow-85C setup slack: `3.957 ns` on `sys_clk_50m`, `18.132 ns` on `i2c_clk`, `313.716 ns` on `audio_bclk`
- Slow-85C hold slack: `0.432 ns` on `sys_clk_50m`, `0.452 ns` on `audio_bclk`, `0.453 ns` on `i2c_clk`
- Slow-85C `sys_clk_50m` Fmax: `62.33 MHz`
- Worst setup path remains RV32I writeback, not the voice datapath: `phase0_rv32i_core|instr_reg[31]` to `phase0_rv32i_core|wb_writeback_data_q[14]`, data delay `15.948 ns`, slack `3.957 ns`

## Resource Delta

Compared against the accepted timing-margin baseline:

| Metric | Timing-Margin Baseline | Two-Voice Build | Delta |
| --- | ---: | ---: | ---: |
| Logic elements | `5683` | `7366` | `+1683` |
| Dedicated registers | `2588` | `3580` | `+992` |
| Memory bits | `266752` | `271360` | `+4608` |
| M9Ks | `33` | `34` | `+1` |
| DSP9 elements | `2` | `4` | `+2` |
| PLLs | `1` | `1` | `0` |

The M9K and DSP increases are expected and justified by the second hardware voice. The build remains below the experiment limit of `8000 / 10320` LEs.

## Mapping Checks

Delay lines:

- voice0 delay line remains synchronous M9K-backed
- voice1 delay line is also synchronous M9K-backed
- no async-read delay-line implementation was introduced

Multipliers:

- voice0 retains one signed embedded 18-bit multiplier
- voice1 adds one signed embedded 18-bit multiplier
- total DSP use is `4` DSP9 elements

## Hardware Smoke

Hardware was not available in this session:

- `quartus_pgm --list` returned `No JTAG hardware available`
- `[System.IO.Ports.SerialPort]::GetPortNames()` returned no COM ports
- ffmpeg could see the external Realtek microphone device, but without JTAG/UART the board could not be programmed or observed

No hardware UART/audio capture was produced for this task. The generated SOF is available at `quartus/phase0/output_files/piano_phase0_top.sof` for verifier or a later hardware pass.

## Residual Risks

- The two voices are simultaneous and share one parameter set. This is enough to measure duplicated reduced-voice cost, but it is not a scheduler, pitch system, or polyphony architecture.
- Hardware audio has not yet been re-captured for this build because the board was unavailable.
- Quartus warnings are the known categories plus the expected second set of delay-line RAM pass-through warnings. They do not indicate async delay-line mapping or DSP loss.

## Verdict

Implementation target met in simulation and Quartus:

- two hardware-owned reduced voices overlap
- mix peak is doubled as expected in simulation (`4164` vs per-voice `2082`)
- mix clip count remains `0`
- LE use is below `8000`
- M9K/DSP growth is documented and expected
- timing remains fully constrained with comfortable positive `sys_clk_50m` slack
