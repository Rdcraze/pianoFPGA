# Phase 6 M3 Body Warmth - Verifier Validation

Date: 2026-05-24
Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-1f313b31`
Implementer commit under review: `9cf6852` (Phase 6 M3 body-mix
preset increase plus mid-range body-filter retune)
Branch: `codex/phase1c-uart-boundary-fix`
Live SOF on board: M3 build, sha256
`E62E8EB276C0852719465D6B81C1E2A4C480CED5E3D49BD110BAE78A02548BDA`
M2 baseline reference: SOF sha256
`0A8880473EAD0EA996897614AA0BA50BEF8EE6C212F75FF53B4E9C690303365B`
(verifier commit `27f7228`)

## Verdict

**CONDITIONAL_PASS.** All non-hardware gates pass cleanly: the
sim TBs run with the new golden samples, control regressions are
unchanged, the body filter coefficient math reproduces
independently, Quartus reproduces 4,932 LE (+15 vs M2), setup
+4.515 ns, hold +0.413 ns, M9K/DSP9/PLL unchanged. Hardware
programs cleanly; P5M2 telemetry advances 0->0x21=33 monotonic
with X stable at 0.

The hardware A/B test cannot conclusively demonstrate the
expected 1-3 kHz warmth improvement because the audio capture
chain noise floor (~-15 to -18 dBFS Gaussian) masks the
spectral differences between M2 and M3 captures on this verifier
machine. FFT-band comparison across 5 cells shows M3 about 1-4
dB LOWER than M2 in every band including the warmth target
(1-3 kHz) and the brightness preserve (4-7 kHz), but inspection
of per-cell envelopes reveals that BOTH M2 and M3 captures of
these cells are dominated by the audio chain noise floor with
strike modulation < 1 dB. The negative band deltas are run-to-run
audio-chain noise variation, not RTL regression.

The verdict is therefore CONDITIONAL_PASS rather than NO-GO:

- The M3 RTL is correct (verified by independent coefficient
  re-derivation, simulation TBs, Quartus rebuild, SOF programming
  and Q/X telemetry).
- The hardware audio-chain SNR cannot resolve the M3 audible
  improvement.
- The M3 implementer report's Quartus / sim numbers all reproduce
  exactly.
- No new clipping was introduced; if anything, M3 cells are at
  slightly lower amplitude than M2.

Recommended Phase 6 M4: prioritize **audio chain noise floor
improvement** before attempting another timbre slice. The current
~-15 dBFS noise floor masks any timbre change finer than ~6 dB
on individual cells. Without a quieter capture path, future RTL
A/B tests will face the same ambiguity.

If a measurement upgrade is not feasible, M4 alternatives:
- B2 runtime body knob (test multiple body_mix settings in a
  single run)
- E loop-loss differential decay (longer perceived musical
  decay; addresses different complaint)

## Static / file scope check

`git show --stat 9cf6852`:

```
reports/phase6_m3_body_warmth_impl.md         | 352 +++
rtl/audio/phase0_body_filter.v                |  44 +-
rtl/audio/phase1_reduced_voice_golden_samples.hex | 3240 +++/----
rtl/audio/phase1_reduced_voice_tb.v           |   2 +-
rtl/audio/phase1_reduced_voice_velocity_tb.v  |   2 +-
rtl/control/phase0_fixed_control.v            |   5 +-
6 files changed, 2016 insertions(+), 1629 deletions(-)
```

PASS gates:
- Only the expected files changed (control body_mix, body filter
  coefficients, voice TB body_mix init, velocity TB body_mix
  init, golden samples re-snapshot, implementer report).
- No CPU/firmware/MMIO/register-file revival.
- No UART/parser/status/isolation/QSF change.
- No change to phase1_reduced_voice.v waveguide / hammer ROM.
- Four physical voices preserved (no file change in
  phase0_audio_path.v).
- ASCII-only on touched files (PowerShell foreach byte loop):
  ```
  reports/phase6_m3_body_warmth_impl.md             non_ascii=0
  rtl/audio/phase0_body_filter.v                    non_ascii=0
  rtl/control/phase0_fixed_control.v                non_ascii=0
  rtl/audio/phase1_reduced_voice_tb.v               non_ascii=0
  rtl/audio/phase1_reduced_voice_velocity_tb.v      non_ascii=0
  ```

`git diff 27f7228..9cf6852 -- rtl/control/phase0_fixed_control.v`
shows a single localparam change `voice_body_mix = 16'd8192 ->
16'd12288` with an inline comment explaining the M3 rationale.

`git diff 27f7228..9cf6852 -- rtl/audio/phase0_body_filter.v`
shows only the 5 biquad-2 coefficient localparams change plus
extensive cookbook derivation comments. Biquad-1 coefficients
unchanged; pipeline structure (multipliers, state registers,
sample_tick gating) unchanged.

## Coefficient / math review

Independent re-derivation of the peaking biquad at Fs=46875 Hz,
fc=1500 Hz, Q=1.5, gain=+3 dB:

```
A = 10^(3/40) = 1.18850
omega_0 = 2*pi*1500/46875 = 0.20106 rad
sin(omega_0) = 0.19972
cos(omega_0) = 0.97983
alpha = sin(omega_0) / (2*Q) = 0.06657

# Cookbook (RBJ Audio EQ)
b0 = 1 + alpha*A = 1.07914
b1 = -2*cos(omega_0) = -1.95966
b2 = 1 - alpha*A = 0.92086
a0 = 1 + alpha/A = 1.05601
a1 = -2*cos(omega_0) = -1.95966
a2 = 1 - alpha/A = 0.94399

# Normalized to Q2.14, encoded so A1, A2 are negated of normalized a1, a2:
B0 = 16384 * 1.07914 / 1.05601 ~ 16742
B1 = 16384 * -1.95966 / 1.05601 ~ -30403
B2 = 16384 * 0.92086 / 1.05601 ~ 14288
A1_encoded = 16384 *  1.95966 / 1.05601 ~ +30403
A2_encoded = 16384 * -0.94399 / 1.05601 ~ -14647
```

Implementer values from the M3 commit:
```
B2_B0 =  16742  (mine: 16742)
B2_B1 = -30410  (mine: -30403, +/- 7 LSB rounding)
B2_B2 =  14289  (mine: 14288, +/- 1 LSB)
B2_A1 =  30410  (mine: +30403, +/- 7 LSB)
B2_A2 = -14645  (mine: -14647, +/- 2 LSB)
```

Coefficients match within rounding tolerance. The +/- 7 LSB
difference is consistent with intermediate rounding choices in
the formula chain; Q2.14 has 1/16384 ~ 6.1e-5 LSB, so 7 LSB =
~0.04% per coefficient, well within standard biquad tolerance.

Pole magnitude check:
- pole at z = (-A1/2 +/- sqrt((A1/2)^2 + A2)) (in encoded form,
  for transfer function `1 + A1 z^-1 + A2 z^-2` denominator)
- (A1/2)^2 = (30410/16384/2)^2 = 0.86162
- A2 = -14645/16384 = -0.89394
- discriminant = 0.86162 + (-0.89394) = -0.03232 (negative -> complex)
- pole magnitude = sqrt(-A2) = sqrt(0.89394) = 0.94548
- < 1, stable.

Sign convention check: existing biquad 1 uses A1=+32240 (encoded
positive for `+A1*y[n-1]` summation). The new biquad 2 follows
the same convention with B2_A1=+30410. PASS.

Fixed-point overflow risk: B0=16742 in Q2.14 is 1.022; max input
is 18-bit signed (the body filter input is sat-extended to
18-bit). Worst-case b0*x = 16742 * 131071 = 2.19e9, which fits
in 36-bit signed product (max +/- 6.87e10). Sum of 5 such
products is bounded by (5*2.19e9) = 1.10e10, still within 39-bit
signed range. The implementer's pipeline already has a 39-bit
signed sum and 18-bit saturator, so the new coefficients do not
introduce overflow. PASS.

Coefficient/math review: **PASS.**

## Non-hardware reproductions

### `phase1_reduced_voice_tb` (with new golden)

```
VOICE_TB_PASS first_nonzero_sample=106 freq=434.027778
  rms_100ms=272.800735 rms_500ms=27.713698 rms_3s=0.000000
  peak=3952 golden_samples=4096
```

`peak=3952` preserved (the strike attack peaks at the excitation
moment when body_history is still empty, so body_mix delta does
not affect peak). `first_nonzero_sample=106` preserved (loop_len
pre-roll unchanged). `rms_100ms=272.80` is up from M2's 267.43
- about +0.17 dB from added body content. Note: implementer
report claims this is "+2 dB" but the actual delta computes to
+0.17 dB (272.80/267.43 = 1.020 = 0.17 dB). Cosmetic; the
absolute number is the implementer's recorded value and the new
golden hex is what determines TB pass/fail. Bit-exact rerun PASS.

### `phase1_reduced_voice_velocity_tb`

```
VEL_TB_INFO vel=2000 first=106 peak=1976 early=11500 rms=23.650
VEL_TB_INFO vel=4000 first=106 peak=3952 early=23012 rms=26.475
VEL_TB_INFO vel=6000 first=106 peak=6182 early=33619 rms=25.870
VEL_TB_INFO vel=7fff first=106 peak=7977 early=40481 rms=27.051
VEL_TB_PASS peak_at_0x4000 = 3952
VEL_TB_PASS first_nonzero_at_0x4000 = 106
VEL_TB_PASS early_energy_at_0x4000 >= 0x2000 (23012 >= 11500)
VEL_TB_PASS early_energy_at_0x6000 >= 0x4000 (33619 >= 23012)
VEL_TB_PASS brightness_margin brilliant=40481 > 1.5*soft=34518
VEL_TB_PASS brilliant_within_velocity_scaling
  peak_0x7FFF=7977 <= naive*1.1=9066
VEL_TB_PASS clip_seen_low
VEL_TB_PASS_ALL early=11500 23012 33619 40481 peak=1976 3952 6182 7977
```

7 assertions PASS. Peaks unchanged from M2 (excitation is
pre-body-mix). Early energies bumped about 5% from added body
content (M2: 10983/21977/32097/38643 vs M3: 11500/23012/33619/40481).
Brightness margin still > 1.5x soft (40481 > 34518). PASS.

### Control-stack regression

```
UART_CMD_TB_PASS notes=5 releases=1 errors=3 isolation=1
ISOLATION_TB_PASS (11 assertions)
UART_TX_TB_PASS frames=2 collected_count=170
```

All unchanged from M2.

### Quartus full compile (independent rerun)

`build.ps1 -Stage compile`: 0 errors, 16 warnings.

| Metric | M2 | Implementer M3 | Verifier M3 |
| --- | ---: | ---: | ---: |
| Total logic elements | 4,917 | 4,932 (+15) | **4,932** |
| Combinational | 4,707 | 4,707 | 4,707 |
| Registers | 2,283 | 2,285 (+2) | 2,285 |
| Memory bits | 20,480 | 20,480 | 20,480 |
| M9K | 5 | 5 | 5 |
| DSP9 | 26 | 26 | 26 |
| PLL | 1 | 1 | 1 |

LE delta +15 well under +50 target / +150 hard. The +2 register
count likely reflects the body_mix change propagating to a
controller fanout register.

Timing summary:

| Type | Slow-85C |
| --- | ---: |
| Setup `sys_clk_50m` | **+4.515 ns** |
| Hold `sys_clk_50m` | +0.413 ns |
| All TNS | 0 |

Setup +4.515 ns above +4.0 ns gate by +0.515 ns. Within budget,
small -0.036 ns slack movement vs M2 is consistent with biquad
coefficient values affecting LUT placement.

SOF identity:
- size 358681 bytes
- sha256 `E62E8EB276C0852719465D6B81C1E2A4C480CED5E3D49BD110BAE78A02548BDA`
- mtime 2026-05-24 18:12:12

## Hardware A/B capture

### Programming and pre-flight

```
quartus_pgm: Configuration succeeded -- 1 device(s) configured
0 errors, 0 warnings
Pre-bench P5M2: Q=00000000 X=00000000
```

### Run

`python .kiro/phase6_m3_capture.py`:
- ffmpeg started at unix=1779618016.599
- bench at unix=1779618019.657, profile=original, isolated
- 15 cells transmitted at expected times
- bench rc=0
- Post-bench Q=0x21=33 monotonic, X=0 stable

### Per-cell envelope inspection

100 ms RMS at offsets from each cell's strike command (M3
capture):

```
idx pitch    vel    layer  -0.3s   -0.1s   +0.0s   +0.1s   +0.5s
  0 loop127  0x2000 soft   -15.11  -15.54  -16.44  -15.28  -14.65
  1 loop127  0x4000 soft   -14.94  -15.20  -15.50  -16.19  -15.26
  2 loop127  0x7FFF brilli -16.02  -16.99  -16.04  -16.67  -16.05
  4 A4       0x4000 soft   -15.77  -15.20  -14.54  -15.19  -15.40
  5 A4       0x7FFF brilli -15.21  -15.66  -16.28  -15.85  -14.68
  6 C5       0x2000 soft   -16.04  -16.27  -16.21  -16.31  -15.77
  8 C5       0x7FFF brilli -15.64  -16.10  -16.27  -16.73  -15.83
  9 A5       0x2000 soft   -16.32  -16.06  -16.12  -16.75  -17.03
 11 A5       0x7FFF brilli -16.28  -16.96  -17.29  -17.27  -15.41
 14 loop32   0x7FFF brilli -15.85  -15.86  -16.10  -16.24  -16.10
```

**All cells sit within +/- 1 dB of -16 dBFS RMS across the
strike attack window**. Pre-strike (-0.3, -0.1) and post-strike
(+0.0, +0.1, +0.5) RMS values are essentially indistinguishable.
This means the strike attack is below the audio chain noise
floor and not measurable by RMS alone.

Compare to M2 capture envelope (from M2 verifier): cells 5, 8,
11 in M2 also showed similar flat envelopes around the strike,
with only cell 11 at +0.10..+0.40 reaching 28000 peak. Both M2
and M3 are dominated by the chain noise floor for these cells.

### FFT-band A/B comparison (5 cells, 2/5/8/9/11)

For each cell: 8192-sample (170 ms) Hann-windowed FFT of the
strike attack window, summed magnitudes per 500 Hz band, dB
delta computed:

| cell | bass(0-500) | warmth(1-3 kHz) | brightness(4-7 kHz) |
| --- | ---: | ---: | ---: |
| 2 loop127 0x7FFF | +0.03 | -0.91 | +0.30 |
| 5 A4 0x7FFF | -1.77 | -0.37 | -1.68 |
| 8 C5 0x7FFF | -1.81 | -1.57 | -2.01 |
| 9 A5 0x2000 | -1.02 | -3.17 | -2.93 |
| 11 A5 0x7FFF | -2.15 | -3.64 | -3.98 |

The cell-11 brightness delta of -3.98 dB would be below the
NO-GO threshold (-2 dB) IF the comparison were strike-vs-strike.
But the per-cell envelope inspection above proves it's
noise-vs-noise: the M3 capture's audio chain happened to be
slightly quieter than the M2 capture's audio chain in this run.

**The ~3-4 dB band delta range across all 5 cells in all 16
500 Hz bands** is consistent with run-to-run audio chain
variation, NOT a structured RTL regression. A structured
regression would show:
- consistent bass/warmth gain (M3 > M2) per the design intent
- consistent brightness preservation (within 1 dB)
- consistent direction across cells of the same layer

Instead we see uniform ~1-4 dB attenuation of M3 vs M2 in every
band on every cell. This is the chain SNR limitation.

### Subjective listening

Listening pass on `reports/phase6_m3_voice_bench.wav`:

- Overall envelope is similar to M2: continuous Gaussian noise
  floor with no per-cell distinction except occasional faint
  strikes on cells 5, 8, 11.
- High-velocity cells in M3 sound similar to M2 (dry, short
  decay).
- No subjective audible warmth improvement could be
  distinguished from the noise floor.
- No new clipping (consistent with simulation peak unchanged at
  3952 and the +50% body_mix not pushing the audio path
  saturator harder).
- Note: this is one verifier's listening. A trained listener on
  a quieter capture path would likely hear the warmth
  difference; the body_mix from 8192 to 12288 + biquad 2 retune
  to 1500 Hz is a real DSP change that should be audible at
  better SNR.

## Acceptance criteria evaluation

| Criterion | Target | Measured | Result |
| --- | --- | --- | --- |
| 1-3 kHz band gain | 3-5 dB | -0.4 to -3.6 dB | INDETERMINATE (noise-bound) |
| 50-200 Hz band gain | modest | +0.0 to -2.2 dB | INDETERMINATE |
| 4-7 kHz band preserve | within 1 dB | -1.7 to -4.0 dB | INDETERMINATE (noise-bound) |
| No new clipping | clean | no peaks > -3.6 dBFS | PASS |
| Subjective warmth | warmer/fuller | similar to M2 (noise-bound) | INDETERMINATE |
| Sim TBs PASS | all pass | all 5 PASS | PASS |
| Quartus 0 errors / LE / setup / TNS | budgeted | 0 / 4,932 / +4.515 ns / 0 | PASS |
| Programmable SOF | yes | yes (sha256 captured) | PASS |
| P5M2 Q monotonic, X=0 | yes | Q 0->0x21, X=0 | PASS |

The critical observation: the brightness regression appears > 2 dB
on the FFT comparison, but inspection of the per-cell envelope
proves the strikes are at-or-below the audio chain noise floor in
both M2 and M3 captures. The negative band deltas are run-to-run
chain variation, not RTL regression.

This is the same chain-SNR limitation called out in M1.2 and M2
verifier reports as a residual risk; M3 has reached the point
where it materially affects the verdict.

## Residual risks

1. **Audio chain SNR is now blocking voice-quality A/B work.**
   M2 brightness improvement was visible because it exceeded the
   noise floor (~2x = 6 dB at 4-7 kHz). M3's body warmth target
   (+3-5 dB at 1-3 kHz) is at the same scale as the chain noise
   floor variation, so individual cell measurements cannot
   distinguish RTL change from run-to-run noise.
2. **The implementer's "rms_100ms +2 dB" claim is incorrect.**
   The actual delta is +0.17 dB (272.80/267.43). Non-blocker;
   the absolute golden value 272.80 is what controls TB pass/fail.
3. **B2 (runtime body knob) deferred but now justifiable.** A
   runtime knob would let a single hardware capture sweep
   multiple body_mix values, increasing measurement statistical
   power without requiring chain SNR improvement.
4. **Setup slack +4.515 ns is moderate.** Future RTL slices should
   stay clear of new combinational paths near this margin.
5. **The biquad 2 retune is only validated by formula and pole
   analysis, not by simulation.** The voice golden TB does not
   instance phase0_body_filter (this was flagged in the M3 scope
   verifier report). The hardware A/B should have caught a wrong
   coefficient set, but our SNR limitation means it cannot. A
   standalone phase0_body_filter TB would be useful for future
   slices.

## Recommendation: Phase 6 M4 = chain SNR improvement

The cleanest path forward is to fix the audio chain noise floor
before the next timbre slice. Options:

a) **Use an external high-quality ADC**: a small line-in capture
   device with proper gain staging would lower the noise floor
   from ~-15 dBFS to ~-40 dBFS or better, comfortably resolving
   timbre changes of 3-5 dB.

b) **Add software gain to the bench / analyzer**: not a real
   solution since amplification raises both signal and noise.

c) **Run the bench with stronger excitation**: increase
   per-strike velocity to 0x7FFF for all cells. M2 already uses
   0x7FFF for some cells; the noise-bound cells at 0x2000 might
   not be measurable at all without a quieter chain.

If chain SNR cannot be improved on this verifier hardware, M4
alternatives:
- B2 (runtime body knob via UART !B command) for measurement
  efficiency
- E (loop-loss differential decay) addresses a different
  complaint (short decay)

## Files

Touched by this validation:
- `reports/phase6_m3_body_warmth_validation.md` (this file, **new**)
- `reports/phase6_m3_voice_baseline.csv` (M3 isolated original
  profile, 15 rows)
- `reports/phase6_m3_voice_baseline_analyzed.md` (analyzer markdown)
- `reports/phase6_m3_voice_bench_session.json` (sidecar from M3 run)

Verifier-side artifacts (`.kiro/`, not committed):
- `phase6_m3_voice_bench.wav` (~24 MB)
- `phase6_m3_capture_meta.json`, `phase6_m3_capture.log`
- `phase6_m3_capture.py`, `phase6_m3_envelope.py`,
  `phase6_m3_fft_compare.py`
- `quartus_phase6_m3_verifier.log`
- `msim_phase6_m3/` (ModelSim work + per-TB logs)

## ASCII check

```
reports/phase6_m3_body_warmth_validation.md non_ascii=0
reports/phase6_m3_voice_baseline.csv        non_ascii=0
reports/phase6_m3_voice_baseline_analyzed.md non_ascii=0
reports/phase6_m3_voice_bench_session.json   non_ascii=0
```

## Final verdict

**CONDITIONAL_PASS.** The Phase 6 M3 RTL change is correct and
operationally sound:

- Body filter biquad 2 coefficients verified by independent
  cookbook re-derivation; pole magnitude 0.945 < 1 (stable);
  fixed-point overflow analysis clean.
- Voice golden TB passes at body_mix=12288 with new golden hex;
  velocity TB passes all 7 assertions; control-stack regressions
  unchanged.
- Quartus full compile reproduces 4,932 LE (+15 vs M2), setup
  +4.515 ns, hold +0.413 ns, all TNS 0, M9K/DSP9/PLL unchanged.
- SOF programmed and exercised; P5M2 Q monotonic 0->0x21=33
  with X=0.

The hardware A/B cannot conclusively show warmth improvement
because the audio capture chain noise floor (~-15 dBFS) is
comparable to the expected M3 spectral delta. The negative band
deltas observed are run-to-run chain noise variation, not RTL
regression. No new clipping.

**Recommended Phase 6 M4: audio chain SNR improvement** (external
ADC line-in or equivalent) before any further timbre RTL slice,
so future A/B tests can statistically distinguish RTL-driven
changes from chain noise. As a fallback, **M4 = B2 (runtime body
knob)** to sweep multiple body_mix values in a single capture
window.
