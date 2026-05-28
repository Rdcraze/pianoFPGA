# Phase 6 M6.6 Next Voice-Quality Axis Scope Validation

Date: 2026-05-28
Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-ff679bb2`
Branch: `codex/phase1c-uart-boundary-fix`
Implementer commit: `0bb286e`
Parent: `b7203ee` (M6.5-DAMP verifier acceptance)

## TL;DR

**PASS.** The M6.6 scope correctly identifies runtime dispersion
(`disp_coeff`) as the next voice-quality axis. The recommendation
is technically sound, bounded, low-risk, and aligned with
voice-quality-over-polyphony. The existing RTL already has
`disp_coeff` as a wire input to the voice; making it runtime costs
only parser + register (~+30 LE) with no constant-folding loss.
The acceptance metric (spectral inharmonicity ratio) is measurable
on the existing post-isolator chain.

## 1. Scope Check

Commit `0bb286e` (diff from `b7203ee`) touches exactly 1 file:

| file | change |
| ---- | ------ |
| reports/phase6_m6_6_voice_quality_next_axis_scope.md | new, scope report |

No RTL, firmware, host-tool, QSF/SDC/PLL, obsolete archive,
generated-output, capture, or unrelated file changes. Clean.

## 2. ASCII Compliance

`reports/phase6_m6_6_voice_quality_next_axis_scope.md`: 7,094 bytes,
ASCII OK (no bytes > 0x7F).

## 3. Baseline Statement Verification

The report states the accepted baseline at `b7203ee`:

| claim | actual | match |
| ----- | ------ | :---: |
| LE 5,237 / 10,320 (51%) | 5,237 (task-e3edf103) | YES |
| Raised +150 LE cap | 5,252 max (orchestrator) | YES |
| Setup +5.213 ns | +5.213 ns (task-e3edf103) | YES |
| M9K 5, DSP9 26, PLL 1 | confirmed | YES |
| Runtime knobs: !B, !D | confirmed | YES |
| A4 swing +3.91 dB/s | +3.91 (task-122ec0a2) | YES |
| C5 swing +3.62 dB/s | +3.62 (task-122ec0a2) | YES |
| CONDITIONAL_PASS | confirmed | YES |
| Body-axis 1-3 kHz closed | confirmed (M6.4-INT) | YES |

All baseline claims are accurate.

## 4. Axis Comparison Assessment

The report compares all required axes:

### 4.1 Inharmonicity/dispersion (RECOMMENDED)

- Acoustic motivation: string stiffness is the defining
  timbral axis after attack and sustain. Correct.
- Lever: existing `disp_coeff_q15` allpass in STATE_AP_FINISH.
  Verified in RTL: `phase1_reduced_voice.v` line 377 uses
  `mult_coeff <= disp_coeff_q15` in the allpass computation.
- Current static value: `16'sd9952` in `phase0_fixed_control.v`
  line 172 as `assign voice_disp_coeff = 16'sd9952`. Verified.
- Wire path: `voice_disp_coeff` is a combinational assign, not
  a registered state machine path. No constant-folding loss.
  Verified by RTL inspection.
- Resource estimate: ~+30 LE. Sound because the voice side
  already receives `disp_coeff` as a port input wire.

### 4.2 Attack/excitation shaping (DEFERRED)

Reasonable deferral. M2 velocity layers already cover the
primary attack axis. Further refinement has unclear acceptance
metrics.

### 4.3 Frequency-dependent loop-loss (DEFERRED)

Reasonable deferral. In-loop IIR adds pipeline risk at current
+5.213 ns margin. Better to explore after dispersion.

### 4.4 Measurement/listening protocol (DEFERRED)

Correctly classified as tooling, not a voice-quality feature.

### 4.5 Controlled detune/chorus (DEFERRED)

Correctly deferred per polyphony-as-support-infrastructure
policy.

## 5. Recommended Slice Assessment

### 5.1 Coherence and boundedness

The M6.6-DISP slice is:
- Single-axis: only `disp_coeff` changes.
- Same pattern as `!B`/`!D`: parser + register + wire.
- No new pipeline stages, no new multipliers, no new RAM.
- Clear out-of-scope list (section 5).

### 5.2 Resource/timing gates

- LE gate: <= +50 hard, <= +30 target. Reasonable given the
  ~+30 LE estimate and no constant-folding loss.
- Setup gate: >= +4.0 ns hard. No new critical path.
- M9K/DSP9/PLL unchanged expected.

### 5.3 Acceptance metric

Spectral inharmonicity ratio: 2nd partial frequency shift
between `!S0000` (no dispersion) and `!S7FFF` (max positive).
PASS gate: >= +5 Hz on A4.

Assessment: this is a well-defined, measurable metric. The
allpass `y[n] = coeff * x[n] + x[n-1] - coeff * y[n-1]`
produces frequency-dependent phase shift that stretches upper
partials. With `coeff=0` the allpass is transparent (no
dispersion). With `coeff=9952/32768 ~ 0.304` the current
default provides moderate inharmonicity. The +5 Hz threshold
on the 2nd partial (~884 Hz for A4) is achievable given the
allpass transfer function.

### 5.4 NO-GO triggers

Implicit from the gates: LE > +50, setup < +4.0 ns, or
unmeasurable inharmonicity shift would trigger NO-GO.

## 6. Alignment Check

- Voice-quality-over-polyphony: YES. Dispersion is a
  single-voice timbral quality, not a polyphony feature.
- No CPU/firmware/MMIO revival: YES. Pure RTL + host tool.
- No fragile body-axis gate: YES. Uses spectral inharmonicity,
  not the closed 1-3 kHz body_mix delta.
- EP4CE10 budget: YES. +30 LE on a 51% utilized device.
- UART not the final feature: YES. UART is the control
  interface, not the product.

## 7. Precision Findings

One minor clarification for the implementer task:

1. The scope says `disp_coeff` is "signed 16-bit" and the
   parser "stores the full 16-bit value without clamping."
   This is correct: the allpass is stable for any coefficient
   in [-32768, +32767]. However, the `!S` command should
   document that negative values produce a different phase
   response (inverted dispersion direction). The implementer
   should note this in the TB/report but no clamping is needed.

## 8. Verdict

**PASS.**

The M6.6 scope is technically sound, well-bounded, low-risk,
and correctly identifies inharmonicity/dispersion as the next
voice-quality axis. The implementation pattern is proven
(`!B`/`!D` precedent), the acceptance metric is measurable,
and the resource estimate is conservative.

### Recommendation

Proceed with M6.6-DISP implementation task as described in
section 4 of the scope. The +50 LE hard gate is appropriate
given the ~+30 LE estimate with no constant-folding loss.
