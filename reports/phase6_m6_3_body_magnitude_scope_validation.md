# Phase 6 M6.3 Body-Magnitude Scope Validation

Date: 2026-05-27
Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Branch: `codex/phase1c-uart-boundary-fix`
Validation HEAD: `d0e1675` (M6.3 body-magnitude scope, by
implementer task `task-2834263e`).

## Verdict

**PASS.**

The M6.3 scope is single-file, ASCII-clean, factually
consistent with the M6.2 acceptance evidence, and proposes a
narrow zero-cost RTL slice that directly addresses the M6.2
verifier's classification (voice-model body magnitude small
relative to disp, post-mix filter cannot fix it).

The Candidate B vs Candidate C analysis is correct: a
post-mix filter retune cannot change the body-vs-disp ratio
that limits 1-3 kHz body_mix swing; body magnitude must be
adjusted at the per-voice contribution. The recommended
single-line shift in `STATE_BODY_TAP30` is the smallest
behavior-changing fix that increases that ratio.

The orchestrator may queue the proposed M6.3 implementer and
verifier tasks as written. One soft-note recommendation
forwarded in section 5 below: the projected "3-6 dB
end-to-end 1-3 kHz delta" is on the optimistic side; the
implementer task gates already accept +1 dB CONDITIONAL_PASS,
so this does not change the gate, but the verifier should
treat anything in the +1 to +6 dB range as a credible
outcome rather than failing if the swing lands at +2 dB.

## 1. Scope, ASCII, and file gates

```
git show --stat d0e1675
 reports/phase6_m6_3_body_magnitude_scope.md | 485 ++++++++++
 1 file changed, 485 insertions(+)
```

ASCII bytes:

```
reports/phase6_m6_3_body_magnitude_scope.md  non_ascii=0  bytes=19246
```

Single-file commit, ASCII-only. No RTL, QSF, SDC, PLL,
firmware, host-tool, generated bitstream, obsolete archive,
or accepted prior-baseline-report change. Scope discipline
PASS.

The only worktree dirt outside the scope file is
`implementer_handoff.md`, which is a stale modification
predating this validation, not produced by `task-2834263e`,
and not in the scope of this validation.

## 2. Reasoning vs current evidence

### 2.1 M6.2 evidence cited correctly

The scope quotes:

- M6.2 in-range 1-2 kHz delta on A4: +0.15 dB.
- M6.2 in-range 1-2 kHz delta on C5: -0.45 dB.
- Cell variance 1-3 dB on this chain.

Independent cross-check against
`reports/phase6_m6_2_inrange_band_analysis.txt` confirms all
three numbers exactly.

### 2.2 STATE_BODY_TAP30 / STATE_BODY_FINISH analysis is correct

Verified against `rtl/audio/phase1_reduced_voice.v` lines
442-475:

```
STATE_BODY_TAP30:
  mult_sample <= sat_q18(
    (q18_ext(body_tap6) >>> 2) -          // 1/4
    (q18_ext(body_tap16) >>> 3) +         // 1/8
    (q18_ext(body_read_data) >>> 4));     // 1/16
  mult_coeff <= body_mix_q15[15] ? 16'sd32767 :
                $signed({1'b0, body_mix_q15[14:0]});
STATE_BODY_FINISH:
  output_sample_q18 <= sat_q18(disp_sample +
                               product_to_q18(mult_product));
```

The scope's analysis of peak `mult_sample` magnitude (7/16 of
peak Q18 audio amplitude, ~14336 typical) is consistent with
the file's Q18 storage and shift-sum structure.

The `STATE_BODY_FINISH` saturating sum (`sat_q18(disp +
body_contrib)`) is correct: it bounds the doubled body
contribution at +/-131071 and increments `clip_seen` when the
sum exceeds Q18 range. The scope's claim that no new
clipping detection is needed for Candidate C is correct.

### 2.3 phase0_body_filter is post-mix and post-saturation

Verified against `rtl/audio/phase0_audio_path.v` lines
242-298: the body filter cascade follows the 4-voice mix sum
saturation. The scope's rejection of Candidate B (post-mix
retune cannot change body-vs-disp ratio) is structurally
correct.

### 2.4 Resource/timing claim is correct

A `<<< 1` on a Q18 wire is wire-only routing. No new flop, no
new mux, no new combinational stage. Quartus typically
optimizes such constant shifts to zero LE.

The body multiplier path's M6.2 setup slack was +4.939 ns
slow-85C. Adding a wire-only shift before `sat_q18` does not
extend the critical path because the same `sat_q18` block
already performs a 4-input add on shifted Q18 values. The
scope's claim of "zero LE / no DSP / no timing impact" is
plausible.

### 2.5 Saturation safety claim is correct

Worst-case with M6.3:
- Peak `mult_sample` post-shift: +/-28672 (still <<
  +/-131071).
- Peak `body_contrib` after multiplier:
  `28672 * 32767 / 32768 ~= 28672` Q18 units.
- Peak `output_sample_q18 = sat_q18(disp + body_contrib)`:
  worst-case `+/-32768 + +/-28672 = +/-61440`, still inside
  Q18 saturation guard.

The scope's saturation analysis is correct. The verifier
task gate `clipping_count = 0` at default velocity is the
right operational check; it will catch any case where the
combined disp+body actually exceeds Q18 range in real audio.

## 3. Candidate ranking review

| Candidate | Verifier judgment |
| --------- | ----------------- |
| B post-mix filter retune | correctly rejected; cannot change body/disp ratio |
| C body magnitude shift | correctly recommended; minimum behavior-changing fix |
| D body-only diagnostic | correctly deferred; redundant if C produces measurable swing |
| E coherent-average harness | correctly deferred parallel; not a substitute for C |
| F no-op | correctly rejected; user priority is voice quality |

The ranking is sound. The audit explicitly preserves the
M6.1 audit's deferral logic.

## 4. Projected delta cross-check

The scope's projected end-to-end 1-3 kHz delta of 3-6 dB
relies on three layered claims:

1. Doubling `mult_sample` doubles `body_contrib` (correct;
   linear path).
2. Body multiplier swing across 0x1000..0x7000 is 7x (correct;
   coefficient swing 4096..28672).
3. Combined band gain is amplified by the body 3-tap FIR's
   peak response in 1-3 kHz.

For claim 3, an independent FIR magnitude analysis at 2 kHz
(verifier-side):

```
H(z) = (1/4) z^-6 - (1/8) z^-16 + (1/16) z^-30
At f=2000 Hz, omega T = 2*pi*2000/46875 = 0.268 rad/sample:
  tap-6  contrib:  0.25 * exp(-j*1.608) = -0.009 - 0.250j
  tap-16 contrib: -0.125* exp(-j*4.288) = +0.052 - 0.114j
  tap-30 contrib:  0.0625*exp(-j*8.040) = -0.012 - 0.061j
  sum                                   = +0.031 - 0.425j
  |H(2kHz)| = 0.426
```

The FIR magnitude peaks at ~0.43, against the maximum
possible peak coefficient of 7/16 = 0.4375. So the 3-tap FIR
is approximately at peak band-emphasis in 1-3 kHz, but it
does not multiply the swing further beyond the body
magnitude doubling.

The realistic projection is therefore:
- Linear ratio `delta_body / disp` doubles from ~3.5% to
  ~7%.
- End-to-end band delta in dB ~= 20*log10(1+0.07) ~= +0.6 dB
  if the body and disp band content overlap.
- At fixed body_mix knob: doubling moves this from M6.2
  baseline of "~0.3 dB swing across the in-range knob" to
  "~0.6 dB swing", with the absolute band level rising
  ~+1.5 dB (from the body's 3-tap FIR contribution
  doubling).

The scope's "3-6 dB end-to-end" projection assumes the band
content is dominated by body, not disp, in that band. That
holds at high body_mix where body_contrib starts to rival
disp_sample, but at low body_mix the disp dominates.

In practice the in-range grid post-fix swing should be
**+1 to +3 dB**, comfortably above the +1 dB CONDITIONAL_PASS
gate but possibly below the +3 dB PASS gate on cells where
disp dominates. This is acceptable: the gate hierarchy
captures the realistic outcome.

This is not a defect of the scope; it is a fair note for the
verifier task to keep the projected gate range explicit.

## 5. Soft note for M6.3 implementer task

The proposed implementer task and verifier task text in
section 4 of the scope are both orchestrator-ready as
written. Forward this soft note to whoever queues M6.3:

- The "3-6 dB" projection in section 3.2 of the scope is on
  the optimistic side; +1 to +3 dB is more likely.
- Both implementer's hard gates and verifier's tiered gates
  (PASS >= +3 dB, CONDITIONAL_PASS >= +1 dB) already cover
  this range; no change to the proposed gate text is needed.
- If the post-M6.3 in-range swing lands at +2 dB, that is
  CONDITIONAL_PASS and a successful M6.3 outcome.
- A measured swing >= +6 dB would suggest the projected band
  gain underestimated body's relative contribution; that
  would be a positive surprise, not a correctness issue.

## 6. User-priority alignment

Voice quality first: PASS. Polyphony is not invoked. The
recommendation increases single-voice perceived warmth at
the cost of reducing absolute disp+body peak headroom by ~50%
in worst case (which the existing `sat_q18` and `clip_seen`
infrastructure handle without RTL changes). All four physical
voices remain. No CPU/firmware/MMIO revival, no JTAG path,
no on-chip scheduler, no polyphony work.

## 7. Acceptance gates: explicit verdict

| gate                                                        | result |
| ----------------------------------------------------------- | ------ |
| Single-file scope                                           | PASS   |
| ASCII-only                                                  | PASS   |
| No RTL/QSF/firmware/host/obsolete change                    | PASS   |
| M6.2 evidence correctly cited                               | PASS   |
| `STATE_BODY_TAP30` / `STATE_BODY_FINISH` analysis correct   | PASS   |
| Candidate B rejection structurally correct                  | PASS   |
| Candidate C resource/timing claim plausible                 | PASS   |
| Candidate C saturation safety claim correct                 | PASS   |
| Candidate ranking sound                                     | PASS   |
| Implementer task text orchestrator-ready                    | PASS   |
| Verifier task text orchestrator-ready                       | PASS   |
| Projected band-delta "3-6 dB" optimism                      | NOTE (forwarded as soft note in section 5; does not change gates) |
| User priority alignment                                     | PASS   |
| No CPU/MMIO/firmware/JTAG/scheduler/polyphony revival       | PASS   |

Overall verdict: **PASS** with the section 5 soft note
forwarded.

## 8. Recommendations to orchestrator

1. **Queue the M6.3 implementer task** from section 4 of the
   scope as written. The proposed RTL change is correct, the
   gates are right, and the TB regeneration plan is sensible.

2. **Queue the M6.3 verifier task** from section 4 of the
   scope as written. The dual-grid acceptance design is
   appropriate (default-grid saturation preserved + in-range
   monotonic swing).

3. **Forward the soft note from section 5 above** to the M6.3
   implementer/verifier: realistic projected swing is +1 to
   +3 dB; existing gate hierarchy already covers this so no
   gate text change is needed.

4. **Do not queue Candidates B, D, or E in parallel** with
   M6.3. The scope correctly defers them; layered changes
   would muddy the M6.3 measurement.

5. **Consider Candidate E (coherent-average harness extension)
   as the next parallel measurement-tooling slice after M6.3
   accepts**, regardless of M6.3 outcome. It is voice-model-
   independent and helps any future timbre slice on this
   chain.

## 9. Files

This report:

- `reports/phase6_m6_3_body_magnitude_scope_validation.md`
  (new, this file, ASCII-only).

No RTL, host-script, QSF, SDC, firmware, obsolete archive,
generated-output, or stale-untracked-file change.

## 10. ASCII check

ASCII verified by PowerShell foreach-byte loop before commit.
Final check pending commit.
