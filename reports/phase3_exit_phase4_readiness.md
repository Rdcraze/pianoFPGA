# Phase 3 Exit Assessment and Phase 4 Readiness Scope

Date: 2026-05-16
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-2a1ad361`
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `7fbe0d4`

Sources:
- `docs/project_brief.md`
- `reports/phase3_architecture_scope.md`
- `reports/phase3_m1_4voice_hardware_validation.md`
- `reports/phase3_m3b_hardware_validation.md`
- `reports/phase3_m4_note_off_hardware_validation.md`
- `reports/phase3_m7a_track_release_validation.md`
- `reports/phase3_m8_no_go_containment_validation.md`
- `reports/phase3_m9_interactive_validation.md`
- `quartus/phase0/output_files/piano_phase0_top.fit.summary` (Thu May 14 21:38:13 2026)
- `quartus/phase0/output_files/piano_phase0_top.sta.summary`

## TL;DR

Phase 3 exit criteria are **substantively met** with one caveat: hardware audio validation under live polyphonic playback was performed in slices but never as a single integrated demo. Architecture is sound, telemetry is rich, and host wrappers (M5/M6/M7a/M9) make the prototype playable without firmware/RTL change.

Resource posture is **tight**: LE 9,992 / 10,320 (97%), DSP 28/46 (61%), ROM 931/1024 (91%). Phase 4 cannot start with new RTL feature work. The recommended first step is a non-invasive **Phase 4 M0 preflight** that quantifies SDRAM integration cost and attribution-style headroom on paper before any code changes.

## 1. Phase 3 Exit Criteria

Per `docs/project_brief.md` lines 140-149:

> Exit criteria:
> - Multiple concurrent notes with acceptable artifacts.
> - Measured resource usage consistent with later expansion.
> - Debug visibility for dropped voices, overload, and clipping.

| Criterion | Status | Evidence |
| --- | --- | --- |
| Multiple concurrent notes | PASS | M3b polyphonic captures show three distinct parameterized commands `!N006A7FFF / !N00407FFF / !N007F4000` accepted onto distinct physical voices with `K=0`, `X=0`. M1 confirms 4-way round-robin (`G=8` no-command, `G=14` commanded). |
| Resource usage measured | PASS | Quartus fit summary recorded: LE 9,992/10,320 (97%), regs 4,233, memory 86,016 bits, DSP 28/46, PLL 1/2, setup `+2.914 ns` slow-85C. Headroom is documented but tight. |
| Debug visibility | PASS | UART telemetry exposes `K` (mix clip), `X` (parser/error), `Q` (accepted commands), `P` (drops), `ST` (steals), and per-voice tags (V/F/T/A/W for v0, Y/U/B/C/M for v1, Z/O/D/E for v2, V3/VT/VA/VV/S3 for v3) plus the `CC` cycle counter measurement hook. Host parser supports the full set including multi-character tags. |

**Verdict: Phase 3 exit criteria met.** No hard gap.

### Caveat: integrated polyphonic audio demo

Each milestone was hardware-validated in isolation (M1 4-voice round-robin, M3b parameterized polyphony, M4 release, M7a host track-and-release, M9 interactive stdin). What we do **not** have is a single capture demonstrating M9 interactive input driving M7a track-and-release wrappers across M3b polyphonic commands and M4 release on hardware as one continuous demo. The host tools and firmware all work; their composition has not been recorded as a single audio artifact.

This is not a Phase 3 exit blocker because the constituent pieces are all individually accepted, but it is the most defensible thing to capture before declaring "Phase 3 closed" for archival. It is not on the critical path for Phase 4 planning.

## 2. Accepted Architecture Summary

### Hardware-owned audio path

- **4 physical voices** instantiated in `rtl/audio/phase0_audio_path.v`, each `phase1_reduced_voice` containing a 128-entry on-chip delay line, asymmetric hammer excitation ROM, all-pass dispersion, damping LPF, and small body FIR.
- **Body/soundboard** 2-stage IIR (low-shelf + peaking biquad) on the post-mix stream, with multicycle SDC `setup=4 / hold=3` accommodating the 80 ns audio sample interval.
- **Mix and saturation** sums the 4 voices with explicit signed clamp to `[-32768, +32767]`.
- **WM8978** I2C bring-up sequence + I2S transmit, `audio_mclk` PLL-derived 12 MHz, MCLK-derived `audio_bclk` and `audio_lrc`, master-mode codec.

### CPU-owned control plane

- **RV32I core** (`rtl/control/phase0_rv32i_core.v`), reset/data init, ROM 1024 / RAM small.
- **Firmware** at `fw/phase0/phase0_main.c`, ROM 931/1024 words, no audio-loop CPU work.
- **Voice scheduling**: 6 logical note slots mapped onto 4 physical voice slots via firmware LRU stealing (M2a). Bare `!N` writes default loop_len/velocity to the chosen physical voice; parameterized `!NLLLLVVVV` writes per-voice registers at `0x98..0xB4`. `!F` triggers shared damper release.
- **Parser**: line-buffered RX with explicit `phase0_rx_line_len` clear on every completed-line return path, post-RX quiet/holdoff, malformed rejection that increments `X` without `Q`.
- **Telemetry**: frozen tag order `I/S/R/V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E/G/H/J/L/N/P/Q/X/CC` plus suffix `V3/VT/VA/VV/S3/ST` for voice3 and steal accounting.

### Host tooling

- `scripts/phase3_m5_keyboard.py` — note-name/MIDI to `!NLLLLVVVV` mapper.
- `scripts/phase3_m6_live_play.py` — sequence-based send/dry-run on top of M5.
- `scripts/phase3_m7_track_release.py` — active-set tracker, sends `!F` only when no notes remain.
- `scripts/phase3_m9_interactive.py` — incremental stdin token processor with transcript and self-check.
- `scripts/phase1c_uart_telemetry.py` — multi-character-tag-aware telemetry parser used by smoke/host tests.

### Rejected and rolled back

- **M8 ROM reclamation (`!D` gate)**: rolled back. Function-extraction overhead exceeded inline savings, ROM rose to 948 (+17). Firmware net-identical to pre-M8 baseline `b0926cf`. `!D` is not a feature.
- **Detuned unison true second loop (Phase 2)**: NO-GO. FSM complexity and timing risk at 87% LE were unacceptable. Tap-only coloration alternative remained available but was not pursued.
- **Damper / cross-coupling (Phase 2)**: deferred behind per-note-state boundary and Phase 3 polyphony architecture.

### Untracked stale artifacts (out of scope)

The following untracked files exist in the worktree and **must remain out of scope** for any Phase 4 planning or implementation:

- `reports/phase3_m3b_debug_uart.txt`
- `reports/phase3_m3b_single_uart.txt`
- `reports/phase3_m5_hardware_uart.txt`
- `reports/phase3_m6_hardware_uart.txt`
- `.kiro/` (local IDE config)

These are verifier-owned scratch from earlier rounds and the local IDE folder. None should be touched by an implementer task.

## 3. Resource Posture and Risk

### Current Quartus fit (HEAD `7fbe0d4`, fit dated 2026-05-14 21:38:13)

| Resource | Used | Capacity | Pct | Headroom |
| --- | --- | --- | --- | --- |
| Total LE | 9,992 | 10,320 | 97% | **328 LE** |
| Combinational | 9,417 | 10,320 | 91% | 903 |
| Logic registers | 4,233 | 10,320 | 41% | 6,087 |
| Total registers | 4,233 | — | — | — |
| Pins | 11 | 180 | 6% | 169 |
| Memory bits | 86,016 | 423,936 | 20% | 337,920 |
| DSP 9-bit | 28 | 46 | 61% | 18 |
| PLL | 1 | 2 | 50% | 1 |

### Timing (slow-85C sys_clk_50m)

| Metric | Slack | Status |
| --- | --- | --- |
| Setup | +2.914 ns | clean |
| Hold | +0.405 ns | clean |
| All clocks (sys/i2c/audio_bclk) | TNS = 0.000 | fully constrained, no violations |

### Firmware

| Metric | Used | Capacity | Free |
| --- | --- | --- | --- |
| ROM | 931 | 1,024 | **93 words** |

### Risk categories

- **LE saturation (97%)** is the dominant risk. Any Phase 4 RTL feature requiring more than ~200 LEs without offsetting reduction would fail to fit. Fitter congestion at 97% can also degrade routability beyond the headline LE count.
- **DSP at 61%** has 18 free 9-bit elements, enough for one more biquad filter or modest multiplier addition. Not a blocker.
- **ROM at 91%** with 93 free words means firmware-only feature additions are tightly constrained. M8 already proved that function extraction does not free ROM in this codebase.
- **Memory bits at 20%** is the cleanest dimension; an SDRAM controller would not need on-chip M9K growth but would inflate LE for the controller logic itself.
- **PLL at 50%** has one free PLL, important if SDRAM brings its own clock domain.

The combination of **97% LE + 91% ROM** means Phase 4 cannot start with code. The first step must be quantitative analysis on paper.

## 4. Phase 4 Options

Per `docs/project_brief.md` lines 154-167, Phase 4 objective is *"Use external memory only where it buys clear value"* with scope including SDRAM for longer delay/state buffers, richer body models, or tables. Below is a fair comparison of candidate first steps.

### Option A: Resource/headroom reclamation (no new features)

**What**: Audit RTL and firmware for behavior-preserving reductions: redundant decode logic in `phase0_control_regs.v`, common-subexpression collapse in the voice/audio pipeline, dead/unreachable firmware paths, telemetry packing. Goal is to recover LE and ROM headroom **before** any new feature work.

**Why now**: 97% LE leaves no room. 91% ROM leaves 93 words. The Phase 1C-A ROM/RAM right-sizing and Phase 1C-B body-pipe optimization patterns established that targeted attribution can free real budget. The Phase 1C-A precedent showed measurable savings; M8 showed that blind extraction does not.

**Risk**: Low to medium. Low if scope stays narrow; medium if it touches voice internals and triggers ModelSim regression. The voice golden-sample TB exists and would catch behavior drift.

**Cost**: 1 implementer task scoping + 1 implementer task per slice.

**Resource impact (target)**: LE -200 to -500, ROM -10 to -30 words.

### Option B: SDRAM feasibility/preflight (no controller yet)

**What**: Documentation-only investigation: confirm board pinout, voltage, refresh requirements, achievable burst rate from `Manuals_Examples/`, estimate LE cost of a minimal MIG-style controller, identify which audio-path data structure (per-voice delay line history? body model coefficient table?) would benefit. Quantify pin budget impact (SDRAM needs ~50 pins on this board) and PLL-domain implications. **No RTL or firmware work in this option.**

**Why now**: Phase 4 explicitly authorizes SDRAM only "where it buys clear value." Before risking any LE on a controller, we need to know what a controller costs and what audible win it actually unlocks. The current 4-voice waveguide already fits all delay state on-chip in M9Ks — the 20% memory bits utilization confirms there is no on-chip memory pressure. SDRAM has to justify itself against richer body models or longer convolution structures.

**Risk**: None. Pure analysis.

**Cost**: 1 implementer scoping task + manual-reader board-fact lookup if needed.

**Resource impact**: 0 (paper-only).

### Option C: Small body-model expansion or table-loading experiment

**What**: Pick one bounded coloration improvement that fits in current headroom. Examples: a 3rd biquad in the body filter (≈100 LE, 7 DSP — DSP fits, LE may not), a small per-voice excitation-table variant, or a tap-based detune coloration on the existing delay line (≈50 LE, no M9K). Implement narrowly and validate.

**Why now**: It would be the smallest "Phase 4 with audible payoff" if a candidate fits. The hammer ROM and body filter are the established Phase 2 successes; one more low-cost coloration could be the right next milestone.

**Risk**: Medium. At 97% LE, any 100+ LE addition risks fit failure. A 50-LE tap addition is plausible. Still, this option implicitly asks Phase 4 to land before headroom recovery, which is fragile.

**Cost**: 1 implementer scoping + 1 implementer task + 1 verifier task.

**Resource impact**: +50 to +200 LE, +0 to +7 DSP. Likely puts LE at or above 99%.

### Comparison

| Criterion | A: Reclamation | B: SDRAM preflight | C: Small body expansion |
| --- | --- | --- | --- |
| Code change in this step | None (audit) | None (paper) | RTL + verify |
| Risk to accepted baseline | Low | None | Medium |
| Unblocks future Phase 4 | Yes (essential) | Yes (informs) | Partial |
| Headroom delta | + (positive) | 0 | - (negative) |
| Has a clear audible payoff this step | No | No | Maybe |
| Compatible with strict 97% LE | Yes | Yes | Risky |

## 5. Recommended Next Tasks

### Recommended sequencing: B then A then C

The ordering that best protects the accepted baseline is:

1. **Phase 4 M0 preflight** (Option B) — proposal/report only. Quantify SDRAM cost and audible-win candidates before risking any LE. No accepted-baseline impact.
2. **Phase 4 M1 reclamation scope** (Option A) — analyze where LE and ROM can be recovered behavior-preservingly. This is preparation for any feature work, not feature work itself.
3. **Phase 4 M2 narrow expansion** (Option C, only if A reclaims enough margin) — specific small coloration step, gated on demonstrated headroom.

This puts paper-only work first, which is appropriate because the **dominant Phase 4 risk is committing RTL changes against a 97% LE baseline without first knowing what the change is supposed to buy and where the budget will come from**.

### Concrete next task — recommended

**Task — Phase 4 M0 SDRAM and headroom preflight (proposal-only)**

- Role: implementer
- Inputs: `docs/board_capabilities_report.md`, `docs/manual_audio_example_report.md`, `Manuals_Examples/EBF EP4CE10 Pro/...`, current Quartus fit/timing summaries
- Output: `reports/phase4_m0_preflight.md`
- Required content:
  - SDRAM pin budget (count, bank assignment, voltage standard, conflicts with other planned peripherals).
  - Estimated LE cost of a minimal SDRAM controller compatible with the EP4CE10 board's IS42S16320B and the 50 MHz / available PLL domain. Identify which existing `Manuals_Examples` design provides the closest reference and what its fit cost is.
  - Audible-win candidates: enumerate at most 3 audio-path features that would actually benefit from off-chip memory (longer body convolution, per-voice longitudinal/dispersion table, sample-style hammer variants). For each, estimate on-chip vs off-chip data size.
  - Comparison: SDRAM controller LE cost vs an equivalent on-chip-only alternative (e.g., body filter expansion, more taps).
  - Go/no-go recommendation: does any candidate justify the SDRAM controller cost at the current 97% LE / 20% memory-bits posture?
- Scope guards (hard):
  - No RTL, firmware, SDC, constraint, PLL, project-file, or host-tool change.
  - No FPGA programming.
  - Documentation only.
  - Do not touch the 4 untracked verifier UART files or `.kiro/`.

**Gates**:

| Gate | Threshold |
| --- | --- |
| Artifact present at `reports/phase4_m0_preflight.md` | required |
| ASCII-only | required |
| Identifies SDRAM pin/bank/voltage budget | required |
| Provides at least one quantitative LE cost reference from `Manuals_Examples/` | required |
| Reaches an explicit go/no-go on SDRAM-first vs reclamation-first | required |

### Optional follow-up task — only if M0 recommends headroom reclamation first

**Task — Phase 4 M1 reclamation scope (proposal-only)**

- Role: implementer
- Inputs: M0 report, current RTL/firmware tree, Phase 1C-A and Phase 1C-B precedents.
- Output: `reports/phase4_m1_reclamation_scope.md`
- Required content: targeted candidates with estimated LE/ROM savings per slice and behavior-preservation arguments.
- Scope guards: same as M0 — no code changes.

The orchestrator should queue M1 only after M0 lands, so the M0 conclusion can drive whether M1 is needed.

## 6. Why This Sequencing Is Safe for the Current EP4CE10 Posture

- **97% LE** means an RTL feature task is one fitter regression away from breaking the accepted M1/M3b/M4 baseline. The accepted SOFs depend on the current synthesis result fitting; a +200 LE feature would risk leaving us with no buildable image and would have to roll back.
- **91% ROM** means a firmware feature task that adds even 30-50 words risks crossing 1024. M8 demonstrated that the firmware codebase does not respond well to function-extraction reclamation, so we cannot assume more ROM is recoverable on demand.
- **Setup +2.914 ns** is healthy but not generous. New RTL paths through the audio mix or body filter would erode this and may push the design back into multi-pass timing fixes.
- **Hardware audio is currently working end-to-end** with ~440 Hz piano-like decay per validated captures across M3b, M4, M7a. Any change that risks rolling that back without a paper-confirmed gain is a net negative.
- **Two scoping tasks (M0, optionally M1) cost zero RTL/firmware risk** and produce the data needed to decide whether Phase 4 should even use SDRAM, or whether on-chip headroom recovery is the better Phase 4 entry.

## 7. Summary

| Item | Status |
| --- | --- |
| Phase 3 exit criteria | Met |
| Open caveat | No single integrated polyphonic-demo capture; not blocking |
| Resource posture | LE 97%, DSP 61%, ROM 91%, setup +2.914 ns |
| Phase 4 scope | Memory/body-model expansion authorized but blocked by headroom |
| Recommended next | Phase 4 M0 SDRAM/headroom preflight, paper only |
| Optional follow-up | Phase 4 M1 reclamation scope, paper only |
| Hard gate before any Phase 4 RTL/firmware change | Approved go/no-go from M0 (and M1 if needed) |

This report is documentation only. No RTL, firmware, SDC, constraint, PLL, generated image, or host tool was modified.
