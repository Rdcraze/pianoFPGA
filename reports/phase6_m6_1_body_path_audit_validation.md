# Phase 6 M6.1 Body-Path Audit Validation

Date: 2026-05-27
Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Branch: `codex/phase1c-uart-boundary-fix`
Validation HEAD: `cc55f74` (M6.1 body-path audit, by implementer
task `task-2776a7a4`).

## Verdict

**PASS with one precision finding.**

The audit correctly identifies a real signed/unsigned mismatch
in `rtl/audio/phase1_reduced_voice.v` line 446. The bug is
consistent with the M6 verifier's non-monotonic 1-3 kHz band
table and the prior M5/M5.1 evidence. The audit's
recommendation to fix it before any body filter coefficient
retune, body gain scalar, or coherent-average extension is
sound and respects the user's voice-quality-first priority.

The orchestrator may queue the proposed M6.2 implementer and
verifier tasks **with one small correction** noted in section
5 below: Candidate A1's actual behavior for `body_mix_q15 >=
0x8000` is **modular wrap of the low 15 bits**, not the
"saturating high" behavior the audit claims in section 5. This
matters for the default M6 sweep grid because A1 maps `0x8000`
to 0 instead of 0x7FFF, producing a genuinely non-monotonic
post-fix default sweep. The audit's recommended in-range
subgrid `[0x1000..0x7000]` is unaffected by this distinction
and remains the right primary acceptance test. The
implementer should choose explicitly between A1 (modular wrap,
zero LE cost) and a 1-bit MSB-saturating variant (truly
monotonic, ~5-10 LE) before committing M6.2.

## 1. Scope, ASCII, and file gates

```
git show --stat cc55f74
 reports/phase6_m6_1_body_path_audit.md | 573 +++++++++
 1 file changed, 573 insertions(+)
```

ASCII byte check:

```
reports/phase6_m6_1_body_path_audit.md  non_ascii=0  bytes=22111
```

Single-file commit, ASCII-only. No RTL, QSF, SDC, PLL,
firmware, host-tool, generated bitstream, obsolete archive, or
prior accepted baseline-report change. Scope discipline PASS.

## 2. Reasoning vs current RTL

### 2.1 Body multiplier signed-cast: real

`rtl/audio/phase1_reduced_voice.v` line 18:

```
input  wire [15:0]        body_mix_q15,
```

Unsigned port declaration. Line 446:

```
mult_coeff  <= $signed(body_mix_q15[15:0]);
```

`mult_coeff` is `reg signed [15:0]`. `$signed(body_mix_q15)`
on an unsigned wire reinterprets the same bit pattern as
two's-complement. For `body_mix_q15 >= 0x8000`, that flips the
sign of the body multiplier. The audit's diagnosis is correct.

The parser side (`rtl/control/phase0_uart_command.v` lines
167-184) explicitly accepts the full 16-bit unsigned range
without clamping and stores it verbatim in `body_mix_runtime`.
The voice-side cast contradicts the parser's stated contract.
The audit's framing is accurate.

### 2.2 Body filter is post-mix and post-saturation: real

`rtl/audio/phase0_audio_path.v` confirms the body filter
follows the 4-voice mix saturation. Audit section 3 frames
this as "correct for soundboard coloration but bounded by what
reaches the post-mix sample," which is fair.

### 2.3 Internal Q18 saturation before the body multiply: real

Audit section 3.3 quantifies that the body component before
the multiplier is at most 7/16 of peak tap magnitude. With
Q18 storage and tap arithmetic shift-down by 2/3/4, the
sustained body contribution is naturally smaller than the
displaced waveguide sample. Audit correctly identifies this
as a design choice rather than a bug; it explains why even
the in-range monotonic subset produces only a few dB swing,
not >10 dB.

### 2.4 Cross-check against verifier band table

Audit section 4 quotes the A4 1-2 kHz row from
`reports/phase6_m6_band_analysis.txt`. Independent rerun
confirms the cited values exactly:

```
0x1000: -77.58 dB
0x2000: -77.11 dB   (+0.47 dB)
0x3000: -76.98 dB   (+0.60 dB)
0x4000: -77.14 dB   (+0.44 dB)
0x6000: -77.72 dB   (-0.14 dB)
0x8000: -76.87 dB   (+0.71 dB)
0xC000: -77.03 dB   (+0.55 dB)
```

The audit's interpretation is consistent: the in-range subset
shows a small positive trend with peak near `0x3000`, the upper
two points (where `body_mix_q15[15] = 1`) appear to "improve"
because the phase-flipped body component happens to add when
naive intuition expects subtraction. The non-monotonic high
half with similar magnitude to the low half is exactly what
the signed-cast hypothesis predicts.

## 3. Candidate comparison review

The audit ranks five remediation candidates (A through F).
Verifier independent assessment:

| Candidate | What it does | Verifier judgment |
| --------- | ------------ | ----------------- |
| A: signed-cast fix | one-line RTL | strictly necessary; preferred |
| B: filter retune | new biquad coefficients | premature without A |
| C: body gain scalar | extra multiply | high risk on +4.620 ns slack; defer |
| D: body-only diagnostic | new control path | redundant if A produces measurable trend |
| E: coherent-average extension | host harness K>1 | useful follow-up, not a substitute |
| F: no-op accept | none | reject; real bug exists |

The ranking is sound. Candidate A as the smallest behavior-
preserving correction is the right next slice.

## 4. Audit's quantitative estimates

Audit section 4 claims a clean post-fix sweep of `[0x1000,
0x2000, 0x3000, 0x4000, 0x5000, 0x6000, 0x7000]` should show
"monotonic 1-3 kHz increase with magnitude ~3-6 dB end-to-end."
Verifier's reading of the existing band table for the in-range
subset shows ~1 dB swing (cell variance limited). The audit's
3-6 dB end-to-end claim assumes coherent averaging or
significantly cleaner inter-cell variance than the
single-shot M6 capture provided.

This is a reasonable acceptance target for a future M6.2
sweep using either the implementer's recommended dense grid
plus longer per-cell pause or an extended harness with K=4
coherent averaging. It is not a guarantee. The verifier task
text in section 6 of the audit correctly distinguishes:
- PASS = >= +3 dB end-to-end on the in-range grid
- CONDITIONAL_PASS = >= +1 dB

That tiered acceptance is right.

## 5. Precision finding: Candidate A1 is modular, not
   saturating

The audit's section 5 describes Candidate A1
(`mult_coeff <= $signed({1'b0, body_mix_q15[14:0]})`) as
treating `0x8000..0xFFFF` as "0x0000..0x7FFF (saturating
high)." That language is wrong.

Independent simulation:

```
value      current(signed-cast)  A1(modular)  alt(MSB-sat)
0x0000              +0                +0           +0
0x1000           +4096             +4096        +4096
0x3000          +12288            +12288       +12288
0x4000          +16384            +16384       +16384
0x6000          +24576            +24576       +24576
0x7FFF          +32767            +32767       +32767
0x8000          -32768                +0       +32767
0x9000          -28672             +4096       +32767
0xC000          -16384            +16384       +32767
0xFFFF              -1            +32767       +32767
```

A1 actually maps `body_mix_q15[15:0]` to `body_mix_q15[14:0]`
(modular wrap of the low 15 bits), so `0x8000` -> 0, `0x9000` ->
+4096, `0xC000` -> +16384, `0xFFFF` -> +32767. The high half
becomes a non-monotonic mirror of the low half rather than a
saturated clip.

For the M6 default sweep grid `[0x1000, 0x2000, 0x3000,
0x4000, 0x6000, 0x8000, 0xC000]`:
- A1 post-fix: `[+4096, +8192, +12288, +16384, +24576, 0, +16384]`
- Alt MSB-saturating: `[+4096, +8192, +12288, +16384, +24576, +32767, +32767]`

A1 produces a zero-coefficient cell (`0x8000` -> no body
contribution at all) followed by a smaller-magnitude cell
(`0xC000` -> +16384), which is genuinely surprising for an
unsigned-style host control surface. Operators who try `!B8000`
expecting "lots of body" will hear no body at all under A1.

The MSB-saturating alternative
(`mult_coeff <= body_mix_q15[15] ? 16'sd32767 :
$signed({1'b0, body_mix_q15[14:0]})`) is one extra mux but
preserves the user-facing intuition: writing larger `!B`
values produces larger body, capped at maximum.

This precision finding does not affect the audit's
recommended in-range subgrid `[0x1000..0x7000]`, where
both A1 and the MSB-saturating variant behave identically.
The audit's M6.2 verifier task text correctly emphasizes the
in-range subgrid as the primary acceptance test, with the
default 7-point grid as a secondary check.

**Recommendation to implementer for M6.2 task text**: when
implementing Candidate A, explicitly choose between A1
(modular wrap, zero LE delta, but non-monotonic for
`!B >= 0x8000`) and an MSB-saturating variant (truly monotonic,
~5-10 LE delta still well inside the +5 LE soft target). The
audit's hard gate of "LE delta <= +5" should be relaxed to "LE
delta <= +20" if the implementer chooses MSB-saturating, since
that produces better operator-facing behavior.

## 6. User-priority alignment

The audit explicitly defers polyphony, larger feature work,
SDRAM, JTAG control, and on-chip strike scheduler. The
recommendation is a single-line RTL fix that improves
single-voice quality control accuracy. Body filter retune,
body gain scalar, and body-only diagnostic mode are all
deferred behind the bug fix. This respects "voice quality
first, polyphony only as support infrastructure."

## 7. Acceptance gates: explicit verdict

| gate                                                               | result |
| ------------------------------------------------------------------ | ------ |
| Single-file scope                                                  | PASS (only `reports/phase6_m6_1_body_path_audit.md`) |
| ASCII-only                                                         | PASS   |
| No RTL/QSF/firmware/host/obsolete change                           | PASS   |
| Cited live RTL line numbers verified                               | PASS (line 446 cast confirmed) |
| Cited verifier band table values verified                          | PASS (A4 1-2 kHz row matches) |
| Bug claim independently verified                                   | PASS (signed cast on unsigned port) |
| Recommended remediation is smallest correct fix                    | PASS (Candidate A is right) |
| Candidate description precision                                    | MISS (A1 is modular, not saturating; section 5 above) |
| Recommended next implementation slice is single-file/single-line   | PASS |
| Hard gates (LE/timing) consistent with M5 baseline                 | PASS |
| No CPU/firmware/MMIO revival                                       | PASS |
| No JTAG command path                                               | PASS |
| No on-chip strike scheduler                                        | PASS |
| No polyphony feature work                                          | PASS |
| Existing `phase1_reduced_voice_tb` golden remains bit-exact post-A | PASS (validated: 0x4000 maps to +16384 unchanged) |

Overall: **PASS** with the precision finding in section 5
recorded for the M6.2 implementer.

## 8. Recommendations to orchestrator

1. **Queue the M6.2 implementer task** from section 6 of the
   audit, with the soft note in section 5 above forwarded to
   the implementer:
   - explicitly choose A1 vs MSB-saturating in M6.2;
   - relax the LE soft cap from +5 to +20 to permit the
     MSB-saturating variant if implementer prefers monotonic
     post-fix default-grid behavior;
   - keep the phase1_reduced_voice_tb at 0x4000 / body_mix
     12288 unchanged (both candidates produce the same
     value at 0x4000).

2. **Queue the M6.2 verifier task** from section 6 of the
   audit. The dual-grid acceptance design (default grid for
   wraparound check, in-range subgrid for monotonic trend
   check) is the right shape. Tiered PASS / CONDITIONAL_PASS
   thresholds (>=+3 dB / >=+1 dB end-to-end) are appropriate
   given known cell-to-cell variance.

3. **Do not queue any of candidates B, C, D, E in parallel.**
   The audit's deferral logic is correct; layered changes on
   an unfixed signed cast would measure a corrupted base.

4. **Document the parser/voice contract change.** Whether A1
   or MSB-saturating is chosen, the parser's existing comment
   ("allow the full 0x0000..0xFFFF range") should be updated
   to reflect that the audio path now treats the high bit as
   either ignored (A1) or saturating (MSB-sat). The parser
   TBs `phase0_uart_command_tb.v` sections 14-17 do not need
   to change because they only verify storage, not audio
   consequence.

## 9. Files

This report:

- `reports/phase6_m6_1_body_path_audit_validation.md` (new,
  this file, ASCII-only).

No RTL, host-script, QSF, SDC, firmware, obsolete archive,
generated-output, or stale-untracked-file change.

## 10. ASCII check

```
reports/phase6_m6_1_body_path_audit_validation.md  non_ascii=0
```

(verified by PowerShell foreach-byte loop before commit)
