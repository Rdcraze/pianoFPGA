# Phase 1 Reduced Voice Validation

Date: `2026-04-24`  
Task: `task-42106eb1`  
Dependency: `task-9fb09496`

## Findings

- No blocking verifier findings. Verdict: PASS. Recommendation: freeze this as the Phase 1 reference baseline; do not expand features until the baseline is recorded.
- The live sample source is hardware-owned. `phase1_reduced_voice` advances from `sample_tick`, owns the delay-line/excitation/filter/body/clip/peak path, and emits `sample_valid`/`tx_sample` directly into the codec path. Firmware only writes defaults, performs codec follow-on writes, and pulses `VOICE_CONTROL.trigger`; it does not synthesize per-sample audio.
- Hardware audio evidence confirms the user-facing behavior changed from the old continuous square tone to a short, decaying A4-like struck-string/plucked-string tone. Clean run-2 capture measured `437.10 Hz` mono, `436.28 Hz` L, `439.75 Hz` R, attack-to-peak about `10 ms`, no full-scale clipping, and about `-21 dB` decay by `1-2 s`.
- Timing/resource scaling is acceptable. The design fits at `6308 / 10320` LEs and closes TimeQuest at slow-85C with `sys_clk_50m` setup slack `+1.234 ns`, TNS `0.000 ns`; reported `sys_clk_50m` Fmax is `53.29 MHz`.
- The delay line is synchronous RAM/M9K-backed. Quartus inferred `altsyncram` for both `128 x 18` logical delay RAM halves with `RAM_BLOCK_TYPE = M9K`; fitter reports `33 / 46` M9Ks total, with the two logical delay memories packed into one physical M9K location. The earlier async-read `8889`-LE failure mode is gone; current fit is `6308` LEs.
- The new `18 x 16` voice multiply maps into embedded multipliers, not LUT logic. Fitter DSP details show `lpm_mult:Mult0` as a signed simple multiplier using one 18-bit DSP block / `2` DSP9 elements; total DSP9 remains `2 / 46`.
- Non-blocking diagnostic caveat: live UART confirms boot/status cadence but firmware still prints only combined `STATUS`, not the full `VOICE_STATUS` peak/clip word. Clip/peak are covered by ModelSim and analog capture in this validation, but a future debug frame for `VOICE_STATUS` would improve field observability.

## Evidence

Firmware and simulation:

| Check | Result |
| --- | --- |
| Firmware build | PASS, regenerated `phase0.elf`, `phase0.bin`, `phase0.mem`, `phase0.mif` |
| ModelSim compile | PASS, `0` errors, `0` warnings |
| Standalone voice TB | `VOICE_TB_PASS first_nonzero_sample=106 freq=438.084112 rms_100ms=292.703180 rms_500ms=35.578467 rms_3s=0.000000 peak=2082` |
| Top happy path | `TB_PASS fabric_status=8019077f soc_status=037f write_count=18 dac_toggle_count=1243 voice_peak_level=2082 uart_capture_count=36` |
| Top NACK path | `TB_NACK_PASS fabric_status=6018073f soc_status=033f nack_count=1 stop_count=1` |

Quartus and timing:

| Metric | Phase 0 board-I/O baseline | Phase 1 verified | Delta |
| --- | ---: | ---: | ---: |
| Logic elements | `4796 / 10320` | `6308 / 10320` | `+1512` |
| Registers | `1520` | `2394` | `+874` |
| Memory bits | `262144 / 423936` | `266752 / 423936` | `+4608` |
| M9Ks | inferred `32 / 46` | `33 / 46` | `+1` |
| DSP9 elements | `2 / 46` | `2 / 46` | `0` |
| PLLs | `1 / 2` | `1 / 2` | `0` |

Slow 1200 mV 85C timing:

| Clock | Setup slack | Setup TNS | Hold slack | Hold TNS |
| --- | ---: | ---: | ---: | ---: |
| `sys_clk_50m` | `+1.234 ns` | `0.000 ns` | `+0.429 ns` | `0.000 ns` |
| `i2c_clk` | `+18.044 ns` | `0.000 ns` | `+0.452 ns` | `0.000 ns` |
| `audio_bclk` | `+315.774 ns` | `0.000 ns` | `+0.451 ns` | `0.000 ns` |

Representative timing categories:

| Category | Worst observed setup path | Slack |
| --- | --- | ---: |
| RV32I/writeback | `instr_reg[15] -> wb_writeback_data_q[9]` | `+1.234 ns` |
| Voice datapath | `mult_coeff[12] -> output_sample_q18[*]` | `+4.757 ns` |
| RAM/delay-line | delay-line RAM address reg -> `mult_sample[*]` | `+6.606 ns` |
| Bus/control | `phase0_control_regs.audio_enable -> voice body_pipe[*]` | `+8.691 ns` |
| Codec/audio boundary | `audio_dacdat -> audio_dacdat` output path | `+315.774 ns` |

TimeQuest reports zero illegal/unconstrained clocks, ports, and I/O paths for setup and hold, and reports the design fully constrained. The inherited `audio_mclk` PLL compensation/non-dedicated-routing warnings remain documented Phase 0 clocking caveats, not Phase 1 timing failures.

Hardware run:

- JTAG cable: `USB-Blaster [USB-0]`; JTAG ID `0x020F10DD`.
- Programmed SOF checksum: `0x004C7C05`; SHA-256 `3C2D80FCF5CE4579C2E9AB9F3EC1922BEC0BB3306D30EC0907E64810C4D55C62`.
- UART run 2 on `COM4`, `115200 8N1`:

```text
R=8018077F
I=50303031
S=8018073F
R=8018077F
R=8018077F
R=8018077F
R=8018077F
R=8018077F
R=8018077F
```

The first `R` is the already-running pre-reprogram status; the `I/S/R` sequence after JTAG confirms the regenerated SOF booted and firmware reached the runtime reporting loop.

External stereo audio run 2:

| Metric | Result |
| --- | ---: |
| Capture | `48000 Hz`, 2 channels, `11.988 s` |
| Chosen post-JTAG event | `2.555 s` to `2.610 s` above threshold |
| Attack-to-peak | `10.000 ms` |
| Fundamental, mono | `437.099 Hz` |
| Fundamental, L/R | `436.277 Hz` / `439.750 Hz` |
| L/R RMS balance, early event | L over R `-0.998 dB` |
| Clipping | `0` exact rail samples; near-full-scale fraction `0.00000000` both channels |
| Decay | `-18.37 dB` by `0.50 s`; `-21.12 dB` by `1.00 s`; `-21.03 dB` by `2.00 s` |

The early spectrum is not the old odd-harmonic square signature. Run 2 shows a decaying transient with dominant fundamental and progressively lower high harmonics; the second harmonic is present (`-4.95 dB` L, `-2.66 dB` R), consistent with the reduced/body-colored transient and analog capture path rather than a pure square-wave baseline.

## Residual Risks

- The current UART firmware does not emit `VOICE_STATUS` or peak meter directly. This does not block Phase 1 freeze, but it should be considered before relying on UART-only field diagnostics.
- The hardware audio evidence is through the PC Realtek analog capture path, so exact amplitude, phase, and harmonic ratios include codec/headphone/cable/input effects. Frequency, decay, and clipping conclusions are still robust.
- The inherited Phase 0 board-I/O timing caveats remain: `audio_mclk`, I2C, UART, and async reset are explicit exclusions where local collateral lacks defensible board-level aperture/skew data.
- Phase 1 remains intentionally fixed-note, single-voice, no-polyphony, no-pedal, no-UI, no-sample-playback, and no exact-48-kHz rework.

## Artifacts

- `reports/phase1_reduced_voice_fw_build.log`
- `reports/phase1_reduced_voice_msim_compile.log`
- `reports/phase1_reduced_voice_msim_voice.log`
- `reports/phase1_reduced_voice_msim_happy.log`
- `reports/phase1_reduced_voice_msim_nack.log`
- `reports/phase1_reduced_voice_quartus_compile.log`
- `reports/phase1_reduced_voice_sta_voice_setup.rpt`
- `reports/phase1_reduced_voice_sta_delay_setup.rpt`
- `reports/phase1_reduced_voice_sta_control_setup.rpt`
- `reports/phase1_reduced_voice_sta_codec_setup.rpt`
- `reports/phase1_reduced_voice_quartus_pgm_run2.log`
- `reports/phase1_reduced_voice_uart_capture_run2.txt`
- `reports/phase1_reduced_voice_capture_external_run2.wav`
- `reports/phase1_reduced_voice_capture_run2_analysis.txt`
- `reports/phase1_reduced_voice_capture_run2_envelope_50ms.txt`
