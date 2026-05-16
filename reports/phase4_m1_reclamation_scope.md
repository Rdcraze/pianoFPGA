# Phase 4 M1 Reclamation Scope

Date: 2026-05-16
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-8a69168b`
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `0043df8`

Sources:
- `reports/phase4_m0_preflight.md`
- `reports/phase3_exit_phase4_readiness.md`
- `quartus/phase0/output_files/piano_phase0_top.fit.rpt` (hierarchy table)
- `quartus/phase0/output_files/piano_phase0_top.fit.summary` (LE 9,992 / 10,320, 97 percent)
- `quartus/phase0/output_files/piano_phase0_top.sta.summary` (slow-85C setup +2.914 ns)
- `rtl/control/phase0_control_regs.v` (472 lines, 975 LE)
- `rtl/audio/phase0_audio_path.v` (467 lines, ~616 LE in glue beyond child instances)
- `rtl/control/phase0_rv32i_core.v` (430 lines, 3,646 LE — out of reclamation scope)
- `rtl/control/phase0_soc_stub.v` (389 lines, **dead file, not in QSF**)
- `quartus/phase0/piano_phase0_top.qsf`
- `reports/phase1c_resource_attribution_acceptance_decision.md`, `reports/phase1c_body_pipe_optimization_acceptance_decision.md` (Phase 1C precedent)
- `reports/phase3_m8_no_go_containment_validation.md` (M8 lesson)

## TL;DR

**Go: a first reclamation slice can plausibly target 200-300 LE recovery; the broader program can plausibly reach 400-600 LE under the right scope.** The dominant non-CPU LE consumers are `phase0_audio_path` glue/mix (~616 LE) and `phase0_control_regs` (975 LE). Both are clean targets for behavior-preserving simplification. The CPU itself (`phase0_rv32i_core`, 3,646 LE) is **not** a reclamation target in this phase: it has already been hardened for timing in M1 and any compaction risks regressing the +2.914 ns slack. ROM is **not** a recommended reclamation target this phase: M8 demonstrated function-extraction does not save ROM in this codebase, and any ROM work risks rolling back accepted M3b/M4/M7a/M8 baselines.

Recommended first slice: **`phase0_control_regs.v` decode/strobe/diag consolidation**, target 200 LE saving, behavior-preserving, golden-sample protected.

## 1. LE Attribution

From `piano_phase0_top.fit.rpt` hierarchy table. Numbers are total LE per entity; the value in parentheses is the LE attributed directly to that entity (excluding children).

| Module | Total LE | Direct LE | Notes |
| --- | ---: | ---: | --- |
| `piano_phase0_top` | 9,992 | 1 | top-level glue is trivial |
| `phase0_audio_path` | **4,712** | 616 | mix/saturation/glue around 3 voices + body filter + sample_gen |
| `phase0_body_filter` | 478 | 376 | 2-stage biquad; 376 LE direct + 18 DSP9 (already DSP-backed) |
| `phase0_sample_gen` | 150 | 150 | test-mode passthrough (square-wave generator) |
| `phase1_reduced_voice` x3 | 2,629 | 2,629 | 872 + 868 + 889 LE per voice; M9K/DSP-backed |
| `phase0_rv32i_soc` | **4,094** | 122 | SoC wrapper: ROM, RAM, CPU, UART MMIO |
| `phase0_rv32i_core` (cpu_inst) | 3,646 | 3,646 | RV32I core, **timing-hardened in M1** |
| `phase0_uart_mmio` | 329 | 195 | UART RX/TX MMIO + parser interface |
| `phase0_boot_rom` | 0 | 0 | M9K-backed (4 M9K) |
| `phase0_data_ram` | 1 | 0 | M9K-backed (4 M9K) |
| `phase0_control_regs` | **975** | 975 | register decode + state + diagnostics |
| `wm8978_codec_stub` | 267 | 64 | WM8978 wrapper |
| `wm8978_boot_seq` | 66 | 66 | I2C init sequencer |
| `wm8978_dac_tx` | 43 | 43 | I2S DAC transmitter |
| `wm8978_i2c_ctrl` | 94 | 94 | I2C bit-banger |
| `phase0_audio_mclk_pll` | 2 | 0 | PLL wrapper |
| `uart_tx` | 45 | 45 | small UART TX |
| `phase0_reset_sync` | 2 | 2 | trivial |

Totals consistent within Quartus packing. The five-row direct-LE breakdown for the candidate-relevant modules:

| Module | Direct LE | % of total |
| --- | ---: | ---: |
| `phase0_rv32i_core` (CPU) | 3,646 | 36% |
| `phase1_reduced_voice` x3 | 2,629 | 26% |
| `phase0_control_regs` | 975 | 10% |
| `phase0_audio_path` glue | 616 | 6% |
| `phase0_body_filter` | 376 | 4% |
| All others | ~1,750 | 18% |

The CPU is the single largest contributor but is out of scope for reclamation in this phase (timing risk). The voice instances are intrinsic to the audio architecture (no mass duplication beyond the 3 instances). That leaves **`phase0_control_regs` and `phase0_audio_path` glue** as the highest-leverage reclamation targets.

## 2. Reclamation Candidates

### Candidate A: `phase0_control_regs` decode/strobe consolidation (high value)

**Current state**: 975 direct LE, 472 source lines. Module exposes 17+ readable status registers, 4-way per-voice control/loop_len/velocity registers, and a shared/legacy register path that mirrors writes to all four voices for backward compatibility (`REG_VOICE_VELOCITY` writes update all `voiceN_velocity`; same for `REG_VOICE_LOOP_LEN`).

**Reclamation patterns**:

1. **Per-voice strobe array packing.** `voice1_*_strobe`, `voice2_*_strobe`, `voice3_*_strobe`, plus the shared `voice_*_strobe`, are each driven by separate case branches that look identical. Refactoring per-voice strobes into an array `voice_trigger_strobe[3:0]` (or vector) and using `voiceN_*` as bit selects collapses the parallel case branches. Quartus often unfolds this back at synthesis, so the actual saving depends on retiming.
2. **Per-voice loop_len/velocity register array.** Same pattern: collapse `voice0_loop_len`/`voice1_loop_len`/.../`voice3_loop_len` into `voice_loop_len_arr[3:0][6:0]`, with the existing shared write writing all four entries via a tight `for` loop. Behavior is bit-exact equivalent.
3. **Status readback mux compaction.** The readback `case` covers ~25 registers, several of which are simple register passthroughs. Where a status register is a `voiceN_*_count` 32-bit pure passthrough, indexing via a small mux replaces a wide concatenated `case` and reduces LUT pressure on the readback bus.
4. **Diag/clip clear strobe consolidation.** The clear-strobe pulse logic is replicated 4x per voice plus shared. A single self-clearing strobe register vector with per-voice mask collapses this.

**Estimated saving**: 150-250 LE realistic. The control_regs module's high LE count for what is essentially a register file suggests Quartus is not packing the duplicated register/strobe paths, which is exactly the pattern that array consolidation tends to help with.

**Files touched**: `rtl/control/phase0_control_regs.v` only.

**Behavior preservation argument**: All accepted reads, writes, defaults, and write-through-to-shared semantics are preserved bit-exact. No new register addresses, no removed addresses, no semantic changes to `REG_VOICE_VELOCITY` / `REG_VOICE_LOOP_LEN` shared writes (still mirror to all four). The change is a Verilog-style refactor from named fields to indexed arrays.

**Regression risk**: Medium. The control register decode is on the path between every UART command and audio behavior. Any drift breaks accepted UART telemetry compatibility (`I/S/R/.../CC/V3/VT/VA/VV/S3/ST`).

**Required verifier evidence**:
- Quartus full compile, LE delta negative, M9K/DSP unchanged, slow-85C setup >= +2.5 ns, hold clean, all TNS = 0
- ModelSim happy/NACK reduced-voice golden-sample TBs PASS (bit-exact match to current golden file)
- ModelSim full-system TB (3-voice trigger + UART command path) PASS
- Hardware UART smoke: program SOF, capture no-command (`G=8 K=0 X=0 Q=0 ST=0 CC stable`) and 6-command (`G=14 Q=6 K=0 X=0`) profiles. K=0 is the hard gate.
- Hardware audio smoke: re-run accepted Phase 1 audio checklist, confirm no regression (continuous ~440 Hz baseline, no clipping)

### Candidate B: `phase0_audio_path` glue and mix path simplification (medium value)

**Current state**: 616 LE direct (excluding child instances). The audio path glues 3 voices, sample_gen, and body filter into a shared mix sum with explicit signed clamp.

**Reclamation patterns**:

1. **Mix sum tree review.** The current 3-voice signed sum and saturation tree is hand-coded. A 4-input signed adder tree (3 voices + sample_gen test path) implemented as `wire signed [N:0] sum = $signed(v0) + $signed(v1) + $signed(v2) + $signed(g);` lets Quartus optimize. If the existing implementation has redundant intermediate registers or extra clamps, a re-expression saves LE.
2. **Sample_gen test-path elision.** `phase0_sample_gen` is a 150 LE test-mode pass-through that exists to support the optional test mode introduced in Phase 1C diagnostics. If the test mode is no longer used at runtime (current default routes through voices), gating its instantiation behind a `localparam ENABLE_TEST_GEN = 0` reclaims the full 150 LE plus 2 DSP9 (since the path is dead unless explicitly selected). **Risk**: confirm with verifier that no accepted hardware capture relies on the sample_gen path. The Phase 1C `c1c922c` diagnostic was kept "as a diagnostic tool" per `reports/orchestrator_pickup_note.md`, so this likely needs orchestrator approval and a fallback path documented.
3. **Body-filter input register pruning.** The body filter has multicycle-relaxed (setup=4) constraints. Some intermediate pipeline registers added during the multicycle fix may be candidates for collapse. **Risk**: this is exactly what closes timing today; touching it is a timing risk. Recommend hold.

**Estimated saving**:
- (1) mix tree: 30-60 LE realistic
- (2) sample_gen elision: 150 LE if approved
- (3) body filter pruning: hold (timing risk too high)

**Files touched**: `rtl/audio/phase0_audio_path.v`, possibly `rtl/audio/phase0_sample_gen.v`.

**Behavior preservation argument**: For mix tree re-expression, the saturation logic is bit-exact identical. For sample_gen elision, the test-mode behavior is removed; this is a feature-removal disguised as reclamation and **requires explicit orchestrator authorization** before the slice can proceed.

**Regression risk**: Low for mix tree re-expression. Medium for sample_gen elision (loses test diagnostic). High for body-filter pruning (timing).

**Required verifier evidence**: Same as Candidate A, plus explicit confirmation that any sample_gen-mode capture procedure used by verifier in the past is not affected.

### Candidate C: Dead-file removal (`phase0_soc_stub.v`)

**Current state**: `rtl/control/phase0_soc_stub.v` (389 lines) is **not** in `quartus/phase0/piano_phase0_top.qsf` and not instantiated anywhere in the synthesis tree. It is a leftover from the M1 RV32I replacement (`task-9d00cc2f`) that superseded the deterministic stub.

**Reclamation pattern**: Delete the file (or move it to `obsolete/` per the precedent in `reports/orchestrator_pickup_note.md`).

**Estimated saving**: 0 LE (file is not synthesized). Pure repo hygiene.

**Files touched**: `rtl/control/phase0_soc_stub.v` deleted; nothing else.

**Behavior preservation argument**: File is dead. No semantic change.

**Regression risk**: None. ModelSim reduced-voice TB does not reference it; QSF does not reference it; top-level does not reference it. A 1-grep verification confirms zero references in code paths that get compiled or simulated.

**Required verifier evidence**: `git grep phase0_soc_stub` returns only the file itself. Quartus full compile unchanged. ModelSim TBs unchanged.

**Why include it anyway**: It removes a misleading leftover, makes the `rtl/control/` directory accurately reflect the synthesized design, and is zero-risk. Bundle with Candidate A as a free cleanup.

### Candidate D: ROM reclamation (NOT recommended this phase)

**Current state**: ROM 931 / 1024 (91%), 93 words free. Phase 3 M8 attempted ROM reclamation via `!D` gate plus function extraction; it ended up adding 17 words instead of saving them, and the entire experiment was rolled back per `reports/phase3_m8_no_go_containment_validation.md`.

**Why not now**: The M8 lesson is specific: GCC for this RV32I target does not aggressively inline back small functions, and the call/prologue/epilogue overhead of extraction exceeds the inline savings for the existing telemetry/parser code. Repeating that experiment without changing the underlying compiler/linker setup is unlikely to yield different results.

**What might unlock this later**: A different target compiler flags audit (e.g., `-Os`, link-time optimization options), a structural firmware refactor to remove duplicated code paths rather than extract them as functions, or a deliberate decision to drop a non-critical telemetry tag. None of these is in scope for an M1 reclamation slice.

**Recommendation**: **Hold ROM reclamation** behind an explicit separate task that first re-evaluates the toolchain options, only after LE reclamation has succeeded and shown headroom is the actual bottleneck.

## 3. Ranking and Go/No-Go

| Rank | Candidate | Est. saving | Risk | Phase 1C precedent | Verdict |
| --- | --- | ---: | --- | --- | --- |
| 1 | A: control_regs decode/strobe consolidation | 150-250 LE | Medium | Yes (1C-A, 1C-B both behavior-preserving) | GO |
| 2 | C: dead-file `phase0_soc_stub.v` removal | 0 LE (hygiene) | None | N/A | GO (bundle with A) |
| 3 | B1: audio_path mix tree re-expression | 30-60 LE | Low | Similar to 1C-B body-pipe | GO if added to A |
| 4 | B2: sample_gen elision | 150 LE | Medium (feature removal) | None | HOLD pending orchestrator authorization |
| 5 | B3: body-filter pruning | unknown | High (timing risk) | None | HOLD |
| 6 | D: ROM reclamation | unknown | High (M8 NO-GO precedent) | M8 negative | HOLD (separate task, different toolchain audit) |

### Can the first slice plausibly target 200 LE?

**Yes.** Candidate A alone targets 150-250 LE; combined with Candidate B1 mix-tree re-expression and Candidate C dead-file cleanup, a single first slice targeting **>=200 LE** is realistic and has a clean precedent in Phase 1C.

### Can the broader reclamation program plausibly reach 400 LE?

**Plausible if Candidate B2 (sample_gen elision) is authorized.** Without B2, the realistic ceiling is 200-300 LE from A + B1 + C. With B2, 350-450 LE is plausible. Going beyond 450 LE would require touching the CPU, which contradicts the Phase 3 M1 timing-hardening commitment, or touching the voice instances, which means changing the audio architecture.

**Verdict**: **Go for a first 200+ LE slice. The full 400 LE target is only reachable with explicit sample_gen elision authorization.**

## 4. Recommended Next Implementation Task

**Task — Phase 4 M2 control-regs and audio-path mix consolidation slice**

- Role: implementer
- Output: code commit + `reports/phase4_m2_reclamation_impl.md`
- Required scope:
  - **In scope**: `rtl/control/phase0_control_regs.v` decode/strobe/array consolidation (Candidate A), `rtl/audio/phase0_audio_path.v` mix-tree re-expression (Candidate B1), `rtl/control/phase0_soc_stub.v` deletion (Candidate C).
  - **Out of scope**: any change to `phase0_rv32i_core.v`, `phase1_reduced_voice.v`, `phase0_body_filter.v`, `phase0_sample_gen.v`, SDC, pins, PLL, firmware, host tools.
  - **Out of scope by design**: register-map changes, UART tag/order/value changes, command-grammar changes, default-parameter changes, accepted-baseline behavior changes.
- Required verification:
  - `fw/phase0/build.ps1` PASS, ROM unchanged at 931
  - ModelSim reduced-voice golden-sample TB PASS bit-exact
  - ModelSim full-system happy + NACK TBs PASS
  - Quartus full compile, errors = 0, warnings <= 16 (Phase 3 baseline)
  - LE delta negative; target -200 LE or better
  - Slow-85C setup slack >= +2.5 ns (current +2.914 ns; allow up to ~0.4 ns erosion if reclamation is aggressive)
  - Hold slack >= +0.4 ns (current +0.405 ns)
  - All TNS = 0
  - M9K and DSP9 unchanged from baseline (16 / 28)
  - PLL = 1
  - Hardware UART smoke if available: no-command G=8 K=0 X=0 Q=0 CC stable; 6-command G=14 Q=6 K=0 X=0; voice3 telemetry V3/VT/VA/VV/S3 increments coherently; ST coherent under burst
  - Hardware audio smoke if available: continuous baseline, no clipping, no audible regression

- Hard gates (any single failure stops promotion):
  - LE delta positive (regression)
  - K > 0 in any valid-command capture
  - Any UART tag value or order changes
  - Setup slack < +2.0 ns slow-85C
  - Any TNS != 0
  - Golden-sample TB diff
  - Any change in command grammar or accepted register addresses

- Stop and report instead of continuing if:
  - LE delta cannot reach -100 (slice not worth it)
  - Any RTL or firmware change beyond the three named files becomes necessary
  - Timing erodes below the +2.5 ns target without recovery options

### Optional follow-up task

**Task — Phase 4 M3 sample_gen elision (only if M2 succeeds and orchestrator authorizes)**

- Required precondition: orchestrator-authorized, with explicit confirmation that the sample_gen test path is no longer required for diagnostics or that an alternative diagnostic exists.
- Estimated saving: ~150 LE additional.
- Risk: medium (feature removal).
- Scope: gate `phase0_sample_gen` instantiation behind a build-time `localparam`, default off; preserve Verilog source for re-enablement; document in `reports/phase4_m3_sample_gen_elision.md`.

## 5. Why This Sequencing Is Safe

- **Candidate A is a textbook Phase 1C-style behavior-preserving refactor.** Phase 1C-A (ROM/RAM right-sizing) and Phase 1C-B (body-pipe optimization) both delivered LE/M9K savings without behavior change and with hardware acceptance. The same playbook applies.
- **Candidate C is zero-risk hygiene.** A dead file becomes confusing context for future agents; removing it is net-positive.
- **Candidate B1 is small and bounded.** Re-expressing a saturated 3-input sum is a 30-60 LE win at most, but it does not touch the body filter timing path that took multi-pass SDC work to close.
- **CPU and voice instances are deliberately untouched.** Phase 3 M1 timing hardening is the basis of the +2.914 ns slack we currently have. Touching `phase0_rv32i_core` puts that at risk for unproven gain.
- **ROM is held behind a separate toolchain-audit task** because M8 already showed function extraction does not work in this codebase. Repeating that pattern is not productive.
- **Hardware acceptance gates are unchanged from Phase 3 M1/M3b/M4** so the verifier playbook is the same and known to work.

## 6. Summary

| Item | Status |
| --- | --- |
| LE attribution complete | Yes (from `piano_phase0_top.fit.rpt`) |
| LE candidates identified (>= 3) | Yes: A (control_regs), B1 (mix tree), B2 (sample_gen, hold), C (dead file) |
| ROM candidate identified | Yes: D, but **HOLD** pending separate toolchain-audit task |
| Behavior-preservation argument per candidate | Yes |
| Verification plan per candidate | Yes |
| First slice plausibly >= 200 LE | Yes (A + B1 + C combined) |
| Broader program plausibly >= 400 LE | Plausible only with B2 authorization |
| Recommended next task | Phase 4 M2 control-regs + audio-path + dead-file slice |
| Optional follow-up | Phase 4 M3 sample_gen elision (gated on orchestrator authorization) |

This report is documentation only. No RTL, firmware, SDC, constraint, PLL, generated image, or host tool was modified.
