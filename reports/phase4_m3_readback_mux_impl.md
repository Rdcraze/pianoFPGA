# Phase 4 M3 Readback Mux Micro-Experiment Report

Date: 2026-05-16
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-22818f8e`
Branch: `codex/phase1c-uart-boundary-fix`
HEAD before: `386698d`

## TL;DR

**NO-GO.** The narrowest behavior-preserving compaction of the
`phase0_control_regs.v` 32-bit readback case (collapsing the explicit
`REG_VOICE_DIAG_CONTROL: reg_rdata = 32'd0;` arm into the existing
`default: reg_rdata = 32'd0;` arm) was implemented and Quartus-validated.
The result is **bit-identical to baseline**: LE 9,992 (unchanged), all
slacks identical to the digit, ROM unchanged at 931. Per the task gate
("If LE delta is positive, zero, or less than 25 LE, revert RTL and commit
only `reports/phase4_m3_readback_mux_impl.md` as NO-GO"), the RTL change
has been reverted. No source changes are committed.

| Gate | Target | Actual | Verdict |
| --- | --- | --- | --- |
| LE reduction | >= 25 LE | 0 LE | NO-GO |
| Setup slack >= +2.0 ns | yes | +2.914 ns (unchanged) | PASS |
| Hold slack | clean | +0.405 ns (unchanged) | PASS |
| All TNS = 0 | yes | yes | PASS |
| ROM = 931 | yes | 931 | PASS |
| M9K, DSP9, PLL unchanged | yes | 16, 28, 1 (unchanged) | PASS |
| Quartus errors | 0 | 0 | PASS |
| Quartus warnings | <= 16 baseline | 16 | PASS |
| ASCII-only on touched files | yes | yes | PASS |
| Behavior preserved | yes | yes (semantically equivalent) | PASS |

## Experiment Design

The Phase 4 M2 NO-GO precedent was that array-vs-scalar refactoring of
the write/strobe/storage logic in `phase0_control_regs.v` regressed by
+146 LE. The M2 follow-up scope explicitly recommended trying only the
readback mux compaction next, with no write-path changes.

The readback mux is a single combinational `case` over
`reg_addr` with about 50 arms. It is gated by `if (reg_rd_en)` and
defaults `reg_rdata` to `32'd0` at the top of the always block. Looking
at the existing arms, exactly one arm is provably redundant against
the default:

```verilog
REG_VOICE_DIAG_CONTROL: begin
    reg_rdata = 32'd0;
end
```

This arm matches the default behavior exactly: the diagnostic-control
register has no readable state, so reads return zero. The arm exists
only for documentation. Removing it lets `REG_VOICE_DIAG_CONTROL` reads
fall through to the existing `default: reg_rdata = 32'd0;` arm. The
read value at address `0x50` is unchanged.

This is the smallest and lowest-risk readback-mux compaction available.
Any larger compaction (zero-extension folding for groups of count-style
registers, e.g. trying to share one `{16'd0, ...}` zero-padder across
several arms) would touch wider logic and is exactly the source-level
trick that the M2 NO-GO showed the toolchain does not reward in this
codebase.

## What Was Attempted

Single one-arm removal in `rtl/control/phase0_control_regs.v`:

```diff
             REG_VOICE_VALID_COUNT: begin
                 reg_rdata = voice_valid_count;
             end
-            REG_VOICE_DIAG_CONTROL: begin
-                reg_rdata = 32'd0;
-            end
             REG_VOICE1_CONTROL: begin
                 reg_rdata = {31'd0, voice1_enable};
             end
```

No write-path changes. No storage changes. No strobe changes. No
default-value changes. No register-map changes. No top-level wiring
changes. No firmware/script/constraint/QSF/generated-output changes.

## Quartus Result

Full Quartus 13.0.1 compile (Analysis & Synthesis, Fitter, Assembler,
TimeQuest) with the experiment applied:

| Metric | Baseline (`386698d`) | After experiment | Delta |
| --- | ---: | ---: | ---: |
| Total logic elements | 9,992 | 9,992 | 0 |
| Total combinational functions | 9,417 | 9,417 | 0 |
| Dedicated logic registers | 4,233 | 4,233 | 0 |
| Total memory bits | 86,016 | 86,016 | 0 |
| Embedded Multiplier 9-bit elements | 28 | 28 | 0 |
| Total PLLs | 1 | 1 | 0 |
| Slow-85C setup `sys_clk_50m` | +2.914 ns | +2.914 ns | 0 |
| Slow-85C hold `sys_clk_50m` | +0.405 ns | +0.405 ns | 0 |
| Slow-85C setup `i2c_clk` | +17.573 ns | +17.573 ns | 0 |
| Slow-85C setup `audio_bclk` | +316.385 ns | +316.385 ns | 0 |
| All TNS | 0 | 0 | 0 |
| Quartus errors | 0 | 0 | 0 |
| Quartus warnings | 16 | 16 | 0 |

Bit-identical. The Quartus minimization in the baseline already merged
the redundant arm into the default branch, so removing it at the source
level produces identical synthesized logic.

The experiment compile timestamp was `2026-05-16 14:54:35` (Sat May 16
2026, fitter "Successful"). Compile log was captured locally to
`.kiro/quartus_m3.log` (not committed; multi-megabyte Quartus stdout
adds no information beyond the `.fit.summary` and `.sta.summary`).

After the NO-GO verdict, the RTL change was reverted via
`git checkout -- rtl/control/phase0_control_regs.v`. Repo is back to
the accepted baseline tree.

## Address-by-Address Equivalence

For the one address affected:

| Address | Symbol | Pre-experiment readback | Post-experiment readback | Equivalent? |
| --- | --- | --- | --- | --- |
| `0x50` | `REG_VOICE_DIAG_CONTROL` | `32'd0` (explicit case arm) | `32'd0` (default fallthrough) | yes |

Every other address in the readback case is unchanged. The default arm
is unchanged (`reg_rdata = 32'd0;`). The unconditional initialization at
the top of the always block (`reg_rdata = 32'd0;`) is unchanged. There
is no behavioral difference at any address.

## Firmware Build

```
PS> .\fw\phase0\build.ps1
Built build/phase0.elf, build/phase0.bin, and build/phase0.mem
```

ROM word count: **931** (unchanged).

## ModelSim

Not run for this experiment. Justification:

- The RTL change was a removal of a redundant case arm with provably
  identical readback value, and the change has been reverted.
- The post-revert source matches the accepted baseline (`386698d`)
  byte-for-byte for `rtl/control/phase0_control_regs.v`.
- Running TBs on a reverted source set adds no new evidence beyond what
  the accepted baseline already validated.

If ModelSim evidence were needed for orchestrator confidence, the
relevant TB would be the top-level happy-path / NACK / UART command path
TB. Those are accepted at the M2 baseline and do not change here.

## Why This Was Likely To Be NO-GO

The M2 NO-GO already established that Quartus 13.0.1 packs this
codebase tightly enough that source-level "this looks redundant"
rewrites in `phase0_control_regs.v` do not produce LE savings. The
readback mux specifically was already a clean case statement over
distinct addresses with a uniform `default: reg_rdata = 32'd0;`. The
synthesizer has already minimized it. Any further compaction at the
case-arm level either:

1. Hits the existing minimization (zero LE delta) -- this was the
   actual outcome.
2. Pulls a wider set of arms together via shared zero-padding or
   structural muxing, which is the M2 Candidate A pattern in disguise
   and risks the same +146-LE class of regression.

The single-arm removal was the only experiment that fit cleanly in the
"readback mux only, no write changes" scope without crossing into
storage/zero-padding refactors that look attractive on paper but cost
LE in this toolchain.

## Recommendation

1. **Accept the NO-GO verdict** for M3 readback-mux compaction. The
   accepted baseline RTL is unchanged.
2. **Do not pursue further `phase0_control_regs.v` LE recovery in this
   branch** without a fundamentally different angle (for example,
   removing or gating diagnostic readback paths that firmware does not
   actually read, which would be a behavior-changing scope decision and
   is explicitly out of M3 scope).
3. The bigger Phase 4 picture remains as M2 stated: on-chip headroom is
   structurally tight at 97% LE, and the easy register-decode/readback
   wins predicted by paper-level scoping do not materialize in this
   Quartus 13.0.1 toolchain. Phase 4 will need a different architectural
   move (e.g., voice time-multiplexing -- explicitly out of M3 scope) or
   acceptance of the headroom limit.

## Honest Assessment

This experiment confirms the M2 lesson at a smaller scale: even the
narrowest, provably equivalent readback-mux compaction in this module
yields zero LE delta. That outcome was the most likely a priori, given
the M2 evidence. The experiment was still worth running because the M2
report explicitly recommended a readback-only attempt, and "we tried it
and the toolchain truly does not reward this kind of compaction in this
module" is a stronger conclusion than "we believe it would not work."

This task therefore lands as an honest NO-GO with no source changes.
The orchestrator's reasonable next steps are:

- **Hold M3 reclamation work in `phase0_control_regs.v`.** Source-level
  compaction in this module is closed.
- **Authorize a structurally different reclamation angle** if Phase 4
  feature work needs LE headroom. Candidates that have not yet been
  attempted include sample_gen elision (held under M1 scope) or
  phase0_audio_path mix-tree reshaping with an explicit pipeline
  experiment, both of which cross M3's "readback mux only" boundary.
- **Or accept the headroom limit and pick Phase 4 features that fit
  inside the current 328-LE margin.**

This report stays narrow per task scope. No new architectural
authorization is taken.

## Committed Result

This task commits **report only**. No RTL/script/constraint/QSF/firmware/
generated-output changes are committed.

Single commit contents:
- add `reports/phase4_m3_readback_mux_impl.md`

Repo state after commit: tree net-identical to `386698d` for all source
files; only this report is added.
