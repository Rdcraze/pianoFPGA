# Phase 1C Third-Voice Validation

Date: 2026-04-28
Agent: Codex verifier
Task: `task-f1a5b36e`

## Verdict

PASS.

The narrow third-voice feasibility slice stays inside the authorization: it adds one optimized reduced voice, preserves the Phase 1C-B register map through `0x6C`, appends only voice2 diagnostics at `0x70` through `0x80`, preserves the existing UART frame order through `K`, and keeps clocking, CPU/ISA, ROM/RAM sizing, sample rate, codec path, coefficients, and defaults unchanged.

Recommendation: promote this build only as a narrow three-voice feasibility baseline after orchestrator acceptance. This PASS does not authorize scheduler/note allocation, a fourth voice, SDRAM, richer physics, UI, sample playback, clock work, CPU expansion, diagnostic removal, or broad register/UART churn.

## References

- `reports/phase1c_third_voice_authorization_decision.md`
- `reports/phase1c_body_pipe_optimization_acceptance_decision.md`
- `reports/phase1c_third_voice_impl_report.md`

## Scope And Compatibility Checks

- Existing firmware register offsets remain unchanged through `PHASE0_REG_VOICE_MIX_CLIP_COUNT` at `0x6C`.
- New additive voice2 registers are `0x70` control, `0x74` status, `0x78` trigger count, `0x7C` active count, and `0x80` valid count.
- Firmware still emits existing post-startup UART frames in order: `V,F,T,A,W,Y,U,B,C,M,K`.
- New UART frames are appended after `K`: `Z` voice2 status, `O` voice2 trigger count, `D` voice2 active count, `E` voice2 valid count.
- Firmware still triggers after codec initialization and the two codec output-gain writes; there is no CPU sample loop, scheduler, allocator, or note-event architecture.
- The mix path sign-extends three voice samples to 18 bits and explicitly saturates to signed 16-bit output.

## Simulation And Firmware

Firmware build passed: `reports/phase1c_third_voice_fw_build.log`.

ModelSim evidence:

| Check | Result | Evidence |
| --- | --- | --- |
| Standalone reduced voice regression | PASS | `VOICE_TB_PASS ... peak=2082 golden_samples=4096` |
| Top happy path | PASS | three voice peaks `2082`, expected mix peak `6246`, mix peak `6246`, trigger counts all `1`, active counts nonzero |
| Unexpected default mix clipping | PASS | `mix_clip_count=0` |
| NACK regression | PASS | `TB_NACK_PASS fabric_status=6018053f soc_status=033f nack_count=1 stop_count=1` |

Relevant logs:

- `reports/phase1c_third_voice_msim_voice.log`
- `reports/phase1c_third_voice_msim_happy.log`
- `reports/phase1c_third_voice_msim_nack.log`

## Resource And Timing Delta

SOF SHA-256: `91784AE1B85E69F989D4CD09273466E14A6FAB66A557AD8ACDA296F990A07A0E`

Programmer checksum: `0x005B2137`

Delta is versus the accepted Phase 1C-B body-pipe baseline.

| Metric | Phase 1C-B Accepted | Third-Voice Build | Delta |
| --- | ---: | ---: | ---: |
| Logic elements | 6,474 / 10,320 | 7,548 / 10,320 | +1,074 |
| Dedicated registers | 2,748 | 3,275 | +527 |
| Memory bits | 75,776 / 423,936 | 80,896 / 423,936 | +5,120 |
| M9Ks | 12 / 46 | 14 / 46 | +2 |
| DSP9 elements | 4 / 46 | 6 / 46 | +2 |
| PLLs | 1 / 2 | 1 / 2 | 0 |
| Slow-85C `sys_clk_50m` setup slack | +3.907 ns | +3.675 ns | -0.232 ns |
| Slow-85C `sys_clk_50m` hold slack | +0.432 ns | +0.433 ns | +0.001 ns |
| Slow-85C `sys_clk_50m` Fmax | 62.14 MHz | 61.26 MHz | -0.88 MHz |

Stop criteria:

| Criterion | Required | Observed | Result |
| --- | ---: | ---: | --- |
| LE use | `<= 8,200 / 10,320` | `7,548 / 10,320` | PASS |
| Slow-85C `sys_clk_50m` setup slack | `>= +1.0 ns` | `+3.675 ns` | PASS |
| Setup/hold constrained | fully constrained | fully constrained | PASS |
| Listed TNS | `0.000` | `0.000` for all listed checks | PASS |

Quartus full compilation passed with `0` errors and `14` warnings. TimeQuest reports setup and hold as fully constrained.

## M9K And DSP Mapping

Fitter evidence preserves the expected storage and multiplier mapping:

- Boot ROM remains `1024 x 32`, using `4` M9Ks.
- Data RAM remains `1024 x 32`, using `4` M9Ks.
- The three reduced voices each have body-history storage plus delay-line storage in M9K-backed RAM. The delay-line pair for each voice is physically packed at a shared M9K location, giving `6` physical voice M9Ks total and `14 / 46` total M9Ks.
- DSP summary shows `3` signed simple 18-bit multipliers, using `6 / 46` DSP9 elements.

Evidence is in `quartus/phase0/output_files/piano_phase0_top.fit.rpt`.

## Hardware Smoke

Independent verifier hardware smoke passed.

JTAG/programming:

- USB-Blaster detected: `reports/phase1c_third_voice_validation_pgm_list.log`
- Programming passed on `EP4CE10F17@1`, JTAG ID `0x020F10DD`: `reports/phase1c_third_voice_validation_pgm.log`
- Programmed checksum: `0x005B2137`

UART capture:

- Port: `COM5`, `115200 8N1`
- Evidence: `reports/phase1c_third_voice_validation_uart_capture.txt`
- Existing frames are present through `K`; appended `Z/O/D/E` voice2 frames follow.
- Steady captured signature:

```text
R=8018077F
V=08220010
T=00000001
Y=08220010
U=00000001
M=18660010
K=00000000
Z=08220010
O=00000001
D=000172B3
E=00022473
```

Interpretation:

- Voice0/voice1/voice2 peaks are `0x0822` (`2082`).
- Mix peak is `0x1866` (`6246`), matching `2082 * 3`.
- Voice2 trigger count is `1`.
- Mix clip count is `0`.

Audio capture:

- Evidence WAV: `reports/phase1c_third_voice_validation_audio_capture.wav`
- Analysis: `reports/phase1c_third_voice_validation_audio_analysis.txt`
- Duration: `11.985 s`
- Event onset: `3.837 s`
- Early RMS: `0.02897325`
- Early peak: `0.14695740`
- Crest factor: `5.072`
- Dominant spectral peak: about `435.9 Hz`
- Autocorrelation F0 estimate: `436.385 Hz`
- Total clipped PCM samples: `0`

Against the accepted Phase 1C-B verifier audio capture, the same analyzer reports the third-voice capture at `+3.37 dB` RMS with `0` clipped samples. That is consistent with the expected louder three-voice default smoke and does not indicate saturation.

## Residual Risks

- This proves one fixed simultaneous third voice, not note allocation or real polyphony management.
- The UART stream is prefix-compatible through existing frames, but consumers that assumed a fixed total frame set must tolerate the appended voice2 diagnostics.
- The third voice costs `+1,074` LEs, `+2` DSP9 elements, and `+2` M9Ks versus Phase 1C-B. Remaining headroom is acceptable for this slice, but it should not be treated as evidence that a fourth voice or richer model is safe.
- Hardware smoke is a focused UART/audio check, not a full analog quality or long-duration stress test.

