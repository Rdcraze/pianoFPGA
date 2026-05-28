# Phase 6 M6.5 Voice-Quality Pivot Scope Validation

Date: 2026-05-28
Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-90f984d0`
Branch: `codex/phase1c-uart-boundary-fix`
Implementer commit: `635fef5` (M6.5 voice-quality pivot scope, task-56fceebe)
M6.4-INT baseline commit: `5ed08ec`
Verdict: **CONDITIONAL_PASS**

## TL;DR

CONDITIONAL_PASS. The scope is single-file, ASCII-clean,
report-only, and strategically correct: it accepts the
M6.4-INT FAIL-on-strict-gate result, properly classifies
the body-axis limit as voice-model-bound, recommends a
sound disposition for the M6.4-INT RTL (KEEP), and pivots
to the right next slice (M6.5-DAMP runtime damping knob).
The candidate axis comparison fairly weighs hammer texture,
detune/chorus, post-waveguide brightness, and measurement-
only support, with the chosen pivot well-justified.

Two non-blocking precision findings prevent full PASS:

1. Section 5.1 oversimplifies the existing
   `voice_damp_mix_reg` state machine in
   `phase0_fixed_control.v`. The current code is not a
   "static localparam"; it is a runtime register with
   reset/note/release behavior baked in. The implementer
   task in section 6 needs to be more specific about
   which `16'd16384` literals (lines 231 and 264) get
   replaced with `damp_mix_runtime` and which release
   value (`16'd32767` at line 306) stays untouched.

2. The damp_mix acoustic semantic direction in section
   5.2 ("damp_mix=0 -> infinite sustain; damp_mix=0x7FFF
   -> heavy damping") needs a quick filter-analysis check
   in the implementer task. The actual loop low-pass IIR
   `lp_state_new = lp_state*(1-alpha) + input*alpha` with
   `alpha = damp_mix/32767` may have the inverted
   semantic, where damp_mix=0 holds lp_state in place
   (effectively dead loop) and damp_mix=0x7FFF gives full
   pass-through (max sustain modulo loop_gain). The
   verifier acceptance gate sweep range and direction
   should be tuned after the implementer confirms the
   actual filter response.

Both findings are minor task-text clarifications, not
architectural gaps. Orchestrator may queue M6.5-DAMP with
the two clarifications added to the implementer task.

## 1. Scope check (PASS)

`git show --stat 635fef5` confirms one file added:

| file                                              | type                  |
| ------------------------------------------------- | --------------------- |
| reports/phase6_m6_5_voice_quality_pivot_scope.md  | scope report (new)    |

`git diff 5ed08ec..635fef5 -- rtl/ quartus/ fw/ scripts/ obsolete/` returns
zero output. RTL, generated images, QSF, SDC, PLL,
firmware, host scripts, and obsolete archive are all
untouched. The M6.4-INT-accepted state is preserved
bit-for-bit.

## 2. ASCII check (PASS)

```
reports/phase6_m6_5_voice_quality_pivot_scope.md  non_ascii=0  total=21701
reports/phase6_m6_5_voice_quality_pivot_scope_validation.md  non_ascii=0
```

## 3. M6.4-INT RTL disposition: KEEP recommendation is reasonable (PASS)

The scope's section 2 trade-off table is accurate: M6.4-INT
saves 29 LE versus M6.3a, gains +0.247 ns slow-85C setup,
and shifts a small amount of energy into 50-200 Hz warmth
(+1.06 dB) and 3-5 kHz brightness (+0.69 dB), at the cost
of slightly less 200-1k passband emphasis (-1.71 dB at
200-500 Hz, -0.89 dB at 500-1k Hz versus M6.3a). Both
fail the strict 1-3 kHz gate by similar margins. KEEP is
the engineering-prudent choice; revert is also defensible
on subjective listening grounds.

Stale golden hex caveat is correctly carried forward (vsim
license-blocked on this host; the M6.4-INT golden has not
been regenerated and remains stale relative to the
post-M6.4-INT RTL). This is the same M6.3a precedent
disposition.

Future comparability: if a future verifier with vsim
regenerates the M6.4-INT golden, both M6.3a and M6.4-INT
captures already exist for FFT band-energy comparison.

## 4. Body-axis limit explanation: structurally sound (PASS)

Section 3 makes three independent arguments:

3.1 **Linearity-cancellation**: the post-mix
`phase0_body_filter` cancels in the body_mix sweep ratio
because both disp and body share the same filter path.
This is the M6.4 NO-GO finding which I (and the M6.4
verifier) have independently validated mathematically and
numerically.

3.2 **Systematic ~2.5 dB prediction-vs-measurement gap**
across two consecutive milestones (M6.3a 1-2k predicted
+2.49 dB measured +0.00 dB; M6.4-INT 1-2k predicted
+2.78 dB measured +0.37 dB). I confirmed the M6.4-INT side
of this myself in task-9fd633f8. The same gap in the same
direction across two structurally different FIR designs
strongly suggests the prediction model is missing
something consistent. Section 3.2's diagnosis (waveguide-
resonant `H_disp(f)` dominates band-energy in 1-3 kHz
rather than the body factor) is the most plausible
explanation.

3.3 **No realistic 3-tap retune can close the gap**.
Doubling the actually-realized delta would require a 6+ tap
FIR (more state, more pipeline). That moves out of "tap
retune" territory into a body synthesis path redesign.

Conclusion to close the body-axis acceptance gate is
correct. The scope explicitly does not recommend more
body_mix or body-FIR retunes as the next slice. PASS on
guardrail (no body axis re-engagement without changing the
measurement model).

## 5. Candidate axis comparison: fair (PASS)

Section 4 compares five candidates:

- 4.1 release/damper refinement (RECOMMENDED)
- 4.2 hammer texture / attack shaping (DEFERRED, M2 already covered)
- 4.3 controlled detune / chorus (DEFERRED, polyphony-direction)
- 4.4 per-voice post-waveguide brightness (DEFERRED, conflicts with M2 layers)
- 4.5 alternate body metric (DEFERRED, measurement-infrastructure)

The reasoning is consistent with the macro direction
(voice-quality first, polyphony as support). The deferral
rationales are honest and don't bury risk. PASS.

## 6. M6.5-DAMP slice technical evaluation (CONDITIONAL_PASS)

### 6.1 Architecture sketch

The proposed sketch (parser !D<vvvv> -> damp_mix_runtime
register -> phase0_fixed_control -> voice_damp_mix wire to
all four voices) is correct in shape. However, the actual
RTL is more nuanced than the scope says.

I inspected `phase0_fixed_control.v` lines 200-310:

- `voice_damp_mix_reg` is already a runtime register
  (`reg [15:0]`), not a localparam.
- Line 231 (reset path): `voice_damp_mix_reg <= 16'd16384;`
- Line 264 (note_strobe path): `voice_damp_mix_reg <= 16'd16384;`
  to clear release damping before each new note.
- Line 306 (release_strobe path): `voice_damp_mix_reg <= 16'd32767;`
  to apply heavy damping on `!F` release.

The scope's section 5.1 says "replace the current static
localparam with the runtime value." That's an
oversimplification. The correct change is:

- Add `input wire [15:0] damp_mix_runtime` port to
  `phase0_fixed_control.v`.
- At the reset path (line 231), set
  `voice_damp_mix_reg <= damp_mix_runtime;` (or pull it
  through a registered version of the input).
- At the note_strobe path (line 264), set
  `voice_damp_mix_reg <= damp_mix_runtime;` so each new
  note returns to the runtime-controlled default rather
  than the hard-coded 16384.
- Leave the release_strobe path (line 306) untouched at
  `16'd32767` so `!F` continues to apply heavy damping.

This is a small precision finding for the M6.5-DAMP
implementer task text. The scope's intent is clearly
right, but the section 5.1 sketch and section 6 task text
need this clarification or the implementer might just
rewire the assign and break note/release semantics.

### 6.2 Acoustic semantic direction (POTENTIALLY INVERTED)

The scope's section 5.2 claims:

> "For damp_mix=16384 (current), the loop's high-frequency
> attenuation per cycle is moderate. For damp_mix=0,
> high-frequency content persists; for damp_mix=32767,
> high-frequency content dies almost immediately."

I inspected the actual filter at
`rtl/audio/phase1_reduced_voice.v` lines 387-400:

```
STATE_DAMP_A_SETUP:
  mult_sample <= dl_sample (current loop tap)
  mult_coeff  <= damp_inv_q15 = 32767 - damp_mix_q15
STATE_DAMP_A_FINISH:
  damp_part_a <= dl_sample * damp_inv_q15 / 32768
  mult_sample <= lp_state (previous filter output)
  mult_coeff  <= damp_mix_q15
STATE_DAMP_B_FINISH:
  lp_state    <= damp_part_a + lp_state * damp_mix_q15 / 32768
              =  dl_sample * (32767 - damp_mix)/32768 + lp_state * damp_mix/32768
```

This is a one-pole IIR low-pass with feedback coefficient
`alpha = damp_mix/32767`:

- `lp_state_new = lp_state * alpha + input * (1 - alpha)`

Where the existing release path raises damp_mix to
`16'd32767`, alpha approaches 1.0, so `lp_state_new ~=
lp_state` with no new input. The feedback loop's loop_gain
multiplier eventually decays the steady-state, but the
damp_mix=32767 setting *increases* the lp_state's memory
of past values, which paradoxically holds the tone longer
in the low frequencies where the loop is actually feeding
back.

I am not 100% sure the scope's acoustic prediction
direction is right. The physics may go the other way:
damp_mix=0 (alpha=0) means `lp_state_new = input`, no IIR
memory, full pass-through at all frequencies, max sustain.
damp_mix=32767 (alpha~=1) means `lp_state_new ~= lp_state`,
which holds the previous value and ignores new input, so
the loop's "fresh" content stops being injected and the
loop dies out via the loop_gain attenuation alone.

The existing release path raising damp_mix to 32767 is
consistent with the second interpretation: alpha~=1 stops
new input from refreshing lp_state, so the loop dies down.

Either way, the M6.5-DAMP architecture is sound; the
implementer just needs to verify the actual semantic
direction by simulation/measurement before locking the
verifier task's expected sweep direction. This is a
non-blocking precision finding that the implementer task
should call out explicitly.

### 6.3 Resource / timing / TB-impact analysis (PASS)

- ~+30 to +50 LE estimate is reasonable based on the M6.2
  `!B` precedent (+173 LE for a similar parser+register+
  audio-path slice; M6.5-DAMP is smaller because it
  reuses the existing audio-path wire).
- Setup margin +5.954 ns gives comfortable headroom; the
  parser is in sys_clk domain, no critical path impact
  expected.
- `phase1_reduced_voice_tb` golden remains bit-exact
  because the default damp_mix_runtime value 16'd16384
  matches the current static value used at trigger.
- `phase0_uart_command_tb` needs a `!D` test-case
  addition mirroring the existing `!B` test pattern.
- Other TBs (velocity, body_mix_sat, isolation,
  status_tx) should pass unchanged.

### 6.4 Acceptance gate (CONDITIONAL_PASS pending semantic check)

Predicted +5 dB/s decay-rate swing between `!D0000` and
`!D7FFF` is a reasonable target *if* the semantic
direction is correct. The exact gate value should be
adjusted after the implementer verifies the filter
direction.

## 7. Macro-direction check (PASS)

- Voice quality first: M6.5-DAMP addresses sustain quality.
- Polyphony as support: damp_mix remains a single shared
  register.
- Fixed-function RTL preserved: no CPU/firmware/MMIO/
  register-file revival.
- No JTAG / on-chip strike scheduler.
- M6.3a/M6.4-INT preserved: scope explicitly preserves
  body FIR and body_mix mapping.
- New UART command `!D` is operator/diagnostic, parallel
  to `!B`. Not a final selling point.

## 8. Verdict and recommended next step

**CONDITIONAL_PASS**.

The scope is strategically correct, body-axis closure is
well-argued, M6.4-INT disposition is sensible, candidate
ranking is fair, and M6.5-DAMP slice direction is the
right next voice-quality lever. Two non-blocking precision
findings need to be incorporated into the M6.5-DAMP
implementer task text:

1. **State-machine clarification**: in
   `rtl/control/phase0_fixed_control.v`, replace the
   `16'd16384` literals at the reset path (line 231) and
   the note_strobe path (line 264) with the new
   `damp_mix_runtime` input. Leave the release_strobe path
   (line 306, `16'd32767`) untouched so `!F` continues to
   apply heavy damping.

2. **Filter semantic verification**: the implementer task
   should explicitly require a brief simulation or
   filter-equation check to confirm the direction of
   damp_mix's acoustic effect (longer sustain at high or
   low values?) before the verifier locks the acceptance
   gate's expected sweep direction. The architecture is
   correct either way; only the gate phrasing depends on
   the semantic.

Orchestrator may queue the M6.5-DAMP implementer task as
written in section 6 of the scope, with these two
clarifications appended.
