# Phase 1 Observability Validation

Date: 2026-04-24
Verifier: verifier
Task: Validate Phase 1 observability hooks

## Verdict

PASS. The Phase 1 observability build is diagnostic-only, preserves the frozen Phase 1 reduced-voice register/API baseline through `0x3C`, keeps the CPU out of the per-sample audio loop, and exposes the requested voice active/clip/peak/counter visibility over MMIO and UART.

Recommendation: proceed to the first controlled scaling experiment. Keep the frozen Phase 1 reduced-voice image as the reference baseline, and use this observability image as the measurement baseline for per-step resource, timing, UART counter, and audio regression checks.

No feature expansion beyond observability was found.

## Source Scope Review

Inputs reviewed:

- `reports/phase1_reference_baseline_decision.md`
- `reports/phase1_reduced_voice_validation.md`
- `reports/phase1_observability_impl_report.md`
- RTL/FW/docs touched by the observability change

Register/API result:

- Existing voice control/status/parameter registers are still `0x20` through `0x3C`:
  `VOICE_CONTROL`, `VOICE_STATUS`, `VOICE_VELOCITY`, `VOICE_LOOP_LEN`,
  `VOICE_LOOP_GAIN`, `VOICE_DAMP_MIX`, `VOICE_DISP_COEFF`, `VOICE_BODY_MIX`.
- New diagnostic registers start after the frozen range:
  `0x40 VOICE_SAMPLE_COUNT`, `0x44 VOICE_TRIGGER_COUNT`,
  `0x48 VOICE_ACTIVE_COUNT`, `0x4C VOICE_VALID_COUNT`,
  `0x50 VOICE_DIAG_CONTROL`.
- `VOICE_DIAG_CONTROL[0]` is write-one clear for the four counters.
- Firmware emits `V=`, `F=`, `T=`, `A=`, `W=` after each `R=`.
- The firmware steady-state loop only delays, reads status/debug counters, and emits UART frames. It does not synthesize or service audio samples.
- The audio datapath still drives `tx_valid = sample_valid_int` and `tx_sample = sample_data_int[15:0]`; `wm8978_dac_tx` sends the same captured `tx_sample` to both L/R slots.

## Regression Results

Firmware and ModelSim:

- Firmware build: PASS (`reports/phase1_observability_validation_fw_build.log`).
- ModelSim compile: PASS, 0 errors / 0 warnings (`reports/phase1_observability_validation_msim_compile.log`).
- Reduced voice TB: PASS, `VOICE_TB_PASS first_nonzero_sample=106 freq=438.084112 rms_100ms=292.703180 rms_500ms=35.578467 rms_3s=0.000000 peak=2082`.
- Top happy path: PASS, `TB_PASS fabric_status=8019077f soc_status=037f write_count=18 dac_toggle_count=1243 voice_peak_level=2082 voice_sample_count=517 voice_trigger_count=1 voice_active_count=359 voice_valid_count=517 uart_capture_count=96`.
- I2C NACK path: PASS, `TB_NACK_PASS fabric_status=6018073f soc_status=033f nack_count=1 stop_count=1`.

Quartus implementation:

- Full compile: PASS, 0 errors / 10 warnings (`reports/phase1_observability_validation_quartus_compile.log`).
- SOF checksum: `0x004DD5CF`.
- SOF SHA-256: `FD95A04309291AD7E5EF1F1B26BFC1677053238CEBE9EBB3E474B6B19EC586D7`.
- TimeQuest fully constrained for setup and hold; unconstrained clocks/ports/paths all 0.
- Clock-related warnings remain the known PLL/MCLK output-pin compensation and non-dedicated routing warnings, not timing failures.

Resource delta versus frozen Phase 1 reduced-voice baseline:

| Metric | Frozen Phase 1 | Observability | Delta |
| --- | ---: | ---: | ---: |
| Logic elements | 6,308 | 6,515 | +207 |
| Dedicated registers | 2,394 | 2,523 | +129 |
| Memory bits | 266,752 | 266,752 | 0 |
| M9Ks | 33 | 33 | 0 |
| DSP9 elements | 2 | 2 | 0 |
| PLLs | 1 | 1 | 0 |

Timing delta versus frozen Phase 1 reduced-voice baseline:

| Metric | Frozen Phase 1 | Observability | Delta |
| --- | ---: | ---: | ---: |
| Slow 85C `sys_clk_50m` setup slack | +1.234 ns | +0.889 ns | -0.345 ns |
| Slow 85C `sys_clk_50m` hold slack | +0.429 ns | +0.432 ns | +0.003 ns |
| Slow 85C `sys_clk_50m` Fmax | 53.29 MHz | 52.33 MHz | -0.96 MHz |
| Slow 85C `i2c_clk` setup slack | n/a | +17.615 ns | pass |
| Slow 85C `audio_bclk` setup slack | n/a | +314.022 ns | pass |

Mapping checks:

- The reduced voice delay line remains M9K-backed: two inferred simple-dual-port M9K RAMs, 128 x 18 each.
- The reduced voice multiplier remains mapped to embedded DSP resources: `lpm_mult:Mult0`, 2 DSP elements / 2 DSP9 elements.
- Memory, M9K, DSP9, and PLL counts are unchanged from the frozen Phase 1 reference.

## Hardware Results

Programming:

- USB-Blaster detected as `USB-Blaster [USB-0]`.
- Programmed `quartus/phase0/output_files/piano_phase0_top.sof` successfully.
- Programmer confirmed checksum `0x004DD5CF` for EP4CE10F17.
- Log: `reports/phase1_observability_validation_quartus_pgm.log`.

UART on `COM4`:

- Post-program reset sequence observed: `I=50303031`, `S=8018073F`.
- First post-trigger debug group: `R=8018077F`, `V=00000011`, `F=000000E5`, `T=00000001`, `A=000000C0`, `W=00000177`.
- Later settled groups: `V=08220010`, `T=00000001`, `A=000172B3`, and advancing `F/W` counters.
- `V=08220010` decodes as peak `0x0822` / 2082, voice enabled, not active, not busy, no clip.
- `A=0x000172B3` is 94,899 active valid samples, about 2.02 s at the 46.875 kHz audio sample cadence.
- UART capture: `reports/phase1_observability_validation_uart_capture.txt`.

External audio capture:

- Capture: `reports/phase1_observability_validation_capture_external.wav`.
- Device path: PC external mic-jack capture path, stereo, 48 kHz, 16-bit PCM, 13.988 s.
- Event onset: about 2.580 s after capture start.
- L channel: f0 `436.110 Hz`, early RMS `0.012367`, peak `0.038910`, 0 clipped samples.
- R channel: f0 `436.044 Hz`, early RMS `0.007398`, peak `0.021729`, 0 clipped samples.
- L/R frequency delta: `0.066 Hz`.
- L/R early RMS balance: L is `+4.463 dB` hotter than R; this is consistent with the known analog/capture wiring imbalance and not a digital-path issue because the RTL transmits the same sample to both slots.
- Decay relative to the early 120 ms reference: `-9.53 dB` by 0.25 s, `-12.93 dB` by 0.50 s, then near capture noise floor.
- Non-square regression check: early mono crest factor `2.87`; higher odd harmonics roll off instead of staying square-wave-flat. H3/H5/H7 are `-9.2/-27.8/-37.4 dBc` on L and `-6.1/-23.0/-26.4 dBc` on R. The stronger H2 component is an analog/capture asymmetry marker, not a digital clipping marker.
- Analysis: `reports/phase1_observability_validation_capture_analysis.txt`.

## Residual Notes

- The PLL/MCLK output routing warnings should stay on the board-level constraint/watch list, but they are not new failures and TimeQuest is fully constrained with positive slack.
- Hardware audio analysis is limited by the external analog capture path and known L/R wiring imbalance. The digital L/R path is mono-identical by RTL inspection.
- The new counters are useful for the next scaling step: require each controlled experiment to report `V/F/T/A/W`, resource/timing deltas, and an external no-clip audio capture before accepting the scale-up.

