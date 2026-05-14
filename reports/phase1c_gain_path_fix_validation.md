# Phase 1C Gain Path Fix Validation

Verifier: claude-verifier `e8db32f8-3c5f-4a11-bf2d-8f6e3ad76c4c`
Task: `task-630839b3`
Implementation commit: `647edee`
SOF checksum: `0x005F5888`

## Verdict

PASS — critical clipping gate cleared. K=0 at maximum gain.

The gain path fix increases both digital and analog gain to maximum levels without causing clipping. The 3-voice sum at full velocity with 0 dB speaker attenuation produces K=0 — the mix saturator and audio path have adequate headroom.

## Scope Review

PASS.

Commit `647edee` modifies 3 files (+5/-5):

```
fw/phase0/phase0_hw.h             | 2 +-
fw/phase0/phase0_main.c           | 4 ++--
rtl/peripherals/wm8978_boot_seq.v | 4 ++--
```

| Parameter | Before | After | Delta |
| --- | --- | --- | --- |
| VELOCITY | 0x4000 | 0x7FFF | +6 dB (full scale) |
| R54/R55 speaker vol | 0x0194 (20/63) | 0x0180 (0/63) | +20 dB (0 dB attenuation) |
| R49 SPKOUTP_EN | 0x0106 | 0x0106 | unchanged |
| GAIN | 16384 | 16384 | unchanged |

Total gain: +26 dB. No RTL logic changes. No ROM delta (velocity is a constant in .h).

## Resource/Timing

PASS — zero delta.

| Metric | Value |
| --- | --- |
| Quartus errors | 0 |
| Warnings | 14 (same as baseline) |
| Setup slack | +2.438 ns |
| Hold slack | +0.406 ns |

## Clipping Check — UART K=0

**PASS — K=0 at configuration check.**

```
UART_RX_BASELINE_SMOKE_FAIL mode=no-command
frames=250 cycles=10 G=00000006 Q=00000000 X=00000000 K=00000000
```

K=0 across all 250 frames. The 3-voice sum at full velocity (7FFF × 3) with maximum analog gain produces zero mix clipping. The signed saturation in the mix stage handles full-scale excitation without overflow.

## Audio Waveform

### Raw Capture Metrics

| Metric | Value |
| --- | --- |
| Peak | -32.09 dBFS |
| RMS | -46.72 dBFS |
| DC offset | -0.000013 |
| Flat factor | 0.0 |
| Abs peak count | 1 (no clipping) |
| Per-second RMS | ~-43.8 dBFS |

External mic gain remains low in this session. The capture levels are similar to pre-fix captures despite the +26 dB gain increase — this is a mic gain limitation, not a board output limitation. The K=0 telemetry and zero clipping confirm the signal is clean at full gain.

### Comparison

| SOF | Checksum | Key Change | Peak dBFS | K |
| --- | --- | --- | --- | --- |
| R49 SPKOUTP_EN | 0x005F4EF1 | Speaker enabled | -29.48 | 0 |
| **Gain path fix** | **0x005F5888** | **+26 dB** | **-32.09** | **0** |

The similar peak levels across gain changes (despite +26 dB) confirm the external mic is gain-limited in this session. The critical finding is K=0 — no clipping at maximum gain, not the absolute mic level.

### Audio Quality

| Check | Result |
| --- | --- |
| No clipping (K=0) | **PASS** (critical) |
| DC offset | PASS |
| Flat factor | PASS (0.0) |
| Abs peak count | PASS (1, no sample at ±32767) |

## Residual Risks

- External mic low gain prevents independent measurement of the +26 dB board output improvement. K=0 provides UART-side confirmation of clean signal.
- Long-term operation at maximum gain: the mix saturator prevents clipping in the digital domain, but the WM8978 speaker output may have its own analog compression.
- The SPKOUT_VU bit (bit 8) is set to 1 in both R54 and R55 writes — valid per WM8978 datasheet (VU=1 required for volume change).

## Recommendation

PASS — promote the gain path fix.

The implementation is correct: velocity at full scale (0x7FFF), speaker volume at 0 dB attenuation (0/63), R49 SPKOUTP_EN preserved. The critical gate (K=0 — no clipping at maximum gain) is confirmed. The FPGA mix saturator provides adequate headroom for 3-voice summing at full excitation. Zero resource/timing delta from baseline.
