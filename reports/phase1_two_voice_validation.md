# Phase 1 Two-Voice Validation

Date: 2026-04-25
Verifier: verifier
Task: `task-ba10e41b`

## Verdict

PASS for software, simulation, fit, and timing validation. The Phase 1 two-voice slice stays within the authorized narrow scope, preserves the accepted register map through `0x50`, keeps synthesis hardware-owned rather than CPU-sample-driven, and remains fully constrained with comfortable positive timing.

Hardware smoke is not included in this pass because the board interfaces were unavailable at validation time: `quartus_pgm -l` reported `No JTAG hardware available`, and Windows reported no serial COM ports. This is a physical availability blocker, not a design failure.

Recommendation: freeze this as the current tool-validated two-voice feasibility baseline. Do not stop for architecture review. Run a deferred board smoke/audio capture when JTAG/UART are visible again before claiming hardware acceptance for this build.

## Scope Review

References reviewed:

- `reports/phase1_timing_margin_acceptance_decision.md`
- `reports/phase1_timing_margin_validation.md`
- `reports/phase1_two_voice_impl_report.md`
- current `rtl/`, `fw/phase0/`, and `docs/phase0_impl_notes.md`

Findings:

- The implementation adds a second `phase1_reduced_voice` instance only; no SDRAM, SD/sample playback, UI/TFT/touch, richer physics, larger CPU, exact-48-kHz clock work, or new bus fabric was found.
- `rtl/audio/phase0_audio_path.v` mixes voice0 and voice1 through a signed 17-bit sum, saturates to signed 16-bit output, and exposes sticky mix clip, mix clip count, and mix peak diagnostics.
- CPU ownership remains control/status/UART only. Firmware triggers each voice once after codec bring-up and then reports counters; it does not service per-sample synthesis.
- Registers through `0x50` are preserved. New two-voice registers start at `0x54` and are documented in both `fw/phase0/phase0_hw.h` and `docs/phase0_impl_notes.md`:
  `VOICE1_CONTROL` `0x54`, `VOICE1_STATUS` `0x58`, `VOICE1_TRIGGER_COUNT` `0x5C`, `VOICE1_ACTIVE_COUNT` `0x60`, `VOICE1_VALID_COUNT` `0x64`, `VOICE_MIX_STATUS` `0x68`, and `VOICE_MIX_CLIP_COUNT` `0x6C`.
- UART observability preserves `I/S/R/V/F/T/A/W` and appends `Y/U/B/C/M/K` for voice1 and mix diagnostics.
- Delay-line RTL remains synchronous with `(* ramstyle = "M9K" *)`; no async-read delay line was introduced.

## Regression Evidence

Firmware:

- Command: `fw/phase0/build.ps1`
- Result: PASS
- Log: `reports/phase1_two_voice_validation_fw_build.log`

ModelSim fresh-library regression:

- Compile: PASS, 0 errors / 0 warnings (`reports/phase1_two_voice_validation_msim_compile.log`).
- Standalone reduced voice TB: PASS, unchanged signature:
  `VOICE_TB_PASS first_nonzero_sample=106 freq=438.084112 rms_100ms=292.703180 rms_500ms=35.578467 rms_3s=0.000000 peak=2082`.
- Top happy path: PASS:
  `TB_PASS fabric_status=8019057f soc_status=037f write_count=18 dac_toggle_count=1304 voice_peak_level=2082 voice1_peak_level=2082 mix_peak_level=4164 voice_sample_count=517 voice_trigger_count=1 voice1_trigger_count=1 voice_active_count=358 voice1_active_count=358 voice_valid_count=516 voice1_valid_count=516 mix_clip_count=0 uart_capture_count=111`.
- Top NACK path: PASS:
  `TB_NACK_PASS fabric_status=6018053f soc_status=033f nack_count=1 stop_count=1`.

Quartus and TimeQuest:

- Full compile: PASS, 0 errors / 12 warnings (`reports/phase1_two_voice_validation_quartus_compile.log`).
- SOF checksum: `0x00553670`.
- SOF SHA-256: `274C3F3178A08E103B500E724ED15E5FDFF0E58D15DD0EFB94514BECC3523A78`.
- TimeQuest reports setup and hold fully constrained.
- Unconstrained clocks, ports, and paths are all 0 for setup and hold.
- All listed TNS values are `0.000`.
- Slow-85C `sys_clk_50m` Fmax is `62.33 MHz`.
- Worst slow-85C setup path remains RV32I writeback, not the voice datapath: `instr_reg[31]` to `wb_writeback_data_q[14]`, data delay `15.948 ns`, slack `+3.957 ns`.

## Resources And Timing

Resource delta versus accepted timing-margin baseline:

| Metric | Timing-Margin Baseline | Two-Voice Build | Delta |
| --- | ---: | ---: | ---: |
| Logic elements | 5,683 / 10,320 | 7,366 / 10,320 | +1,683 |
| Dedicated registers | 2,588 | 3,580 | +992 |
| Memory bits | 266,752 / 423,936 | 271,360 / 423,936 | +4,608 |
| M9Ks | 33 / 46 | 34 / 46 | +1 |
| DSP9 elements | 2 / 46 | 4 / 46 | +2 |
| PLLs | 1 / 2 | 1 / 2 | 0 |

Timing delta versus accepted timing-margin baseline:

| Metric | Timing-Margin Baseline | Two-Voice Build | Delta |
| --- | ---: | ---: | ---: |
| Slow-85C `sys_clk_50m` setup slack | +3.170 ns | +3.957 ns | +0.787 ns |
| Slow-85C `sys_clk_50m` hold slack | +0.432 ns | +0.432 ns | 0.000 ns |
| Slow-85C `sys_clk_50m` Fmax | 59.42 MHz | 62.33 MHz | +2.91 MHz |
| Slow-85C `i2c_clk` setup slack | +18.167 ns | +18.132 ns | -0.035 ns |
| Slow-85C `audio_bclk` setup slack | +315.933 ns | +313.716 ns | -2.217 ns |

The build remains below the experiment limit of 8,000 LEs by 634 LEs.

## Mapping Checks

- Fitter total M9K use is `34 / 46`.
- Voice0 and voice1 each infer two logical `128 x 18` simple-dual-port M9K delay memories. The fitter packs each voice's pair into one physical M9K location, so the duplicated voice increases total M9Ks by one.
- Total voice delay-line memory grows by `4,608` bits, matching two additional `128 x 18` logical memories for voice1.
- Quartus infers two signed `lpm_mult` blocks, one per voice, using `4` DSP9 elements total (`2` DSP9 per 18-bit signed multiplier).
- The expected RAM pass-through warnings remain because Quartus is matching synchronous read-during-write behavior; they are not async-read delay-line mappings.

## Hardware Status

Hardware validation could not run in this pass:

- `reports/phase1_two_voice_validation_quartus_pgm_list.log` records `No JTAG hardware available`.
- `reports/phase1_two_voice_validation_serial_ports.txt` records `(none)`.
- The board was therefore not programmed, no UART `Y/U/B/C/M/K` frames were captured, and no external audio capture was produced for this build.

Deferred hardware check when interfaces return:

- Program `quartus/phase0/output_files/piano_phase0_top.sof`.
- Capture UART at `115200 8N1` and confirm baseline `I/S/R/V/F/T/A/W` plus new `Y/U/B/C/M/K`; expected trigger counts are `T=1`, `U=1`, and `K=0` for the current simultaneous two-voice firmware.
- Capture analog audio and confirm no clipping, no square-wave regression, and two-voice overlap/saturation behavior consistent with the simulated mix peak doubling.

## Residual Risks

- Hardware audio and UART behavior for this exact SOF remain unverified because JTAG and COM interfaces were absent.
- The slice proves duplicated simultaneous reduced voices only. It is not a scheduler, pitch system, pedal/damper model, or broader polyphony architecture.
- The design is now at 71% LE utilization and 74% physical M9K utilization. This is acceptable for the controlled two-voice experiment, but further voice scaling should be treated as an architecture decision rather than a simple duplication exercise.
