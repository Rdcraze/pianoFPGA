# Phase 4 M6 Fit-Margin Feature Scope Validation

Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-c015169a` (depends on implementer `task-5ec19ae9`)
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `4785c93`

## Verdict

**PASS.** The Phase 4 M6 fit-within-margin feature scope report is sound, source-grounded, planning-only, and ASCII-only. The recommendation to queue a Phase 4 M7 implementer task that adds velocity-layered hammer excitation in `rtl/audio/phase1_reduced_voice.v` only is technically plausible, fits the 328 LE margin with reserve, and the proposed no-go gates are concrete.

## Scope check

`git show --stat 4785c93`:
- `reports/phase4_m6_fit_margin_feature_scope.md` (+291 lines, new)

No RTL, firmware, host tools, SDC, constraints, QSF/project files, PLL, generated outputs, or unrelated docs were modified. PASS.

## ASCII check

`reports/phase4_m6_fit_margin_feature_scope.md`: 0 non-ASCII bytes (size 22,063). PASS.

## Baseline resource spot-check

Read directly from current `quartus/phase0/output_files/` (refreshed at `eafb6d3`, valid through `4785c93` because no source change):

- LE 9,992 / 10,320 (97%), 328 LE free
- Combinational 9,417, regs 4,233, M9K 16, DSP9 28, PLL 1
- Setup slow-85C `sys_clk_50m` +2.914 ns, hold +0.405 ns, all TNS 0
- Firmware ROM `fw/phase0/build/phase0.bin` = 3,724 bytes = 931 words

All baseline numbers in the report match the on-disk evidence. PASS.

## Technical plausibility of M7 recommendation

Spot-check of `rtl/audio/phase1_reduced_voice.v`:

- `excitation_rom` is a 16-entry constant function (lines 144-166) indexed by a 4-bit `index`. Current peak is `16'd32627` at index 3, matching the report's "no entry exceeds 16'd32767" upper bound rationale.
- `velocity_q15` is an input port (line 13) available everywhere in the FSM, including at trigger time and at `STATE_GAIN_FINISH` where `excitation_rom(excite_index)` is currently consumed (line 307).
- The trigger latch block at `if (reset_strobe || (trigger_strobe && enable))` (line 214) is exactly the place to add a single `velocity_layer_q <= (velocity_q15 >= 16'h6000)` register update, as the report specifies.
- `STATE_GAIN_FINISH` -> `STATE_EXCITE_FINISH` `>>> 1` (line 323) saturates cleanly into Q18, so a layer-1 peak of up to `16'd32767` will not overflow.

The recommended slice fits inside `phase1_reduced_voice.v` with no port changes; `phase0_audio_path.v` already passes `velocity_q15` to each instance, and no register-map change is required because the threshold is a localparam in the slice. The report's 30-50 LE per-voice estimate (120-200 LE total at 4 voices) is plausible for a 16-entry constant ROM duplication with a 1-bit selector, given that hammer ROM constants are pure LUT4 today.

Behavior-preservation argument is sound: layer 0 is bit-exact today, the threshold is set above the existing reduced-voice TB default, so the existing golden-sample TB selects layer 0 and stays bit-exact. PASS.

## Recommendation assessment

The recommended slice is well-scoped:

1. Allowlist of touched files limited to `rtl/audio/phase1_reduced_voice.v` only. No firmware, no `phase0_control_regs.v`, no `phase0_audio_path.v`, no `phase0_body_filter.v`. This avoids the M2 trap and the body-filter timing risk.
2. Hard NO-GO ceiling at +250 LE (78 LE reserve) is appropriate given the M2 +146 LE / M5 -43 LE fitter-variance precedent.
3. Setup-slack gate >= +2.5 ns budgets 0.4 ns of erosion below the +2.914 ns baseline, which is reasonable for a register + comparator + 16-entry mux on a non-critical path.
4. M9K, DSP9, and PLL gates are exact-zero-delta, which matches the design intent (constant ROM duplication adds none of those).
5. Golden-sample TB bit-exact gate at the existing TB velocity is enforced by setting the threshold above the TB default (the report's "Option 1" first-slice discipline). This is the right risk posture.
6. Comparison table covers all three serious candidates plus rejection rationale for sympathetic resonance, pre-strike noise, SDRAM, and sample playback. Rejected items are correctly out of scope under the architecture guard, M0 SDRAM hold, or `docs/project_brief.md` blocked-features list.

Minor observations, none blocking:

- The report's threshold value `16'h6000` (75% of `16'h7FFF`) is an implementer choice. Verification should confirm that this is genuinely above the existing reduced-voice TB's default `velocity_q15`. The report instructs the implementer to do that check before commit, which is correct discipline.
- The audible payoff in the first slice will be limited because the threshold is high; only velocities >= 75% will hear layer 1. A follow-up slice may lower the threshold and regenerate the golden sample, which the report acknowledges and defers correctly.
- Damper release shaping (Candidate C) reuses `mult_sample`/`mult_coeff` regs as a possibility; the report flags the LE upper bound (320 LE, exceeds the 250 LE ceiling) and holds it correctly.
- Body-filter coefficient bank (Candidate B) timing risk is correctly flagged. The report holds it pending a separate TimeQuest analysis, which is the right call.

The recommendation is decisive (one slice, allowlist + denylist + NO-GO gates) without being overbroad.

## Report-hygiene note

The report header reads `HEAD: eafb6d3`, but `git log` shows the actual parent of `4785c93` is `32e7c7a` (the M5 compile-refresh validation commit). `git diff eafb6d3 32e7c7a --stat` shows the only delta between the two cited heads is the addition of `reports/phase4_m5_baseline_compile_refresh_validation.md` (+79 lines, report-only).

So the substantive claim, that the M6 report's resource baseline reflects a clean, just-refreshed compile of the current source, is correct: source files at `eafb6d3` and `32e7c7a` are byte-identical because both intermediate commits in between are report-only. The cited HEAD is stale wording, not a factual error in the resource baseline.

This is a recurring pattern (M5 report cited `81105ab` instead of `4ce5f21`; this M6 report cites `eafb6d3` instead of `32e7c7a`). Recording for implementer report hygiene: cite the actual parent commit (`git rev-parse HEAD~1` at write time) or omit the HEAD line entirely. Not a blocker for acceptance.

## Hardware skip

Hardware UART/audio not run. Justification: this validates a planning report; commit `4785c93` is report-only and changes no synthesized or executed code path. PASS by inertia.

## Final verdict

**PASS.** Phase 4 M6 fit-within-margin feature scope is acceptance-grade. Orchestrator may queue the proposed Phase 4 M7 implementer task to add velocity-layered hammer excitation in `rtl/audio/phase1_reduced_voice.v` only, with the no-go gates and out-of-scope guards stated in section 4 of the report.
