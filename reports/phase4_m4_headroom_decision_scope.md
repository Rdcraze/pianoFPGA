# Phase 4 M4 Headroom Decision Scope

Date: 2026-05-23
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-91be7a1f`
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `07d9a49`

Sources:
- `reports/phase4_m0_preflight.md` (SDRAM preflight, reclamation-first decision)
- `reports/phase4_m1_reclamation_scope.md` (LE attribution + candidate inventory)
- `reports/phase4_m2_reclamation_impl.md` (Candidate A NO-GO at +146 LE, Candidate C accepted)
- `reports/phase4_m2_reclamation_validation.md` (verifier accept of M2 baseline)
- `reports/phase4_m3_readback_mux_impl.md` (NO-GO at 0 LE delta)
- `reports/phase4_m3_readback_mux_validation.md` (verifier accept of M3 NO-GO)
- `reports/phase1c_sample_gen_test_impl_report.md` (sample_gen diagnostic origin)
- `reports/phase1c_sample_gen_test_validation.md` (codec verified, bottleneck identified)
- `reports/orchestrator_pickup_note.md` (project state at clean baseline)
- `docs/project_brief.md` (Phase 4 scope, blocked features)
- `rtl/audio/phase0_audio_path.v` (live source)
- `rtl/audio/phase0_sample_gen.v` (live source, ~150 LE per M1)
- `rtl/control/phase0_control_regs.v` (live source, baseline)
- `fw/phase0/phase0_main.c` (live source)
- `quartus/phase0/output_files/piano_phase0_top.fit.summary` (LE 9,992 / 10,320)
- `quartus/phase0/output_files/piano_phase0_top.sta.summary` (setup +2.914 ns)

## TL;DR

**Recommendation: queue a Phase 4 M5 task to implement a build-time gating of `phase0_sample_gen` (Candidate B2 from M1 scope), targeting ~150 LE recovery. Hold all other paths.**

Source-level compaction in `phase0_control_regs.v` is now closed by M2 + M3 evidence in the Quartus 13.0.1 toolchain. The audio-path mix-tree experiment (B1) is bounded at 30-60 LE on paper but carries the same "Quartus has already packed it" risk that produced the M3 zero-delta result on a comparable target. Voice time-multiplexing and SDRAM remain blocked by the architecture guard and the headroom-first decision in M0; neither has a justifying consumer at the current Phase 4 fidelity tier.

`phase0_sample_gen` is the highest-payoff legal candidate that remains. It is currently unreachable in production (the `use_sample_gen` mux is gated on all four voices being disabled, which the accepted firmware never causes), and its original codec-isolation diagnostic value has already been redeemed and is documented in the validation report. Gating it behind a build-time parameter preserves the ability to re-enable the diagnostic later by parameter flip and rebuild, without keeping ~150 LE of unreachable logic on the device today.

| Gate | Recommendation |
| --- | --- |
| Take implementation action this task | NO (planning only) |
| Continue compaction inside `phase0_control_regs.v` | NO (closed by M2/M3) |
| Authorize sample_gen build-time gating (B2) | YES, as the next Phase 4 M5 implementer task |
| Authorize audio-path mix-tree experiment (B1) | NO unless B2 is rejected; same toolchain-pack risk |
| Authorize voice time-multiplexing | NO (architecture guard: 4 physical voices) |
| Authorize SDRAM integration now | NO (no consumer; M0 conclusion still holds) |
| Accept the 328-LE margin and stop | Conditional fallback if B2 is rejected by orchestrator |

## 1. State Synthesis

### Accepted baseline (post-M3 = post-M2 = post-M3b)

| Metric | Value | Source |
| --- | ---: | --- |
| Total logic elements | 9,992 / 10,320 (97%) | `piano_phase0_top.fit.summary` |
| Combinational functions | 9,417 / 10,320 (91%) | same |
| Dedicated logic registers | 4,233 / 10,320 (41%) | same |
| Memory bits | 86,016 / 423,936 (20%) | same |
| M9K blocks | 16 | same |
| Embedded multiplier 9-bit | 28 / 46 (61%) | same |
| PLLs | 1 / 2 | same |
| Slow-85C setup `sys_clk_50m` | +2.914 ns, TNS 0 | `piano_phase0_top.sta.summary` |
| Slow-85C hold `sys_clk_50m` | +0.405 ns, TNS 0 | same |
| ROM words | 931 / 1024 (91%) | `phase4_m2_reclamation_validation.md` |
| Free LE margin | 328 | derived |
| Free ROM margin | 93 words | derived |

### What M2 + M3 closed

- M2 Candidate A (control_regs array/strobe consolidation): NO-GO, +146 LE regression, reverted. Quartus 13.0.1 already packs the named scalar register/decode pattern in this module tightly; the array refactor materialized a per-bit indexed mux that grew combinational LCs.
- M3 readback-mux narrow compaction: NO-GO, 0 LE delta. The redundant `REG_VOICE_DIAG_CONTROL` arm collapsing into the `default` arm was already merged by Quartus in the baseline; source-level removal yielded zero synthesized-logic delta.
- Joint conclusion: source-level "this looks redundant" rewrites in `phase0_control_regs.v` are exhausted in this toolchain. The 975 direct LE in that module are already minimized by Quartus and are not behavior-preservingly recoverable through Verilog-style refactors.

### What M2 accepted (zero-cost)

- Candidate C: `rtl/control/phase0_soc_stub.v` deletion. 389 lines removed, 0 LE delta because the file was never in the QSF or any synthesis input. Pure repo hygiene.

### Architectural facts that gate the remaining options

- Four physical voice instances in `rtl/audio/phase0_audio_path.v`: `phase1_reduced_voice_inst`, `phase1_reduced_voice1_inst`, `phase1_reduced_voice2_inst`, `phase1_reduced_voice3_inst`. The architecture guard in the orchestrator pickup notes prohibits reducing voice count.
- `phase0_sample_gen` is instantiated unconditionally and routed through a `use_sample_gen` mux at lines 285-289 of `rtl/audio/phase0_audio_path.v`:

  ```verilog
  assign use_sample_gen = audio_enable && tone_enable &&
                          !voice_enable && !voice1_enable && !voice2_enable && !voice3_enable;
  assign tx_valid  = use_sample_gen ? sample_gen_valid : sample_valid_any;
  assign tx_sample = use_sample_gen ? sample_gen_data  : body_filter_out;
  ```

- Production firmware (`fw/phase0/phase0_main.c`, `phase0_program_defaults` at line 224, plus `phase0_write_voice_control` etc.) always uses `VOICE_CONTROL_BASELINE = ENABLE_M`, so production never disables all four voices simultaneously. The `use_sample_gen` mux therefore never selects sample_gen in production audio.
- Codec hardware is verified end-to-end per `reports/phase1c_sample_gen_test_validation.md`: peak -5.58 dBFS, RMS -7.54 dBFS through the WM8978 + speaker path. The original diagnostic question that motivated `c1c922c` ("is the codec broken or is it the waveguide gain") is answered. The waveguide gain bottleneck was then identified and addressed in subsequent commits (`647edee`, `c25d1a7`, `ad94631`).

## 2. Sample_gen-Specific Analysis

This section addresses the task's required item 4: whether sample_gen is still needed as an accepted hardware diagnostic, what evidence would be lost if removed or gated, and whether an alternative exists.

### Original diagnostic role

`phase0_sample_gen` was added in `c1c922c` to route a known-good square-wave generator directly to the DAC path, bypassing the waveguide voices, in order to isolate whether low audio output was caused by the waveguide digital path or the WM8978 codec / speaker hardware. The diagnostic worked and the codec was confirmed correct (verifier validation at `reports/phase1c_sample_gen_test_validation.md`).

### Current diagnostic reachability

In the current accepted firmware:
- `phase0_program_defaults` issues `phase0_write_voice_control(CLIP_CLEAR_M)` etc. for voices 0/1/2 and `phase0_mmio_write32(VOICE3_CONTROL, CLIP_CLEAR_M)` for voice 3. None of these write `ENABLE_M`, but the helper functions OR in `*_BASELINE = ENABLE_M`, so all four voices come up enabled.
- After codec init, `phase0_run_round_robin_smoke()` triggers voice activity. Voices remain enabled.
- There is no firmware path that disables all four voices simultaneously. The `use_sample_gen` mux gate (`!voice_enable && !voice1_enable && !voice2_enable && !voice3_enable`) is unreachable in production audio.

### Evidence that would be lost if sample_gen is removed entirely (hard delete)

- Ability to quickly re-isolate codec failure from waveguide failure by setting GAIN=32767, disabling all four voices, and triggering through `REG_CONTROL.TRIGGER_M` to drive a square wave into the DAC.
- This evidence has *already been collected* and documented; the diagnostic does not need to be re-run unless the codec hardware path changes (which would be a Phase 6 / hardware-replacement event, not a Phase 4 audio-fidelity event).

### Alternative diagnostics that exist today

- The waveguide voices themselves can be driven with a synthetic loud excitation (high velocity, low decay) and produce a known-amplitude output through the body filter. The accepted gain trace (`reports/phase1c_modelsim_gain_trace.md`) provides the bit-accurate digital amplitude expectation; comparing measured DAC output amplitude against that expectation isolates codec vs digital almost as effectively as the sample_gen path.
- The body filter has a `voice_body_bypass` register bit. With bypass set and all damping/displacement minimized, the voice path is close to a pure delay-line oscillator and serves as a usable fallback square/triangle source.
- Loopback/observability through the `voice_mix_*` telemetry tags (`Z`, `O`, `D`, `K`) gives bit-accurate digital peak/clip evidence without needing sample_gen at all.

### Distinguishing feature removal from behavior-preserving optimization

This is a critical scoping question. The two variants are not equivalent:

| Variant | What it does | Behavior delta in production | Behavior delta in diagnostic mode | Reversibility |
| --- | --- | --- | --- | --- |
| Hard delete | remove `phase0_sample_gen.v`, `phase0_sample_gen_inst`, the `use_sample_gen` mux, and the `wave_sel`/`phase_step`/`gain`/`decay_step` register ports that feed it; replace `tx_valid`/`tx_sample` assignments with the voice path unconditionally | none (mux output is always voice path in prod today) | full loss of square-wave diagnostic; would need to be reimplemented from scratch | hard (reverts a deletion across 2 RTL files + 1 control_regs port set) |
| **Soft build-time gate (recommended)** | introduce `localparam ENABLE_SAMPLE_GEN = 0` in `phase0_audio_path`; under the `0` branch, do not instantiate `phase0_sample_gen_inst` and force `tx_valid = sample_valid_any; tx_sample = body_filter_out;` (no mux); leave `phase0_sample_gen.v` as a source file; leave the `wave_sel`/`phase_step`/`gain`/`decay_step` register ports unchanged so the register map and firmware are bit-exact compatible | none | recoverable by changing `ENABLE_SAMPLE_GEN` to `1` and recompiling | easy (single-line parameter flip + Quartus rebuild) |

The soft build-time gate is **behavior-preserving optimization** in production: every register write, every UART tag, every audio sample value, every command response is bit-exact identical to the current accepted baseline because the `use_sample_gen` branch of the mux is unreachable in production firmware. It is **not** a feature removal in the sense that the code, the ports, and the register addresses for `wave_sel`/`phase_step`/`gain`/`decay_step` continue to exist; only the synthesized instance is gated out. This distinction matters because the project brief's "no sample playback" guardrail (referenced in `docs/project_brief.md` Phase 4 scope) is concerned with introducing sample-based audio, not with whether an unused diagnostic path occupies LEs on the device.

### Verdict on sample_gen scope

- Sample_gen is **not currently a needed runtime diagnostic** because the codec evidence has been collected and the firmware no longer activates its path.
- Its **paper-level diagnostic role is recoverable** by parameter flip and rebuild, plus the alternative diagnostics listed above.
- A **soft build-time gate is the right scope**: it captures the LE recovery (~150 LE) without erasing the diagnostic from the source tree and without changing any production behavior bit.

## 3. Options Comparison

The task requires comparing at least the four named options.

### Option I: Accept the current 328-LE margin and only pursue features that fit

**Estimated LE recovery**: 0.

**What it enables**: Any single Phase 4 audio coloration that fits in <=300 LE (after a small reserve). From M0 section 3, this includes:
- A small 256-tap mono FIR body coloration (~16 KiB on-chip, fits memory-wise; cost is LE/DSP, harder to estimate but likely <200 LE if reusing existing DSP9 macros).
- A modest hammer-table expansion (~200-400 LE).
- A small per-voice modal addition (1-2 resonators only; ~150-300 LE).

**What it forecloses**: Anything richer than the smallest tier. Modal banks of 8+ resonators, 1024-tap FIR bodies, and FDN-style soundboards all need several hundred LE that are not currently available.

**Risk**: Low for the smallest tier. High once any candidate exceeds ~250 LE, because there is no margin for the unexpected (e.g., body-filter pipelining or pin/timing fixes).

**Verdict**: **Acceptable as fallback.** This is what we live with if no further reclamation is approved. It does not enable the Phase 4 fidelity targets that motivated reclamation in the first place.

### Option II: Authorize sample_gen build-time gating (B2 from M1 scope)

**Estimated LE recovery**: ~150 LE (M1 inventory: `phase0_sample_gen` direct LE = 150).

**What it enables**: A 478-LE post-gate margin. Combined with the existing 328 LE and accepting the M0 conservative baseline, this is enough headroom for one mid-sized Phase 4 feature (modal bank with 4-6 resonators, or a 512-tap FIR body coloration, or a small FDN body).

**Risk**: Low. Production behavior is preserved bit-exact (proven above by reachability analysis of the `use_sample_gen` mux). Diagnostic is recoverable by parameter flip. Verification is the same standard playbook (golden-sample TBs + Quartus full compile + hardware UART smoke + audio checklist).

**One concrete caveat**: The 150-LE estimate is from M1 scope inspection. The M2 NO-GO and M3 zero-delta results show the M1 estimates can be wrong in this toolchain. The gate must include a stop condition: if Quartus reports <50 LE recovery after gating, the change is reverted as NO-GO and we move to Option III or accept Option I.

**Verdict**: **Recommended.** Highest-payoff legal candidate. Smallest scope. Behavior-preserving in production. Diagnostically reversible. Has explicit M1-scope precedent identifying it as the next-highest target.

### Option III: Bounded `phase0_audio_path` mix-tree / glue experiment (B1 from M1 scope)

**Estimated LE recovery**: 30-60 LE on paper.

**Specific tries available**:
1. Re-express the 4-input signed sum tree (lines 240-249 of `phase0_audio_path.v`) by expanding the manual sign-extension into a single `wire signed [18:0] mix_sum = $signed({{3{voice0_sample_data[15]}}, voice0_sample_data}) + ...` form, letting Quartus pick the adder topology. This is the M1 Candidate B1 description.
2. Collapse the registered `mix_sample_sat_reg` -> body filter input pipeline into a combinational pass-through if the body filter input is not on the timing-critical path. (Risk: this register was added during Phase 1C body-pipe work and may be load-bearing for setup slack.)
3. Reduce the redundant `excite_busy_any || active_any || sample_valid_any` OR-trees by computing one and reusing it (very small; <10 LE).

**Risk**: Medium. The M2 +146 LE NO-GO and M3 0 LE delta both showed Quartus 13.0.1 already minimizes this kind of obvious redundancy. The audio path mix tree is structurally similar to the M3 readback-mux case in that the source already has a single combinational `+` chain with explicit sign extension. The expected outcome is 0 to small positive delta. Try (2) on the `mix_sample_sat_reg` directly conflicts with the body-pipe optimization; touching it puts setup slack at risk and is essentially what the Phase 1C body-pipe optimization explicitly added.

**Verdict**: **Not recommended as next step.** The expected payoff (30-60 LE) is below the 50-LE NO-GO threshold proposed for B2. If Option II is rejected by the orchestrator, this is the only remaining legal source-level experiment, but its expected value is low and its variance is high. Run it only as a fallback, with a hard stop at Quartus zero-delta or worse.

### Option IV: Broader architectural moves (voice time-multiplexing, SDRAM)

**Voice time-multiplexing**: Reduce 4 physical voice instances to 1 or 2 via TDM. Estimated LE recovery: 1,500-2,500 (since 3 voices = 2,629 direct LE per the M1 inventory). **BLOCKED by the architecture guard ("never reduce voice count"). Not legal in this branch.** Even if the guard were lifted, it would be a Phase 4 architectural rewrite, not a reclamation slice; it would require a fresh M0-style preflight, fresh SDC analysis (because per-voice timing changes shape), fresh golden-sample TBs (because per-sample arithmetic order changes), and orchestrator authorization at a level above the current Phase 4 milestone scope.

**SDRAM integration**: Per `reports/phase4_m0_preflight.md` section 3, no Phase 4 audio candidate has been identified that *needs* >32 KiB off-chip storage. The on-chip M9K usage is at 20% (16 / 46), and every Phase 4 fidelity candidate that has a clear audible payoff (1024-tap mono body FIR, modal banks, FDN with reasonable delay sizes, velocity-layered hammer at realistic scale) fits in on-chip M9K. Spending +700 to +1,100 LE on a controller for a resource that is not currently a constraint is structurally a net negative under the current LE budget. **Hold per the M0 conclusion.** SDRAM becomes the right next move only if (a) headroom is recovered and (b) a specific consumer is identified that genuinely needs >32 KiB of off-chip memory. Neither is true at HEAD.

**Verdict**: **Both blocked at the current state.** Voice TDM is blocked by the architecture guard. SDRAM is blocked by the absence of a consumer.

## 4. Risk Tabulation

| Option | LE delta (expected) | Behavior delta in production | Diagnostic recoverable? | Architecture guard | Orchestrator authorization needed |
| --- | ---: | --- | --- | --- | --- |
| I. Accept | 0 | none | n/a | yes | no |
| II. sample_gen gate | -150 (target) | none | yes (parameter flip) | yes | yes (sample_gen elision was held) |
| III. mix-tree | -30 to -60 (or 0) | none | n/a (no diagnostic involved) | yes | no |
| IV-a. voice TDM | -1500 to -2500 | major (per-sample arithmetic order changes) | yes (commit revert) | **NO** | yes + guard suspension |
| IV-b. SDRAM | +700 to +1100 (regression now) | added latency on any path that reads SDRAM | n/a | yes | yes + Phase 4 milestone re-plan |

## 5. Recommended Next Task (one only)

**Phase 4 M5 sample_gen build-time gating (implementation slice)**

- Role: implementer
- Output: code commits + `reports/phase4_m5_sample_gen_gate_impl.md`
- In scope:
  - `rtl/audio/phase0_audio_path.v`:
    - add `localparam ENABLE_SAMPLE_GEN = 1'b0;`
    - wrap the `phase0_sample_gen_inst` instance and the `use_sample_gen` mux assigns in a `generate ... if (ENABLE_SAMPLE_GEN) ... else ... endgenerate` block. Under `0`, do not instantiate the module; assign `tx_valid = sample_valid_any;` and `tx_sample = body_filter_out;` directly. Tie unused `sample_gen_data`/`sample_gen_valid`/`sample_gen_active` wires (they only exist in the `1` branch).
    - leave the module-input ports `wave_sel`, `phase_step`, `gain`, `decay_step` on `phase0_audio_path` unchanged so the parent `piano_phase0_top` wiring and `phase0_control_regs` ports are not touched.
  - leave `rtl/audio/phase0_sample_gen.v` source file in place (no deletion).
- Out of scope:
  - `rtl/control/phase0_control_regs.v` (no register-map change; `wave_sel`/`phase_step`/`gain`/`decay_step` continue to be readable/writable; firmware compatibility preserved).
  - `fw/phase0/*` (no firmware change required; the control register reads/writes still function; the register map is unchanged).
  - SDC, QSF, pins, PLL, generated outputs, host tools, untracked verifier files.
  - Any change to voice instances, body filter, mix-tree expression, control-regs storage/decode/readback.

- Touched files (allowlist):
  - `rtl/audio/phase0_audio_path.v` (only)
  - `reports/phase4_m5_sample_gen_gate_impl.md` (new)

- Verification plan:
  - `fw/phase0/build.ps1` PASS, ROM unchanged at 931 (firmware is untouched, but rebuild as evidence).
  - ModelSim reduced-voice golden-sample TB: PASS bit-exact.
  - ModelSim full-system happy + NACK TBs: PASS.
  - Quartus full compile: errors = 0, warnings <= 16.
  - LE delta: target -100 LE or better (M1 scope estimate is -150).
  - Setup slack slow-85C `sys_clk_50m`: >= +2.5 ns.
  - Hold slack: >= +0.4 ns.
  - All TNS = 0.
  - M9K: 16 (unchanged) or lower.
  - DSP9: 28 (unchanged).
  - PLL: 1 (unchanged).
  - Hardware UART smoke (verifier): no-command profile `G=8 K=0 X=0 Q=0 ST=0 CC` stable; 6-command profile `G=14 Q=6 K=0 X=0`; voice3 telemetry V3/VT/VA/VV/S3 increments coherently; ST coherent under burst.
  - Hardware audio smoke (verifier): continuous baseline, no clipping, no audible regression vs accepted M3 baseline.

- Hard NO-GO gates (any single failure stops promotion and triggers RTL revert):
  - LE delta worse than -50 (the toolchain did not reward the change; behavior of `phase0_control_regs.v` M2/M3 NO-GO precedent applies).
  - LE positive (regression).
  - Setup slack < +2.0 ns slow-85C.
  - Any TNS != 0.
  - Any UART tag value, order, or grammar change.
  - Any register-map change.
  - K > 0 in any valid-command capture.
  - Golden-sample TB diff.
  - M9K or DSP9 changes by more than 0.

- Stop and report instead of continuing if:
  - LE delta cannot reach -50 after the gate is in place.
  - Any RTL or firmware change beyond `rtl/audio/phase0_audio_path.v` becomes necessary.
  - Body filter or voice timing erodes setup slack below +2.5 ns.

- Expected artifact: `reports/phase4_m5_sample_gen_gate_impl.md` (single committed report) plus the RTL change commit on `codex/phase1c-uart-boundary-fix`.

### Why this is the safest next move

- Behavior preservation is provable by reachability: `use_sample_gen` is unreachable in production firmware, so removing the instance under that gate is bit-exact equivalent to the live behavior.
- The diagnostic is preserved as source-level documentation and as a parameter flip.
- The hard NO-GO gate (-50 LE minimum) protects against the M2/M3 toolchain-pack pattern: if Quartus does not actually reward the gate, we revert the RTL and ship a NO-GO report, exactly as we did in M3.
- Out-of-scope guards keep the slice small enough to verify quickly with the existing playbook.

### What evidence would be missing to authorize a different option

- Option I (accept): no missing evidence. This is just the do-nothing fallback.
- Option III (mix-tree): would require an accepted argument that the M2/M3 NO-GO pattern does not apply to the audio-path mix tree. Without that argument, the expected value is low. The cleanest way to gather that evidence would be a paper experiment: search Quartus's existing fitter logs (`piano_phase0_top.fit.rpt` hierarchy attribution and `piano_phase0_top.map.rpt` if accessible) for the actual LCs allocated to the mix-tree adder, and only proceed if those LCs exist as separable from the body filter and the saturation logic.
- Option IV-a (voice TDM): would require explicit orchestrator suspension of the architecture guard, plus a fresh M0-style preflight covering per-voice timing, golden-sample TB regeneration plan, and a Phase 4 milestone re-plan.
- Option IV-b (SDRAM): would require a specific Phase 4 audio feature that demonstrably needs >32 KiB of off-chip memory. Per M0 section 3, every Phase 4 candidate with a clear audible payoff fits in on-chip M9K, so this evidence is not naturally present and would need to be authorized by the orchestrator as a deliberate fidelity-tier upgrade.

## 6. What This Report Does NOT Do

- No RTL, firmware, host tool, SDC, QSF, project-file, constraint, PLL, or generated-output change.
- Does not authorize sample_gen elision by editing code; the recommendation is for the orchestrator to queue the M5 implementer task.
- Does not reduce physical voice count.
- Does not change any UART tag, register address, command grammar, or telemetry semantics.
- Does not touch the `.kiro/` directory or any of the untracked verifier UART files (`reports/phase3_m3b_debug_uart.txt`, `reports/phase3_m3b_single_uart.txt`, `reports/phase3_m5_hardware_uart.txt`, `reports/phase3_m6_hardware_uart.txt`).
- ASCII-only by construction.

## 7. Summary

| Item | Status |
| --- | --- |
| Synthesis of M0 / M1 / M2 / M3 reports complete | yes |
| Live source re-check complete | yes (audio_path, sample_gen, control_regs, phase0_main.c) |
| Decision report at `reports/phase4_m4_headroom_decision_scope.md` | this file |
| Compared all four required options | yes |
| sample_gen diagnostic analysis (still needed? alternatives?) | yes (section 2) |
| Distinguished feature removal from behavior-preserving optimization | yes (section 2 table) |
| One recommended next task with full scope | yes (section 5) |
| ASCII-only | yes |
| Out-of-scope guards respected | yes |

This report is documentation only. No RTL, firmware, SDC, constraint, PLL, generated image, or host tool was modified.
