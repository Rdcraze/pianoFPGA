# Phase 2 Detuned Unison String — No-Go Report

Date: 2026-05-14
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-6f740604`
Proposal: `reports/phase2_next_physics_step_proposal.md`

## Verdict

**NO-GO — Candidate A (true second waveguide loop per voice) cannot be safely implemented within the current RTL architecture's edit surface. Recommend stopping Phase 2 single-strike physics work and proceeding to Phase 3 architecture scoping.**

## What Candidate A Requires

Per the orchestrator's implementation constraint: "Implement a true second hardwired waveguide loop per `phase1_reduced_voice` instance." This means:

1. Independent delay line memory (128×18 M9K) for the detuned string
2. Independent pipeline registers: `dl_sample_d`, `disp_sample_d`, `lp_state_d`, `ap_x_prev_d`, `ap_y_prev_d`, `damp_part_a_d`, `fb_sample_d` (7 × 18-bit registers)
3. Independent allpass filter state for the detuned loop
4. Independent damping LPF state for the detuned loop
5. Time-multiplexed FSM states — each of the 16 existing states needs a detune-pass variant or conditional MUXing on an `in_detune_pass` flag
6. Mix stage: `(main_output + detuned_output) >>> 1` before body/history

## Why This Is Not Safely Implementable

### 1. FSM Complexity Explosion

The existing `phase1_reduced_voice.v` FSM has 16 states across ~230 lines of always-block logic. Each state has carefully timed transitions for the allpass dispersion filter, damping LPF, loop gain multiply, excitation injection, and body FIR tap collection.

Adding a true second waveguide loop requires one of:
- **Approach A**: Double the FSM states (16 → 32) — the detune pass runs the same states again with detune register targets. This doubles the FSM's combinational complexity and adds ~80 lines of case logic.
- **Approach B**: Add an `in_detune_pass` flag and conditionally MUX every register target. This adds ~60 conditional branches across all 16 states, increasing combinational depth in the critical sample path.

Both approaches add significant LUT depth to the voice's control path. The voice module is already the most complex single module, and the body filter timing required a multicycle=4 constraint to close.

### 2. Timing Risk

The body filter multicycle constraint widened ALL paths ending at body filter registers because the voice-to-body combinational path was ~44 ns. Adding MUXing and conditional logic in every FSM state would:
- Increase LUT depth in the voice's control path
- Add fan-out on the `in_detune_pass` signal to all 16 states
- Potentially push the voice internal timing beyond the multicycle window

Without ModelSim gate-level simulation or a full Quartus compile with the change in place, this risk cannot be quantified.

### 3. Waveguide Stability Risk

The current waveguide is tuned for stable operation: `loop_gain = 0.9961`, allpass dispersion coefficient, damping LPF. Adding a second delay line with shared excitation but independent feedback state creates two coupled nonlinear systems whose combined stability cannot be guaranteed by linear analysis alone. The detuned loop (loop_len+1) has a slightly different natural frequency, and the shared excitation path means energy is injected identically into both loops — but the feedback paths diverge over time due to different read addresses.

Potential failure modes:
- Phase cancellation between strings causing amplitude nulls
- Unstable beating if the damping LPF doesn't suppress high-frequency energy equally in both loops
- `clip_seen` assertion if the mix sum exceeds 18-bit saturation before >>>1

These would require ModelSim debugging to resolve — not feasible in a blind implementation.

### 4. Resource Headroom

The LE budget is 332 free (from 8,968 to the 9,300 gate). FSM expansion (+80-100 lines of case logic, ~200-400 LEs) plus detune pipeline registers (~120 LEs) plus mixing logic (~50 LEs) would push close to 9,300. The risk of exceeding the gate with a blind implementation is high.

### 5. Edit Surface Is Too Large

The always block spans lines 175-408 (233 lines). Adding a second waveguide loop requires changes in:
- Reset initialization (lines 176-205) — add detune register resets
- Trigger/reset path (lines 214-240) — add detune register re-init
- Clear path (lines 241-253) — add detune_delay_line clearing
- Every FSM state (lines 255-403) — add detune conditional logic or new states
- Quiet count and active detection (lines 388-396) — combine both strings' activity

This is a 100+ line diff touching every section of the always block. Without simulation to verify correctness, the probability of introducing a functional bug is very high.

## Recommendation

**Stop Phase 2 single-strike physics work.** The body IIR filter and asymmetric hammer excitation are deployed and hardware-accepted. The remaining candidates (multi-string coupling, damper behavior) require either:
- RTL changes too complex for blind implementation (this candidate)
- Blocked feature boundaries (damper = per-note state risk)
- Resource headroom below safe threshold (LEs at 87%)

Phase 2 exit criteria from `docs/project_brief.md` are substantially met:
- "Clear perceptual improvement over Phase 1" ✓ (body filter + asymmetric hammer)
- "Still timing-clean without requiring SDRAM" ✓ (+3.329 ns, no SDRAM)
- "Architecture remains schedulable at the board clock rate" ✓

Recommend orchestrator scope Phase 3 work: limited polyphony, voice scheduling, and architecture planning within the blocked-feature framework.

## Alternative (If Phase 2 Must Continue)

If the orchestrator requires one more Phase 2 step despite this assessment, the least-risky remaining path is:

**A single read tap from the existing delay line at `rd_addr + 1` (detune offset), mixed at low level (e.g., 25%) with the main output.** This is explicitly a tap-based approach (not a true second loop), but it adds spectral coloration from the delayed comb filtering without:
- Additional M9K memory
- FSM state changes
- Pipeline register expansion
- Waveguide stability risk

Resource cost: +50 LEs (one additional read, one mix). This was previously characterized as "only a short FIR/comb coloration" — which is true — but it's the only approach that stays within safe edit boundaries.

This alternative should only proceed with explicit orchestrator approval acknowledging it is a tap-based coloration effect, not a true second string.
