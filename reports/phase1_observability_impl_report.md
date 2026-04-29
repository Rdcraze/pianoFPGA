# Phase 1 Observability Implementation Report

Task: `task-7c2e4ebf`  
Date: `2026-04-24`  
Role: `implementer`

## Summary

Added measurement/debug visibility to the frozen Phase 1 reference baseline without changing the voice model.

Preserved:

- Phase 1 single reduced voice audio behavior
- existing register offsets through `0x3C`
- nominal `46.875 kHz` sample-rate contract
- board-I/O timing model
- synchronous M9K-backed delay-line implementation
- CPU-out-of-the-per-sample-loop ownership split

## New Diagnostic Registers

New registers are placed after the existing voice register map:

- `0x40 VOICE_SAMPLE_COUNT`: read-only 32-bit counter incremented on every `sample_tick`
- `0x44 VOICE_TRIGGER_COUNT`: read-only 32-bit counter incremented when a voice trigger is accepted while enabled
- `0x48 VOICE_ACTIVE_COUNT`: read-only 32-bit counter incremented when `sample_valid` is asserted while the voice is active
- `0x4C VOICE_VALID_COUNT`: read-only 32-bit counter incremented on every voice `sample_valid`
- `0x50 VOICE_DIAG_CONTROL`: bit `0` write-one clears the four diagnostic counters

The existing `0x24 VOICE_STATUS` remains the active/excite/clip/sample-valid/peak status register. The existing `VOICE_CONTROL.clip_clear` sticky-clip clear path remains unchanged.

## UART Format

Firmware still emits the original `I=`, `S=`, and `R=` ASCII hex frames. After each `R=` status frame it now emits:

- `V=`: `VOICE_STATUS`
- `F=`: `VOICE_SAMPLE_COUNT`
- `T=`: `VOICE_TRIGGER_COUNT`
- `A=`: `VOICE_ACTIVE_COUNT`
- `W=`: `VOICE_VALID_COUNT`

This preserves the first three existing bring-up frames while adding field-visible voice state and runtime counters.

## Validation

Firmware:

- Command: `powershell -ExecutionPolicy Bypass -File fw/phase0/build.ps1`
- Result: PASS; regenerated firmware image and `phase0_fw.mif`

Standalone voice simulation:

- Command: `vsim -c work.phase1_reduced_voice_tb -do "run -all; quit -f"`
- Result: PASS
- Output: `VOICE_TB_PASS first_nonzero_sample=106 freq=438.084112 rms_100ms=292.703180 rms_500ms=35.578467 rms_3s=0.000000 peak=2082`

ModelSim full RTL compile:

- Command: `vlog D:\quartus\quartus\eda\sim_lib\altera_mf.v ... rtl\top\piano_phase0_top_tb.v`
- Result: PASS, `0` errors, `0` warnings

Happy-path simulation:

- Command: `vsim -voptargs=+acc -c work.piano_phase0_top_tb -do "run 12 ms; quit -f"`
- Result: PASS
- Output: `TB_PASS fabric_status=8019077f soc_status=037f write_count=18 dac_toggle_count=1243 voice_peak_level=2082 voice_sample_count=517 voice_trigger_count=1 voice_active_count=359 voice_valid_count=517 uart_capture_count=96`

Targeted-NACK simulation:

- Command: `vsim -voptargs=+acc -c work.piano_phase0_top_nack_tb -do "run 12 ms; quit -f"`
- Result: PASS
- Output: `TB_NACK_PASS fabric_status=6018073f soc_status=033f nack_count=1 stop_count=1`

Quartus full compile:

- Command: `powershell -ExecutionPolicy Bypass -File quartus\phase0\build.ps1 -Stage compile`
- Result: PASS, `0` errors, `10` warnings, regenerated `quartus/phase0/output_files/piano_phase0_top.sof`

Final fit:

- Logic elements: `6515 / 10320`
- Registers: `2523`
- Memory bits: `266752 / 423936`
- Embedded multiplier 9-bit elements: `2 / 46`
- PLLs: `1 / 2`

Delta versus frozen Phase 1 reference:

- Logic elements: `+207`
- Registers: `+129`
- Memory bits: `+0`
- DSP9 elements: `+0`
- PLLs: `+0`

TimeQuest:

- Fully constrained for setup and hold
- Slow `85C` setup slack: `0.889 ns` on `sys_clk_50m`, `17.615 ns` on `i2c_clk`, `314.022 ns` on `audio_bclk`
- Slow `85C` hold slack: `0.432 ns` on `sys_clk_50m`, `0.453 ns` on `i2c_clk`, `0.452 ns` on `audio_bclk`
- All listed TNS values are `0.000`

## Hardware Smoke

Hardware was visible:

- JTAG: `USB-Blaster [USB-0]`
- UART: `COM4`

Programmed the current SOF:

- Command: `quartus_pgm -m jtag -c "USB-Blaster [USB-0]" -o "p;quartus/phase0/output_files/piano_phase0_top.sof"`
- Result: PASS, configured `EP4CE10F17@1`
- SOF checksum reported by programmer: `0x004DD5CF`

UART capture at `115200` baud showed recurring diagnostic frames:

```text
R=8018077F
V=08220010
F=00089BD4
T=00000001
A=000172B3
W=00089C66
R=8018077F
V=08220010
F=000A546A
T=00000001
A=000172B3
W=000A54FC
```

Interpretation:

- `T=00000001` confirms one accepted default trigger.
- `F` and `W` advance between reports, confirming ongoing frame/sample-valid accounting.
- `A` holds after the voice decays inactive, which is expected for an accumulated active-sample counter.
- `V=08220010` reports voice enabled with peak meter `0x0822` and no active/clip bit set by the time of this late capture.

No automated external audio capture path was available in this session, so hardware audio was not remeasured here. The voice unit regression and prior Phase 1 reference capture remain the audio-behavior evidence for this observability-only change.

## Caveats

Remaining warnings are the same understood baseline class:

- current playback-only RTL still does not consume `audio_adcdat`
- PLL forwarded-clock warnings remain for `audio_mclk`
- Quartus still emits pass-through warnings for inferred small delay RAMs, while preserving M9K mapping

The diagnostic counters are intentionally simple 32-bit wraparound counters. They are for runtime observability and scaling decisions, not formal event logging.
