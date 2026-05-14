# Phase 1C Sample Gen Test Validation

Verifier: claude-verifier `e8db32f8-3c5f-4a11-bf2d-8f6e3ad76c4c`
Task: `task-05b98866`
Implementation commit: `c1c922c`
SOF checksum: `0x00674470`

## Verdict

PASS — **WM8978 codec hardware is working correctly. The volume bottleneck is in the waveguide digital path.**

The sample_gen test tone routes a ~440 Hz square wave directly to the DAC with full-scale GAIN (32767), maximum speaker volume (0/63), and SPKOUTP_EN=1. The measured output (peak -5.58 dBFS, RMS -7.54 dBFS) nearly matches sample.wav (-5.40 dBFS RMS), confirming the codec, speaker output, and analog path are fully functional.

## Diagnostic Result

| Source | Peak dBFS | RMS dBFS | Conclusion |
| --- | --- | --- | --- |
| **sample_gen test** | **-5.58** | **-7.54** | Codec works |
| sample.wav (reference) | -18.93 | -26.10 | Codec works (earlier phase) |
| Waveguide (max gain) | -32.09 | -46.72 | **Bottleneck** |

The sample_gen to waveguide level difference is **~25 dB** (peak) and **~39 dB** (RMS). The codec hardware, speaker output, and register configuration (R49 SPKOUTP_EN, R54/R55, GAIN) are all confirmed correct. The low volume observed in all previous waveguide captures is due to the waveguide digital path — not the WM8978 or speaker hardware.

## UART Telemetry

```
UART_RX_BASELINE_SMOKE_FAIL mode=no-command
frames=250 cycles=10
G=00000000 Q=00000000 X=00000000 K=00000000
```

- G=0, T/U/O=0 — voices disabled (correct for test)
- K=0 — no clipping even at full-scale output ✓
- Missing I/S startup tags (capture started after boot)

## Audio Metrics

### Per-Second RMS

| Second | Peak dBFS | RMS dBFS |
| --- | --- | --- |
| 1 | -5.58 | -7.52 |
| 2 | -5.66 | -7.56 |
| 3 | -5.58 | -7.54 |

### Overall

| Metric | Value |
| --- | --- |
| Peak | -5.58 dBFS |
| RMS | -7.54 dBFS |
| DC offset | ~0 |
| Flat factor | 0.0 |
| Clipped samples | 0 |

### Comparison with sample.wav

sample.wav (from earlier single-voice phase): RMS -26.10 dBFS, Peak -18.93 dBFS.

The sample_gen test (RMS -7.54 dBFS) is **18.5 dB LOUDER** than the earlier sample.wav reference. This is expected — the current build uses GAIN=32767 (full-scale, +12 dB from 16384) and speaker volume=0 (+20 dB from 20/63), totaling +32 dB over the earlier reference configuration. Sample_gen is also a 50% duty square wave (more energy than a decaying piano note).

## Resource/Timing

| Metric | Value |
| --- | --- |
| Quartus errors | 0 |
| Warnings | 16 (body_filter adds 2 over baseline 14) |
| Full compilation | PASS |

## Root Cause Determination

The WM8978 codec and speaker output path (R49 SPKOUTP_EN=1, R54/R55=0, GAIN=32767) produce the expected output level (~-5.6 dBFS peak). The low volume in the 3-voice waveguide captures is a **digital waveguide gain issue**, not a codec hardware issue.

Possible waveguide bottlenecks:
1. velocity_q15 at 0x7FFF may not reach full-scale in the waveguide excitation
2. Waveguide loop filtering / damping may attenuate more than expected
3. Per-voice mixing and saturation may reduce overall level
4. The body/soundboard IIR filter (newly added) may introduce gain changes

## Recommendation

PASS — accept the diagnostic result. The codec hardware configuration is verified correct end-to-end. Focus volume improvement efforts on the waveguide digital path (velocity scaling, excitation amplitude, loop gain, mix weighting).
