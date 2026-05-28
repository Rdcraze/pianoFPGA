# Phase 6 M6.4-INT Internal Body-FIR Scope Validation

Date: 2026-05-28
Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-8844ef33`
Branch: `codex/phase1c-uart-boundary-fix`
Implementer commit: `c333e3d` (M6.4-INT scope: recommend Cand E (4/12/24 FIR delays), task-65b8cffa)
M6.3a baseline commit: `5ca80d9`
Verdict: **CONDITIONAL_PASS**

## TL;DR

CONDITIONAL_PASS. The implementer's M6.4-INT scope is
mathematically sound, addresses the M6.4 precision finding
correctly, and identifies the right structural lever
(internal-FIR delay change). Numerical analysis is
independently reproducible. However, the section 5.1 RTL
diff (`body_wr_ptr - 5'd5/13/25`) does NOT implement the
Cand E response (delays 4/12/24) shown in the report's
analysis tables; it implements Cand A (delays 5/13/25).
Both clear the +1 dB CONDITIONAL_PASS gate in 1-2 kHz and
2-3 kHz, but the orchestrator should resolve this
labeling/mapping inconsistency in the M6.4-INT implementer
task before it commits.

## 1. Scope check (PASS)

`git show --stat c333e3d` confirms two files added:

| file                                       | type                     |
| ------------------------------------------ | ------------------------ |
| reports/phase6_m6_4_int_fir_scope.md       | scope report (new)       |
| reports/m6_4_int_fir_response.py           | numerical helper (new)   |

`git diff 2cada59..c333e3d -- rtl/ quartus/ fw/ scripts/ obsolete/` returns
no output (verified). The M6.3a-accepted RTL state, M6.4
NO-GO scope, QSF, SDC, PLL, firmware, host scripts, and
obsolete archive are all untouched.

## 2. ASCII check (PASS)

```
reports/phase6_m6_4_int_fir_scope.md   non_ascii=0
reports/m6_4_int_fir_response.py       non_ascii=0
reports/phase6_m6_4_int_fir_scope_validation.md  non_ascii=0
```

## 3. M6.3a hardware audit precision finding addressed (PASS)

The M6.4 verifier (task-5fea5640, section 7.1) flagged that
the prior M6.4 scope's "averaged A4+C5" hardware deltas could
not be reconciled from the recorded data. The M6.4-INT scope
re-pulls per-pitch deltas directly from
`reports/phase6_m6_3a_inrange_band_analysis.txt` and computes
energy-mean across A4 and C5. I independently re-derived the
energy-mean values:

```
band     A4 dB     C5 dB     verifier energy-mean
50-200   +0.53     -0.58     +0.01    (matches scope)
200-500  +1.33     +1.16     +1.25    (matches scope)
500-1k   +1.19     +1.90     +1.56    (matches scope)
1-2k     -0.69     +0.60     +0.00    (matches scope)
2-3k     +0.52     +0.70     +0.61    (matches scope)
3-5k     -0.47     -0.18     -0.32    (matches scope)
```

The M6.4-INT helper script reproduces these values byte-for-
byte. The prior M6.4 precision finding is fully resolved.

## 4. Live RTL re-inventory (PASS)

I independently confirmed the implementer's source-code
inspection:

- `body_history` is 32-deep (`reg signed [17:0] body_history [0:31]`), 5-bit address line 81.
- Current tap addresses are `body_wr_ptr - 5'd7/17/31` at lines 104-106.
- `body_history` is written in STATE_WRITE_SAMPLE at `body_wr_ptr`, then `body_wr_ptr` increments by 1 in the same clock edge (line 498).
- `body_read_data` is registered (line 247): `body_read_data <= body_history[body_read_addr]`.
- The body-tap sequence runs entirely within one audio sample tick (between strikes); `body_wr_ptr` does not change during the WAIT/TAP states.

I traced one tick: at sample n's body taps, `body_wr_ptr`
holds the value that `body_history[body_wr_ptr]` has not yet
been written for sample n. By induction, `body_history[body_wr_ptr - k]`
holds disp[n-k] for k=1..32. So:

- Source `body_wr_ptr - 5'd7` reads disp[n-7], FIR delay = 7 samples.
- Source `body_wr_ptr - 5'd5` reads disp[n-5], FIR delay = 5 samples.
- Source `body_wr_ptr - 5'd4` reads disp[n-4], FIR delay = 4 samples.

The 1-cycle `body_read_data` register adds intra-tick FSM
latency but does not change which audio sample is delivered.
**Source delay value equals effective FIR delay.**

This matches the implementer's statement that the current
design has effective delays `7/17/31`. It does NOT match the
implementer's claim in section 5.1 that source `5/13/25`
yields effective delays `4/12/24`. See section 7 for details.

## 5. Cancellation/cancellation-zone math independently reproduced (PASS)

Helper script output reproduces exactly when re-derived from
scratch.

Current FIR (delays 7/17/31, weights +0.5 / -0.25 / +0.125):

| f Hz | mag dB  | phase deg |
| ---: | ------: | --------: |
|  200 |  -8.90  |   -10.6   |
|  500 | -10.43  |   -17.2   |
| 1000 |  -7.82  |    -7.6   |
| 1500 |  -2.94  |   -39.7   |
| 2000 |  -1.39  |   -85.9   |
| 2500 |  -2.59  |  -128.8   |
| 3000 |  -5.00  |  -155.3   |

Cand E delays 4/12/24 with same weights:

| f Hz | mag dB  | phase deg |
| ---: | ------: | --------: |
|  200 |  -8.79  |    -7.8   |
|  500 | -10.07  |   -14.3   |
| 1000 | -10.04  |    +0.7   |
| 1500 |  -5.16  |    -7.2   |
| 2000 |  -2.21  |   -37.9   |
| 2500 |  -1.51  |   -72.7   |
| 3000 |  -2.62  |  -103.2   |

Phase rotation through 2-3 kHz drops from current `-86 to -155 deg`
(strongly cancelling) to Cand E's `-38 to -103 deg` (mostly
additive). The first phase-cancellation zero moves above the
acceptance band.

Band-averaged predicted body_mix delta from 0x1000 to 0x7000
(verified by my own 64-point integration over each band):

| band   | current 7/17/31 | Cand E (4/12/24) | Cand A (5/13/25) |
| ------ | ---------------:| ----------------:| ----------------:|
| 1-2k   |        +2.49    |         +2.78    |         +2.67    |
| 2-3k   |        -2.56    |         +2.55    |         +1.68    |

Both Cand E and Cand A clear CONDITIONAL_PASS (>= +1 dB)
in 1-2 kHz and 2-3 kHz. Cand E clears PASS (>= +3 dB) in
neither (max is +2.78 in 1-2k); both clear CONDITIONAL_PASS
in both bands.

## 6. Saturation/depth/resource analysis (PASS)

- Tap weights unchanged from M6.3a (+0.5 / -0.25 / +0.125),
  so worst-case body_partial magnitude at sat_q18 input is
  unchanged. No new clipping risk. PASS.
- body_history depth 32. Cand E max source delay 24 (or 25
  for Cand A). Both fit. PASS.
- Address-constant change is wire-only; expected LE delta
  is essentially 0 with small fitter variance. PASS.
- M9K, DSP9, PLL: unchanged. PASS.
- Setup margin: same combinational block as M6.3a. Expected
  unchanged. PASS.

## 7. Cand E source-vs-effective delay inconsistency (PRECISION FINDING)

This is the only blocker for full PASS. The scope is
self-inconsistent on the relationship between RTL source
constants and effective FIR delays:

- Section 2 ("Live RTL inventory") correctly states that the
  current source `5'd7/17/31` produces effective FIR delays
  `7/17/31`.
- The helper script's `Cand E` is computed with delay tuple
  `(4, 12, 24)` (line 154 of `reports/m6_4_int_fir_response.py`).
- Section 5.1's recommended RTL change is
  `body_wr_ptr - 5'd5/13/25`, which by the same inductive
  trace I performed in section 4 produces effective FIR
  delays `5/13/25`. This is the helper's `Cand A`, not
  `Cand E`.
- Section 5.1 explains this as "the source uses one-indexed
  offsets that yield 7/17/31 sample delays; Cand E's
  4/12/24-sample delays correspond to source constants
  5/13/25" plus "1-cycle read-pipe latency". I cannot
  reproduce this -1 offset relation from the RTL: the
  registered `body_read_data` adds FSM clock latency, not
  audio-sample latency, because `body_wr_ptr` does not move
  during the in-tick FSM sequence.

If the section 5.1 RTL diff is committed as written, the
synthesized FIR will be Cand A's response (1-2k +2.67 dB,
2-3k +1.68 dB), which still clears CONDITIONAL_PASS in both
bands but is suboptimal in 2-3 kHz vs Cand E (+2.55 dB).

Recommended resolution for the M6.4-INT implementer task:

(a) **Preferred**: Update the RTL diff to use source
`5'd4/12/24` to actually implement the Cand E response, OR
(b) Accept that the recommendation is in fact Cand A, rename
the recommended candidate "Cand A", and update predicted
band-delta gates accordingly.

Either way the orchestrator should remove the
source-vs-effective ambiguity in the implementer task text
before it commits. This is a small clarification, not a
math/architecture fix.

## 8. Hardware audit interpretation check (PASS)

The scope correctly notes that current M6.3a measured
energy-mean is +0.00 dB at 1-2k vs predicted +2.49 dB, and
+0.61 dB at 2-3k vs predicted -2.56 dB. The 1-2k gap (~2.5 dB)
is within the verifier's documented 1-3 dB cell-to-cell
variance. The 2-3k gap (~3.2 dB) is also plausibly within
chain noise plus measurement variance.

The qualitative shape (small positive low, near-null in
1-2k, slight positive in 2-3k) reproduces the predicted
shape modulo the noise. No misreading.

## 9. Macro-direction check (PASS)

- Voice quality first, polyphony as support: OK
- Fixed-function RTL preserved: OK
- No CPU/firmware/MMIO/register-file revival: OK
- No JTAG command path / on-chip strike scheduler / new UART syntax: OK
- M6.3a accepted state preserved (zero RTL diff vs 5ca80d9): OK
- No body_mix mapping or weight change (only tap delays): OK
- No body_filter coefficient change: OK

## 10. Verdict and recommended next steps

**CONDITIONAL_PASS**.

The scope is mathematically correct, evidence-grounded, and
identifies the right next lever. The single precision
finding (section 7) requires a one-line clarification in the
M6.4-INT implementer task to ensure the committed RTL
matches the recommended candidate. Either resolution path
(use 4/12/24 source for true Cand E, or accept 5/13/25 as
Cand A and update predicted gates) is technically valid.

Orchestrator may queue the M6.4-INT implementer task as
written in section 6 of the scope report, with the addition
of an explicit instruction to either:

> Use `body_wr_ptr - 5'd4`, `5'd12`, `5'd24` to implement
> the Cand E response (predicted 1-2k +2.78 dB, 2-3k +2.55 dB).

OR

> Accept Cand A behavior with source `body_wr_ptr - 5'd5/13/25`
> and adjust the verifier acceptance comparison to expect
> Cand A predictions (1-2k +2.67 dB, 2-3k +1.68 dB).

Both candidates clear CONDITIONAL_PASS gates. The Cand E
option is preferred because it yields a stronger 2-3 kHz
response (+2.55 dB vs +1.68 dB), and the source change is
identical in cost.

The remaining acceptance plan (golden hex regeneration on a
host with valid ModelSim license, then live FFT band A/B)
remains correct and orchestrator-ready.
