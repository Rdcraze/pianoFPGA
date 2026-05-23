# Phase 4 M3 Readback-Mux Validation

Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-8ada40b5` (depends on implementer `task-22818f8e`)
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `07d9a49`

## Verdict

**PASS.** M3 readback-mux compaction is rejected as NO-GO. Source baseline is byte-identical to the accepted post-M2 baseline at `386698d`; commit `07d9a49` is report-only and adds `reports/phase4_m3_readback_mux_impl.md` with no synthesis or behavior impact. Existing fit/timing/firmware artifacts remain authoritative.

## Scope check

`git show --stat 07d9a49`:
- `reports/phase4_m3_readback_mux_impl.md` (+229 lines, new)

No RTL, firmware, host tools, SDC, constraints, QSF/project files, generated outputs, or unrelated docs/reports were modified. PASS.

## Source-equivalence check

`git diff 386698d 07d9a49 -- rtl/control/phase0_control_regs.v` returns no diff. The implementer's experimental compaction was reverted before commit, leaving the readback mux at HEAD identical to the accepted post-M2 baseline. PASS.

The reported equivalence is also semantically sound at the source level. In current `rtl/control/phase0_control_regs.v`:

- Line 387-389: `REG_VOICE_DIAG_CONTROL: begin reg_rdata = 32'd0; end`
- Line 465-467: `default: begin reg_rdata = 32'd0; end`

Both arms emit identical `32'd0`, so collapsing the explicit case into the default fallthrough is bit-identical to a Verilog reader and to Quartus 13.0.1, which already merged them upstream. Independently consistent with the implementer's NO-GO finding.

## ASCII check

`reports/phase4_m3_readback_mux_impl.md`: 0 non-ASCII bytes (size 9,759). PASS.

## Firmware / ROM

`fw/phase0/build/phase0.bin`: 3,724 bytes = **931 words**. Matches accepted M3b/M9/M2 baseline. PASS.

A fresh firmware rebuild was not run because `fw/phase0/` is unchanged at HEAD `07d9a49` versus `386698d`; the existing artifact is authoritative.

## Fit / timing

Existing Quartus output files reused; both timestamped Sat May 16 2026 14:54 (post-M2 baseline build), which is correct because committed RTL/QSF/SDC are unchanged at HEAD `07d9a49`:

- `output_files/piano_phase0_top.fit.summary`: LE 9,992 / 10,320 (97%), comb 9,417, regs 4,233, memory bits 86,016, M9K 16, DSP9 28 / 46, PLL 1.
- `output_files/piano_phase0_top.sta.summary`: slow-85C `sys_clk_50m` setup +2.914 ns, hold +0.405 ns, all clocks/corners TNS 0.

Identical to the accepted M2 baseline numbers. PASS.

## Hardware skip

Hardware UART/audio not run. Justification: commit is report-only, no RTL or firmware behavior changed at HEAD versus the accepted M3b/M9/M2 baseline; no SOF regeneration is required. PASS by inertia.

## Final verdict

**PASS.** Phase 4 M3 readback-mux compaction is rejected as NO-GO. Source-level compaction in `phase0_control_regs.v` is now closed for this Quartus toolchain (M2 lesson confirmed at smaller scale). Baseline remains LE 9,992, M9K 16, DSP9 28, +2.914 ns setup, ROM 931. Safe to continue.
