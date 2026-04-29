# Phase 1C-B Body-Pipe Optimization Implementation Report

Date: 2026-04-28
Agent: Codex implementer
Task: `task-81201ceb`

## Verdict

PASS, with an explicit resource tradeoff.

The reduced-voice body pipe is now stored in synchronous circular tap RAM instead of a 32-entry shifting register pipe. Standalone voice behavior is bit-exact against a 4096-sample golden trace generated from the accepted Phase 1C-A RTL, and the top-level two-voice happy/NACK signatures are preserved.

This reduces total LE use by `908` and dedicated registers by `832` versus the Phase 1C-A baseline. It intentionally spends `2` extra M9Ks, one per voice, because the new body tap history maps to M9K-backed storage. Existing delay-line M9K mapping and multiplier DSP mapping remain intact.

No third voice, scheduler, SDRAM, richer physics, coefficient/default change, sample playback, UI, larger CPU, clock/PLL/sample-rate change, register-map expansion, UART expansion, ROM/RAM change, or unrelated cleanup was added.

## Changed Files

- `rtl/audio/phase1_reduced_voice.v`
- `rtl/audio/phase1_reduced_voice_tb.v`
- `rtl/audio/phase1_reduced_voice_golden_samples.hex`
- `reports/phase1c_body_pipe_optimization_impl_report.md`

Generated validation collateral was refreshed under `fw/phase0/build/`, `phase0_fw.mif`, `quartus/phase0/`, `phase1c_bodypipe_work/`, and `reports/phase1c_body_pipe_*`.

## Storage Change

Old body-pipe state:

- `reg signed [17:0] body_pipe [0:31]`
- 32 sample-history entries, `576` flip-flops per voice before synthesis packing.
- Every output sample shifted all 32 entries.
- Only `body_pipe[6]`, `body_pipe[16]`, and `body_pipe[30]` fed the body coloration mix.

New body-tap state:

- `(* ramstyle = "M9K" *) reg signed [17:0] body_history [0:31]`
- one 32 x 18 synchronous circular RAM per voice
- a 5-bit write pointer records the current `disp_sample`
- synchronous tap reads use pre-write offsets `wr_ptr - 7`, `wr_ptr - 17`, and `wr_ptr - 31`, preserving the exact old `body_pipe[6]`, `[16]`, and `[30]` values seen by the mix for the current sample
- body mix arithmetic is unchanged:
  `(tap6 >>> 2) - (tap16 >>> 3) + (tap30 >>> 4)`, then scaled by `body_mix_q15`

The added wait/capture states fit inside the existing `sample_tick` interval; sample-valid count and top-level counters remain unchanged.

## Validation

Firmware:

- Firmware build: PASS (`reports/phase1c_body_pipe_fw_build.log`).

Standalone voice:

- Golden trace generation from the pre-optimization Phase 1C-A RTL: PASS (`reports/phase1c_body_pipe_golden_write.log`).
- Post-optimization voice regression: PASS with exact 4096-sample golden comparison and unchanged signature (`reports/phase1c_body_pipe_msim_voice.log`):
  `VOICE_TB_PASS first_nonzero_sample=106 freq=438.084112 rms_100ms=292.703180 rms_500ms=35.578467 rms_3s=0.000000 peak=2082 golden_samples=4096`

ModelSim top:

- Full compile: PASS, `0` errors / `0` warnings (`reports/phase1c_body_pipe_msim_compile.log`).
- Happy path: PASS, unchanged two-voice/mix signature (`reports/phase1c_body_pipe_msim_happy.log`):
  `voice_peak_level=2082`, `voice1_peak_level=2082`, `mix_peak_level=4164`, `mix_clip_count=0`, `uart_capture_count=111`.
- NACK path: PASS (`reports/phase1c_body_pipe_msim_nack.log`):
  `TB_NACK_PASS fabric_status=6018053f soc_status=033f nack_count=1 stop_count=1`.

Quartus and TimeQuest:

- Full compile: PASS, `0` errors / `12` warnings (`reports/phase1c_body_pipe_quartus_compile.log`).
- SOF SHA-256: `48BAB4ACBAD44899E5FB8E25B89496B4E4A8C1AFEF0CF110178EB8C481849510`.
- Programmer checksum: `0x0050ADE7`.
- Slow 85C setup slack: `sys_clk_50m +3.907 ns`, `i2c_clk +18.101 ns`, `audio_bclk +315.561 ns`.
- Slow 85C hold slack: `sys_clk_50m +0.432 ns`, `audio_bclk +0.453 ns`, `i2c_clk +0.453 ns`.
- Slow 85C Fmax: `sys_clk_50m 62.14 MHz`, `i2c_clk 178.48 MHz`, `audio_bclk 28.13 MHz`.

Hardware smoke:

- USB-Blaster detected (`reports/phase1c_body_pipe_quartus_pgm_list.log`).
- Programming succeeded twice, including during audio capture (`reports/phase1c_body_pipe_quartus_pgm.log`).
- UART on `COM5`, `115200 8N1`, captured recurring two-voice diagnostics (`reports/phase1c_body_pipe_uart_capture.txt`):

```text
R=8018077F
V=08220010
T=00000001
Y=08220010
U=00000001
M=10440010
K=00000000
```

- External Realtek audio capture: PASS (`reports/phase1c_body_pipe_audio_capture.wav`, `reports/phase1c_body_pipe_audio_analysis.txt`).
- Audio analysis: event onset `3.290 s`, mono F0 `436.363636 Hz`, mono early crest factor `3.478157`, total clipped samples `0`, and decay `-19.12 dB` by `0.50 s`.

## Resource Delta

Delta is versus the accepted Phase 1C-A ROM/RAM right-sized baseline.

| Metric | Phase 1C-A | Phase 1C-B | Delta |
| --- | ---: | ---: | ---: |
| Logic elements | 7,382 / 10,320 | 6,474 / 10,320 | -908 |
| Dedicated registers | 3,580 | 2,748 | -832 |
| Memory bits | 74,752 / 423,936 | 75,776 / 423,936 | +1,024 |
| M9Ks | 10 / 46 | 12 / 46 | +2 |
| DSP9 elements | 4 / 46 | 4 / 46 | 0 |
| PLLs | 1 / 2 | 1 / 2 | 0 |
| Slow 85C `sys_clk_50m` setup slack | +3.214 ns | +3.907 ns | +0.693 ns |
| Slow 85C `sys_clk_50m` hold slack | +0.433 ns | +0.432 ns | -0.001 ns |
| Slow 85C `sys_clk_50m` Fmax | 59.57 MHz | 62.14 MHz | +2.57 MHz |

Per-voice hierarchy:

| Block | Phase 1C-A | Phase 1C-B | Delta |
| --- | ---: | ---: | ---: |
| Voice 0 logic cells | 1,327 | 864 | -463 |
| Voice 1 logic cells | 1,334 | 869 | -465 |
| Per-voice registers | 843 | 427 | -416 |
| Per-voice memory bits | 4,608 | 5,120 | +512 |
| Per-voice M9Ks | 1 | 2 | +1 |
| Per-voice DSP elements | 2 | 2 | 0 |

## Mapping Check

Preserved mapping:

- each reduced voice still contains the original synchronous delay-line M9K implementation
- each reduced voice still maps its signed 18-bit multiplier to `2` DSP elements / `1` DSP18x18
- boot ROM remains `1024 x 32`, `4` M9Ks
- data RAM remains `1024 x 32`, `4` M9Ks

Intentional new mapping:

- each reduced voice now has one additional M9K-backed `body_history` memory (`512` implementation bits, `1` M9K)

## Residual Notes

The optimization is behavior-preserving and materially reduces LE/register pressure, which is the relevant bottleneck for later scaling. The cost is two extra M9Ks. Because Phase 1C-A recovered substantial M9K headroom, total M9K use remains modest at `12 / 46`, but this should still be treated as an explicit acceptance decision rather than hidden overhead.

If the project later requires zero additional M9Ks, this exact implementation should not be promoted; the Phase 1C-A baseline remains the rollback point.
