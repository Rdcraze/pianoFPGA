# Phase 6 M3 Voice-Quality Scope - Verifier Validation

Date: 2026-05-24
Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-b3dc8e5c`
Implementer commit under review: `1777e36` (Phase 6 M3 scope:
body-mix increase + body-filter mid-range retune)
Branch: `codex/phase1c-uart-boundary-fix`

## Verdict

**PASS.** The implementer's M3 scope report is well-reasoned,
honest about its assumptions, technically feasible, and comes with
orchestrator-ready implementer + verifier task text. The
recommendation (B1: fixed body_mix preset increase plus body-filter
biquad-2 mid-range retune) is the correct next slice given the M2
verifier's listening evidence and current resource/timing margins.

The orchestrator may queue the M3 implementer task with the
section 5 task text as written. One small clarification noted in
section 5 of this report; no scope blockers.

## Static / file scope check

`git show --stat 1777e36`:

```
reports/phase6_m3_next_voice_quality_scope.md | 466 ++++++++++++++++
1 file changed, 466 insertions(+)
```

PASS gates:
- Single-file change. No RTL, no QSF, no scripts, no obsolete, no
  firmware.
- ASCII-only: byte count 20310, non_ascii=0 (PowerShell foreach
  byte loop).
- Scope-only / planning-only milestone, as required.

## Architecture alignment

Verified by reading the report:
- No CPU/firmware/MMIO/register-file revival proposed for M3.
- No new UART command syntax for the recommended B1 slice (the
  runtime body knob B2 is explicitly deferred to a later
  milestone).
- Four physical `phase1_reduced_voice` instances preserved.
- Polyphony framed correctly as "support/regression
  infrastructure" - not a product feature.

PASS.

## Recommendation reasoning

The report's chain of reasoning:

1. M2 closed brightness gap (verifier evidence: 1.7-2.7x energy
   gain in 4-7 kHz bands at A5 0x7FFF).
2. M2 verifier's listening notes converge on dryness/warmth/short
   decay as the next single most-audible weakness.
3. Body filter is the most direct RTL handle for warmth.
4. Fixed retune is lower risk than runtime knob (B2), loop-loss
   filter shape (E), or pre-strike noise (D) given current setup
   slack +4.551 ns.
5. Audio-chain noise-floor improvement is host-side
   infrastructure, not a voice-quality feature; not blocking M3.

This chain is consistent with what the M2 validation report
documented and with the currently-built RTL state.

The trade-off candidly acknowledged in section 4 ("M3 will
explicitly break the M2 soft-layer byte-exact preservation") is
correct: the body filter sits in the audio path and the body_mix
multiplier inside the voice both affect velocity 0x4000 output.

PASS on reasoning.

## Technical feasibility check

### Current `voice_body_mix` value

`grep` of `rtl/control/phase0_fixed_control.v`:

```
assign voice_body_mix   = 16'd8192;
```

Confirmed. The proposed change to `16'd12288` is a single localparam
edit; +50% audible body content.

### Current `phase0_body_filter.v` biquad 2

`rtl/audio/phase0_body_filter.v` lines 19-25:

```
// Q2.14 coefficients for Biquad 2: Peaking (+3 dB, fc~200 Hz, Q~1.0)
localparam signed [15:0] B2_B0 =  16'sd16459;
localparam signed [15:0] B2_B1 = -16'sd32391;
localparam signed [15:0] B2_B2 =  16'sd15943;
localparam signed [15:0] B2_A1 =  16'sd32391;
localparam signed [15:0] B2_A2 = -16'sd16019;
```

Confirmed. The proposed change is a 5-coefficient retune from
peaking @ 200 Hz Q~1.0 to peaking @ 1500 Hz Q~1.5, both at +3 dB.
Structurally identical: 5 multiplier inputs change, no new state,
no new combinational depth, no new biquad stage. LE delta should
be negligible.

### Cookbook coefficient verification

Independently re-derived for peaking biquad at Fs=46875 Hz,
fc=1500 Hz, Q=1.5, gain=+3 dB:

```
A = 10^(3/40) = sqrt(10^(3/20)) ~ 1.1885
omega_0 = 2*pi*1500/46875 ~ 0.20106
sin(omega_0) ~ 0.19972
cos(omega_0) ~ 0.97983
alpha = sin(omega_0) / (2*Q) = 0.19972 / 3 ~ 0.06657

# Unnormalized
b0 = 1 + alpha*A   ~ 1.07914
b1 = -2*cos(omega_0) ~ -1.95966
b2 = 1 - alpha*A   ~ 0.92086
a0 = 1 + alpha/A   ~ 1.05601
a1 = -2*cos(omega_0) ~ -1.95966
a2 = 1 - alpha/A   ~ 0.94399

# Normalized (Q2.14, multiply by 16384, divide by a0):
B0 = 16384 * 1.07914 / 1.05601 ~ 16742
B1 = 16384 * -1.95966 / 1.05601 ~ -30403
B2 = 16384 * 0.92086 / 1.05601 ~ 14288
A1 = 16384 *  1.95966 / 1.05601 ~ +30403  (DF1 sign convention)
A2 = 16384 * -0.94399 / 1.05601 ~ -14647
```

All five coefficients fit in 16-bit signed (max +/- 32767). The
cookbook formula path is mathematically sound. The implementer is
expected to compute and document these (or equivalent values) in
the M3 implementer report.

Note: the existing biquad in `phase0_body_filter.v` uses sign
convention where `A1 > 0` (e.g. existing B1_A1 = +32240 for the
shelf, matching `y[n] = b0*x[n] + ... + A1*y[n-1] + ...` where
the negated a1 is encoded). The new B2_A1 should similarly be
positive in this convention. The implementer must match the
existing sign convention.

### Internal voice body section vs external body_filter

The voice instance `phase1_reduced_voice.v` has its own internal
body tap-line (`body_history`, `body_tap6/16/30`) which is mixed
into the voice output via `body_mix_q15` (the value passed in
from the controller's `voice_body_mix`). This is INTERNAL to the
voice, separate from the external `phase0_body_filter` biquad
chain that operates on the post-mix audio path.

Increasing `voice_body_mix` from 8192 to 12288 changes the gain of
the voice's internal body-tap mix. Retuning biquad 2 in the
external body filter changes the post-mix coloration. These are
two different DSP stages and they compose; both contribute to
audible warmth.

The reduced-voice golden TB will see the body_mix change because
the voice's `body_mix_q15` input directly affects the voice's
output. The external biquad retune does NOT show up in the
reduced-voice golden TB because that TB does not instance the
external body filter. So the implementer's expected golden
re-snapshot (peak number changes) only captures the body_mix
delta, NOT the external biquad retune. The external biquad
retune's audible effect can only be measured at the system level
(post-audio-path-mix) which the voice TB does not exercise.

This nuance is not explicitly addressed in section 4 of the
scope report, but it does NOT change the proposed implementer
work; it only clarifies which test will catch which change. The
hardware A/B is the joint test for both changes.

**Recommendation to orchestrator and implementer**: in section 4
of the implementer report (per section 5 of the scope), the
implementer should state: "Voice golden TB peak changes due to
body_mix=12288. Biquad 2 retune is independently validated by a
new mini-TB that exercises phase0_body_filter standalone with a
known impulse, OR by hardware A/B."

This is a small clarification, not a blocker.

### LE/timing budget feasibility

Both proposed RTL changes are coefficient/constant edits with no
new combinational depth and no new state. LE delta should be
near zero; the <= +50 target is conservative. Setup slack should
remain near M2's +4.551 ns. The +4.0 ns gate has +0.551 ns
cushion in M2 and the proposed M3 changes do not consume any of
that cushion.

PASS on technical feasibility.

## Implementer / verifier task text completeness

### Section 5 (implementer task text)

Covers:
- Required reading (current scope, M2 reports, RTL files)
- Specific file edits with line counts
- Exact coefficient derivation expectation (Fs=46875, fc=1500,
  Q=1.5, +3 dB)
- TB updates (golden re-snapshot for reduced-voice, peak update
  for velocity TB, no change for control-stack TBs)
- Quartus targets (LE <= +50 / +150 hard, setup >= +4.0 ns hard,
  M9K/DSP9/PLL unchanged, 0 errors / 16 warnings)
- New report `reports/phase6_m3_body_warmth_impl.md`
- Hard guardrails (no firmware, no UART syntax, no new biquad
  stage, no waveguide change, no QSF change, ASCII-only)
- Stop-and-report NO-GO triggers (setup < +4.0 ns, LE > +150,
  audio TB structural failure)

Slight gap (small; non-blocker): the section 5 text says the
voice golden TB "will produce a new peak value" but does NOT
explicitly say that the external body filter retune is invisible
to the voice TB. The implementer report should clarify which test
sees which change. Recommend the orchestrator append: "the
phase0_body_filter coefficient retune is not exercised by the
reduced-voice golden TB; document that the M3 hardware A/B is
the primary test for the biquad change."

### Section 6 (verifier task text)

Covers:
- Coefficient computation re-derivation
- File-scope confirmation
- Sim TB regression (golden, velocity, command, isolation)
- Quartus rebuild
- SOF programming and identity recording
- M2-vs-M3 hardware A/B captures with cells 2, 5, 8, 9, 11
- FFT band comparisons (1-3 kHz gain target, 50-200 Hz modest
  gain, 4-7 kHz no regression)
- No new clipping check
- Subjective listener report
- NO-GO conditions (brightness regression > 1 dB at 4-7 kHz,
  muddier sound)
- Validation report path
- Fall-through M4 recommendation paths if M3 outcome is weak

Section 6 is complete and orchestrator-ready as written.

## Honest assessment cross-check

Section 8 of the scope report acknowledges:

- M3 is conservative; the strongest argument is post-M2 listening
  evidence convergence on dryness/warmth.
- Warmth is harder to measure than brightness because 1-3 kHz
  band overlaps strike content, body resonance, and chain noise.
- Soft-layer golden bit-exact preservation will explicitly break
  in M3.
- If M3 verifier finds warmth gain unconvincing, M4 should
  continue with B (raise body_mix more, or runtime knob), or
  pivot to E (loop-loss differential decay).

This honest framing matches the verifier-side reality discovered
during M1.2 and M2 validation. PASS.

## Residual risks

1. **The implementer must use the existing biquad sign convention**
   (A1 positive for the encoded `y[n] = ... + A1*y[n-1]` style).
   The cookbook a1 is negative; the encoded localparam B2_A1 must
   be the positive of the cookbook a1. This convention is already
   used by existing biquad 1 in the file and is non-blocker if
   the implementer reads the existing pattern, but it should be
   explicitly called out.
2. **Voice golden TB only catches body_mix change, not biquad
   retune.** The biquad retune relies entirely on hardware A/B
   for validation. The implementer report should make this
   trade-off clear.
3. **+50% body_mix could push the audio-path mix saturator
   harder.** M2 cells were clean precisely because layer 2's
   total energy is lower. If raising body_mix re-introduces
   saturation on M2-clean cells, that's a NO-GO. The verifier
   acceptance criteria correctly call this out.
4. **1-3 kHz band gain is hard to measure at SNR ~ -18 dBFS.**
   The report acknowledges this. Use FFT band comparisons over
   the strike attack window, NOT the analyzer's centroid metric.
5. **Setup slack +4.551 ns has +0.551 ns cushion above the
   +4.0 ns gate.** Coefficient retune should not consume any of
   this cushion (no new combinational depth), but a NO-GO trigger
   at +4.0 ns is correctly written into both implementer and
   verifier task text.

## ASCII check on this report

```
reports/phase6_m3_next_voice_quality_scope_validation.md non_ascii=0
```

(Verified before commit by PowerShell foreach byte loop.)

## Final verdict

**PASS.** Phase 6 M3 scope is approved for implementer queueing
as written. The scope:

- Correctly identifies dryness/warmth as the next audible weakness
  to address.
- Recommends the lowest-risk, highest-audible-value path
  (B1 fixed retune, not B2 runtime knob).
- Validates technical feasibility (current values verified,
  cookbook math reproduces, no new combinational depth).
- Provides complete and orchestrator-ready implementer + verifier
  task text.
- Honestly acknowledges trade-offs (broken soft-layer golden,
  warmth measurement difficulty at SNR -18 dBFS).
- Documents NO-GO conditions correctly.

One small clarification recommended (the voice golden TB only
catches the body_mix change, not the biquad retune; document the
biquad retune is hardware-A/B-validated). This is non-blocking;
the orchestrator may either append the clarification when queuing
the implementer task, or rely on the implementer to surface it
in the implementation report.

The orchestrator may queue the M3 B1 implementer task at this
scope's section 5 text.
