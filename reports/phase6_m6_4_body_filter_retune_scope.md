# Phase 6 M6.4 Body-Filter Retune Scope

Date: 2026-05-27
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-5c38456e`
Branch: `codex/phase1c-uart-boundary-fix`
Parent commit: `5ca80d9` (M6.3a body magnitude doubling) /
`969fe9f` (M6.3a verifier validation)

## TL;DR

**Recommendation: NO-GO on coefficient-only retune of
`phase0_body_filter`. Pivot to internal-FIR M6.4-INT.**

Mathematically, the post-mix `phase0_body_filter` cascade
**cannot** change the dB delta the verifier measures between
two body_mix sweep values, at any frequency. The filter is
linear and applied to `(disp_sample + body_contrib)` jointly,
so it factors out of the delta:

```
delta_dB(f) = 20*log10( |H_filter(f) * (disp + body_high)|
                      / |H_filter(f) * (disp + body_low)| )
            = 20*log10( |disp + body_high| / |disp + body_low| )
```

The filter response cancels. This is reproduced numerically in
`reports/m6_4_compute_response.py` (committed) and matches the
M6.3a verifier evidence band-for-band:

| band   | predicted (this analysis) | M6.3a hardware (averaged A4+C5) |
| ------ | ------------------------:| -------------------------------:|
| 50-200 |               +2.02 dB   |                       +1.39 dB  |
| 200-500|               +1.81 dB   |                       +1.16 dB  |
| 500-1k |               +1.79 dB   |                       +1.90 dB  |
| 1-2k   |              **+2.80 dB**|                       +1.16 dB  |
| 2-3k   |               -0.81 dB   |                       -0.36 dB  |

Predicted 1-2k delta is +2.80 dB and predicted 2-3k delta is
-0.81 dB. The hardware shows similar shape with broadband
chain-noise smearing. The 2-3 kHz negative is a real
phase-cancellation artifact of the internal 3-tap FIR, not a
filter or measurement issue.

The right fix is **inside `phase1_reduced_voice.v`'s 3-tap body
FIR**, not in `phase0_body_filter`. Section 4 lays out a
proposed FIR retune (M6.4-INT) and proposed task text.

## 1. Inputs

Reviewed:

- `reports/phase6_m6_3a_body_gain_validation.md`
- `reports/phase6_m6_3a_inrange_band_analysis.txt`
- `reports/phase6_m6_3a_default_band_analysis.txt`
- `reports/phase6_m6_3a_inrange_sweep.csv`
- `reports/phase6_m3_body_warmth_impl.md`
- `reports/phase6_m3_body_warmth_validation.md`
- `reports/phase6_m3_next_voice_quality_scope.md`
- `rtl/audio/phase0_body_filter.v` (live coefficients
  inspected at HEAD)
- `rtl/audio/phase0_audio_path.v` (filter placement: post-mix,
  post-saturation)
- `rtl/audio/phase1_reduced_voice.v` (internal body FIR taps
  6, 16, 30; post-M6.3a coefficients 1/2, -1/4, +1/8)

Numerical helper: `reports/m6_4_compute_response.py`
(committed; reproducible Python stdlib analysis).

## 2. Live `phase0_body_filter` response

Two cascaded biquads at `Fs = 46875 Hz`, applied post-mix on
the summed 4-voice signal:

| f Hz | B1 (low-shelf) dB | B2 (peaking) dB | cascade dB |
| ---: | ---------------: | --------------: | ---------: |
|   50 |          +5.97   |          +0.03  |     +6.00  |
|  100 |          +5.56   |          +0.03  |     +5.59  |
|  200 |          +2.93   |          +0.05  |     +2.98  |
|  300 |          +1.05   |          +0.09  |     +1.14  |
|  500 |          +0.19   |          +0.21  |     +0.40  |
|  700 |          +0.06   |          +0.45  |     +0.51  |
| 1000 |          +0.02   |          +1.21  |     +1.23  |
| 1200 |          +0.01   |          +2.09  |     +2.11  |
| **1500** |      +0.01   |      **+2.99**  |   **+2.99** |
| 1800 |          +0.00   |          +2.24  |     +2.25  |
| 2000 |          +0.00   |          +1.65  |     +1.65  |
| 2500 |          +0.00   |          +0.81  |     +0.81  |
| 3000 |          +0.00   |          +0.47  |     +0.48  |
| 4000 |          +0.00   |          +0.22  |     +0.22  |

The M3 retune is correctly implemented: biquad 2 peaks at
+2.99 dB at 1500 Hz with Q=1.5. The low-shelf adds bass
warmth as designed. **There is no bug in the live filter.**

## 3. Why M6.3a body_mix delta did not show up at 1-3 kHz

### 3.1 The body filter sees the SUM, not the body alone

Architecture (verified at HEAD):

```
phase1_reduced_voice (x4)  -->  phase0_audio_path mix --> phase0_body_filter --> codec
   |
   produces sample_data_q15 = q18_to_q15(disp_sample
                                         + body_contrib)
```

`body_contrib = body_FIR_3tap(disp_sample) * body_mix_q15 / 32768`
inside the voice. The summed mix is then passed through the
body filter cascade as one block.

Linearity: H_filter(f) is applied identically to the
high-body-mix and low-body-mix outputs, so when the verifier
computes `delta_dB(f)` between two sweeps:

```
output(f, gain) = H_filter(f) * H_disp_to_mix(f) * (1 + H_FIR(f) * gain)
delta_dB(f)     = 20*log10(|1 + H_FIR(f)*gain_high|
                          / |1 + H_FIR(f)*gain_low|)
```

H_filter(f) and H_disp_to_mix(f) cancel. The delta is
purely a function of the internal `H_FIR(f)` and the gain
swing. Sanity-check confirmed numerically in
`reports/m6_4_compute_response.py`: the "filter present" and
"filter removed" tables in section 4 of the helper output
are byte-for-byte identical (the two cancel exactly in
floating point under uniform mix assumptions).

### 3.2 The 3-tap body FIR puts most energy below 1 kHz and
has a near-null at 2-3 kHz

Internal FIR (post-M6.3a doubling):

```
H_FIR(z) = 0.5 * z^-6 - 0.25 * z^-16 + 0.125 * z^-30
```

Magnitude / phase response at Fs=46875 Hz:

| f Hz | |H_FIR| dB | phase deg |
| ---: | ---------:| ---------:|
|   50 |    -8.54  |     -2.8  |
|  100 |    -8.62  |     -5.6  |
|  200 |    -8.90  |    -10.6  |
|  300 |    -9.34  |    -14.7  |
|  500 |   -10.43  |    -17.2  |
|  700 |   -10.67  |    -11.3  |
| 1000 |    -7.82  |     -7.6  |
| 1200 |    -5.48  |    -16.6  |
| 1500 |    -2.94  |    -39.7  |
| 1800 |    -1.64  |    -67.1  |
| 2000 |    -1.39  |    -85.9  |
| 2500 |    -2.59  |   -128.8  |
| 3000 |    -5.00  |   -155.3  |
| 4000 |    -5.61  |   +148.9  |

Two structural facts about this FIR:

1. **Largest gain band is 1.5-2.5 kHz** (`-1.4` to `-3` dB),
   not 200-1000 Hz. The body component is in the right band
   in absolute terms.
2. **Phase rotates rapidly through 1-3 kHz**. At 1.5-2 kHz
   the body contribution lags the mix by about -40 to -86
   degrees (still mostly in-phase, additive). At 2-3 kHz
   the body component flips toward 180 degrees out of phase
   (-128 to -155 degrees), which means doubling its magnitude
   actually **reduces** total band energy by partial
   cancellation with disp_sample.

This is exactly the M6.3a verifier observation: 1-2k delta
+1.16 dB (positive but small), 2-3k delta -0.36 dB (slightly
negative). Both predicted by the FIR phase rotation.

### 3.3 The "200 Hz - 1 kHz dominant" appearance is partly
a chain-noise-floor artifact

In `reports/phase6_m6_3a_inrange_band_analysis.txt`, the
200-500 Hz and 500-1k Hz bands show large positive deltas
(+1.16 dB and +1.90 dB averaged), which the verifier
interpreted as "body magnitude went up below 1 kHz." The
analysis above shows the predicted FIR-driven delta in those
bands is ~+1.8 dB - close to the observed +1.16 to +1.90 dB.
The discrepancy in 1-2k is partly because the FIR delta there
is ~+2.8 dB (predicted) vs +1.16 dB measured, a 1.5-2 dB gap
attributable to chain noise / cell variance.

The verifier's framing ("body filter coefficients didn't push
energy into 1-3 kHz") is reasonable but misses that the
filter cannot push the delta into a band; only the FIR can.

## 4. Why the four candidate paths fan out

### 4.1 Coefficient-only `phase0_body_filter` retune (REJECTED)

Variants considered:
- Stronger biquad 2 peak at 1500 Hz (+6 dB instead of +3 dB).
- Move biquad 2 peak to 2000-2500 Hz.
- Adjust biquad 1 low-shelf to attenuate sub-1 kHz instead of
  boost.

All three are **functionally null** for the M6.3a body_mix
delta gate, by the cancellation argument in section 3.1. The
filter sees the summed signal `(disp + body)`. Multiplying
the sum by H_filter(f) at any frequency does not change the
ratio of two sums that share the same H_filter(f).

A filter retune still has audible value (different overall
tone color), but it does NOT move the verifier's 1-3 kHz
delta acceptance metric.

**Reject coefficient-only retune.**

### 4.2 Stronger/narrower biquad 2 peak in 1-3 kHz (REJECTED)

Same cancellation argument as 4.1.

### 4.3 Adjust biquad 1 low-shelf to reduce sub-1 kHz (REJECTED)

Same cancellation argument as 4.1.

### 4.4 Internal 3-tap FIR retune (RECOMMENDED, M6.4-INT)

The only way to change the body_mix delta in any specific
band is to change `H_FIR(f)`. Two structural levers:

A. **Move the FIR taps** to shift the response shape. Tap
   delays 6/16/30 produce nulls and peaks at frequencies
   determined by `Fs / (delay difference)`. Different tap
   positions (e.g. 4/12/24) give different peak/null
   placement.

B. **Re-weight the FIR coefficients** to change the relative
   contribution of each tap. The sign pattern (`+, -, +`) is
   what creates the band-pass-like shape; changing signs or
   relative magnitudes shifts that shape.

Goal: get the FIR to have:

- More gain in 1-3 kHz (currently -3 to -5 dB across this
  band).
- Less phase rotation in 2-3 kHz so the body adds rather than
  cancels (currently -128 to -155 degrees at 2.5-3 kHz).

Sketch of one viable retune (NOT a final design):

```
H_FIR_v2(z) = 0.5 * z^-4 - 0.25 * z^-12 + 0.125 * z^-24
```

The shorter delays (4/12/24 instead of 6/16/30) move the
first FIR null up by ~50% in frequency, pushing more energy
into 1-2 kHz and reducing the 2-3 kHz null. Without
running it through `phase1_reduced_voice`'s actual
strike-driven body history, this is a starting point, not a
verified design.

**Practical concern**: changing `body_history` tap addresses
requires changes inside `phase1_reduced_voice.v` at
`STATE_BODY_TAP6`/`16`/`30` (the addr generation) and
possibly `body_wr_ptr` width. That is more invasive than
the M6.3a single-line shift. It also forces a golden-hex
regeneration (vsim license-blocked on this host).

### 4.5 Other voice-quality axes (DEFER, not in scope)

E.g. add hammer noise component, second loop pole, stiffness,
etc. Out of scope for M6.4 which is explicitly about getting
the body_mix knob to register at 1-3 kHz.

## 5. Recommendation

**M6.4 = NO-GO on body filter retune. Replace with M6.4-INT:
internal FIR re-weighting / re-tapping inside
`phase1_reduced_voice.v`.**

The body filter retune cannot move the verifier's measurement
at any frequency. Spending an implementation slice on it
would be wasted effort and would risk audible side effects
(different overall tone color) without any benefit to the
acceptance gate.

The internal FIR change is the structurally correct lever
but is a more invasive RTL change than M6.3a was. Before
implementation, M6.4-INT needs its own scope task to:

1. Pick exact tap delays (4/12/24? 5/13/25? evidence-driven).
2. Pick exact tap weights to balance band shape vs Q18
   saturation headroom.
3. Verify simulation predicts the desired band-energy delta
   shift toward 1-3 kHz.
4. Estimate LE cost of changing tap addresses in
   `STATE_BODY_TAP*` states (probably small; tap addresses
   are wires today).

Alternative path the orchestrator may prefer: **defer further
body work** and move to a different voice-quality axis
(e.g. hammer texture, attack shaping, chorus/detune, longer
release) where the audible payoff per LE is higher. The body
knob is now functional and operator-tunable; the strict 1-3
kHz acceptance gate may be an over-constraint.

## 6. Proposed task text

### M6.4 implementer task: NO-GO containment

> Replace task-5c38456e's M6.4 RTL implementation slice with
> a NO-GO containment commit. The M6.4 scope task report
> (this file) demonstrates that coefficient-only retune of
> `phase0_body_filter` cannot move the body_mix delta at any
> frequency by linearity (the filter sees the summed signal,
> not the body alone). The recommended next slice is
> internal-FIR M6.4-INT, which has its own scope task.
>
> Action: orchestrator should not assign an M6.4 implementer
> task for `phase0_body_filter` retune. Either queue
> M6.4-INT-scope (separate planning task to design the
> internal FIR change) or pick a different voice-quality
> axis.

### M6.4-INT scope task (proposed, if orchestrator wants to
   pursue body)

> Scope an M6.4-INT internal-FIR retune in
> `phase1_reduced_voice.v`. Examine alternative tap delays
> and weights that:
> - Shift the peak FIR response from current 1.5-2 kHz to
>   center on 1-3 kHz.
> - Reduce phase rotation through 2-3 kHz so body adds rather
>   than cancels with disp.
> - Stay within Q18 internal saturation headroom and the
>   existing body_history M9K storage.
> Estimate LE cost (probably small but non-zero), simulation
> requirements (golden hex regeneration; vsim required), and
> deliver a recommended tap design in a scope report.
> Implementer task to follow if scope confirms feasibility.

### M6.4 verifier task: validation of NO-GO

> Validate the M6.4 NO-GO scope/containment. Confirm:
> 1. Scope: only `reports/phase6_m6_4_body_filter_retune_scope.md`
>    plus optional helper `reports/m6_4_compute_response.py`
>    changed.
> 2. ASCII-only on touched files.
> 3. Mathematical claim independently re-derivable: filter
>    cancellation in the body_mix delta. Reproduce the
>    numerical analysis (the helper script is committed).
> 4. M6.3a-accepted RTL/golden state at HEAD `5ca80d9`
>    unchanged.
> 5. Submit `reports/phase6_m6_4_body_filter_retune_validation.md`.

## 7. Out of scope

- No RTL change.
- No QSF/SDC/PLL/firmware/host-script change.
- No body_filter coefficient retune (recommended NO-GO).
- No internal FIR retune in this task (would be M6.4-INT
  follow-up).
- No body-only diagnostic mode.
- No coherent-average harness extension.
- No new UART command syntax.
- No CPU/MMIO/firmware/register-file revival.
- No JTAG command path.
- No on-chip strike scheduler.
- No polyphony feature work.
- No edits to verifier-protected untracked files.

## 8. Files

This commit:

- `reports/phase6_m6_4_body_filter_retune_scope.md` (this
  report, new).
- `reports/m6_4_compute_response.py` (numerical analysis
  helper; committed so verifier can independently reproduce
  the cancellation result and band-delta numbers; pure
  stdlib).

Both ASCII-only.

## 9. ASCII check

```
reports/phase6_m6_4_body_filter_retune_scope.md  non_ascii=0
reports/m6_4_compute_response.py                 non_ascii=0
```
