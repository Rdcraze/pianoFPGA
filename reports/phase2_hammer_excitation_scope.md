# Phase 2 Hammer Excitation Scoping Report

Date: 2026-05-12
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-ad94d1d9`
Sources: `reports/orchestrator_pickup_note.md`, `docs/project_brief.md`, `reports/phase2_body_filter_validation.md`, `reports/phase1c_modelsim_gain_trace.md`, `reports/phase1c_clean_baseline_revalidation.md`, `rtl/audio/phase1_reduced_voice.v`, `rtl/audio/phase0_audio_path.v`, `fw/phase0/phase0_main.c`, `fw/phase0/phase0_hw.h`

## Selected Improvement

**Asymmetric attack-shaped hammer excitation ROM** — replace the current symmetric 16-sample triangular burst with an asymmetric hammer waveform that has rapid attack, sharp peak, and slower exponential-like decay.

This is the single lowest-risk Phase 2 physics improvement. It touches exactly one code location (the `excitation_rom` function's 16 constants), requires zero RTL structural changes, zero register changes, zero firmware changes, and zero parameter additions.

## Rationale

### Why this candidate

1. **Highest impact-to-risk ratio**: The excitation waveform defines the entire initial transient — the most perceptually salient part of a struck-string sound. A better hammer shape makes the piano sound more "piano-like" without touching the waveguide core, delay line, damping, body filter, or voice control logic.

2. **ROM-only change**: The existing `excitation_rom` function (lines 144-166 of `phase1_reduced_voice.v`) takes a 4-bit index and returns a 16-bit value. Replacing its 16 constants with a new asymmetric waveform requires no new registers, no new multipliers, no new state machines, no new control signals.

3. **Single-strike**: The hammer waveform fires once per trigger, then the `excite_busy` flag clears. No re-trigger behavior, no sustain interaction, no per-note state. The existing trigger → clear → excite → waveguide loop sequence is preserved unchanged.

4. **Proven safe**: The current excitation peaks at ROM value 32627, which after ×2 velocity scaling and >>>1 guard yields -12.1 dBFS per voice with K=0. An asymmetric waveform with the same peak keeps the same gain margin.

5. **No new blocked features**: No registers, UART commands, host parameters, per-note state, parameter banks, voice stealing, SDRAM, PLL work, CPU loop work, or diagnostic scaffolding.

### Why not other candidates

| Candidate | Rejection reason |
| --- | --- |
| Multi-string coupling | Adds second/third delay lines with detuning — LE/M9K risk, requires register expansion for coupling parameters, introduces per-note state risk |
| Damper behavior | Requires sustained state machine (damper engage/release), introduces per-note state risk, needs new control path |
| Sample playback excitation | Explicitly blocked; requires SDRAM or larger ROM |
| Per-voice parameter banks | Explicitly blocked; requires register-map expansion |
| Re-trigger/sustain diagnostics | Already obsoleted (c95f08a); architecturally incompatible with delay-line reset on trigger |

## Current Excitation ROM

```verilog
// lines 144-166, phase1_reduced_voice.v
function [15:0] excitation_rom;
    input [3:0] index;
    begin
        case (index)
            4'd0:  excitation_rom = 16'd6021;   // gentle ramp up
            4'd1:  excitation_rom = 16'd11837;
            4'd2:  excitation_rom = 16'd17250;
            4'd3:  excitation_rom = 16'd22075;
            4'd4:  excitation_rom = 16'd26149;
            4'd5:  excitation_rom = 16'd29332;
            4'd6:  excitation_rom = 16'd31516;
            4'd7:  excitation_rom = 16'd32627;   // flat top (sample 7-8)
            4'd8:  excitation_rom = 16'd32627;
            4'd9:  excitation_rom = 16'd31516;
            4'd10: excitation_rom = 16'd29332;   // symmetric decay
            4'd11: excitation_rom = 16'd26149;
            4'd12: excitation_rom = 16'd22075;
            4'd13: excitation_rom = 16'd17250;
            4'd14: excitation_rom = 16'd11837;
            default: excitation_rom = 16'd6021;
        endcase
    end
endfunction
```

Shape: gentle linear attack (7 samples) → flat top (2 samples) → symmetric linear decay (7 samples). Total duration: 16 samples = ~341 µs at 46.875 kHz.

This is physically unrealistic for a piano hammer:
- Real hammer felt compresses nonlinearly at contact, producing a much sharper attack
- The hammer then rebounds with a slower decay determined by felt relaxation
- Symmetric shape lacks the "percussive snap" characteristic of a real hammer strike

## Proposed Asymmetric Hammer ROM

### Design

| Index | Value | Fraction of peak | Description |
| --- | --- | --- | --- |
| 0 | 1200 | 3.7% | Pre-contact (hammer approaching) |
| 1 | 9000 | 27.6% | Initial contact |
| 2 | 24000 | 73.6% | Compression peak |
| 3 | 32627 | 100.0% | Maximum compression (same peak as current) |
| 4 | 26000 | 79.7% | Early rebound |
| 5 | 19500 | 59.8% | Felt relaxation |
| 6 | 14300 | 43.8% | Rebound decay |
| 7 | 10400 | 31.9% | |
| 8 | 7500 | 23.0% | |
| 9 | 5300 | 16.2% | |
| 10 | 3700 | 11.3% | |
| 11 | 2500 | 7.7% | |
| 12 | 1600 | 4.9% | |
| 13 | 1000 | 3.1% | |
| 14 | 500 | 1.5% | Late tail |
| 15 | 200 | 0.6% | Hammer fully separated |

Shape: 3-sample rapid attack → sharp peak → 12-sample exponential-like decay. Same peak amplitude (32627) as the current excitation. Same total duration (16 samples).

### Why this shape

- **Rapid attack (indices 0-3)**: Models the nonlinear stiffening of hammer felt as it compresses against the string. The hammer velocity translates to felt compression over a very short time window, producing a sharp pressure pulse.
- **Sharp peak (index 3)**: The single-sample peak at the same amplitude as the current flat-top means the peak energy is unchanged — K=0 margin is preserved.
- **Exponential-like decay (indices 4-15)**: Models the gradual felt relaxation and hammer rebound. Real hammer contact has a much longer tail than attack, and the asymmetric shape provides this.
- **Zero crossing not needed**: A negative tail (hammer pulling string) would be physically accurate but changes the excitation energy balance and risks clipping. Deferred.

### No negative tail decision

A real hammer strike includes a small negative excursion (the hammer pulls the string slightly during rebound). This can be added as a refinement in a future workstream if the asymmetric attack alone proves insufficient. The negative tail would require reducing the positive peak to maintain K=0 and should be validated with a dedicated pass.

## Exact Code Touch Points

### Primary (only RTL change)

**File**: `rtl/audio/phase1_reduced_voice.v`, lines 144-166

**Change**: Replace the 16 `excitation_rom` constant values with the proposed asymmetric waveform.

No other RTL changes. The `excitation_rom` function's signature, calling site (line 307), and all surrounding pipeline logic remain identical.

### Documentation (no code changes)

- `reports/phase1c_modelsim_gain_trace.md` — update node #1 (excitation ROM) to reflect new peak shape
- New report: `reports/phase2_hammer_excitation_validation.md` — verifier validation
- New report: `reports/phase2_hammer_excitation_impl.md` — implementation evidence

### No changes to

- `rtl/audio/phase0_audio_path.v` — voice instantiation and mix pipeline unchanged
- `fw/phase0/phase0_main.c` — velocity, trigger, smoke profile unchanged
- `fw/phase0/phase0_hw.h` — no new registers, no bit definition changes
- `rtl/control/phase0_control_regs.v` — register map unchanged
- Any constraints, build scripts, project files, or bitstream metadata

## Why Single-Strike (No Re-Trigger Dependency)

The hammer excitation ROM fires exactly once per trigger strobe (`excite_index` counts 0→15, then `excite_busy` clears at line 324). The excitation is fully consumed before the waveguide loop begins its free oscillation. Key properties:

1. No state persists between triggers beyond the 16-sample burst window.
2. The `trigger_strobe && enable` path (line 214) resets `excite_index` to 0 and sets `excite_busy` high, starting a fresh excitation.
3. The delay line is cleared on trigger (clear_active path, lines 241-253), so there is no interaction between successive strikes.
4. No sustained hammer contact, no damper state, no re-trigger position tracking.

This means: any hammer ROM shape works identically for the first strike and all subsequent strikes. There is no re-trigger-specific behavior that needs testing or modification.

## Expected Resource / Timing / ROM Impact

| Category | Impact | Rationale |
| --- | --- | --- |
| LEs | Zero | No new logic, no new registers, no new state machine states. Same 16-entry ROM implemented as LUT logic. |
| M9Ks | Zero | The excitation ROM is a LUT-based case statement, not an M9K. |
| DSPs | Zero | Same single 34-bit multiply for velocity scaling. |
| PLLs | Zero | No clock changes. |
| Timing slack | Zero | Same combinational path depth (LUT → multiplier → shift → saturate). |
| ROM word delta | Zero | Firmware unchanged. |
| UART bandwidth | Zero | Same report cadence, same tag count. |

**Expected resource delta: zero across all categories.** This is the narrowest possible RTL change — 16 constant replacements in a LUT that already exists.

## Required Simulation / Golden-Sample Updates

### ModelSim

1. Run the existing `phase1_reduced_voice_tb` with new ROM values.
2. Verify: `excite_sample` peak still at 32,626 (±100), peak timing shifts to sample index ~3 instead of ~7.
3. Verify: delay line injection value unchanged in magnitude.
4. Verify: `output_sample_q18` spectrum shows sharper attack transient.
5. Verify: `clip_seen` remains 0 for one voice at velocity=0x7FFF.

### Golden-sample waveform

1. Capture audio from a single-voice trigger with the new ROM.
2. Compare attack envelope shape against current baseline: expect sharper onset (faster rise), similar sustain/decay.
3. Compare FFT: expect slightly broader high-frequency content during the first ~20 ms due to sharper attack.

## Hardware Validation Plan

### Quartus compile

1. Full compile: `quartus_sh --flow compile piano_phase0_top`
2. Confirm: 0 new errors, same warning count (14-16).
3. Confirm: LEs at 7,963 / 10,320 (unchanged).
4. Confirm: M9Ks at 14 / 46 (unchanged).
5. Confirm: DSPs unchanged.
6. Confirm: sys_clk_50m setup slack unchanged at +2.438 ns (slow-85C).

### UART telemetry

Capture no-command and six-command profiles:

| Profile | Expected |
| --- | --- |
| No-command | `G=6 Q=0 X=0 K=0 CC=0x003D0900` |
| Six-command | `G=12 Q=6 X=0 K=0 CC=<constant>` |

K=0 is the critical gate — the asymmetric ROM must not cause mix clipping. CC stability must be ±5% across 5 consecutive reports.

### Audio checklist (Phase 1C)

Per `reports/phase1c_audio_verification_checklist.md`:

| Check | Expectation |
| --- | --- |
| K=0 | No clipping |
| Flat factor | 0 (no DC offset, no asymmetry in steady state) |
| Fundamental pitch | Unchanged (same waveguide loop_len=106) |
| Attack transient | Sharper onset, faster rise |
| Sustained level | Unchanged (same loop gain) |
| DC offset | ~0 |
| No dropouts/artifacts | PASS |

### A/B listening comparison

Recommended: record a short sequence with both old and new ROM, compare for:
- Perceived "hammer snap" at note onset
- Overall tonal quality (should be unchanged after the first ~50 ms)
- No harshness or clipping artifacts

## No-Go Criteria

The implementation is rejected if any of:

1. K > 0 in no-command or six-command smoke (mix clipping).
2. Any existing UART tag value changes (G, Q, X, CC, or voice diag tags).
3. LE count increases (indicates unintended synthesis change).
4. Timing slack degrades below +2.438 ns.
5. Waveform checklist fails (DC offset, flat factor, dropout, artifact).
6. Perceived audio quality is worse than current symmetric ROM (A/B listening).
7. Any blocked feature is touched (registers, UART commands, per-note state, etc.).

## Go Gates

Before implementation begins:

1. This scoping report is reviewed and accepted by the orchestrator.
2. A distinct implementation task is created referencing this report.
3. The implementation is explicitly limited to: replace 16 ROM constants in `excitation_rom`, rerun ModelSim, compile Quartus, validate hardware.
4. No RTL structural changes, no firmware changes, no register changes.

## Explicit Deferrals

### Multi-string coupling (deferred)

Multi-string coupling adds a second or third detuned delay line per voice with cross-coupling coefficients. Risk assessment:

- **LE risk**: Each additional delay line is a 128-entry M9K RAM plus associated read/write logic. A 2-string voice would roughly double the per-voice M9K count from 4 to 8, exceeding the 14/46 anchor.
- **Register risk**: Cross-coupling parameters (detune amount, coupling coefficient) require register-map expansion.
- **Per-note state risk**: Different string pairs have different detune amounts per note, pushing toward per-note parameter banks (blocked).
- **Verdict**: Defer until a separate scoping task explicitly authorizes register-map expansion and addresses the per-note state boundary. The asymmetric hammer ROM provides a meaningful single-strike improvement without touching this risk area.

### Damper behavior (deferred)

Damper modeling requires a sustained state machine (damper pedal engage/release), decay-rate modulation, and interaction with the waveguide loop. Risk assessment:

- **State machine risk**: Damper behavior is fundamentally multi-trigger — it modulates an already-ringing note rather than initiating a new strike. This requires a new control path that interacts with the active waveguide state.
- **Per-note state risk**: Different notes have different damper timing, pushing toward per-note state (blocked).
- **Control path risk**: Would require either a new UART command or CPU-modulated register, neither of which is scoped in the current baseline.
- **Verdict**: Defer. The damper is the highest-risk remaining Phase 2 item and should be its own scoping task after the hammer excitation improvement is validated.

### Contact-shape filter (deferred, optional next step)

A one-pole LPF applied to the excitation output would soften the very high-frequency content of the hammer strike without changing the ROM shape. Risk assessment:

- **LE risk**: Low — one additional multiplier and one register per voice, reused from the existing DSP inference pattern.
- **Parameter risk**: If the filter is hardwired (fixed coefficient), no register impact. If tunable, requires a new register field.
- **Verdict**: Deferred as an optional refinement. The ROM shape change alone may produce sufficient improvement. If the asymmetric attack sounds too harsh, a hardwired one-pole LPF at ~4 kHz is the next-lowest-risk addition.

## Summary

One change. Sixteen constants. Zero resource delta. Replaces a symmetric triangular hammer burst with a physically motivated asymmetric attack shape (rapid rise, sharp peak, exponential decay). No registers, no firmware, no UART, no parameters, no blocked features. The smallest possible single-strike physics improvement that makes the piano sound more like a piano.
