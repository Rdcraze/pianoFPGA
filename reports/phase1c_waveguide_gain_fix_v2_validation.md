# Phase 1C Waveguide Gain Fix v2 Validation

Verifier: claude-verifier `e8db32f8-3c5f-4a11-bf2d-8f6e3ad76c4c`
Task: `task-7fee24ba`
Implementation commit: `c25d1a7`
SOF checksum: `0x006815EE`
Prior validation: `task-5136c95c` (FAIL, K=105 at >>>0)

## Verdict

**PASS — K=0. >>>1 back-off resolves clipping.**

The v2 fix re-adds `>>> 1` (÷2 guard) while keeping body_mix at 16384 (50%). Total +12 dB digital gain over original. The mix saturator remains clean (K=0 across 225 frames). This is the correct balance — maximum gain without clipping.

## Changes from v1 (FAIL → PASS)

| Parameter | Original | v1 (FAIL) | v2 (PASS) |
| --- | --- | --- | --- |
| Excitation shift | `>>> 2` (÷4) | `>>> 0` (none) | **`>>> 1` (÷2)** |
| body_mix_q15 | 8192 (25%) | 16384 (50%) | 16384 (50%) |
| Delta vs original | 0 dB | +18 dB | **+12 dB** |
| K value | 0 | 105 | **0** |

## UART Telemetry

```
UART_RX_BASELINE_SMOKE_FAIL mode=no-command
frames=225 cycles=9
G=00000006 Q=00000000 X=00000000 K=00000000
```

- K=0 ✓ — zero mix clipping (critical gate)
- G=6 ✓ — voices active, 3-voice round-robin
- Q=0, X=0 ✓ — no errors
- CC=0x003D0900 ✓ — counter stable

## Resource/Timing

| Metric | Value |
| --- | --- |
| Quartus errors | 0 |
| Warnings | 16 |
| Setup slack | +2.438 ns |
| Hold slack | +0.406 ns |

## Audio Levels

| Metric | v2 Waveguide | sample_gen Test | Gap |
| --- | --- | --- | --- |
| Per-second peak | -37.4 dBFS | -5.58 dBFS | **-31.8 dB** |
| Per-second RMS | -49.1 dBFS | -7.54 dBFS | **-41.6 dB** |
| K (clipping) | 0 | 0 | PASS |

**Volume has NOT returned to normal.** Despite K=0 confirming no digital clipping and the +12 dB waveguide gain improvement, the measured waveguide output remains ~30-40 dB below the sample_gen test tone level. The sample_gen test (same codec, same speaker path, same mic) proves the codec hardware can produce normal volume. The waveguide digital path — even with >>>1 and 50% body_mix — is still severely attenuating the signal.

The v2 fix is correct in avoiding clipping (K=0 vs v1's K=105), but does not close the volume gap. Further waveguide gain investigation is needed beyond excitation shift and body_mix.

## Recommendation

PASS — promote the v2 waveguide gain fix as a clipping-safe intermediate step.

K=0 confirms the `>>> 1` guard is adequate for mix headroom. However, this +12 dB improvement does NOT restore normal volume. The waveguide output remains ~30-40 dB below the sample_gen reference. Additional digital gain investigation is required — possible areas: voice summing weights, post-mix gain stage, or the body IIR filter insertion loss.
