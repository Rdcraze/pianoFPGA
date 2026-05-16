# Phase 4 M2 Reclamation Implementation Report

Date: 2026-05-16
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-0692867c`
Branch: `codex/phase1c-uart-boundary-fix`
HEAD before: `86fcf8a`

## TL;DR

**Partial NO-GO.** Candidate A (control_regs decode/strobe consolidation) was implemented and Quartus-validated; it **regressed LE by +146** instead of saving. The change has been reverted. Candidate C (delete dead `phase0_soc_stub.v`) was implemented and confirms zero LE/timing impact. No other slice is committed in this task. Net result: minor repo hygiene only; LE budget unchanged at 9,992 / 10,320.

| Gate | Target | Actual | Verdict |
| --- | --- | --- | --- |
| LE delta | <= -100 (soft); >= -200 ideal | 0 (after revert) | NO-GO on reclamation; PASS on hygiene |
| Setup slack >= +2.5 ns | yes | +2.914 ns (unchanged) | PASS |
| Hold slack | clean | +0.405 ns (unchanged) | PASS |
| All TNS = 0 | yes | yes | PASS |
| ROM = 931 | yes | 931 | PASS |
| M9K = 16, DSP9 = 28 | yes | 16, 28 (unchanged) | PASS |
| 4 voices preserved | yes | yes | PASS |
| UART/register/tag semantics unchanged | yes | yes (no RTL edit shipped) | PASS |
| Quartus compile errors | 0 | 0 | PASS |
| Quartus warnings | <= 16 baseline | 16 | PASS |

## Files Changed

| Path | Action | Notes |
| --- | --- | --- |
| `rtl/control/phase0_soc_stub.v` | **deleted** | Dead since Phase 3 M1 RV32I replacement; not in QSF, not instantiated, not in any TB or sim/build script. Only references were in historical reports and stale `tmp/`/`sim*/` ModelSim work caches. |

No other source file changed. The control_regs experiment was reverted before commit.

## What Was Attempted on Candidate A

I rewrote `rtl/control/phase0_control_regs.v` to:

1. Replace four named scalar per-voice state regs (`voice1_enable`, `voice1_trigger_strobe`, ..., per voice 1..3, plus voice0 path) with a 4-element array `v_enable_arr [3:0]`, `v_trigger_arr [3:0]`, `v_reset_arr [3:0]`, `v_clip_clear_arr [3:0]`.
2. Same for `voiceN_velocity` and `voiceN_loop_len`: collapsed into `v_velocity_arr [3:0]` and `v_loop_len_arr [3:0]`.
3. Added a small `voice_ctrl_idx`/`voice_loop_idx`/`voice_vel_idx` decoder (combinational case) to map per-voice register addresses (`REG_VOICEN_CONTROL`, `REG_VOICEN_LOOP_LEN`, `REG_VOICEN_VELOCITY`) onto array indices.
4. Drove the original scalar `voiceN_*` outputs from the array via `assign` (port type changed from `output reg` to `output wire`; semantics identical for downstream wires).
5. Preserved REG_VOICE_VELOCITY (0x28) and REG_VOICE_LOOP_LEN (0x2C) shared-write semantics: both still mirror to all four per-voice slots and the legacy scalar.
6. Preserved every reset default, register address, and strobe pulse rule.

### Quartus result (before revert)

| Metric | Baseline (pre-M2) | After Candidate A | Delta |
| --- | ---: | ---: | ---: |
| Total logic elements | 9,992 | **10,138** | **+146** |
| Combinational functions | 9,417 | 9,722 | +305 |
| Dedicated logic registers | 4,233 | 4,237 | +4 |
| Memory bits | 86,016 | 86,016 | 0 |
| Embedded Multiplier 9-bit | 28 | 28 | 0 |
| PLL | 1 | 1 | 0 |
| Slow-85C setup slack `sys_clk_50m` | +2.914 ns | +2.872 ns | -0.042 ns |
| Hold slack | +0.405 ns | +0.405 ns | 0 |
| TNS | 0 | 0 | 0 |
| Errors | 0 | 0 | 0 |
| Warnings | 16 | 16 | 0 |

Setup slack was still well above the +2.0 ns hard gate, but the LE went the wrong direction. Per the M2 task gate ("if recovery is <100 LE, stop and mark NO-GO"), I reverted the change.

## Why the LE Increased

The Phase 1 attribution hypothesis was that Quartus would pack the array storage tighter than four named registers. In practice, the opposite happened in this codebase:

- The original named scalars (`voice1_enable`, `voice2_enable`, ...) are independently driven by literal-address case branches. Quartus appears to have already been packing the original 4 x (enable/trigger/reset/clip_clear) into a tight set of LCs, and the per-address case decode shared LUT inputs efficiently.
- The new array-based form forced Quartus to materialize an indexed register array with a separate combinational `voice_ctrl_idx` decoder. The combinational LUTs to compute `idx`, gate writes by `voice_ctrl_match`, and select between shared-mirror writes and indexed writes added 305 combinational LCs (with only 4 register-LC reduction). Net: LE up.
- The same pattern shows up in the legacy `REG_VOICE_VELOCITY`/`REG_VOICE_LOOP_LEN` shared-mirror writes: the array form looks tidier but synthesizes to wider per-bit MUX logic between the shared write source, the indexed write source, and the per-voice read paths.

This is consistent with the M8 ROM-reclamation NO-GO precedent in spirit: code that looks more compact at the source level does not always synthesize/compile smaller in this toolchain. The Phase 1C-A and Phase 1C-B precedents both succeeded at memory- and tap-storage-level optimization, not at register-decode consolidation, which is the relevant difference.

## Candidate C: dead-file deletion

`rtl/control/phase0_soc_stub.v` was the deterministic bring-up agent that Phase 3 M1 (`task-9d00cc2f`) replaced with the real `phase0_rv32i_core` plus `phase0_rv32i_soc` integration. Verification:

- `quartus/phase0/piano_phase0_top.qsf` does not list it (`grep` clean).
- `rtl/top/piano_phase0_top.v` instantiates `phase0_rv32i_soc`, not `phase0_soc_stub`.
- `rtl/audio/phase1_reduced_voice_tb.v` does not reference it.
- `rtl/top/piano_phase0_top_tb.v` does not reference it.
- `fw/phase0/build.ps1` and `quartus/phase0/build.ps1` do not reference it.
- `git grep` over live source/script/firmware/scripts/docs/reports paths confirms the only references are in:
  - the dead file itself
  - historical reports (`reports/phase0_*`, `reports/phase4_m1_reclamation_scope.md`)
  - stale ModelSim work areas under `tmp/` and `sim*/` (these are caches, not sources)

After deletion, Quartus full compile is **bit-identical to baseline** (9,992 LE, +2.914 ns setup, 16 warnings, 0 errors). This is repo hygiene with zero behavior cost.

## Verification Performed

### Firmware build

```
PS> .\fw\phase0\build.ps1
Built build/phase0.elf, build/phase0.bin, and build/phase0.mem
```

ROM word count: **931** (unchanged).

### Quartus full compile

```
PS> Push-Location quartus\phase0; .\build.ps1 -Stage compile; Pop-Location
... Quartus II 64-Bit Shell was successful. 0 errors, 16 warnings ...
```

Two compiles were run:
1. After Candidate A + Candidate C: 10,138 LE, +2.872 ns. **REGRESSION; reverted.**
2. After Candidate C only (revert in place): 9,992 LE, +2.914 ns. **Bit-identical to baseline.**

Logs preserved at:
- `.kiro/quartus_m2.log` (Candidate A regression run)
- `.kiro/quartus_m2_revert.log` (post-revert clean run)

Both logs are local-only (not committed) -- they are large multi-megabyte Quartus stdout dumps and add no information beyond the `.fit.summary` and `.sta.summary` already in `quartus/phase0/output_files/`.

### ModelSim

Not run for this slice. Justification:
- Candidate A was reverted; no RTL behavior change shipped that needs simulation.
- Candidate C is a delete of a non-instantiated file; ModelSim source set is unaffected (the dead file is not in any compile script).
- The reduced-voice golden-sample TB is for `phase1_reduced_voice` only, which is out of M2 scope and was not modified.

## What's NOT in This Commit

- `rtl/audio/phase0_audio_path.v` (Candidate B1 mix-tree re-expression). Skipped because the dominant LE concern (Candidate A) regressed, so Candidate B1's marginal 30-60 LE win is no longer the priority. The audio_path mix-tree is also already pretty tight; given the pattern from Candidate A, similar collapse attempts on the OR-trees risk a similar regression and would need a separate, careful experiment.
- Sample_gen elision (B2): held per M1 scope, would need orchestrator authorization.
- Body-filter pruning (B3): held per M1 scope, timing risk.
- ROM reclamation (D): held per M1 scope and M8 precedent.

## Recommendation

1. **Accept Candidate C** as a small repo-hygiene improvement (delete `phase0_soc_stub.v`).
2. **Treat Candidate A as NO-GO** for the array-consolidation strategy. If LE recovery from `phase0_control_regs.v` is desired later, a different strategy is needed: not array-vs-scalar, but rather **selective collapse of the 32-bit readback case** (which is the largest single combinational construct in the module) without touching the write logic. That is a separate, narrower experiment for a future scoping task.
3. **Do not pursue further Candidate A variants** in this branch without first proving in a smaller test the variant actually saves LE in this Quartus 13.0.1 toolchain.
4. The bigger Phase 4 picture remains: SDRAM is held, headroom recovery is the right direction, but the easy wins on this codebase are not where the M1 scope predicted. Phase 4 may need a fundamentally different architectural path (e.g., voice time-multiplexing -- explicitly out of scope for M2) rather than register-file refactoring.

## Honest Assessment

The M1 scope estimate of "150-250 LE" recoverable from `phase0_control_regs.v` was wrong for this implementation strategy. The 975 direct LE in that module are mostly in **register storage and address-decode that Quartus is already packing well**, not in unpacked combinational duplication that an array refactor could collapse. The lesson is structurally similar to M8: Verilog-level "this looks repeated, surely it can be consolidated" does not necessarily translate to fewer LE after the toolchain runs.

This task therefore lands as a partial NO-GO with one small hygiene win. The orchestrator's two reasonable next steps are:

- **Path 1 (smaller, narrower scoping)**: queue a focused implementer task to try only the 32-bit readback `case` compaction (read mux only, no write changes). Estimate 30-100 LE; likely lower regression risk.
- **Path 2 (broader rethink)**: accept that on-chip headroom is structurally tight at 97% LE and revisit the Phase 4 M0 conclusion. Either authorize sample_gen elision (B2) for ~150 LE, accept the headroom limit and pursue features that fit, or move forward with the SDRAM preflight despite the headroom cost if a specific consumer can be defined.

This report stays narrow per task scope. No new architectural decisions are taken.

## Committed Result

Implementation commit: `5db0378` on branch `codex/phase1c-uart-boundary-fix`.

Single commit contents:
- delete `rtl/control/phase0_soc_stub.v` (Candidate C, dead-file removal)
- add `reports/phase4_m2_reclamation_impl.md`

No other source changes. Candidate A (control_regs array consolidation) was implemented locally, Quartus-validated to regress by +146 LE, and reverted before this commit; the reverted experiment is therefore not represented in the diff. Post-commit Quartus full compile is bit-identical to the pre-M2 baseline: LE 9,992, ROM 931, setup +2.914 ns, hold +0.405 ns, M9K 16, DSP9 28, 0 errors, 16 warnings.
