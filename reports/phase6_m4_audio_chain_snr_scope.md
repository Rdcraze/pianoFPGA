# Phase 6 M4 Audio-Chain SNR Scope

Date: 2026-05-24
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-54137ef2`
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `9cf6852` (Phase 6 M3 body-warmth, verifier CONDITIONAL_PASS)

## TL;DR

**Recommendation: Phase 6 M4 = software-only repeated-capture
coherent averaging** in the existing bench/analyzer host tools. No
hardware purchase required; no RTL change; no QSF change. Each
benchmark cell becomes N consecutive reset+strike events; the
analyzer aligns the N segments by per-strike send timestamps and
coherently sums the time-domain windows before computing FFT band
metrics. Coherent averaging of K strikes gives `+10*log10(K) dB`
SNR for time-locked signal, easily 12 dB at K=16, which is enough
to resolve the 3-5 dB body-warmth deltas that M3 could not
distinguish from the ~-15 dBFS Gaussian audio chain floor.

If the implementer-side simulation of the averaging math shows it
is insufficient (e.g. the chain noise has structured, time-locked
content not removable by coherent averaging), the M5 fallback is
B2 (runtime body knob) or an external-ADC purchase decision.

| M4 (this scope) | M5 (queued, deferred) |
| --- | --- |
| Software-only: `--repeats K` flag in bench + coherent FFT averaging in analyzer | External ADC line-in capture device, or B2 runtime body knob |
| `scripts/phase6_m1_voice_bench.py` extended with `--repeats K` | New scripts `scripts/phase6_m4_*.py` if needed |
| `scripts/phase6_m1_voice_analyze.py` extended with coherent averaging mode + per-cell SNR report | RTL change for B2 runtime body knob in `phase0_uart_command.v` and `phase0_fixed_control.v` |
| New: `scripts/phase6_m4_noise_floor.py` for silence-window characterization | (no RTL change in M4) |
| New: `reports/phase6_m4_repeated_capture_impl.md` with re-runs of M2 vs M3 A/B at K>=8 | New: `reports/phase6_m5_*.md` |
| RTL change: NONE | Resource budget per slice: case-by-case |
| Hardware capture: required (verifier task) | Hardware capture: required |

## 1. Live state at the start of M4

| Metric | Value |
| --- | ---: |
| HEAD | `9cf6852` (Phase 6 M3 PASS) |
| LE | 4,932 / 10,320 (48%) |
| Setup slack slow-85C `sys_clk_50m` | +4.515 ns |
| Hold | +0.413 ns clean |
| All TNS | 0 |
| M9K / DSP9 / PLL | 5 / 26 / 1 |
| Errors / warnings | 0 / 16 |

Audio chain (verifier machine, `wave_{090C046E-...}`): Realtek
endpoint, ~-15 to -18 dBFS Gaussian noise floor on silence
captures. M2 brightness was 4-7 kHz +6 dB delta and was
measurable. M3 body warmth was 1-3 kHz +3-5 dB delta target,
overlapping the noise variance, so the M3 verifier report could
not statistically separate the change from chain noise.

## 2. Concrete measurement goals

These are the goal numbers the M4 deliverable must achieve so
future timbre A/B tests are decisive:

| Metric | Target | Reason |
| --- | --- | --- |
| Silence-window noise floor RMS | <= -30 dBFS | Currently ~-15 dBFS; need 15 dB headroom to resolve 3 dB timbre deltas |
| Strike-vs-noise SNR (cell 5 A4 0x7FFF) | >= 20 dB | M2/M3 strikes peak around -16 dBFS, noise ~-15 dBFS, current SNR ~1 dB. Target SNR allows individual cell A/B without averaging. |
| Run-to-run FFT band variance | <= 1 dB across 5 repeats | M3 saw ~3 dB chain variation across band comparisons. Target lets us treat 3-5 dB target deltas as statistically significant. |
| Cells per A/B with K=16 averaging | 5 (cells 2/5/8/9/11) | Same cells M2/M3 verifier focused on; consistent A/B target across slices. |

These goals are achievable with software-only coherent averaging
(K=16 -> +12 dB SNR; combined with the chain's intrinsic ~-15 dBFS
floor that gives a synthetic floor of ~-27 dBFS, and run-to-run
variance scales as sqrt(1/K) = 0.25 vs current single-capture).

## 3. M4 path comparison

### A. Software-only repeated-capture coherent averaging (RECOMMENDED)

How it works:
- Bench sends K consecutive reset+strike+wait events per cell
  using the existing `!I1` isolation mode (M1.2 reset-on-!F
  semantics) and the existing `!N` strike command.
- Bench records the K send timestamps in the sidecar JSON.
- Analyzer reads the WAV, extracts K time-locked windows around
  each cell's K strikes, aligns them by send_t_session_s plus
  audio-start-unix offset, and coherently sums them before
  computing FFT band metrics.
- Coherent averaging gain: +10*log10(K) dB for time-locked signal.
  At K=16, 12 dB; at K=32, 15 dB.

Pros:
- **No new hardware required**.
- No RTL change; the existing M1.2 reset-on-!F is exactly the
  primitive needed.
- No QSF change.
- Reusable across all future timbre A/B tests (M5+, M6+).
- Reduces run-to-run variance by sqrt(K).

Cons:
- Per-cell capture time grows from 6 s to ~6*K s. At K=16, the
  full 5-cell A/B becomes ~8 minutes per run. Acceptable.
- If the chain noise has time-locked structured content (e.g.
  60 Hz hum, switch-mode supply noise), coherent averaging will
  preserve it. The noise-floor characterization mode (deliverable
  3 below) will detect this case before timbre A/B runs.

LE/timing risk: NONE (no RTL touched).

Testability: HIGH. Both `--self-check` modes can validate the
averaging math against synthetic stimuli with known SNR; live
hardware A/B can directly compare K=1 vs K=16 to demonstrate
the predicted +12 dB SNR gain.

### B. External ADC purchase

Pros:
- Likely highest absolute SNR floor (-60 dBFS or better).
- No coherent-averaging assumption.

Cons:
- Requires hardware purchase / setup; not feasible in this
  scope.
- Verifier machine specific; would block this slice indefinitely
  if no ADC is available.

DEFERRED to a future slice. The recommendation is: only resort to
external ADC if option A produces fewer than 12 dB of effective
SNR gain.

### C. Stronger excitation / louder strikes

Pros:
- Trivially raises strike-to-noise ratio.

Cons:
- Re-introduces the M2-era saturation problem the M3 body filter
  retune was designed around. Voice0 already produces +/- 32767
  peaks at velocity 0x7FFF; pushing harder requires changing
  static parameters (loop_gain, body_mix), which is RTL change.
- Risks audio path saturation or loop instability.

REJECT for M4. Not aligned with the user's "voice quality over
polyphony" priority.

### D. B2 runtime body knob

Pros:
- Single capture sweeps multiple body_mix values without
  reprogramming.
- Useful as a measurement amplifier (large delta values ->
  measurable change vs noise).

Cons:
- Doesn't address the actual SNR limitation; bigger deltas are
  measurable but the noise floor problem persists for all future
  slices.
- Adds UART command surface (parser + status changes) that the
  M3 scope explicitly deferred.

DEFER to M5 fallback if option A is insufficient.

### E. No-op / defer

REJECT. M3 verdict CONDITIONAL_PASS specifically blocks decisive
voice-quality A/B work until SNR improves. Deferring measurement
infrastructure now means the next timbre RTL slice is blocked on
the same problem.

## 4. M4 recommended slice deliverables

### Files touched

| Path | Change | Lines |
| --- | --- | ---: |
| `scripts/phase6_m1_voice_bench.py` | Add `--repeats K` flag; per cell, send K consecutive reset+strike events with appropriate timing; record K-tuple of send timestamps in the sidecar `cells[i].repeats[]`. | ~50 |
| `scripts/phase6_m1_voice_analyze.py` | Add `--coherent-average` (default off) that reads sidecar repeats and coherently sums per-cell time-locked windows before FFT band computation. Add per-cell SNR report (strike-window RMS / silence-window RMS). | ~80 |
| `scripts/phase6_m4_noise_floor.py` (new) | Capture pure silence (no UART activity, no strikes), compute spectral noise floor, report hum frequencies (60/120/180 Hz), Gaussian-vs-structured noise classification. | ~150 |
| `reports/phase6_m4_repeated_capture_impl.md` (new) | Implementation report with self-check evidence and a deferral note for live hardware verification. | new |

### Files NOT touched

- All `rtl/*` files (no RTL change).
- `quartus/phase0/piano_phase0_top.qsf`.
- `obsolete/`.
- `scripts/phase3_*.py` (Phase 3 host wrappers).
- `scripts/phase5_m3_p5m2_decode.py`.
- Verifier-protected untracked files / `.kiro/`.

### UART / RTL surface

NONE. No new commands, no new RTL. The bench uses the existing
`!I1`, `!I0`, `!F`, `!NLLLLVVVV` commands.

### Stimulus design

Per cell, repeated K times:

```
1. Send `!F\r\n` (silence and reset voice0; M1.2 semantics)
2. Wait settle_s (default 1.0 s)
3. Send `!N{loop_len_hex}{velocity_hex}\r\n` (strike)
4. Wait capture_s (default 4.0 s)
5. Wait pause_s (default 1.0 s)
```

All K events for a cell happen back-to-back before moving to the
next cell. Total per-cell time = K * (settle_s + capture_s + pause_s)
= K * 6.0 s. Total run for a 5-cell focus list at K=16 =
5 * 16 * 6 s = 480 s = 8 min.

### Sidecar format extension

```json
{
    "schema": "phase6_m1_voice_bench.v2",
    "repeats": K,
    "cells": [
        {
            "index": 0, "loop_len": 127, "velocity": 0x2000,
            "command": "!N007F2000",
            "send_t_session_s": [t0, t1, t2, ..., tK-1]
        },
        ...
    ]
}
```

The schema bump (`v1` -> `v2`) lets the analyzer detect repeats
mode. K=1 is identical to v1 behavior except `send_t_session_s`
is wrapped in a list.

### Coherent averaging math

For a cell with K strikes at times `t_0 ... t_{K-1}` and capture
window length W samples, the analyzer:

1. For each strike `i in [0, K)`, extract samples
   `s_i[0..W-1]` starting at `t_i + audio_offset`.
2. Compute the coherent average:
   `avg[w] = (sum_{i} s_i[w]) / K` for `w in [0, W)`.
3. Apply Hann window and FFT to `avg[]`.
4. Compute FFT band magnitudes per the existing M3 pipeline.

For a strike with deterministic excitation and additive Gaussian
chain noise:
- Time-locked excitation: `K * peak_strike` after summing.
- Noise: `K * sigma * randn` summed -> `sigma * sqrt(K)` RMS.
- After /K normalization: signal stays at `peak_strike`, noise
  drops to `sigma / sqrt(K)`.
- SNR gain: `+10*log10(K) dB`.

At K=16 -> +12 dB. The expected M3 band delta of 3-5 dB now
sits 7-9 dB above the (averaged) noise floor.

### Per-cell SNR report

The analyzer computes for each cell:

- `strike_rms_dbfs`: RMS of the strike-window after coherent
  averaging.
- `noise_rms_dbfs`: RMS of a known-silent window (pre-strike or
  inter-strike pause).
- `snr_db = strike_rms_dbfs - noise_rms_dbfs`.

A cell with `snr_db >= 20` is "usable for individual A/B"; cells
with `snr_db >= 10` are usable for FFT band comparisons. Cells
below `snr_db = 10` should be marked indeterminate.

### Noise-floor characterization

`scripts/phase6_m4_noise_floor.py`:
- Programs nothing; assumes M2/M3 SOF is already on the board.
- Runs `!F\r\n` once (drain), then captures 30 s of pure silence
  via the same audio capture path used in M3.
- Computes:
  - Overall RMS dBFS (target for `noise_rms_dbfs` baseline).
  - Spectral magnitude at known interference frequencies: 50 Hz,
    60 Hz, 100 Hz, 120 Hz, 180 Hz, 240 Hz.
  - Gaussian-fit chi-squared for time-domain samples.
  - Worst FFT bin in 0-10 kHz range.

A clean Gaussian chain shows uniform spectrum, no spikes at
power-grid harmonics. A noisy chain (e.g. SMPS hum) shows spikes
at 60/120 Hz that coherent averaging cannot remove. Reporting
this lets us decide whether software-only averaging is enough or
external ADC is required.

### Sample size / variance gates

Per cell at K=16:
- Coherent-averaged SNR >= 10 dB (8 dB margin above the chain
  Gaussian RMS).
- Run-to-run variance across 3 separate K=16 captures of the
  same cell <= 1 dB in any 500 Hz band.

If both gates PASS on at least 4 of 5 focus cells (2/5/8/9/11),
M4 is declared sufficient and future timbre A/B tests can use
the K=16 averaging mode as the standard methodology.

If gates FAIL, M4's `phase6_m4_noise_floor.md` should classify
the noise structure (Gaussian vs hum-dominated vs SMPS-induced)
and recommend either external ADC purchase or B2 runtime body
knob as the M5 fallback.

### LE/timing budget

NONE (no RTL change).

## 5. Implementer task text (orchestrator-ready)

> Implement Phase 6 M4: software-only repeated-capture coherent
> averaging for audio-chain SNR improvement.
>
> Read first:
> - `reports/phase6_m4_audio_chain_snr_scope.md` (this scope)
> - `reports/phase6_m3_body_warmth_validation.md`
> - `reports/phase6_m2_velocity_brightness_validation.md`
> - `reports/phase6_m1_2_voice_reset_baseline_validation.md`
> - `scripts/phase6_m1_voice_bench.py`
> - `scripts/phase6_m1_voice_analyze.py`
>
> Required deliverables:
>
> 1. Modify `scripts/phase6_m1_voice_bench.py`:
>    - Add `--repeats K` argument (default 1).
>    - When K > 1, each cell sends K back-to-back reset+strike
>      events using the existing `!F` and `!NLLLLVVVV` commands
>      with the M1.2 reset-on-!F semantics.
>    - Sidecar schema bumps to `phase6_m1_voice_bench.v2` and
>      each cell records a list of send timestamps.
>    - `--self-check` validates: (a) K=1 backward-compatible
>      sidecar matches v1 layout when repeats=1; (b) K=4
>      grid command bytes; (c) sidecar JSON round-trip.
>    - `--plan` shows the K-multiplied total time and example
>      send sequence.
>
> 2. Modify `scripts/phase6_m1_voice_analyze.py`:
>    - Detect sidecar schema v1 vs v2.
>    - Add `--coherent-average` flag (default OFF).
>    - When set with v2 sidecar, extract K strike windows per
>      cell, coherently average them in time domain, compute FFT
>      band metrics on the averaged window.
>    - When set with v1 sidecar, ignore the flag with a warning.
>    - Add per-cell SNR computation: `snr_db = strike_rms - noise_rms`.
>    - Output CSV gains a `repeats` column and `snr_db` column.
>    - `--self-check` validates the coherent averaging math
>      against a synthetic test vector with known SNR (Gaussian
>      noise + deterministic decaying sine).
>
> 3. New `scripts/phase6_m4_noise_floor.py`:
>    - Pure-Python (stdlib + pyserial). ASCII-only.
>    - Captures 30 s of pure silence via existing audio capture
>      flow.
>    - Computes overall RMS dBFS, spectral magnitudes at
>      50/60/100/120/180/240 Hz, Gaussian-fit chi-squared.
>    - Reports a one-line classification: "GAUSSIAN_CLEAN" /
>      "HUM_60HZ_DOMINATED" / "GAUSSIAN_PLUS_HUM" / etc.
>    - `--self-check` mode validates the classifier against
>      synthetic vectors.
>
> 4. New `reports/phase6_m4_repeated_capture_impl.md`:
>    - Documents both `--self-check` outputs.
>    - Documents the coherent-averaging math and SNR target.
>    - Defers live hardware capture to the M4 verifier task.
>
> Hard validation gates:
>
> - All three Python `--self-check` modes PASS.
> - No RTL/QSF/firmware/obsolete change.
> - No new UART command syntax.
> - ASCII-only on all touched files.
> - Sidecar schema v2 must be backward-compatible: a v2 sidecar
>   with K=1 must analyze identically to a v1 sidecar (modulo
>   the new SNR column).
> - The coherent-averaging math `--self-check` synthetic test
>   must demonstrate the expected `+10*log10(K) dB` SNR gain at
>   K=16 to within 0.5 dB.
>
> Stop-and-report (NO-GO) triggers:
> - Self-check synthetic shows materially less than +12 dB SNR
>   gain at K=16 (would mean the algorithm is wrong).
> - Sidecar v2 fails JSON round-trip.
>
> Live hardware capture is deferred to the M4 verifier task per
> project discipline rule.
>
> Refs: `task-54137ef2`.

## 6. Verifier task text (orchestrator-ready)

> Validate Phase 6 M4 software-only SNR improvement.
>
> Required:
>
> 1. Confirm only the expected files changed (3 scripts + 1
>    report). No RTL/QSF/firmware change.
> 2. Re-run all 3 implementer `--self-check` modes (bench,
>    analyzer, noise-floor). All PASS.
> 3. Run the noise-floor characterization on the verifier
>    machine. Record the classification and the spectral
>    magnitudes at 50/60/100/120/180/240 Hz.
> 4. Run the M3 build (currently programmed) with the bench's
>    new `--repeats 16 --single-voice-isolate` flag against the
>    5 focus cells (2, 5, 8, 9, 11). One full capture run. WAV
>    saved locally; do not commit.
> 5. Run the analyzer with `--coherent-average` against the K=16
>    capture. Record per-cell SNR.
> 6. Compute FFT band comparisons against the M2 baseline (which
>    was a K=1 capture). The K=16 result should show the expected
>    M3 body warmth gains (+3-5 dB at 1-3 kHz, brightness preserve
>    at 4-7 kHz) within the run-to-run variance gate.
> 7. (Optional, recommended) Run the same K=16 protocol against
>    the M2 SOF (reprogram briefly), to provide a clean K=16 vs
>    K=16 A/B that does not depend on M2's K=1 baseline.
> 8. Validate the variance gate: re-run a K=16 capture of one
>    cell 3 times; FFT band variance across the 3 runs should be
>    <= 1 dB.
>
> Acceptance criteria:
>
> - Self-checks PASS.
> - Noise-floor characterization completes and reports a
>   classification.
> - K=16 captures show >= 10 dB SNR on at least 4 of 5 focus
>   cells.
> - K=16 vs K=16 M2/M3 A/B shows the expected M3 warmth
>   improvement and brightness preservation.
> - Run-to-run variance gate PASS.
>
> If any criterion fails, the verifier should classify the
> failure as "noise floor exceeds software averaging capability"
> (recommend M5 = external ADC) or "M4 software is buggy"
> (return to implementer with details).
>
> Submit `reports/phase6_m4_repeated_capture_validation.md`.

## 7. Out of scope for this scope task

- No RTL change. No QSF change. No firmware change. No obsolete
  archive change.
- No CPU/firmware/MMIO/register-file revival.
- No new UART command syntax.
- No polyphony feature work.
- No edits to `.kiro/` or verifier-protected untracked artifacts.

ASCII-only by construction.

## 8. Honest assessment

This M4 slice is the right next step but it is fundamentally a
**measurement infrastructure** improvement, not a voice-quality
improvement. The user's stated priority is voice quality; the
honest argument for spending an M4 cycle on measurement is that
the next 3-5 voice-quality slices will be blocked on the same
SNR problem M3 hit. Investing once in coherent averaging unlocks
those slices.

The weakness of this M4: if the audio chain has time-locked
structured noise (60 Hz hum, SMPS spikes at predictable
frequencies), coherent averaging cannot remove it. The
noise-floor characterization deliverable detects this case
explicitly so we don't claim success when the chain is actually
hum-dominated.

If the M4 verifier finds chain noise is hum-dominated (i.e. K=16
averaging gets less than 6 dB of effective SNR gain), the M5
recommendation should be:

- Procure a small line-in capture device (USB-audio with proper
  gain staging), OR
- Implement B2 runtime body knob so a single capture can sweep
  body_mix values and produce larger intra-run deltas, OR
- Both.

The M4 verifier task is the correct gate to make that decision.

This M4 is conservative: software-only changes, host tools
unchanged in their command surface, the existing M1.2/M2/M3 SOF
on the board can be A/B'd against without reprogramming.
