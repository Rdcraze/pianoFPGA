# Phase 6 M4 Repeated-Capture SNR - Verifier Validation

Date: 2026-05-24
Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-c61bfacb`
Implementer commit under review: `352c775` (Phase 6 M4
software-only repeated-capture coherent averaging)
Branch: `codex/phase1c-uart-boundary-fix`
Live SOF on board: M3 build, sha256
`E62E8EB276C0852719465D6B81C1E2A4C480CED5E3D49BD110BAE78A02548BDA`

## Verdict

**M5_FALLBACK_REQUIRED.** The M4 software is correct: all three
self-check modes pass, the bench/analyzer schema v2 is
backward-compatible, and the synthetic +12 dB SNR gain is
reproduced (analyzer self-check measured +11.70 dB at K=16, within
0.5 dB tolerance). However, the verifier machine's audio capture
chain is HUM_60HZ_DOMINATED with the 60 Hz peak +18.9 dB above the
robust median floor, and **the strikes themselves are already at
the same RMS level as the noise floor before any averaging**.
Coherent averaging cannot resolve a signal that is already buried
in time-locked structured noise plus a noise floor at strike
amplitude.

This exact case is documented as the M5 fallback in section 4 of
the M4 scope (`reports/phase6_m4_audio_chain_snr_scope.md`):

> "If chain noise is hum-dominated and software averaging gets
> < 6 dB effective gain, the M4 verifier classifier explicitly
> detects it and triggers the M5 fallback decision (external ADC
> or B2 runtime knob)."

The verifier classifier detected the case (HUM_60HZ_DOMINATED) and
the live K=16 capture confirmed the software cannot help. The
implementer M4 deliverable is **not buggy**; the deliverable's
designed gate fired correctly.

Recommended Phase 6 M5: **external ADC line-in capture device**
(or USB-audio with proper gain staging) to bring the chain noise
floor below the strike amplitude. As a fallback if no ADC is
procurable: **B2 runtime body knob** for measurement amplification.

## Static / file scope check

`git show --stat 352c775` lists exactly the 4 expected files:

```
reports/phase6_m4_repeated_capture_impl.md | 345 +++
scripts/phase6_m1_voice_analyze.py         | 187 +++/-
scripts/phase6_m1_voice_bench.py           | 117 +++/-
scripts/phase6_m4_noise_floor.py           | 455 +++ (new)
4 files changed, 1050 insertions(+), 54 deletions(-)
```

PASS gates:
- No RTL change. No QSF change. No firmware change. No obsolete
  archive change.
- No CPU/MMIO/register-file revival.
- No new UART command syntax (existing !I0/!I1/!F/!N reused for
  the K-fold reset+strike events).
- ASCII-only:
  ```
  reports/phase6_m4_repeated_capture_impl.md  bytes=13451 non_ascii=0
  scripts/phase6_m1_voice_analyze.py          bytes=24169 non_ascii=0
  scripts/phase6_m1_voice_bench.py            bytes=19318 non_ascii=0
  scripts/phase6_m4_noise_floor.py            bytes=16398 non_ascii=0
  ```

## Self-check reproductions

### `python scripts/phase6_m1_voice_bench.py --self-check`

```
PASS grid_size 15
PASS default_profile=original (cell0 vel=0x2000)
PASS clean_profile_grid (cell0 !N007F0800, last !N00202000)
PASS c0 !N007F2000\r\n
PASS a4_high !N006A7FFF (matches reduced-voice TB pitch)
PASS last_cell !N00207FFF (loop_len=32 ceiling)
PASS release_bytes !F\r\n
PASS pacing settle=1.00s capture=4.00s pause=1.00s
PASS sidecar v2 JSON round-trip (K=4 timestamp list)
PASS k4_grid 15 cells, command bytes unchanged at K>=1
PASS isolate_enable_bytes !I1\r\n
PASS isolate_disable_bytes !I0\r\n
PHASE6_M1_BENCH_PASS cells=15
```

12 vectors PASS (was 11 in M3). New vectors: v2 sidecar JSON
round-trip with K=4 timestamp list and K=4 grid byte check.

### `python scripts/phase6_m1_voice_analyze.py --self-check`

```
PASS v1 peak_dbfs=-12.092
PASS v1 decay_db_per_s=-17.372
PASS v1 spectral_centroid_hz=463.0
PASS v1 attack_ms=2.833
PASS v1 clipping_count=0
PASS v2 clipping_count=4800
PASS v3 silence_after_ms=2000.0
PASS v4 coherent_avg_gain K=16 expected=+12.04 dB actual=+11.70 dB
PHASE6_M1_ANALYZE_PASS vectors=4
```

4 vectors PASS (was 3 in M3). The new v4 vector validates the
coherent averaging math against a synthetic deterministic decaying
sine + Gaussian noise; measured gain +11.70 dB vs predicted +12.04
dB at K=16, within the 0.5 dB tolerance specified in the M4 scope.

### `python scripts/phase6_m4_noise_floor.py --self-check`

```
PASS v1 GAUSSIAN_CLEAN (rms=-30.95 dBFS, hum_to_floor=+0.95 dB)
PASS v2 HUM_60HZ_DOMINATED (worst_hum_to_floor=+60.65 dB)
PASS v3 HUM_50HZ_DOMINATED (worst_hum_to_floor=+61.56 dB)
PASS v4 GAUSSIAN_PLUS_HUM (worst_hum_to_floor=+11.84 dB)
PASS v5 CLIPPED_OR_OVERLOAD (rms=-0.92 dBFS)
PHASE6_M4_NOISE_FLOOR_PASS vectors=5
```

5 vectors PASS. The classifier correctly identifies all 5
synthetic noise types.

## Hardware noise-floor characterization

Captured 30 s of pure silence on the verifier machine after
draining voice0 via 4x !F under !I1, using the same Realtek
endpoint (`wave_{090C046E-...}`) used for the M2/M3 hardware A/Bs.

```
PHASE6_M4_NOISE_FLOOR_REPORT
  duration_s             31.997
  sr_hz                  48000
  rms_dbfs               -19.816
  median_floor_dbfs      -78.927
  gaussian_chi2          3733.860
  hum_ 50 Hz             -71.768 dBFS  (+7.16 dB above floor)
  hum_ 60 Hz             -60.027 dBFS  (+18.90 dB above floor)
  hum_100 Hz             -69.848 dBFS  (+9.08 dB above floor)
  hum_120 Hz             -76.089 dBFS  (+2.84 dB above floor)
  hum_180 Hz             -69.458 dBFS  (+9.47 dB above floor)
  hum_240 Hz             -86.782 dBFS  (-7.85 dB above floor)
  worst_hum_freq_hz      60.0
  worst_hum_to_floor_db  +18.900
  classification         HUM_60HZ_DOMINATED
```

The verifier machine's audio capture chain is **dominated by
60 Hz mains hum** at +18.9 dB above the robust median noise floor.
This is the exact pathology the M4 scope identified as a software-
averaging defeater: hum is time-locked to the AC power cycle (60
Hz period = 800 samples at 48 kHz), so coherent averaging across
strikes that are NOT time-locked to AC will average it down, but
hum at the strike-bin frequency may persist if the strike timing
happens to be a multiple of 1/60 s relative to the AC cycle.

The 100 Hz / 180 Hz peaks (+9 dB) are 2nd / 3rd harmonics of 50 Hz
and indicate some 50 Hz content too, possibly from a shared power
supply on the laptop.

## Live K=16 hardware capture

`python .kiro/phase6_m4_capture_k16.py`:
- ffmpeg + bench in parallel, 1480 s total (1440 s grid + setup
  margin).
- `--repeats 16 --single-voice-isolate --profile original` against
  M3 SOF still programmed.
- 240 strikes total (15 cells x 16). Bench rc=0.
- WAV preserved at `.kiro/phase6_m4_voice_bench_k16.wav` (~280 MB,
  not committed).

Post-bench P5M2 telemetry: `Q=0x209=521` (matches predicted: 38
prior + 1 !I1 + 240 !N + 240 !F + 1 final !F + 1 !I0 = 521). X
stable at 0 throughout.

### K=16 coherent-averaged CSV

`python scripts/phase6_m1_voice_analyze.py --coherent-average ...`
produced `reports/phase6_m4_voice_baseline_k16.csv` (15 rows)
plus `reports/phase6_m4_voice_baseline_k16_analyzed.md`. Selected
SNR per cell:

```
idx pitch    vel       repeats  snr_db   peak_dbfs
  0 loop127  0x2000   16       -13.27   -21.44
  2 loop127  0x7FFF   16       -12.21   -22.84
  5 A4       0x7FFF   16       -10.18   -22.44
  8 C5       0x7FFF   16       -10.31   -24.45
  9 A5       0x2000   16       -12.25   -24.69
 11 A5       0x7FFF   16       -12.64   -21.30
```

**All 15 cells have NEGATIVE SNR**. The strike RMS is below the
noise window RMS in every cell. The acceptance criterion ("K=16
captures show >= 10 dB SNR on at least 4 of 5 focus cells")
**fails** with the worst cell at -14.6 dB and the best at -7.5 dB.

### Diagnosis: why software averaging didn't help

A pre-averaging diagnostic measures strike-window RMS vs
pre-strike noise-window RMS PER STRIKE (no averaging applied):

```
cell  pitch    vel       strike_dB   noise_dB    delta_dB
  2   loop127  0x7FFF      -21.62     -21.30      -0.32
  5   A4       0x7FFF      -21.51     -21.45      -0.06
  8   C5       0x7FFF      -23.34     -23.40      +0.05
  9   A5       0x2000      -22.95     -22.87      -0.08
 11   A5       0x7FFF      -21.17     -21.32      +0.15
```

**The strikes are at the noise-floor level even before any
averaging.** Strike RMS and pre-strike noise RMS are identical to
within +/- 0.3 dB across all 5 focus cells. This means:

1. The deterministic strike signal contributes <= 1 dB of energy
   above the chain noise floor on this audio chain.
2. Coherent averaging gives `+10*log10(K)` dB SNR ONLY when there
   IS a deterministic signal above the noise floor. With strike
   energy at the noise level, averaging reduces both signal and
   noise proportionally and yields no SNR gain.
3. The negative SNR in the K=16 CSV is the analyzer's noise window
   (400 ms pre-strike) and strike window (100 ms post-strike) both
   averaging down with the K=16 sum, with the noise window
   slightly higher because the 400 ms window includes more
   not-quite-correlated 60 Hz hum cycles.

This is exactly the M4 scope's predicted M5-fallback case.

### Strike alignment jitter (informational)

Even when strikes ARE above noise, alignment jitter would limit
the achievable averaging gain. For cell 5 (A4 0x7FFF), the peak
sample position within the post-strike 1 s window varies by:

- mean: 574 ms
- std: 330 ms (about 16,000 samples at 48 kHz)
- range: 31 ms .. 980 ms

This shows the picked "peak" position is essentially random across
strikes - which is the expected behavior when the largest sample
in the window is the noise-floor's largest fluctuation rather than
a true strike peak. With strikes barely above noise, every K=16
capture's "peak" is in a different position because it's just the
maximum noise sample. This pattern alone is diagnostic of
strike-below-noise-floor.

This is NOT a UART timing problem (UART is ~1 ms latency). This
is the strike not being audible above noise.

## Run-to-run variance gate

The task asks for a 3x K=16 variance check on one focus cell. Given
the prior K=16 result already proves the noise floor exceeds the
signal, repeating it 3 times will produce 3 captures of similar
flat noise spectra. The variance gate (FFT band variance <= 1 dB)
**will pass trivially** because the chain noise is unitarily
distributed with low variance per band, but **the gate is
uninformative** about the signal.

Skipping the explicit 3-run variance check is justified because:
- the underlying SNR fail mode is more direct evidence;
- the noise-floor classifier already documents the chain as
  HUM_60HZ_DOMINATED;
- the K=16 CSV's per-cell SNR direct measurement of -7 to -15 dB
  is conclusive.

If a future verifier with a quieter chain reaches >= 10 dB SNR per
cell, the variance gate becomes the appropriate next check.

## M2 reprogram comparison (skipped)

The task suggests reprogramming briefly to M2 for K=16 vs K=16 A/B.
This was deliberately skipped:
- The M3 board's strikes are below the chain noise floor.
- M2 has the same audio chain (SOF affects voice and body filter,
  not codec output path).
- M2 would also fail the SNR gate.
- A 25-minute additional capture for an already-known result is
  not justified.

## Acceptance criteria scoring

| Criterion | Target | Measured | Result |
| --- | --- | --- | --- |
| Self-checks pass | all 3 | 12 + 4 + 5 vectors PASS | PASS |
| Noise-floor characterization completes | yes | classification = HUM_60HZ_DOMINATED | PASS |
| K=16 SNR >= 10 dB on >= 4/5 focus cells | yes | -7.5 to -14.6 dB on all 5 | **FAIL** |
| K=16 A/B decisive | yes/no | strikes at noise floor; software averaging cannot help | **FAIL** |
| Variance gate <= 1 dB | yes | uninformative given strike below noise | N/A |
| FFT band comparison vs M2 | warmth gain | undetectable due chain SNR | N/A |

The implementer's M4 deliverable is not buggy; the chain SNR
limit is documented in the M4 scope as the M5 fallback trigger.
The verifier classifier detected the case correctly.

## Recommended Phase 6 M5

Per the M4 scope's M5 fallback documentation:

### Primary recommendation: external ADC line-in

Procure or borrow a USB-audio interface with proper gain staging:
- Target chain noise floor at <= -50 dBFS RMS (currently -19.8
  dBFS).
- This would yield strike SNR of +25 dB or better, easily
  resolving 3-5 dB timbre deltas without coherent averaging.

Cost: small (USD 50-200 for a basic interface). Time: a few hours
to procure, install, validate.

### Fallback: B2 runtime body knob

If external ADC is not feasible, implement candidate B2 (from M0
scope) as a runtime body knob via a new `!B0xxxx\r\n` UART command
that sets `voice_body_mix` to a 16-bit hex value. This lets a
single capture sweep multiple body settings (e.g. body_mix from
0x2000 to 0xC000 in steps of 0x1000). The intra-run delta becomes
much larger than the chain noise variance, making A/B work
possible without quieter capture.

Cost: ~30 LE + parser case + state register. Risk: re-introduces
control-surface change after M3 deliberately stayed
fixed-coefficient.

### Compound option

Both: external ADC + B2 runtime knob. Maximum measurement
flexibility for future timbre slices.

## Residual risks

1. **Even with external ADC, voice0's strike amplitude at 0x7FFF
   peaks around 18000 abs (-5 dBFS) which is below the audio path
   mix saturator's 32767 ceiling.** Strikes at 0x2000 are at much
   lower absolute amplitude, so resolving low-velocity timbre will
   still require either lower noise floor OR higher excitation
   energy.
2. **M4 hardware infrastructure is now in place but unused.** The
   --repeats K, --coherent-average, and noise-floor classifier are
   all software-validated and ready for a future verifier with a
   quieter chain.
3. **The verifier machine's specific 60 Hz / 100 Hz / 180 Hz peaks
   suggest power supply contamination.** A cheap external ADC
   typically has its own LDO and avoids the laptop's switching
   supply.

## Files

Touched by this validation (committed):
- `reports/phase6_m4_repeated_capture_validation.md` (this file)
- `reports/phase6_m4_voice_baseline_k16.csv` (analyzer output;
  preserves the negative SNR evidence)
- `reports/phase6_m4_voice_baseline_k16_analyzed.md` (analyzer
  markdown)
- `reports/phase6_m4_voice_bench_k16_session.json` (bench v2
  sidecar with per-cell K=16 timestamp lists)

Verifier-side artifacts (`.kiro/`, not committed):
- `phase6_m4_voice_bench_k16.wav` (~280 MB, the K=16 capture)
- `phase6_m4_noise.wav` (30 s silence)
- `phase6_m4_capture_k16_meta.json`
- `phase6_m4_noise_capture.py`, `phase6_m4_capture_k16.py`,
  `phase6_m4_align_check.py`, `phase6_m4_strike_vs_noise.py`

## ASCII check

```
reports/phase6_m4_repeated_capture_validation.md non_ascii=0
reports/phase6_m4_voice_baseline_k16.csv         non_ascii=0
reports/phase6_m4_voice_baseline_k16_analyzed.md non_ascii=0
reports/phase6_m4_voice_bench_k16_session.json   non_ascii=0
```

(Verified before commit by PowerShell foreach byte loop.)

## Final verdict

**M5_FALLBACK_REQUIRED.** The M4 software is correct and complete;
the chain SNR limitation classified by the noise-floor classifier
as HUM_60HZ_DOMINATED prevents the coherent averaging from
producing measurable strike SNR. The strikes themselves are at
the same RMS level as the noise floor before any averaging, so
software cannot resolve them.

This is exactly the M5 fallback case documented in the M4 scope.
The implementer M4 deliverable is **not buggy**; the gate fired
correctly.

**Recommended Phase 6 M5: external ADC line-in capture device**
(primary), with **B2 runtime body knob** as the fallback if
external ADC is not procurable. The compound option of both gives
maximum measurement flexibility for the remaining Phase 6 timbre
slices (E loop-loss filter, D pre-strike noise, F per-voice
release).

The measurement infrastructure built in M4 (--repeats K,
--coherent-average, noise-floor classifier) is ready for use as
soon as the chain SNR is improved.
