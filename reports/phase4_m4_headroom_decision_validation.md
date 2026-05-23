# Phase 4 M4 Headroom Decision Validation

Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-c87ee6e6` (depends on implementer `task-91be7a1f`)
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `81105ab`

## Verdict

**PASS.** The Phase 4 M4 headroom decision report is sound, source-grounded, planning-only, and ASCII-only. The recommendation to queue a Phase 4 M5 implementer task that gates `phase0_sample_gen` behind a build-time `localparam ENABLE_SAMPLE_GEN` in `rtl/audio/phase0_audio_path.v` is reasonable and the proposed no-go gates are concrete enough to prevent another M2/M3-style toolchain-pack regression from being shipped.

## Scope check

`git show --stat 81105ab`:
- `reports/phase4_m4_headroom_decision_scope.md` (+286 lines, new)

No RTL, firmware, host tools, SDC, constraints, QSF/project files, PLL, generated outputs, or unrelated docs were modified. PASS.

## ASCII check

`reports/phase4_m4_headroom_decision_scope.md`: 0 non-ASCII bytes (size 25,589). PASS.

## Source spot-checks

| Claim | Source | Result |
| --- | --- | --- |
| M2 Candidate A regressed +146 LE; M2 Candidate C accepted as inert | `reports/phase4_m2_reclamation_validation.md` (PASS) | Confirmed |
| M3 readback-mux 0 LE delta and reverted | `reports/phase4_m3_readback_mux_validation.md` (PASS) | Confirmed |
| Baseline LE 9,992 / 10,320, M9K 16, DSP9 28, +2.914 ns setup, ROM 931 | `quartus/phase0/output_files/piano_phase0_top.fit.summary` and `.sta.summary`, `fw/phase0/build/phase0.bin` (3,724 B = 931 words) | Confirmed |
| Four physical voices in `phase0_audio_path.v` | grep on `phase1_reduced_voice` shows `phase1_reduced_voice_inst`, `phase1_reduced_voice1_inst`, `phase1_reduced_voice2_inst`, `phase1_reduced_voice3_inst` | Confirmed |
| `use_sample_gen` mux gates on all four voices disabled | `rtl/audio/phase0_audio_path.v` lines 285-287: `assign use_sample_gen = audio_enable && tone_enable && !voice_enable && !voice1_enable && !voice2_enable && !voice3_enable;` | Confirmed |
| Production firmware never disables all four voices | `fw/phase0/phase0_main.c` defines `PHASE0_VOICE_CONTROL_BASELINE = ENABLE_M` (line 13-14), `PHASE0_VOICE1/2_CONTROL_BASELINE` similarly, and `VOICE3_CONTROL_ENABLE_M` is OR'd in for voice 3 (line 324). All voice writes always include the enable bit. | Confirmed |
| `tx_valid`/`tx_sample` mux at lines 288-289 selects sample_gen only when `use_sample_gen` is asserted | grep result lines 288-289 quoted in report match source verbatim | Confirmed |
| sample_gen diagnostic evidence at `reports/phase1c_sample_gen_test_validation.md` | File exists in repo from M3b/Phase 1C era | Confirmed (referenced earlier in this branch) |

No factual claim in the report contradicts the source. PASS.

## Recommendation assessment

The recommended M5 slice is well-scoped:

1. Allowlist of touched files limited to `rtl/audio/phase0_audio_path.v` plus the new report. This avoids the M2 trap of touching `phase0_control_regs.v` storage/decode/readback.
2. Behavior preservation is provable from reachability: production firmware always sets `ENABLE_M` on every voice control write, so `!voice_enable && !voice1_enable && !voice2_enable && !voice3_enable` is never true and the `use_sample_gen` branch is unreachable. Removing the instance under that branch is therefore bit-exact equivalent to current production behavior.
3. The diagnostic is preserved as a single-line parameter flip plus rebuild; the source file is not deleted.
4. The hard NO-GO gate (LE delta worse than -50 reverts the RTL) protects against the M2/M3 toolchain-pack pattern. This is the right defensive posture given Quartus 13.0.1 has repeatedly already merged "obvious" redundancy upstream.
5. Setup-slack and TNS gates (+2.5 ns / 0) are tighter than the accepted baseline (+2.914 ns / 0), keeping a clear margin.
6. Hardware UART/audio gates (`G=8 K=0 X=0 Q=0` no-command, `G=14 Q=6 K=0 X=0` 6-command, voice3 telemetry coherent, ST coherent under burst) match the M3b/M9 acceptance contract.

Minor observations, none blocking:

- The report's section 5 says "rebuild [firmware] as evidence" even though firmware is untouched. That is a sound discipline (forces ROM = 931 to be re-confirmed after the gate is in place, even if no firmware change is intended) and avoids accidentally accepting a build that drifted.
- Section 5 also asks the M5 task to confirm M9K and DSP9 do not change; that is appropriate because the gated-out instance contains no M9K or DSP9 (`phase0_sample_gen` is purely a phase accumulator + envelope counter), so a delta there would indicate Quartus also pulled in or pushed out neighbouring logic.
- The "blocked features" framing in Phase 4 scope is correctly applied: gating sample_gen does not introduce sample playback (the named blocked feature) and does not change the register map. The report distinguishes feature removal (hard delete) from behavior-preserving optimization (build-time gate), and recommends only the latter. PASS on the guardrail.

The other three options (accept, mix-tree, voice TDM/SDRAM) are evaluated honestly: accept is the fallback, mix-tree is downgraded with justification tied to the M2/M3 NO-GO precedent, and TDM/SDRAM are correctly identified as outside the architecture guard / lacking a consumer.

## Hardware skip

Hardware UART/audio not run. Justification: this validates a planning report; commit `81105ab` is report-only and changes no synthesized or executed code path. PASS by inertia.

## Final verdict

**PASS.** Phase 4 M4 headroom decision report is acceptance-grade. Orchestrator may queue the proposed Phase 4 M5 implementer task to gate `phase0_sample_gen` behind a `localparam ENABLE_SAMPLE_GEN = 1'b0` in `rtl/audio/phase0_audio_path.v` only, with the no-go gates and out-of-scope guards stated in section 5 of the report.
