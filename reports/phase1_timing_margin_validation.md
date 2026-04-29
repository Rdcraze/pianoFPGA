# Phase 1 Timing Margin Validation

Date: 2026-04-24
Verifier: verifier
Task: `task-89751417`

## Verdict

PASS. The Phase 1 timing/resource margin hardening pass is localized to RV32I control-plane retiming, preserves the accepted Phase 1 sound/observability baseline, and materially improves timing/resource margin.

Recommendation: the next controlled experiment may be a two-voice feasibility slice. Keep it as a single-dimension experiment only: no richer physics, no UI, no SDRAM, no sample playback, no clock-contract rework, and require the same firmware/ModelSim/Quartus/UART/audio evidence before accepting it.

No feature expansion beyond timing/resource hardening was found.

## Scope Review

Inputs reviewed:

- `reports/phase1_observability_acceptance_decision.md`
- `reports/phase1_observability_validation.md`
- `reports/phase1_timing_margin_impl_report.md`
- Current RTL/firmware/docs relevant to CPU, register map, UART reporting, and audio datapath

Source findings:

- `rtl/control/phase0_rv32i_core.v` adds `STATE_DECODE` plus `rs1_value_q` and `rs2_value_q` staging before execute. EXEC uses the staged operands for JALR, branches, loads/stores, OP-IMM, and OP instructions.
- This adds one decode cycle per firmware instruction, but the CPU remains outside the per-sample audio loop.
- Voice registers through `0x3C` are preserved, and diagnostic registers through `0x50` remain compatible: `VOICE_SAMPLE_COUNT`, `VOICE_TRIGGER_COUNT`, `VOICE_ACTIVE_COUNT`, `VOICE_VALID_COUNT`, and `VOICE_DIAG_CONTROL`.
- Firmware still emits `I/S/R` and the accepted `V/F/T/A/W` debug frames.
- `phase1_reduced_voice` still contains the `ramstyle = "M9K"` delay line and the signed multiplier expression.
- The audio path still drives `tx_valid = sample_valid_int` and `tx_sample = sample_data_int[15:0]`; DAC serialization still sends the same frame sample to both L/R slots.

## Regression Evidence

Firmware and ModelSim:

- Firmware build: PASS (`reports/phase1_timing_margin_validation_fw_build.log`).
- ModelSim fresh-library compile: PASS, 0 errors / 0 warnings (`reports/phase1_timing_margin_validation_msim_fresh_compile.log`).
- Reduced voice TB: PASS, unchanged signature:
  `VOICE_TB_PASS first_nonzero_sample=106 freq=438.084112 rms_100ms=292.703180 rms_500ms=35.578467 rms_3s=0.000000 peak=2082`.
- Top happy path: PASS, 0 errors / 0 warnings:
  `TB_PASS fabric_status=8019077f soc_status=037f write_count=18 dac_toggle_count=1236 voice_peak_level=2082 voice_sample_count=517 voice_trigger_count=1 voice_active_count=358 voice_valid_count=516 uart_capture_count=96`.
- NACK path: PASS, 0 errors / 0 warnings:
  `TB_NACK_PASS fabric_status=6018073f soc_status=033f nack_count=1 stop_count=1`.
- The top-level count shift versus the observability validation (`dac_toggle_count 1243->1236`, `active 359->358`, `valid 517->516`) is consistent with the added decode cycle and does not change trigger count, peak, UART frame count, or status behavior.

Quartus:

- Full compile: PASS, 0 errors / 10 known warnings (`reports/phase1_timing_margin_validation_quartus_compile.log`).
- SOF checksum: `0x0047FF19`.
- SOF SHA-256: `22ADDED0CF998F728B63CD94CE6493CEEC9B506E115C9680F11A6C3986E15626`.
- TimeQuest: fully constrained for setup and hold; unconstrained clocks/ports/paths all 0.
- Worst slow-85C `sys_clk_50m` path is RV32I writeback, not voice datapath:
  `instr_reg[28]` to `wb_writeback_data_q[12]`, data delay `16.752 ns`, slack `+3.170 ns`.

## Timing And Resources

Resource delta versus accepted observability baseline:

| Metric | Observability | Timing-Margin | Delta |
| --- | ---: | ---: | ---: |
| Logic elements | 6,515 | 5,683 | -832 |
| Dedicated registers | 2,523 | 2,588 | +65 |
| Memory bits | 266,752 | 266,752 | 0 |
| M9Ks | 33 | 33 | 0 |
| DSP9 elements | 2 | 2 | 0 |
| PLLs | 1 | 1 | 0 |

Timing delta versus accepted observability baseline:

| Metric | Observability | Timing-Margin | Delta |
| --- | ---: | ---: | ---: |
| Slow 85C `sys_clk_50m` setup slack | +0.889 ns | +3.170 ns | +2.281 ns |
| Slow 85C `sys_clk_50m` hold slack | +0.432 ns | +0.432 ns | 0.000 ns |
| Slow 85C `sys_clk_50m` Fmax | 52.33 MHz | 59.42 MHz | +7.09 MHz |
| Slow 85C `i2c_clk` setup slack | +17.615 ns | +18.167 ns | +0.552 ns |
| Slow 85C `audio_bclk` setup slack | +314.022 ns | +315.933 ns | +1.911 ns |

Mapping checks:

- Delay line remains M9K-backed: two inferred simple-dual-port `128 x 18` M9K RAMs.
- Voice multiplier remains DSP-backed: one signed 18-bit multiplier using 2 DSP9 elements.
- Memory, M9K, DSP9, and PLL counts are unchanged from both the frozen Phase 1 and accepted observability baselines.

## Hardware Evidence

Programming:

- USB-Blaster detected as `USB-Blaster [USB-0]`.
- Programmed regenerated `quartus/phase0/output_files/piano_phase0_top.sof` successfully.
- Programmer confirmed checksum `0x0047FF19`.
- Log: `reports/phase1_timing_margin_validation_quartus_pgm.log`.

UART on `COM4`, `115200 8N1`:

- Captured startup: `I=50303031`, `S=8018073F`.
- First post-trigger debug group:
  `R=8018077F`, `V=00000011`, `F=000000E4`, `T=00000001`, `A=000000C1`, `W=00000178`.
- Later settled group:
  `R=8018077F`, `V=08220010`, `F=00087D6B`, `T=00000001`, `A=000172B3`, `W=00087DFE`.
- `V=08220010` decodes as peak `2082`, voice enabled, sample-valid low at read time, no clip, not busy, inactive after decay.
- `F/W` advance across groups; `A=0x000172B3` remains the accumulated active-valid count after decay.
- Capture: `reports/phase1_timing_margin_validation_uart_capture.txt`.

External audio capture:

- Capture: `reports/phase1_timing_margin_validation_audio_capture.wav`.
- Analysis: `reports/phase1_timing_margin_validation_audio_analysis.txt`.
- Capture path: external Realtek mic-jack path, stereo, 48 kHz, 16-bit PCM, 14.987 s.
- Event onset: about 2.620 s after capture start.
- L channel: f0 `436.101 Hz`, early RMS `0.012525`, peak `0.035736`, 0 clipped samples.
- R channel: f0 `436.138 Hz`, early RMS `0.007952`, peak `0.021393`, 0 clipped samples.
- L/R frequency delta: `-0.038 Hz`; L is `+3.946 dB` hotter than R, consistent with known analog/capture imbalance.
- Mono f0: `436.113 Hz`; early crest factor `2.841`.
- Decay relative to early reference: `-8.21 dB` at 0.25 s, `-16.45 dB` at 0.50 s, then near capture-noise floor.
- Non-square regression check: zero clipped samples and crest factor far above a clipped square wave; higher harmonics roll off.

## Residual Notes

- The known Quartus warnings remain on the watch list: unused `audio_adcdat`, RAM pass-through messages for the synchronous M9K delay line, incomplete pin assignment warning, and PLL/audio MCLK forwarded-clock warnings. They are not new timing failures.
- The retimed CPU is slower per instruction. Current firmware and UART reporting still pass; future firmware changes should remember this is a tiny control core, not a throughput path.
- Two-voice feasibility should be a narrow prototype slice with the same acceptance gates: positive fully constrained timing, documented resource delta, M9K/DSP mapping, `V/F/T/A/W` hardware counters, and non-clipping external audio capture.

