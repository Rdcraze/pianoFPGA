# Phase 6 M6.3 Body-Gain NO-GO Validation

Date: 2026-05-27
Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Branch: `codex/phase1c-uart-boundary-fix`
Validation HEAD: `e18ac7a` (M6.3 NO-GO body magnitude doubling
exceeds +20 LE gate, by implementer task `task-a6ddcf85`).

## Verdict

**PASS as a NO-GO containment record.**

The implementer correctly classified Candidate C as exceeding
the orchestrator's `<= +20 LE` hard gate, reverted the RTL
back to the M6.2-accepted baseline (`db65ac8`), and committed
a transparent report-only NO-GO with measured Quartus evidence.
RTL working tree, Quartus `output_files`, and committed source
are all at the M6.2-accepted state. No new feature work was
silently smuggled in. The three follow-up paths in section 5
of the impl report are sensible.

Verifier independently reproduced the variant 1 LE delta and
timing numbers with a fresh Quartus full compile against the
attempted RTL, then re-baselined back to M6.2. The implementer's
fitter analysis is exact: variant 1 produces LE 5,131 (+43 vs
M6.2 baseline 5,088), comb 4,912, registers 2,313, setup
slow-85C `sys_clk_50m` +5.707 ns, hold +0.409 ns, all TNS 0,
0 errors.

The M6.3 scope's "0 LE / wire-only" projection was indeed
wrong for the Quartus 13.0.1 fitter on Cyclone IV E. M6.3
Candidate C as scoped is structurally correct but not
gate-compliant under the current orchestrator-set caps. No
M6.3 hardware sweep was run or expected because RTL was
reverted.

The validation thus accepts the NO-GO containment and forwards
the orchestrator decision back: pick one of three follow-up
paths (cap raise, smaller-magnitude variant, or pivot to
Candidate D body-only diagnostic).

## 1. Scope, ASCII, and file gates

```
git show --stat e18ac7a
 reports/phase6_m6_3_body_gain_impl.md   | 277 +++++++++
 reports/phase6_m6_3_quartus_compile.log | 776 +++++++++++++++
 2 files changed, 1053 insertions(+)
```

ASCII bytes:

```
reports/phase6_m6_3_body_gain_impl.md     non_ascii=0  bytes=11726
reports/phase6_m6_3_quartus_compile.log   non_ascii=0  bytes=64079
rtl/audio/phase1_reduced_voice.v          non_ascii=0  bytes=22324
```

Two-file commit, ASCII-only. RTL on disk is unchanged from
`db65ac8` (M6.2 baseline):

```
git diff db65ac8..e18ac7a -- rtl/audio/phase1_reduced_voice.v
(no output)
```

No QSF, SDC, PLL, firmware, host-tool, generated bitstream,
obsolete archive, or accepted prior-baseline-report change.
Scope discipline PASS.

## 2. Verifier-side independent reproduction

Following the implementer report's exact variant 1 patch:

```
STATE_BODY_TAP30: begin
    mult_sample <= sat_q18(((q18_ext(body_tap6) >>> 2) -
                            (q18_ext(body_tap16) >>> 3) +
                            (q18_ext(body_read_data) >>> 4))
                           <<< 1);
```

I applied this temporarily to `rtl/audio/phase1_reduced_voice.v`,
ran a full Quartus compile, recorded the fit/timing evidence,
then `git checkout HEAD --` reverted the file back to the
M6.2 baseline and re-ran a final compile to restore the
`output_files` to M6.2 numbers.

### Variant 1 (M6.3 attempt) reproduced numbers

| metric                                | M6.2 baseline    | Implementer report | Verifier rerun     |
| ------------------------------------- | ---------------: | -----------------: | -----------------: |
| Total LE                              | 5,088 / 10,320   | 5,131 / 10,320     | **5,131 / 10,320** |
| LE delta vs M6.2                      |       -          | **+43**            | **+43**            |
| Combinational functions               | 4,848            | 4,912              | **4,912**          |
| Dedicated logic registers             | 2,241            | 2,313              | **2,313**          |
| Total memory bits                     | 20,480           | 20,480             | 20,480             |
| DSP9 elements                         | 26 / 46          | 26 / 46            | 26 / 46            |
| PLL                                   | 1 / 2            | 1 / 2              | 1 / 2              |
| Setup slow-85C `sys_clk_50m`          | +4.939 ns        | +5.707 ns          | **+5.707 ns**      |
| Hold slow-85C `sys_clk_50m`           | +0.397 ns        | +0.409 ns          | **+0.409 ns**      |
| All TNS                               |     0            |     0              |     0              |
| Quartus errors / warnings             |   0 / 16         |   0 / 16           |   0 / 16           |

Every implementer number reproduces exactly. The +43 LE delta
is real and toolchain-dependent (Quartus 13.0.1 on Cyclone IV
E), not a synthesis transient.

### Variant 1 actually improves timing

Setup slack rose from +4.939 ns (M6.2 baseline) to +5.707 ns
with the variant 1 shift, a +0.768 ns gain. The fitter is
trading more LE for shorter critical paths in the saturation
comparator. This is consistent with the implementer's
section 4 explanation: the shift forces a wider operand into
`sat_q18`, the synthesizer chooses a faster but less area-
efficient comparator, and packing optimizations from M6.2
that saved 17 LE no longer apply.

### Re-baseline to M6.2 confirms restoration

After reverting via `git checkout HEAD -- rtl/audio/phase1_reduced_voice.v`
and rerunning Quartus, the `output_files` show LE 5,088,
setup +4.939 ns, matching the M6.2 baseline. No persistent
M6.3 attempt artifacts remain in the worktree.

## 3. Implementer report quality review

The impl report at `reports/phase6_m6_3_body_gain_impl.md` is:

- **Honest about the scope's projection error.** Section 4
  ("Why the cost is real, not a synthesis quirk") explains
  why the M6.3 scope's "0 LE wire-only" projection was wrong
  for this fitter. This matches my own analysis below.
- **Comprehensive about alternatives.** Variant 2 (per-tap
  shift reduction) was tried and produced +70 LE, even worse.
- **Comprehensive about follow-up paths.** Section 5 lists
  three orchestrator-actionable next steps in priority order.
- **Conservative about acceptance.** RTL is reverted, output
  files are re-baselined, no NO-GO RTL is left lying in the
  worktree.
- **Transparent about ModelSim license blocker.** Same
  blocker as M6.2; verifier inherits the same constraint.

The implementer's preferred follow-up (5.1: orchestrator
relaxes the LE cap to ~50 LE, citing the M5 precedent at
task-3beccc57) is the path I would also recommend. See
section 6 below.

## 4. Why the M6.3 scope's projection was off

The M6.3 scope and my own M6.3 scope validation both
reasoned that `<<< 1` on a Q18 wire is "wire-only" routing
and should cost zero LE. That reasoning is correct in
isolation: the bit pattern just shifts one position higher
inside the same `sat_q18` block.

The M6.2 commit specifically saved 17 LE because the
simpler MSB-saturating mux replaced a `$signed(...)` cast
and the fitter was free to pack the surrounding register
file more aggressively. Adding `<<< 1` defeats those
particular optimizations because:

1. The post-shift result is one bit wider, requiring a
   wider comparator into `sat_q18`.
2. The wider comparator forces the synthesizer to allocate
   more LUT inputs to its saturation comparison logic.
3. Cyclone IV E LUT-4 fabric tends to amplify width changes
   into LUT count growth where Stratix-style LUT-6 fabric
   would absorb them.
4. M6.2's tight register packing depended on specific bit
   widths that change with the shift.

This is a **toolchain-and-fabric-specific cost** that the
M6.3 scope (and my M6.3 scope validation) underestimated. I
cross-checked by inspecting the actual M6.3 attempt fit
report: the +43 LE growth is concentrated in the body-multiplier
hierarchy (`STATE_BODY_TAP30` and the surrounding state
machine logic), confirming the structural origin.

This does not invalidate the audio model reasoning. Doubling
`mult_sample` would still produce the analyzed +1 to +3 dB
in-range body_mix swing if the LE cost were budgeted in. The
question is purely whether the +43 LE cost is acceptable.

## 5. Follow-up path comparison

The implementer's section 5 lists three paths. Verifier
review:

### 5.1 Orchestrator relaxes the LE cap (PREFERRED)

- **Cost**: +43 LE versus M6.2 baseline 5,088, leaving ~5,189
  free LE on EP4CE10. Headroom remains comfortable.
- **Risk**: Low. Setup slack actually improves by +0.768 ns.
  No DSP/M9K/PLL impact. No timing/clipping concern.
- **Audio benefit**: ~+1 to +3 dB in-range 1-3 kHz body_mix
  swing per the M6.3 scope validation analysis (which I
  forwarded as a soft note: realistic projection is below
  the optimistic 3-6 dB but firmly above the +1 dB
  CONDITIONAL_PASS gate).
- **Precedent**: M5 raised its hard cap from +150 LE to +200
  LE under task-3beccc57 because the +173 LE intrinsic cost
  was unavoidable and the audio benefit (runtime body_mix
  knob) was material.
- **Effort**: One follow-on implementer task plus one
  follow-on verifier task. ModelSim golden regeneration
  remains blocked on this host's invalid license, so the
  verifier owns that step.

### 5.2 Smaller-magnitude variant (CONDITIONAL_PASS path)

- **Cost**: probably 5-15 LE, well inside any reasonable cap.
- **Risk**: Different audio outcome. A 33% body magnitude
  bump would scale projected swing to ~+0.7 to +1.3 dB,
  which clears the CONDITIONAL_PASS gate (>= +1 dB) but
  almost certainly misses PASS (>= +3 dB).
- **Audio benefit**: Smaller. The body knob would be more
  audibly useful than M6.2 but still subjectively subtle.
- **Effort**: One follow-on scope task to define the
  variant precisely, then implementer + verifier.

### 5.3 Pivot to Candidate D (body-only diagnostic mode)

- **Cost**: Higher LE than C variant 1; new control flag,
  parser command, audio-path mux, new TB. Probably +50 to
  +150 LE.
- **Risk**: New UART command surface (e.g. `!Z1`/`!Z0`),
  more state in `phase0_audio_path.v`, more parser TB
  coverage needed.
- **Audio benefit**: Indirect. Body-only mode is a measurement
  tool; it does not by itself improve the user-facing voice.
  It does conclusively settle whether the body filter and
  body multiplier work, which would tell us whether C is
  even worth doing.
- **Effort**: New scope + implementer + verifier cycle. M6.1
  audit explicitly deferred D behind C; pivoting now reverses
  that ordering.

### Verifier recommendation

Path 5.1 is the lowest-risk highest-audio-benefit option.
Path 5.2 is a fallback if orchestrator wants to preserve the
+20 LE cap. Path 5.3 is the right move if user priority shifts
from "make body knob audible" to "diagnose voice model
behavior in isolation."

I would NOT recommend a no-op accept; the M6.2 CONDITIONAL_PASS
left an unresolved measurement gate, and the body knob is
operationally pointless at the current 0.3 dB swing.

## 6. ModelSim and TB status

Implementer report section 7 notes:

- `vlog -sv` clean compile on both variants.
- `vsim` blocked by documented invalid local license.
- No golden regeneration attempted because the gate failed
  before that step would matter.

Verifier-side: same license blocker. I confirmed `vlog`
clean compile on both variants. Existing M6.2-accepted
goldens remain valid because RTL is reverted.

## 7. User-priority alignment

Voice quality first: PASS. Polyphony is not invoked. The
NO-GO is honest and does not claim to "ship" the body-gain
fix. Implementer correctly avoided silent silent fixes that
would have skipped the gate.

All four physical voices remain. No CPU/firmware/MMIO
revival, no JTAG path, no on-chip scheduler, no polyphony
work, no obsolete revival.

## 8. Acceptance gates: explicit verdict

| gate                                                                | result |
| ------------------------------------------------------------------- | ------ |
| Scope: only impl report + Quartus log changed                       | PASS   |
| ASCII-only on touched files                                         | PASS   |
| RTL on disk reverted to M6.2 baseline                               | PASS (verified by `git diff` empty) |
| Quartus output_files re-baselined to M6.2                           | PASS (LE 5,088, setup +4.939 ns reproduced) |
| Implementer's variant 1 LE delta independently reproduced           | PASS (+43 LE, exact match) |
| Implementer's variant 1 timing independently reproduced             | PASS (+5.707 ns setup, exact match) |
| LE delta `<= +20 LE` hard gate                                      | MISS (+43 LE, NO-GO correctly classified) |
| No body_filter retune, body-only diagnostic, or harness extension   | PASS |
| No firmware/CPU/MMIO/JTAG/scheduler/polyphony revival               | PASS |
| Three follow-up paths sensible and orchestrator-actionable          | PASS |
| ModelSim `vlog -sv` clean (vsim blocked by license)                 | PASS (compile clean; license blocker documented) |

Overall verdict: **PASS as NO-GO containment**. The implementer
correctly classified Candidate C as gate-non-compliant under
the current `<= +20 LE` cap, reverted RTL, and submitted
transparent evidence. Verifier independent reproduction
confirms every number.

## 9. Recommendations to orchestrator

1. **Accept the M6.3 NO-GO as recorded.** RTL is at M6.2
   baseline, output_files match M6.2, no silent feature
   creep. The committed evidence is sufficient for future
   reference.

2. **Choose a follow-up path.** Verifier preference is 5.1
   (relax LE cap to ~50 LE, citing M5 precedent). Path 5.2
   (smaller-magnitude variant) is the conservative
   alternative. Path 5.3 (Candidate D body-only diagnostic)
   reverses the M6.1 audit's ordering and is appropriate
   only if user priority changes.

3. **If 5.1 is chosen**, queue a follow-on implementer task
   that:
   - Re-applies variant 1 RTL (same single-line change as
     the attempted M6.3).
   - Regenerates `rtl/audio/phase1_reduced_voice_golden_samples.hex`
     via the `+WRITE_GOLDEN` plusarg path. ModelSim license
     remains blocked on this host; the implementer or
     verifier with a valid license owns this step.
   - Updates `phase1_reduced_voice_velocity_tb` expected
     peaks if needed, preserving inequality intent.
   - Confirms `phase1_reduced_voice_body_mix_sat_tb` PASS
     unchanged (saturation TB is bit-equality assertion
     between three body_mix values, preserved under uniform
     doubling).
   - Submits a follow-on impl report and a fresh Quartus
     compile log under a new task ID.

4. **If 5.2 is chosen**, queue a fresh scope task to define
   the smaller-magnitude variant precisely (which tap to
   shift, expected band swing, expected LE cost).

5. **Do NOT queue the M6.3 verifier task as written**
   (`scripts/phase6_m6_body_mix_sweep.py --run` against the
   M6.3 SOF). There is no M6.3 SOF; RTL is at M6.2 baseline.
   The verifier task would just re-validate M6.2, which was
   already accepted at validation commit `b332743`.

6. **Consider Candidate E (coherent-average harness extension)
   as a parallel measurement-tooling slice.** It is voice-
   model-independent and would help any subsequent body-gain
   slice (5.1 or 5.2) achieve cleaner band-energy A/B with
   K=4 or K=8 averaging.

## 10. Files

This report:

- `reports/phase6_m6_3_body_gain_validation.md` (new, this
  file, ASCII-only).

Verifier-side (`.kiro/`, not committed):

- `m63_verify_compile.log` (variant 1 verification compile)
- `m63_rebaseline_compile.log` (re-baseline compile)

No RTL, host-script, QSF, SDC, firmware, obsolete archive,
generated-output, or stale-untracked-file change.

## 11. ASCII check

ASCII verified by PowerShell foreach-byte loop before commit.
