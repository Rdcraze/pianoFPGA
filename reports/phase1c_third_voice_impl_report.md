# Phase 1C Third-Voice Implementation Report

Date: 2026-04-28
Agent: Codex implementer
Task: `task-6dcb6013`

## Verdict

PASS.

The narrow third-voice feasibility slice instantiates one additional optimized reduced voice, triggers all three voices from the existing post-codec firmware path, mixes three signed 16-bit voice samples with explicit signed saturation, and appends only the minimum voice2 diagnostics after the existing UART frame sequence.

The implementation stays inside the authorized scope: no scheduler, note allocator, fourth voice, SDRAM, richer physics, coefficient/default change, sample playback, UI, CPU/ISA expansion, clock/PLL/sample-rate change, ROM/RAM sizing change, diagnostic removal, or unrelated cleanup was added.

## Changed Files

- `rtl/audio/phase0_audio_path.v`
- `rtl/control/phase0_control_regs.v`
- `rtl/top/piano_phase0_top.v`
- `rtl/top/piano_phase0_top_tb.v`
- `fw/phase0/phase0_hw.h`
- `fw/phase0/phase0_main.c`
- `reports/phase1c_third_voice_impl_report.md`

Generated validation collateral was refreshed under `fw/phase0/build/`, `phase0_fw.mif`, `quartus/phase0/`, `phase1c_thirdvoice_work/`, and `reports/phase1c_third_voice_*`.

## Register And UART Additions

Existing registers through `0x6C` are unchanged.

New additive registers:

| Offset | Name | Notes |
| --- | --- | --- |
| `0x70` | `PHASE0_REG_VOICE2_CONTROL` | bit0 enable, bit1 trigger, bit2 reset, bit8 clip clear |
| `0x74` | `PHASE0_REG_VOICE2_STATUS` | same status layout as voice0/voice1 |
| `0x78` | `PHASE0_REG_VOICE2_TRIGGER_COUNT` | voice2 trigger count |
| `0x7C` | `PHASE0_REG_VOICE2_ACTIVE_COUNT` | voice2 active sample count |
| `0x80` | `PHASE0_REG_VOICE2_VALID_COUNT` | voice2 valid sample count |

Existing UART frames remain in their previous order:

`V, F, T, A, W, Y, U, B, C, M, K`

New frames are appended after `K`:

`Z` = voice2 status, `O` = voice2 trigger count, `D` = voice2 active count, `E` = voice2 valid count.

## Trigger And Mix Behavior

Firmware still waits for codec initialization and writes the two codec output-gain registers before triggering voices. It now issues one-shot trigger strobes for voice0, voice1, and voice2. After those strobes, all three reduced-voice engines run autonomously in the hardware sample path; there is no CPU sample-loop involvement and no scheduler or allocator.

The mix path now sign-extends all three 16-bit voice samples to 18 bits:

- `voice0_mix_ext`
- `voice1_mix_ext`
- `voice2_mix_ext`

The three-way sum is saturated explicitly to signed 16-bit output range before driving `tx_sample`. Default smoke behavior produces the expected three-voice peak of `6246` (`2082 * 3`) with `mix_clip_count=0`.

## Validation

Firmware:

- Firmware build: PASS (`reports/phase1c_third_voice_fw_build.log`)
- ROM image size: `241` words / `1024` configured words

ModelSim:

- Compile: PASS, `0` errors / `0` warnings (`reports/phase1c_third_voice_msim_compile.log`)
- Standalone reduced voice: PASS (`reports/phase1c_third_voice_msim_voice.log`)
  - `VOICE_TB_PASS first_nonzero_sample=106 freq=438.084112 rms_100ms=292.703180 rms_500ms=35.578467 rms_3s=0.000000 peak=2082 golden_samples=4096`
- Top happy path: PASS (`reports/phase1c_third_voice_msim_happy.log`)
  - `voice_peak_level=2082`
  - `voice1_peak_level=2082`
  - `voice2_peak_level=2082`
  - `expected_mix_peak=6246`
  - `mix_peak_level=6246`
  - `voice_trigger_count=1`, `voice1_trigger_count=1`, `voice2_trigger_count=1`
  - `mix_clip_count=0`
- NACK path: PASS (`reports/phase1c_third_voice_msim_nack.log`)
  - `TB_NACK_PASS fabric_status=6018053f soc_status=033f nack_count=1 stop_count=1`

Quartus and TimeQuest:

- Full compile: PASS, `0` errors / `14` warnings (`reports/phase1c_third_voice_quartus_compile.log`)
- SOF SHA-256: `91784AE1B85E69F989D4CD09273466E14A6FAB66A557AD8ACDA296F990A07A0E`
- Programmer checksum: `0x005B2137`
- TimeQuest setup/hold fully constrained.
- All listed TNS values are `0.000`.

## Resource Delta

Delta is versus the accepted Phase 1C-B baseline.

| Metric | Phase 1C-B Baseline | Third-Voice Build | Delta |
| --- | ---: | ---: | ---: |
| Logic elements | 6,474 / 10,320 | 7,548 / 10,320 | +1,074 |
| Dedicated registers | 2,748 | 3,275 | +527 |
| Memory bits | 75,776 / 423,936 | 80,896 / 423,936 | +5,120 |
| M9Ks | 12 / 46 | 14 / 46 | +2 |
| DSP9 elements | 4 / 46 | 6 / 46 | +2 |
| PLLs | 1 / 2 | 1 / 2 | 0 |
| Slow 85C `sys_clk_50m` setup slack | +3.907 ns | +3.675 ns | -0.232 ns |
| Slow 85C `sys_clk_50m` hold slack | +0.432 ns | +0.433 ns | +0.001 ns |
| Slow 85C `sys_clk_50m` Fmax | 62.14 MHz | 61.26 MHz | -0.88 MHz |

Stop criteria status:

- LE use is below `8,200`: PASS (`7,548`)
- `sys_clk_50m` setup slack is above `+1.0 ns`: PASS (`+3.675 ns`)
- setup/hold are fully constrained: PASS
- listed TNS is zero: PASS
- existing register/UART compatibility through Phase 1C-B map is preserved: PASS
- default mix clips unexpectedly: PASS, no clipping observed

## Mapping Check

Preserved mapping:

- Boot ROM remains `1024 x 32`, `4` M9Ks.
- Data RAM remains `1024 x 32`, `4` M9Ks.
- Each reduced voice still uses synchronous M9K-backed delay-line storage.
- Each reduced voice still maps `Mult0` to a signed 18-bit simple multiplier using `2` DSP9 elements.

New expected mapping:

- The added voice2 contributes one body-history RAM and the existing delay-line RAM pair, fitting as `2` additional physical M9Ks.
- Total reduced-voice multiplier use is now `6` DSP9 elements for three voices.

## Hardware Smoke

JTAG:

- USB-Blaster detected (`reports/phase1c_third_voice_quartus_pgm_list.log`)
- Programming succeeded on `EP4CE10F17@1` (`reports/phase1c_third_voice_quartus_pgm.log`)
- Programming during audio capture also succeeded (`reports/phase1c_third_voice_quartus_pgm_during_audio.log`)

UART:

- COM5, `115200 8N1`, captured recurring diagnostics (`reports/phase1c_third_voice_uart_capture.txt`)
- Capture begins mid-stream with a few partial bytes, then clean frames follow:

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
E=00176F01
```

Audio:

- External Realtek capture succeeded (`reports/phase1c_third_voice_audio_capture.wav`, `reports/phase1c_third_voice_audio_ffmpeg.log`)
- Analysis result (`reports/phase1c_third_voice_audio_analysis.txt`):
  - event onset `4.900 s`
  - mono F0 `433.333333 Hz`
  - mono early RMS `0.03412067`
  - mono early peak `0.13191223`
  - mono crest factor `3.866051`
  - total clipped samples `0`
  - decay at `0.50 s`: `-20.43 dB` relative to the event reference

## Residual Notes

This build is a feasibility result, not an automatic baseline replacement. It demonstrates that a third duplicated optimized reduced voice fits below the authorized LE and timing limits with clean sim and hardware smoke. Acceptance should still be decided separately by the orchestrator/verifier.
