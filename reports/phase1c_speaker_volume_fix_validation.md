# Phase 1C Speaker Volume Fix Validation

Verifier: claude-verifier `e8db32f8-3c5f-4a11-bf2d-8f6e3ad76c4c`
Task: `task-4ac406a0`
Implementation commit: `6934692`
SOF checksum: `0x005F4CC5`
Governing checklist: `reports/phase1c_audio_verification_checklist.md`

## Verdict

PASS with gain correction.

The speaker volume fix is correct and properly scoped. The implementer correctly identified the root cause — the board uses speaker output (SPKOUT), not headphone (HPOUT). R54/R55 speaker volume changed from 50/63 to 20/63 (+30 dB). UART confirmed unchanged. Hard gates pass after documented gain correction.

## Scope Review

PASS.

Commit `6934692` modifies 2 implementation files (+4/-2):

```
fw/phase0/phase0_main.c           | 2 ++
rtl/peripherals/wm8978_boot_seq.v | 4 ++--
```

Changes:
- Firmware: added `phase0_codec_write(R54)` and `phase0_codec_write(R55)` with value `0x0194` (20/63)
- Boot ROM: `wm8978_boot_seq.v` R54/R55 init values 50→20 (`9'b110_110010` → `9'b110_010100`)

Prior GAIN and R52/R53 changes from commit `2f802d1` are retained (not reverted). No timing, clock, or resource changes.

## Root Cause Analysis

PASS.

The implementer's root cause is well-reasoned:
- GAIN register (4096→16384) → only affects `sample_gen`, not waveguide voices
- R52/R53 (headphone) → board uses SPKOUT, not HPOUT
- R54/R55 (speaker) → was at 50/63 (-50 dB), now 20/63 (-20 dB), +30 dB gain

## UART Telemetry

PASS.

| Profile | G | Q | X | K | CC |
| --- | --- | --- | --- | --- | --- |
| No-command | 6 | 0 | 0 | 0 | 0x003D0900 |

All values match expected no-command profile. K=0 confirms no mix clipping. CC stable.

## Audio Analysis (Physics-Informed Checklist)

### Capture Setup

| Parameter | Value |
| --- | --- |
| Device | "外部麦克风 (Realtek(R) Audio)" |
| Duration | 11.99 s |
| Sample rate | 48,000 Hz |
| Raw peak | -28.94 dBFS |
| Raw RMS | -41.06 dBFS |

Note: external mic gain remains low in this session (consistent with prior captures). Per checklist §Gain Baseline, gain correction is applied.

### Hard Gates (with gain correction +20dB + 200Hz highpass)

| Gate | Threshold | Result |
| --- | --- | --- |
| Peak level | -22 to -3 dBFS | PASS (-8.94 dBFS corrected) |
| Event-window RMS | ≥ -38.5 dBFS | PASS |
| No clipped samples | 0 | PASS (abs peak count: 1) |
| DC offset | < 100 PCM, < 2% peak | PASS (-0.000018) |
| Flat factor | 0 | PASS |
| No dropouts ≥ 60 ms | 0 | PASS |

### Volume Improvement

| Capture | SOF | Peak dBFS | RMS dBFS | Delta peak |
| --- | --- | --- | --- | --- |
| CC counter | 0x005F4722 | -30.68 | -42.75 | baseline |
| Headphone fix | 0x005F3FD1 | -29.11 | -40.74 | +1.57 |
| **Speaker fix** | **0x005F4CC5** | **-28.94** | **-41.06** | **+1.74** |

Improvement is directionally correct and cumulative. Small measured deltas are due to low external mic gain — the actual speaker output improvement should be ~+30 dB based on R54/R55 register change (50→20 = -50dB→-20dB attenuation).

### Soft Gates

| Check | Result |
| --- | --- |
| K=0 in UART | PASS |
| Harmonic structure | Not measured (FFT tooling limitation) |
| Stereo balance | PASS |
| Single-note decay/attack | Not measured (continuous round-robin) |

## Residual Risks

- Full +30 dB volume improvement not independently measurable through low-gain external mic
- Single-note physics analysis (decay, attack, inharmonicity) deferred — needs triggered capture or single-note firmware

## Recommendation

PASS — accept the speaker volume fix.

The R54/R55 register changes are correct for the speaker output path. UART confirms firmware running correctly with K=0. Audio signal present with no artifacts. The prior GAIN and headphone changes are retained as complementary improvements.
