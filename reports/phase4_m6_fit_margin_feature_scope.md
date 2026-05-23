# Phase 4 M6 Fit-Within-Margin Feature Scope

Date: 2026-05-23
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-5ec19ae9`
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `eafb6d3`

Sources:
- `reports/phase4_m0_preflight.md` (SDRAM held; reclamation-first)
- `reports/phase4_m4_headroom_decision_scope.md` (M4 plan, 4 options)
- `reports/phase4_m5_sample_gen_gate_impl.md` (NO-GO, -43 LE)
- `reports/phase4_m5_sample_gen_gate_validation.md` (verifier accept of M5 NO-GO)
- `reports/phase4_m5_baseline_compile_refresh_validation.md` (refreshed baseline)
- `rtl/audio/phase1_reduced_voice.v` (per-voice synthesis, instantiated 4x)
- `rtl/audio/phase0_body_filter.v` (2-stage biquad, single instance)
- `rtl/audio/phase0_audio_path.v` (mix tree, 4 voice instances, sample_gen mux)
- `rtl/control/phase0_control_regs.v` (register map; do not reopen)
- `fw/phase0/phase0_main.c` (control plane, telemetry)
- `quartus/phase0/output_files/piano_phase0_top.fit.summary` (LE 9,992 / 10,320)
- `docs/project_brief.md` Phase 4 scope

## TL;DR

**Recommendation: queue a Phase 4 M7 task to add velocity-layered hammer excitation in `phase1_reduced_voice.v` only.** The change is a tightly bounded second hammer-curve ROM selected by a velocity threshold latched at trigger time. It is the most piano-realistic audible improvement among the candidates that fit safely inside the 328 LE margin, it does not touch the timing-critical body filter, it does not change the register map or telemetry, and the per-voice cost has a credible 30-50 LE upper bound (120-200 LE x4 voices). The recommended slice sets a hard NO-GO at +250 LE total to keep at least 78 LE of fitter-variance reserve.

The other two candidates (body-filter coefficient bank, damper release shaping) are kept as fallbacks but carry larger timing risk or smaller audible payoff.

| Gate | Recommendation |
| --- | --- |
| Take implementation action this task | NO (planning only) |
| Recommend next implementer task | YES (M7: velocity-layered hammer ROM in `phase1_reduced_voice.v`) |
| Reopen `phase0_control_regs.v` reclamation | NO (closed by M2/M3) |
| Reopen sample_gen gate | NO (closed by M5) |
| Modify body filter coefficients in this slice | NO (timing risk; reserve for later) |
| Reduce physical voice count | NO (architecture guard) |
| Authorize SDRAM | NO (M0 conclusion unchanged) |

## 1. Resource Posture (refreshed M5 baseline)

| Metric | Value | Free margin |
| --- | ---: | ---: |
| Total logic elements | 9,992 / 10,320 (97%) | **328 LE** |
| Combinational functions | 9,417 / 10,320 | n/a |
| Dedicated logic registers | 4,233 / 10,320 (41%) | 6,087 |
| Memory bits | 86,016 / 423,936 (20%) | 337,920 |
| M9K equivalent | 16 | 30 (out of 46) |
| Embedded multiplier 9-bit | 28 / 46 (61%) | **18** |
| PLLs | 1 / 2 (50%) | 1 |
| Slow-85C setup `sys_clk_50m` | +2.914 ns | +0.914 ns above +2.0 ns floor |
| Slow-85C hold `sys_clk_50m` | +0.405 ns | +0.405 ns |
| All TNS | 0 | n/a |
| ROM words | 931 / 1024 (91%) | **93 words** |

**LE is the binding constraint.** M9K, DSP9, registers, and timing are not. ROM is comfortable for a small firmware-side addition (e.g. one extra register-write helper).

**Per-voice amplification factor**: any change inside `phase1_reduced_voice.v` is instantiated 4 times. A 50-LE-per-voice change costs 200 LE total. The recommended slice must therefore design for an explicit per-voice budget.

## 2. Phase 4 Feature Candidates

### Candidate A: Velocity-layered hammer excitation (recommended)

**What**: The current hammer excitation ROM in `phase1_reduced_voice.v` (`excitation_rom` function) is a single 16-entry table indexed by `excite_index` 0..15. The amplitude scales by `velocity_q15` but the **timbre** of the strike does not change with velocity. Real pianos have velocity-dependent spectral content: harder strikes are brighter (more high-frequency content) because the hammer compresses harder against the string. Add a second 16-entry "bright" curve and select between the two at trigger time based on a velocity threshold.

```
function [15:0] excitation_rom_v;
    input [3:0] index;
    input       layer;          // 0 = soft, 1 = bright
    case ({layer, index})
        // existing 16 entries become layer 0 ("soft")
        // new 16 entries for layer 1 ("bright"): higher initial peak,
        //   sharper attack, slightly more energy in the early indices
    endcase
endfunction

reg velocity_layer_q;
// at trigger time (in the existing reset/trigger block):
velocity_layer_q <= (velocity_q15 >= 16'h6000); // ~75% as a safe default
```

The layer is **latched at trigger** and stays constant for the 16-tick excitation window, so the timing-critical state machine is unchanged.

**LE estimate**:
- Second 16-entry constant ROM, selected by 1 mux bit: ~16-25 LUT4s = ~25-40 LE per voice. Quartus typically shares constant decoders well.
- 1 register (`velocity_layer_q`) and 1 comparator at trigger: ~3-5 LE per voice.
- Total per voice: 30-50 LE. **Total all voices: 120-200 LE.**

**DSP9 / M9K**: 0 / 0. The hammer ROM is already pure combinational LUT4; adding a second curve does not change that.

**ROM (firmware)**: 0 words added if velocity-layer threshold is fixed in RTL. ~5 words if a register is added to make the threshold tunable; not recommended for the first slice.

**Setup-slack risk**: Low. The change adds one register (`velocity_layer_q`) and a 16-bit comparator on the existing trigger path, and a 1-input mux on the existing `excitation_rom` lookup. None is on the critical path (the critical path is in `phase0_rv32i_core`).

**Behavior risk in production**: Low. Existing default behavior is preserved by mapping the current 16-entry ROM to layer 0 unchanged. Any legacy capture taken with a "soft" velocity (`velocity_q15 < 0x6000`, i.e. < 75%) will reproduce bit-exact.

**Behavior risk for golden-sample TBs**: **Medium**. The existing reduced-voice golden-sample TB likely uses a high velocity, which would now select layer 1 and produce different sample data. The TB will need a deliberate update or a per-test layer override. This is the main verification cost. Two options:

1. Set the threshold to a value that makes existing test velocities select layer 0 (preserves TB bit-exact). This is the safest first slice; the audible improvement is then unlocked only at the high end of the velocity range.
2. Regenerate the golden file. More work, but unlocks the layer at velocities near the existing TB defaults.

Recommend Option 1 for the first slice: pick the threshold above the TB default, ship the layer dormant, validate bit-exact against the existing TB, then in a later slice lower the threshold to expose the layer.

**Touched files** (recommended scope):
- `rtl/audio/phase1_reduced_voice.v` only.

**Why this is the right Candidate A**: it is a piano-realistic spectral feature, fits comfortably inside the LE margin, has no DSP/M9K cost, has zero firmware impact, has a credible bit-exact behavior preservation story, and does not touch the timing-critical body filter or the per-voice synthesis FSM topology.

### Candidate B: Body-filter coefficient bank (fallback)

**What**: `rtl/audio/phase0_body_filter.v` currently hard-codes 2-stage biquad coefficients (low-shelf + peaking, ~200 Hz). Add a 2-bit register `body_voicing[1:0]` selecting one of 2-4 alternate coefficient sets ("small", "medium", "large" body coloration). The biquad structure stays the same; only the localparam constants become indexed.

**LE estimate**:
- 2-4 alternate coefficient sets x 5 16-bit coefficients per biquad x 2 biquads = 80 16-bit constants in mux structure. As pure constant lookup, this synthesizes well: 80-150 LE depending on layer count.
- 1 register `body_voicing[1:0]` and the register write path in `phase0_control_regs.v`: ~10-15 LE.
- Total: 100-200 LE.

**DSP9 / M9K**: 0 / 0.

**ROM (firmware)**: ~5-10 words for a setter helper.

**Setup-slack risk**: **Medium**. The body filter sits on the audio output path and the multi-cycle relaxation is calibrated to the current coefficient values. Switching to runtime-mux coefficients adds combinational depth between the constant inputs and the multipliers; if the synthesizer cannot retime through the mux, slack erodes. This is the opposite of safe.

**Behavior risk for golden-sample TB**: High if the default voicing changes. Low if `body_voicing == 2'b00` is the existing coefficient set bit-exact.

**Touched files**:
- `rtl/audio/phase0_body_filter.v`
- `rtl/control/phase0_control_regs.v` (one new register address, low-risk write-only port)
- `fw/phase0/phase0_main.c` (one default-write line)

**Verdict**: Real but the timing risk and cross-file scope are larger than Candidate A's. Holding as fallback if Candidate A produces a NO-GO from fitter variance.

### Candidate C: Damper release shaping (fallback)

**What**: The current voice exits via the `quiet_count` mechanism: when `|output| < 16` for 65,536 sample ticks (~1.4 s at 48 kHz), `active <= 1'b0`. The transition from "still ringing softly" to "off" is abrupt at the FSM level; the body filter's IIR tail still attenuates softly, but per-voice energy contribution drops to zero in one tick.

Add a "damper release" mode that, instead of zeroing on `quiet_count` expiry, ramps `output_sample_q18` down with a small per-tick attenuation (e.g. multiply by 0.99 in Q15) for ~16 ticks before the abrupt off. This emulates a soft damper engagement.

**LE estimate**: 30-80 LE per voice = 120-320 LE. Wide range because the multiplier reuse versus a new dedicated multiplier choice is non-obvious. The state machine adds a new state.

**DSP9 / M9K**: Possibly 0 (multiplier reused) or +1 (new dedicated). 0 / 0 if the existing `mult_sample`/`mult_coeff` regs can be reused for the release-ramp tick.

**ROM (firmware)**: 0.

**Setup-slack risk**: Low to medium. Adds a state to the existing per-voice FSM, which is not on the critical path.

**Behavior risk for golden-sample TB**: Medium. The TB likely runs the voice through trigger and excite_busy and stops capturing well before the quiet_count expiry (which is ~1.4 s, far longer than typical TB windows). If the TB ends before damper release fires, behavior is bit-exact preserved. Recommend confirming this via TB inspection before scoping the slice.

**Touched files**:
- `rtl/audio/phase1_reduced_voice.v`

**Verdict**: Audibly subtle but real. The LE estimate variance is the main concern (320 LE upper bound exceeds the 250 LE recommended slice target). Holding as fallback.

### Candidate D considered and rejected: cross-voice sympathetic resonance

Cross-voice mixing into each voice's body_history would require per-voice 4-input mixers with attenuation regs, and the cross-feed adds a feedback loop across the per-voice modules that is hard to time-close. Estimated LE: 200-500. Audible win is subtle. **Reject** at this stage; reconsider only after voice TDM authorization.

### Candidate E considered and rejected: pre-strike noise burst

Adding an LFSR-based pre-strike noise window is appealing for "thunk" attack realism, but pseudo-random state across 4 voices either needs 4 independent LFSRs (extra registers and state) or a shared LFSR (cross-voice timing dependency). Estimated LE: 50-150 per voice = 200-600 total. **Reject** at this stage; reconsider only after voice TDM authorization.

### Candidate F considered and rejected: SDRAM integration

Per `reports/phase4_m0_preflight.md` section 3, the M0 conclusion was that no Phase 4 audio candidate has been identified that needs >32 KiB off-chip storage, and that the cost of an SDRAM controller (~700-1100 LE plus 1 PLL) consumes the on-chip headroom that would otherwise host the audio feature. Nothing in M2/M3/M4/M5 changed that conclusion. The current 328 LE margin is genuinely insufficient for an SDRAM controller introduction. **Hold** as M0 directed.

### Candidate G considered and rejected: sample playback

Explicitly blocked by `docs/project_brief.md` Phase 4 scope ("no sample playback" is on the project's blocked-features list). **Reject.**

## 3. Comparison Table

| Candidate | LE estimate | DSP / M9K | ROM | Timing risk | TB risk | Audible payoff | Files | Verdict |
| --- | ---: | ---: | ---: | --- | --- | --- | --- | --- |
| A. Velocity-layered hammer | **120-200** | 0 / 0 | 0 | Low | Low (with threshold above TB default) | Medium-high (velocity-dependent timbre) | 1 RTL | **GO (recommended)** |
| B. Body-filter coefficient bank | 100-200 | 0 / 0 | ~5 | Medium | Low | Medium (selectable body voicing) | 2 RTL + 1 fw | Hold as fallback |
| C. Damper release shaping | 120-320 | 0 / 0 | 0 | Low-medium | Low | Low-medium (subtle release) | 1 RTL | Hold (LE range too wide) |
| D. Sympathetic resonance | 200-500 | 0 / 0 | 0 | High (cross-voice fb) | Medium | Medium (subtle resonance) | 1+ RTL | Rejected |
| E. Pre-strike noise burst | 200-600 | 0 / 0 | 0 | Medium | Medium | Medium (attack thunk) | 1 RTL | Rejected |
| F. SDRAM | -700 to -1100 (regression now) | 0 / +1 M9K | 0 | Medium | High (multi-clock) | n/a (no consumer) | many | Rejected (M0) |
| G. Sample playback | n/a | n/a | n/a | n/a | n/a | n/a | many | Blocked by project brief |

## 4. Recommended Next Implementation Task

**Phase 4 M7 velocity-layered hammer excitation slice**

- Role: implementer
- Output: code commits + `reports/phase4_m7_velocity_layered_hammer_impl.md`

### In scope (allowlist)

- `rtl/audio/phase1_reduced_voice.v`:
  - Extend the `excitation_rom` function (or add a sibling `excitation_rom_v`) to take a `layer` bit selecting between two 16-entry hammer curves.
    - Layer 0: bit-exact preservation of the current 16-entry table (today's curve).
    - Layer 1: a "bright" curve with a sharper attack and slightly higher early peak. Suggested values are an implementer judgement bounded by the constraint that no entry exceeds 16'd32767 (current peak is 16'd32627; layer 1 may go up to 16'd32767, after which the existing `velocity_q15` multiplier and the >>>1 in `STATE_EXCITE_FINISH` saturate cleanly into Q18).
  - Add a single 1-bit register `velocity_layer_q` per voice instance.
  - At trigger time (in the existing `reset_strobe || (trigger_strobe && enable)` block), set `velocity_layer_q <= (velocity_q15 >= 16'h6000)`. This threshold (75% of full scale) is chosen to be **above the existing reduced-voice golden-sample TB's default velocity** so the TB selects layer 0 and the bit-exact behavior preservation argument holds.
  - At `STATE_GAIN_FINISH` excitation step, replace the call `excitation_rom(excite_index)` with `excitation_rom(excite_index, velocity_layer_q)`.

### Out of scope (denylist)

- Any change to `rtl/control/phase0_control_regs.v`. The velocity threshold stays as a localparam in `phase1_reduced_voice.v` for this slice; making it tunable is a follow-up task.
- Any change to `rtl/audio/phase0_audio_path.v` (the per-voice instantiation already passes `velocity_q15`; no port changes).
- Any change to `rtl/audio/phase0_body_filter.v`, `rtl/audio/phase0_sample_gen.v`, the four physical voice instance count, the UART/register map, telemetry tags, command grammar.
- Any firmware change. The default velocity behavior is preserved.
- Any SDC/QSF/PLL/pin/host-tool/generated-output change.
- Any reopening of M2/M3/M5 source-level reclamation.

### Hard NO-GO gates (any single failure stops promotion and triggers RTL revert)

1. LE total exceeds **+250 LE** (target ~150 LE; ceiling **+250 LE** for fitter-variance reserve).
2. LE total positive at any value but the LE total exceeds the +250 LE ceiling.
3. Setup slack slow-85C `sys_clk_50m` < +2.5 ns (current +2.914 ns; budget 0.4 ns of erosion).
4. Hold slack < +0.3 ns at any corner.
5. Any TNS != 0 at any corner.
6. M9K block count != 16 (any non-zero delta).
7. DSP9 count != 28 (any non-zero delta).
8. PLL count != 1.
9. ROM word count != 931.
10. Quartus errors != 0.
11. Quartus warnings > 16 + 2 cosmetic for the new function arm. New non-cosmetic warnings (e.g., latch inference, missing case, undriven net) are NO-GO regardless of count.
12. ModelSim reduced-voice golden-sample TB diff at the existing TB velocity (must be bit-exact; the TB threshold is chosen specifically so layer 0 is selected).
13. Any source change outside `rtl/audio/phase1_reduced_voice.v`.

### Stop and report instead of continuing if

- The fitter places more than +250 LE (NO-GO and revert per gate 1).
- Any NO-GO gate trips.
- The TB at the existing velocity does not match bit-exact (indicates the threshold is wrong; revert and produce a NO-GO report rather than tuning the threshold inline).
- New audible artifacts appear in golden-sample diff or in hardware (verifier finding).

### Required validation before handoff

- `fw/phase0/build.ps1` PASS, ROM 931 (firmware untouched, but rebuild as evidence).
- ModelSim reduced-voice golden-sample TB PASS bit-exact (with threshold above TB default; layer 0 selected).
- ModelSim full-system happy + NACK TBs PASS (UART command grammar unchanged).
- Quartus full compile, errors = 0, warnings <= baseline + 2 cosmetic.
- Resource report: LE delta, comb, regs, M9K, DSP9, PLL.
- Timing report: setup slack `sys_clk_50m`, hold slack, all clocks all corners, TNS.
- ASCII-only on touched files.
- 4 voice instances preserved.
- UART tag order unchanged: `I/S/R/V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E/G/H/J/L/N/P/Q/X/CC/V3/VT/VA/VV/S3/ST`.
- Static design proof: explain why `velocity_layer_q` is a stable per-voice register that does not introduce a metastability or CDC concern (it is sys_clk-domain only and updated only in the existing trigger block).

### Hardware acceptance (verifier)

- No-command profile: G stable, K=0, X=0, Q=0, ST=0, CC stable.
- 6-command profile: G=14, Q=6, K=0, X=0.
- Voice 3 telemetry V3/VT/VA/VV/S3 increments coherently.
- Audio capture: continuous baseline at low-velocity layer 0 should be **bit-exact** to accepted M5 baseline (because layer 0 is the existing curve). Audio capture at high-velocity (selecting layer 1) should be audibly brighter on attack but not clip. K=0 is the hard gate.

### Expected artifact

- Implementation commit if all gates pass; otherwise report-only NO-GO commit
- `reports/phase4_m7_velocity_layered_hammer_impl.md`

### Why this slice is the right next step

- Audible payoff is **piano-realistic** (real pianos have velocity-dependent spectral content), which advances the Phase 4 fidelity goal directly. The current synthesis already correctly scales amplitude with velocity but has no spectral velocity dependence; this slice adds the missing dimension.
- It is the only candidate that **avoids touching the timing-critical body filter**, the **register map**, **firmware behavior**, and any cross-file scope.
- The threshold-above-TB-default discipline gives a clean bit-exact-preservation story for the golden-sample TB, which is the single biggest verifier-cost variable in any audio change.
- Per-voice cost has a credible **30-50 LE upper bound**, which times 4 voices is well inside the 250 LE ceiling with a 78+ LE reserve for fitter variance. This is the discipline the M2/M3/M5 lessons say to apply.

## 5. What Evidence Would Be Missing to Choose Differently

- **Choosing Candidate B instead**: would require a setup-slack erosion budget the project does not currently have. The body filter's multi-cycle relaxation was carefully tuned in Phase 1C/2. Switching to runtime-mux coefficients without re-running SDC is risky. Missing evidence: a TimeQuest analysis showing the mux insertion does not push the body filter onto the critical path. That analysis is itself a separate scoping task.
- **Choosing Candidate C instead**: would require a tighter LE upper bound. Damper release shaping has a 320 LE upper bound that exceeds the slice target. Missing evidence: a paper-level confirmation that the existing `mult_sample`/`mult_coeff` regs can be reused for the release-tick multiply without creating a structural hazard, which would tighten the estimate to <200 LE.
- **Choosing not to implement anything**: would require evidence that no audible Phase 4 fidelity improvement fits in 328 LE. The existence of Candidate A refutes that.
- **Reopening sample_gen elision under a +25 LE gate**: not in this report's scope; the M5 verifier already accepted the +50 LE gate as the right threshold.
- **Authorizing voice TDM**: still gated by the architecture guard. Out of scope here.

## 6. What This Report Does NOT Do

- No RTL, firmware, host tool, SDC, QSF, project-file, constraint, PLL, or generated-output change.
- Does not modify the recommended values for layer-1 hammer ROM entries; those are an implementer decision in M7 within the bounds (no entry exceeds 16'd32767).
- Does not change any UART tag, register address, command grammar, or telemetry semantics.
- Does not touch `.kiro/`, the four untracked verifier UART files, or any other guarded paths.
- ASCII-only by construction.

## 7. Summary

| Item | Status |
| --- | --- |
| Synthesized M0/M4/M5 reports | yes |
| Re-checked live audio sources (`phase1_reduced_voice.v`, `phase0_body_filter.v`, `phase0_audio_path.v`, `phase0_control_regs.v`, `phase0_main.c`) | yes |
| Compared at least three candidates inside the 328 LE margin | yes (A, B, C; plus rejected D, E, F, G) |
| Estimated LE / DSP / M9K / ROM / timing risk for each | yes |
| Recommended exactly one next implementation slice | yes (M7 velocity-layered hammer in `phase1_reduced_voice.v`) |
| Slice targets <=250 LE added with reserve | yes (target ~150 LE, ceiling +250 LE) |
| ASCII-only | yes |
| Out-of-scope guards respected | yes |

This report is documentation only. No RTL, firmware, SDC, constraint, PLL, generated image, or host tool was modified.
