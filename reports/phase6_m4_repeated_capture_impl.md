# Phase 6 M4 Repeated-Capture Coherent Averaging Implementation Report

Date: 2026-05-24
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-e104f473`
Branch: `codex/phase1c-uart-boundary-fix`
Parent commit: `0c38ce3` (Phase 6 M4 scope PASS)

## TL;DR

**PASS for non-hardware coverage.** Phase 6 M4 lands three
host-tool changes that together unlock subtle voice-quality A/B
testing on the existing audio capture chain:

1. **`scripts/phase6_m1_voice_bench.py`**: `--repeats K` flag.
   Each cell becomes K back-to-back reset+strike events using the
   accepted M1.2 isolation `!F`+`!N` semantics. Sidecar bumps to
   `phase6_m1_voice_bench.v2` with per-cell timestamp lists and
   a `repeats` field.
2. **`scripts/phase6_m1_voice_analyze.py`**: `--coherent-average`
   flag plus per-cell `snr_db` metric. For v2 sidecars with K>1,
   the analyzer extracts K time-locked windows per cell and
   coherently averages them in time domain before computing the
   FFT band metrics. Yields `+10*log10(K) dB` SNR for time-locked
   excitation. v1 sidecars still work; the flag is ignored with a
   warning. CSV gains `repeats` and `snr_db` columns.
3. **`scripts/phase6_m4_noise_floor.py`** (new): characterizes
   chain noise as one of GAUSSIAN_CLEAN, GAUSSIAN_PLUS_HUM,
   HUM_60HZ_DOMINATED, HUM_50HZ_DOMINATED, CLIPPED_OR_OVERLOAD,
   or INDETERMINATE. Reports RMS dBFS, median spectral floor,
   per-power-grid-harmonic spectral magnitudes (50/60/100/120/180/
   240 Hz), Gaussian-fit chi-squared, and worst hum-to-floor ratio
   in dB. So we don't claim coherent-averaging success on a
   chain where the noise is dominated by structured hum that
   averaging cannot remove.

All three Python `--self-check` modes PASS:
- Bench: 12 vectors PASS.
- Analyzer: 4 vectors PASS, including a synthetic K=16 coherent
  averaging vector that demonstrates the predicted +10*log10(16)
  = +12.04 dB SNR gain (measured +11.70 dB residual reduction,
  within 0.5 dB of the prediction).
- Noise floor: 5 classifier vectors PASS (Gaussian-clean, 60 Hz
  dominated, 50 Hz dominated, mixed Gaussian+hum, clipped).

| Gate | Target | Actual | Verdict |
| --- | --- | --- | --- |
| Bench `--self-check` | PASS | 12 vectors PASS | PASS |
| Analyzer `--self-check` | PASS, K=16 gain within 0.5 dB | 4 vectors PASS, gain +11.70 dB vs +12.04 dB predicted | PASS |
| Noise-floor `--self-check` | PASS | 5 classifier vectors PASS | PASS |
| Sidecar v2 backward-compatible | yes | v2 K=1 analyzes identically to v1 (gain `repeats=1`/`snr_db` columns) | PASS |
| K=16 synthetic SNR gain | within 0.5 dB of +12.04 dB | +11.70 dB | PASS |
| ASCII-only on touched files | yes | yes | PASS |
| No RTL/QSF/firmware/obsolete change | yes | none touched | PASS |
| No new UART command syntax | yes | uses existing `!I1`/`!I0`/`!F`/`!NLLLLVVVV` only | PASS |
| No CPU/firmware/MMIO revival | yes | confirmed | PASS |
| Live capture | hardware | DEFERRED to verifier | n/a |

## 1. Bench changes

### Repeats logic

When `--repeats K > 1`, the bench restructures the per-cell loop
so each cell becomes K back-to-back reset+strike events. The
inner loop:

```
for r in range(K):
    ser.write(b"!F\r\n")          # M1.2 hard reset of voice0
    sleep(settle_s)
    send_t = monotonic() - session_start
    ser.write(cell.command_bytes)  # !NLLLLVVVV strike
    send_times.append(send_t)
    sleep(capture_s)
    sleep(pause_s)
```

The K send timestamps are recorded in the cell's
`send_t_session_s` list (now a list of K floats; v1 was a single
float).

### Sidecar v2 schema

```json
{
    "schema": "phase6_m1_voice_bench.v2",
    "repeats": K,
    "single_voice_isolate": true,
    "profile": "original",
    "session_start_unix": 1700000000.0,
    "pre_commands":  [{"command": "!I1", "send_t_session_s": 0.005}],
    "cells": [
        {
            "index": 0,
            "loop_len": 127,
            "velocity": 0x2000,
            "pitch_name": "loop127",
            "command": "!N007F2000",
            "send_t_session_s": [t_0, t_1, t_2, ..., t_{K-1}]
        },
        ...
    ],
    "post_commands": [
        {"command": "!F",  "send_t_session_s": 5.500},
        {"command": "!I0", "send_t_session_s": 5.555}
    ]
}
```

Backward-compatible note: at `repeats=1` the v2 sidecar still
records a single-element list. The analyzer detects schema v2 and
treats the timestamp field as a list always.

### `--plan --repeats N`

Banner output now shows the K-multiplied total time and a "K
times for coherent averaging" note.

### `--self-check` (12 vectors)

1. `grid_size = 15`
2. `default_profile=original (cell0 vel=0x2000)`
3. `clean_profile_grid (cell0 !N007F0800, last !N00202000)`
4. `c0 !N007F2000\r\n`
5. `a4_high !N006A7FFF (matches reduced-voice TB pitch)`
6. `last_cell !N00207FFF (loop_len=32 ceiling)`
7. `release_bytes !F\r\n`
8. `pacing settle=1.00s capture=4.00s pause=1.00s`
9. **NEW** `sidecar v2 JSON round-trip (K=4 timestamp list)`
10. **NEW** `k4_grid 15 cells, command bytes unchanged at K>=1`
11. `isolate_enable_bytes !I1\r\n`
12. `isolate_disable_bytes !I0\r\n`

Output: `PHASE6_M1_BENCH_PASS cells=15`.

## 2. Analyzer changes

### Schema detection

`run_real()` now checks for both `phase6_m1_voice_bench.v1` and
`phase6_m1_voice_bench.v2`. v2 is detected and the
`send_t_session_s` field is parsed as a list; v1's scalar is
wrapped in a single-element list.

### `--coherent-average` flag

When set with v2 sidecar: each cell extracts K time-locked windows
of length `CAPTURE_S` samples, sums them in time domain, divides
by K. The FFT band metrics are then computed from the averaged
window. The math:

```
avg[n] = (1/K) * sum_{i in [0,K)} samples[start_i + n]   for n in [0, W)
```

For deterministic excitation `s[n]` plus independent additive
Gaussian noise `e_i[n]` with RMS sigma:
- Signal: K copies of `s[n]` sum coherently to `K*s[n]`, divided
  by K -> `s[n]`. Signal RMS unchanged.
- Noise: K independent samples of variance sigma^2 sum to a
  Gaussian with variance K*sigma^2, divided by K -> variance
  sigma^2/K, RMS sigma/sqrt(K). Noise RMS drops by sqrt(K).
- SNR gain: `+10*log10(K) dB`.

When set with v1 sidecar: warning printed, flag ignored, single
strike per cell analyzed identically to the v1 baseline.

### Per-cell SNR

The analyzer adds a `snr_db` column computed as:

```
snr_db = 20 * log10(strike_window_rms / noise_window_rms)
```

The strike window is the 4 s after the (averaged) strike. The
noise window is the 0.4 s of pre-strike audio (0.5 s before the
first strike). For v1 sidecars / `--coherent-average OFF`, the
strike window is the single strike's CAPTURE_S samples.

### CSV/MD output extension

Two new columns added to the CSV header (and the markdown table):
`repeats` (the K value, 1 if averaging is off) and `snr_db`.
Existing columns are untouched, so older analyzer scripts that
read the CSV header still work for the columns they care about.

### `--self-check` (4 vectors)

1. (existing) Decaying sine peak/decay/centroid/attack/clipping.
2. (existing) Full-scale clipping count.
3. (existing) Silence count.
4. **NEW** Coherent averaging gain check at K=16. Synthesizes 16
   noisy copies of a 440 Hz decaying sine at known peak/sigma.
   Subtracts the known signal from both single-strike and
   coherent-averaged windows. Computes `20*log10(single_residual_rms
   / averaged_residual_rms)`.

   ```
   PASS v4 coherent_avg_gain K=16 expected=+12.04 dB actual=+11.70 dB
   ```

   Within 0.5 dB tolerance, well within the predicted
   `+10*log10(K)` law.

Output: `PHASE6_M1_ANALYZE_PASS vectors=4`.

## 3. Noise-floor characterization tool

`scripts/phase6_m4_noise_floor.py` is new. Pure stdlib (no numpy).

### Algorithm

1. Read the WAV (or stub-out for the implementer-side `--capture`
   mode).
2. Compute the overall RMS in dBFS.
3. Compute a robust median noise floor in dBFS by Goertzel-probing
   20 anchor frequencies that are deliberately offset from
   power-grid harmonics: 73, 137, 211, 293, 419, 547, 683, 829,
   977, 1153, 1373, 1733, 2179, 2719, 3343, 4133, 5099, 6173,
   7411, 9067 Hz. The median of these 20 magnitudes converted to
   dBFS is the "median floor".
4. Compute the Goertzel magnitude in dBFS at each power-grid
   harmonic (50, 60, 100, 120, 180, 240 Hz).
5. Find the worst hum-to-floor ratio across the 6 harmonics.
6. Compute a Gaussian-fit chi-squared of the time-domain samples
   over 16 buckets between mean +/- 3 sigma.
7. Classify:
   - `CLIPPED_OR_OVERLOAD` if overall RMS > -1 dBFS.
   - `HUM_60HZ_DOMINATED` if worst hum > +12 dB above floor and
     the worst harmonic is 60 or 120 Hz.
   - `HUM_50HZ_DOMINATED` if worst hum > +12 dB and worst is 50
     or 100 Hz.
   - `GAUSSIAN_PLUS_HUM` if worst hum is +6..+12 dB above floor.
   - `GAUSSIAN_CLEAN` if worst hum < +6 dB above floor and
     Gaussian chi-squared is below threshold.
   - `INDETERMINATE` otherwise.

### `--self-check` (5 vectors)

1. Pure Gaussian noise -> `GAUSSIAN_CLEAN`.
2. 60 Hz hum + low Gaussian floor -> `HUM_60HZ_DOMINATED`.
3. 50 Hz hum + low Gaussian floor -> `HUM_50HZ_DOMINATED`.
4. Small 60 Hz hum (~+12 dB above floor) + Gaussian -> `GAUSSIAN_PLUS_HUM`.
5. Full-scale 440 Hz sine -> `CLIPPED_OR_OVERLOAD`.

Output: `PHASE6_M4_NOISE_FLOOR_PASS vectors=5`.

### Modes

```
python scripts/phase6_m4_noise_floor.py --self-check
python scripts/phase6_m4_noise_floor.py --wav PATH
python scripts/phase6_m4_noise_floor.py --capture       # verifier-only
```

The `--capture` mode is intentionally stubbed on the implementer
side and prints an explicit error: hardware audio capture is the
verifier's responsibility per project discipline. The verifier
should capture 30 s of pure silence using their existing audio
flow and feed it to `--wav`.

## 4. Hardware deferral and recapture protocol (for verifier)

Per project discipline rule, the live hardware capture for M4 is
deferred to the M4 verifier task. Suggested protocol:

1. Verify the M3 SOF (`9cf6852` / sha256 `E62E8EB276...`) is on
   the board, or program if needed.
2. **Noise-floor characterization**:
   ```
   ffmpeg ... -t 30 reports/phase6_m4_silence.wav
   python scripts/phase6_m4_noise_floor.py --wav reports/phase6_m4_silence.wav
   ```
   Capture 30 s of pure silence (UART idle, no commands sent).
   Record the classification.
3. **K=16 capture against M3 SOF**:
   ```
   python scripts/phase6_m1_voice_bench.py --run --port COM5 \
       --single-voice-isolate --repeats 16 \
       --sidecar reports/phase6_m4_voice_bench_session.json
   ```
   Total bench time ~1440 s for the full 15-cell grid (or
   subset to the 5 focus cells: 2, 5, 8, 9, 11 -> ~480 s).
4. **Analyze with coherent averaging**:
   ```
   python scripts/phase6_m1_voice_analyze.py \
       --wav reports/phase6_m4_voice_bench.wav \
       --sidecar reports/phase6_m4_voice_bench_session.json \
       --coherent-average \
       --out reports/phase6_m4_voice_baseline_K16.csv \
       --out-md reports/phase6_m4_voice_baseline_K16_analyzed.md
   ```
5. **Variance gate**: re-run the K=16 capture twice more on the
   same SOF; FFT band variance across the 3 runs should be <= 1
   dB on each focus cell.
6. **M2 vs M3 A/B** (optional but recommended): reprogram M2 SOF,
   run the same `--repeats 16` protocol, compare the K=16 M2 vs
   K=16 M3 FFT bands. Body warmth target gain (+3-5 dB at 1-3
   kHz) should now be statistically resolvable.

### Acceptance criteria

| Gate | Target |
| --- | --- |
| Self-checks (3 scripts) | PASS |
| Noise-floor classification | reported (any value) |
| K=16 capture per-cell SNR | >= 10 dB on >= 4 of 5 focus cells |
| Run-to-run variance | <= 1 dB across 3 K=16 captures of one cell |
| K=16 M2 vs K=16 M3 1-3 kHz delta | +3 to +5 dB on at least 3 cells |
| K=16 M2 vs K=16 M3 4-7 kHz delta | within 1 dB |

If chain noise classifies as `HUM_60HZ_DOMINATED` or
`HUM_50HZ_DOMINATED` AND coherent averaging yields less than 6 dB
of effective gain (because the hum is time-locked to mains
frequency, not to the strike send timestamps), M5 fallback per the
M4 scope: external ADC purchase or B2 runtime body knob. The
verifier classifier explicitly detects this case.

## 5. Out of scope

- No RTL change. No QSF change. No firmware change. No obsolete
  archive change.
- No new UART command syntax.
- No CPU/firmware/MMIO/register-file revival.
- No edits to verifier-protected untracked files or `.kiro/`.

ASCII-only.

## 6. Committed result

This commit contains:

- modify: `scripts/phase6_m1_voice_bench.py`
  (`--repeats K`, sidecar v2 schema with timestamp lists,
   updated `--self-check` with v2 round-trip and K=4 grid)
- modify: `scripts/phase6_m1_voice_analyze.py`
  (schema v1/v2 detection, `--coherent-average` flag,
   `coherent_average()` and `compute_snr_db()` helpers,
   `repeats` and `snr_db` CSV columns, updated `--self-check`
   with K=16 gain vector)
- new: `scripts/phase6_m4_noise_floor.py`
  (Goertzel-based hum probing, robust median floor estimation,
   Gaussian chi-squared, classifier with 5 self-check vectors)
- new: `reports/phase6_m4_repeated_capture_impl.md` (this file)
