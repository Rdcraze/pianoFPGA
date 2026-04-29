# Phase 1 Timing Margin Implementation Report

Task: `task-e3bb63b1`  
Date: `2026-04-24`  
Role: `implementer`

## Summary

Performed a localized timing-margin hardening pass on the accepted Phase 1 observability build.

The only RTL behavior change is inside the tiny RV32I control core: `rtl/control/phase0_rv32i_core.v` now has a `STATE_DECODE` operand-capture stage. The control CPU captures `rs1_value_q` and `rs2_value_q` before execute, so the register-file read mux no longer sits in the same cycle as the ALU/writeback mux.

Preserved:

- Phase 1 single reduced-voice sound engine and defaults
- register compatibility through `0x50`
- UART `I/S/R/V/F/T/A/W` observability
- nominal `46.875 kHz` sample-rate contract
- CPU-out-of-the-per-sample-loop split
- synchronous M9K-backed delay line
- DSP-backed voice multiplier

The control CPU now spends one additional cycle in decode per instruction. That affects only firmware throughput/report timing, not per-sample synthesis or the default note parameters.

## Timing Path Before And After

Accepted observability baseline:

- Slow-85C `sys_clk_50m` setup slack: `0.889 ns`
- Slow-85C `sys_clk_50m` Fmax: `52.33 MHz`
- Representative worst path: `phase0_rv32i_core|instr_reg[18]` to `phase0_rv32i_core|wb_writeback_data_q[20]`
- Data delay on that path: `19.504 ns`
- Worst path class: RV32I register-file/decode/writeback, not the voice datapath

After hardening:

- Slow-85C `sys_clk_50m` setup slack: `3.170 ns`
- Slow-85C `sys_clk_50m` Fmax: `59.42 MHz`
- Representative worst path: `phase0_rv32i_core|instr_reg[28]` to `phase0_rv32i_core|wb_writeback_data_q[12]`
- Data delay on that path: `16.752 ns`
- Worst path class remains RV32I writeback, but the register operand read is now staged

Delta:

- `sys_clk_50m` setup slack improved by `+2.281 ns` versus observability baseline
- `sys_clk_50m` setup slack is `+1.936 ns` above the frozen pre-observability Phase 1 `+1.234 ns` target reference
- `sys_clk_50m` Fmax improved by `+7.09 MHz` versus observability baseline

## Resource Delta

| Metric | Observability Baseline | Timing-Margin Build | Delta |
| --- | ---: | ---: | ---: |
| Logic elements | `6515` | `5683` | `-832` |
| Dedicated registers | `2523` | `2588` | `+65` |
| Memory bits | `266752` | `266752` | `0` |
| M9Ks | `33` | `33` | `0` |
| DSP9 elements | `2` | `2` | `0` |
| PLLs | `1` | `1` | `0` |

The register increase is the two 32-bit operand staging registers plus small state/decode overhead. The fitter packed the retimed control path better, reducing final logic elements.

## Validation

Firmware:

- Command: `powershell -ExecutionPolicy Bypass -File fw\phase0\build.ps1`
- Result: PASS

ModelSim:

- Full compile command: `vlog D:\quartus\quartus\eda\sim_lib\altera_mf.v ... rtl\top\piano_phase0_top_tb.v`
- Result: PASS, `0` errors, `0` warnings
- Voice TB: `VOICE_TB_PASS first_nonzero_sample=106 freq=438.084112 rms_100ms=292.703180 rms_500ms=35.578467 rms_3s=0.000000 peak=2082`
- Happy-path TB: `TB_PASS fabric_status=8019077f soc_status=037f write_count=18 dac_toggle_count=1236 voice_peak_level=2082 voice_sample_count=517 voice_trigger_count=1 voice_active_count=358 voice_valid_count=516 uart_capture_count=96`
- NACK TB: `TB_NACK_PASS fabric_status=6018073f soc_status=033f nack_count=1 stop_count=1`

Quartus:

- Command: `powershell -ExecutionPolicy Bypass -File quartus\phase0\build.ps1 -Stage compile`
- Result: PASS, `0` errors, `10` warnings
- SOF checksum reported by programmer: `0x0047FF19`
- SOF SHA-256: `22ADDED0CF998F728B63CD94CE6493CEEC9B506E115C9680F11A6C3986E15626`

TimeQuest:

- Fully constrained for setup and hold
- Slow-85C setup slack: `3.170 ns` on `sys_clk_50m`, `18.167 ns` on `i2c_clk`, `315.933 ns` on `audio_bclk`
- Slow-85C hold slack: `0.432 ns` on `sys_clk_50m`, `0.453 ns` on `audio_bclk`, `0.453 ns` on `i2c_clk`
- All listed TNS values are `0.000`

Mapping checks:

- Delay line remains M9K-backed: two simple-dual-port `128 x 18` M9K RAMs.
- Voice multiplier remains DSP-backed: one signed embedded 18-bit multiplier, `2` DSP9 elements.
- No memory/M9K/DSP/PLL increase.

## Hardware Smoke

Programming:

- JTAG cable: `USB-Blaster [USB-0]`
- Command: `quartus_pgm -m jtag -c "USB-Blaster [USB-0]" -o "p;quartus/phase0/output_files/piano_phase0_top.sof"`
- Result: PASS, configured `EP4CE10F17@1`
- Programmer checksum: `0x0047FF19`

UART:

- Port: `COM4`, `115200 8N1`
- Capture artifact: `reports/phase1_timing_margin_uart_capture.txt`
- Observed repeated runtime diagnostics:

```text
R=8018077F
V=08220010
F=004A427B
T=00000001
A=000172B3
W=004A430F
```

Interpretation:

- `T=00000001` confirms one accepted default trigger.
- `F` and `W` advance across groups.
- `A=000172B3` remains the accumulated active-valid sample count after decay.
- `V=08220010` reports peak `0x0822` / `2082`, voice enabled, no late active/clip bit.

External audio capture:

- Capture artifact: `reports/phase1_timing_margin_audio_capture.wav`
- Analysis artifact: `reports/phase1_timing_margin_audio_analysis.txt`
- Capture path: DirectShow external Realtek microphone input, stereo, 48 kHz, 16-bit PCM
- Duration: `14.988 s`
- Detected onset: `2.187 s`
- Mono fundamental: `435.955 Hz`
- Channel fundamentals: `435.964 Hz` left, `435.900 Hz` right
- Early mono RMS/peak: `0.010480` / `0.030899`
- Early crest factor: `2.948`
- Clipped samples: `0` left, `0` right
- Decay versus early window: `-10.16 dB` at `0.25 s`, `-12.42 dB` at `0.50 s`, `-13.50 dB` at `2.00 s`

This is consistent with the accepted Phase 1 decaying non-square tone and shows no clipping regression.

## Residual Notes

- The retime intentionally slows only the firmware control plane by one decode cycle per instruction. The audio engine remains hardware-owned and sample-timed.
- The happy-path simulation counters differ slightly from the observability implementation report because the default trigger happens a few fabric cycles later. The standalone voice TB signature, peak level, trigger count, UART frame count, and hardware audio behavior remain compatible.
- Remaining Quartus warnings are the known playback-only `audio_adcdat` warning, PLL forwarded-clock warnings for `audio_mclk`, and RAM pass-through warnings while preserving M9K mapping.
