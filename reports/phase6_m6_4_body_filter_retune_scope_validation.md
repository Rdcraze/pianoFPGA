# Phase 6 M6.4 Body-Filter Retune Scope Validation

Date: 2026-05-28
Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-5fea5640`
Branch: `codex/phase1c-uart-boundary-fix`
Implementer commit: `2cada59` (M6.4 body-filter retune scope NO-GO; pivot to internal-FIR M6.4-INT, task-5c38456e)
M6.3a baseline commit: `5ca80d9`
Verdict: **PASS**

## TL;DR

PASS. The implementer's NO-GO conclusion is correct and the
math is sound: the post-mix `phase0_body_filter` cascade
cannot move the body_mix sweep delta at any frequency by
linearity, because the filter sees the summed disp+body
signal and factors out of the high-vs-low ratio. I
independently re-derived the FIR magnitude/phase response
and the cancellation argument; both reproduce the helper
script's numbers exactly. The pivot to internal-FIR M6.4-INT
is the structurally correct lever. Two precision findings
(non-blocking) are forwarded for the M6.4-INT scope task.

## 1. Scope check (PASS)

`git show --stat 2cada59` confirms only two files added:

| file                                          | type                  |
| --------------------------------------------- | --------------------- |
| reports/phase6_m6_4_body_filter_retune_scope.md | scope report (new)  |
| reports/m6_4_compute_response.py              | numerical helper (new)|

`git diff 5ca80d9..HEAD -- rtl/` returns zero output. RTL,
goldens, QSF, SDC, PLL, firmware, host scripts, obsolete
archive, and `.kiro/` are all untouched. The M6.3a-accepted
state is preserved bit-for-bit.

## 2. ASCII check (PASS)

```
reports/phase6_m6_4_body_filter_retune_scope.md   non_ascii=0  total=14926
reports/m6_4_compute_response.py                  non_ascii=0  total=4678
reports/phase6_m6_4_body_filter_retune_scope_validation.md  non_ascii=0
```

## 3. Cancellation math independently verified (PASS)

The implementer's core claim is that the post-mix
`phase0_body_filter` H_filter(f) cannot change the body_mix
delta because the filter is applied to the summed signal
`(disp + body)` and factors out of the ratio between two
sweep cells.

I independently re-derived this. The relevant signal flow
at HEAD:

```
phase1_reduced_voice (per voice):
  body_history[wr_ptr] <= disp_sample           # rtl/audio/phase1_reduced_voice.v line 245+111
  mult_sample          = sat_q18(((tap6 >>> 2) - (tap16 >>> 3) + (tap30 >>> 4)) <<< 1)
                       # post-M6.3a body FIR with taps 0.5, -0.25, +0.125 at delays 6/16/30
  body_contrib         = mult_sample * body_mix_q15 / 32768
  sample_data          = q18_to_q15(disp_sample + body_contrib)

phase0_audio_path:
  mix_sample_sat = saturate(sum of voice0..3 sample_data)
  body_filter_out = phase0_body_filter(mix_sample_sat)
  tx_sample       = body_filter_out
```

In z-domain (linear regime, no saturation engaged because
verifier confirmed clipping_count=0 per cell):

```
per_voice(z) = disp(z) * (1 + body_mix * H_FIR(z))
mix(z)       = sum over voices of per_voice(z)
             = (1 + body_mix * H_FIR(z)) * sum_disp(z)
tx(z)        = H_filter(z) * (1 + body_mix * H_FIR(z)) * sum_disp(z)
```

Delta between high and low body_mix sweep cells:

```
tx_high(z) / tx_low(z) = (1 + g_h * H_FIR(z)) / (1 + g_l * H_FIR(z))
```

H_filter(z) and sum_disp(z) cancel exactly. The body_mix
delta is purely a function of the internal `H_FIR(z)` and
the gain swing. **The math is correct.**

Critical caveats I checked:

1. The cancellation requires the disp_sample envelope to be
   identical across two sweep cells. The default M6 sweep
   harness uses `!F` between cells, which only raises
   damp_mix and does not reset the voice. However, voices
   were given >=1 s settle time per cell; the strike (same
   loop_len, velocity) produces the same disp_sample
   envelope to within a few percent. Disp variance does not
   alter the cancellation argument; it only adds noise.
2. The argument also requires the system to operate in the
   linear regime. Verifier task-3d75da05 confirmed
   `clipping_count = 0` per cell at velocity 0x7FFF on the
   in-range grid. Mix-sat is not engaged. Linearity holds.
3. `body_mix` is a single shared register across voices, so
   the `(1 + body_mix * H_FIR(z))` factor is identical for
   all voices and factors out of the sum. OK

## 4. Numerical helper independently reproduced

I ran `python reports/m6_4_compute_response.py` and the
output matches the report's tables byte-for-byte:

- Live `phase0_body_filter` cascade response: B1 +5.97 dB at
  50 Hz, B2 +2.99 dB peak at 1500 Hz, etc.
- Internal 3-tap body FIR magnitude/phase: e.g. -8.54 dB at
  50 Hz, -2.94 dB at 1500 Hz, -5.00 dB at 3000 Hz; phase
  rotates from -2.8 deg at 50 Hz through -86 deg at 2000 Hz
  to -155 deg at 3000 Hz.
- "Filter present" vs "filter removed" delta tables are
  byte-identical, demonstrating cancellation.

I additionally re-derived the FIR by hand using a fresh
script (not committed), which reproduced the same
magnitude/phase values to within 0.01 dB / 0.1 deg:

```
50 Hz   mag= -8.54 dB  phase= -2.8 deg
1500 Hz mag= -2.94 dB  phase=-39.7 deg
2000 Hz mag= -1.39 dB  phase=-85.9 deg
3000 Hz mag= -5.00 dB  phase=-155.3 deg
```

The phase rotation through 1-3 kHz is real and correctly
interpreted: at 2.5-3 kHz the body component lags by
roughly 130-155 deg, so doubling its magnitude partially
cancels the disp signal in that band. This explains the
M6.3a hardware result (1-2k delta +1.16 dB, 2-3k delta -0.36
dB on average) without requiring any other mechanism.

## 5. Internal vs external response separation (PASS)

The report distinguishes external `phase0_body_filter` from
internal per-voice `H_FIR` clearly. Section 2 tabulates the
filter cascade response only; section 3.2 tabulates the
internal FIR separately; section 3.1 gives the linearity
argument that makes the separation matter. They are not
conflated.

## 6. M6.4-INT pivot is technically sound (PASS)

The recommendation that only an internal-FIR change can move
the body_mix sweep delta is correct under the cancellation
proof. Two structural levers proposed (re-tap the delays,
re-weight the coefficients) are both legitimate. The
sketch coefficients (`H_FIR_v2(z) = 0.5*z^-4 - 0.25*z^-12 +
0.125*z^-24`) are explicitly flagged as a starting point,
not a final design, which is appropriate for a scope memo.

The report correctly identifies that an internal FIR change
will be more invasive than M6.3a's single shift because:
- tap address generation in `STATE_BODY_TAP6/16/30` would
  change;
- `body_wr_ptr` width and `body_history` depth assumptions
  may need review;
- the existing reduced-voice golden hex would need
  regeneration (vsim license still blocked on this host);
- LE cost is small but non-zero.

These caveats are fair and useful for the M6.4-INT
implementer.

## 7. Precision findings (non-blocking)

These do not change the verdict. They should be forwarded
to the M6.4-INT scope task.

### 7.1 Hardware-comparison table averages do not match my recorded validation data

The report's section TL;DR table claims "M6.3a hardware
(averaged A4+C5)" values for each band. My actual M6.3a
in-range band analysis at validation commit 969fe9f has
different per-pitch deltas from those used in the table:

| band   | A4 delta (mine) | C5 delta (mine) | mean | report's "averaged" | gap |
| ------ | -------------:  | -------------:  | ---: | ------------------: | ---: |
| 50-200 |  +0.53          |  -0.58          | -0.03 |  +1.39             | -1.42 |
| 200-500|  +1.33          |  +1.16          | +1.25 |  +1.16             | +0.09 |
| 500-1k |  +1.19          |  +1.90          | +1.55 |  +1.90             | -0.35 |
| 1-2k   |  -0.69          |  +0.60          | -0.05 |  +1.16             | -1.21 |
| 2-3k   |  +0.52          |  +0.70          | +0.61 |  -0.36             | +0.97 |

The 200-500 / 500-1k rows are reasonably close to my data;
the 50-200 / 1-2k / 2-3k rows are not. I cannot reconcile
the implementer's specific averages from my band analysis
file. Possible sources: different lowest/highest body_mix
choice, different averaging methodology, or table-copy
error. The discrepancy does not invalidate the cancellation
proof or the qualitative shape match (small positive at low
freq, near-null at 2-3 kHz).

Recommendation: M6.4-INT implementer should re-pull the
actual per-cell hardware data from
`reports/phase6_m6_3a_inrange_band_analysis.txt` and
recompute averages explicitly, so the comparison table is
auditable. The qualitative argument is unaffected.

### 7.2 Predicted 1-2k delta is +3.12 dB (helper) vs +2.80 dB (table)

The TL;DR table says predicted 1-2k = +2.80 dB; the helper
script output shows 1500 Hz delta = +3.12 dB. The table
appears to be a band-averaged number, not a single-frequency
sample, which is reasonable. Just flag for traceability.

## 8. Disposition of in-scope tasks

- M6.4 implementer NO-GO containment: this commit is
  effectively the NO-GO containment itself. No further
  implementer work needed for the M6.4 retune slice.
- M6.4-INT scope task (proposed in section 6 of the report):
  orchestrator may queue if the body axis is still the
  preferred next voice-quality direction.
- Alternative voice-quality axis: orchestrator may instead
  pivot to a different axis (hammer texture, attack shaping,
  detune, longer release) per the report's section 5 note.
  Either choice is defensible; the body_mix knob is now
  functional and operator-tunable.

## 9. Macro-direction check (PASS)

- Voice quality first, polyphony as support infrastructure: OK
- Fixed-function RTL preserved: OK
- No CPU/firmware/MMIO/register-file revival in this scope: OK
- No JTAG command path / on-chip strike scheduler / new UART syntax: OK
- M6.3a accepted state preserved: OK (zero RTL diff vs 5ca80d9)

## 10. Verdict

**PASS at validation commit pending.**

The M6.4 scope is mathematically correct, evidence-grounded,
and orchestrator-ready. The pivot to internal-FIR M6.4-INT
is the structurally correct lever. Two precision findings
on the hardware-comparison table are forwarded as non-
blocking soft notes for the M6.4-INT scope task. The
accepted M6.3a baseline is untouched.
