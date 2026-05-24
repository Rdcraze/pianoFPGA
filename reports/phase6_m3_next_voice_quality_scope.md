# Phase 6 M3 Next Voice-Quality Scope

Date: 2026-05-24
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-f080de76`
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `904d3e2` (Phase 6 M2 velocity-to-brightness PASS)

## TL;DR

**Recommendation: M3 = body-mix preset increase plus body-filter
mid-range retune.** The accepted M2 brilliant layer made
high-velocity strikes brighter and saturation-clean, but the
verifier and listening evidence agree that the next perceptual
weakness is **dryness / lack of body warmth / short decay**. The
lowest-risk, highest-audible-value slice is a small fixed change
to the body coloration: raise `voice_body_mix` from 16'd8192 to
16'd12288 in `phase0_fixed_control.v`, and retune the second
biquad in `phase0_body_filter.v` from a 200 Hz peak to a 1500 Hz
peak so the body filter contributes mid-range presence in addition
to its existing low-shelf bass warmth. No new UART command syntax,
no new biquad stage, no audio path rewrite, no CPU/firmware/MMIO
revival. Four physical voices preserved.

This is **candidate B** from the Phase 6 M0 scope, but in its
"narrower" form: a fixed-coefficient retune rather than a runtime
body-filter knob. The runtime knob is deferred to a later milestone
if the fixed retune leaves listeners wanting more dial-in control.

| M3 (this scope) | M4 (queued, deferred) |
| --- | --- |
| body_mix preset increase + biquad 2 retune (fixed) | runtime body knob via `!B` UART command (if needed) |
| Modify `rtl/control/phase0_fixed_control.v` (1 line) | Or: candidate E loop-loss differential attenuation |
| Modify `rtl/audio/phase0_body_filter.v` (5-6 coefficient values) | Or: audio capture chain noise floor improvement |
| New: `reports/phase6_m3_body_warmth_impl.md` | New: `reports/phase6_m4_*.md` |
| RTL change: small, no new state | LE budget per slice: <= +200 |
| Hardware gate: A/B audible warmth vs M2, no regression on brightness | Hardware gate: feature-specific |

## 1. Live state at the start of M3

Live commit: `904d3e2`. After-M2 reality:

| Metric | Value |
| --- | ---: |
| LE | 4,917 / 10,320 (48%) |
| Combinational | 4,707 |
| Registers | 2,283 |
| M9K / DSP9 / PLL | 5 / 26 / 1 |
| Setup slow-85C `sys_clk_50m` | +4.551 ns |
| Hold slow-85C | +0.432 ns |
| All TNS | 0 |
| Quartus errors / warnings | 0 / 16 |
| Free LE budget | 5,403 (52%) |
| Setup margin above +4.0 ns gate | +0.551 ns |

Setup slack moved from M1.2's +5.431 ns to M2's +4.551 ns; the
biquad multiplier stages in `phase0_body_filter.v` already sit
near the worst path.  **Any M3 slice that lengthens combinational
depth in the audio path is high-risk for slack.**

## 2. Verifier evidence summary

From `reports/phase6_m2_velocity_brightness_validation.md` (M2
PASS):

- M2 produced clear high-velocity brightness improvement (4-7 kHz
  bands ~2x the energy of M1.2 at A5 0x7FFF).
- M2 high-velocity strikes are clean (no mix-bus saturation), an
  unexpected benefit of layer 2's lower total ROM sum.
- Soft-layer regression cells (vel 0x4000) are byte-identical to
  M1.2 in simulation.
- Subjective listening notes: "short decay (waveguide loop_gain
  limit)", "dryness; lacks body warmth", "still short decay".
- Spectral_centroid_hz from the analyzer is unreliable at the
  current SNR; future A/B work should rely on FFT-based band
  comparisons over windowed strike attack regions.
- Setup slack moderate (+4.551 ns).

From `reports/phase6_m1_2_voice_reset_baseline_validation.md` (M1.2
CONDITIONAL PASS, the baseline M2 was measured against):

- Audio capture chain noise floor ~ -18 dBFS Gaussian limits
  low-velocity measurement.
- Cells 2, 5, 8, 9, 11 are the cleanly capturable cells (3
  pitches, 2 velocity layers). M3 should focus its A/B on these.

## 3. Candidate comparison

### B (body coloration)

Two flavors:
- **B1 (recommended)**: fixed retune of body_mix_q15 and biquad 2.
- **B2 (deferred)**: runtime body knob via new UART command.

B1 audible value: **HIGH for dryness/warmth**. The current body
filter is two biquads both centered at 200 Hz: a low-shelf +6 dB
plus a peaking +3 dB. This already adds bass warmth but provides
no mid-range presence. Real pianos have considerable energy in the
1-3 kHz range from soundboard resonance; adding a mid-range
presence peak is the standard way to introduce warmth without
muddying the strike. Combined with raising `voice_body_mix` from
16'd8192 to 16'd12288, the body content's audible contribution
gains ~3 dB.

B1 LE/timing risk: **LOW**. Only the biquad coefficient localparams
change; structure of `phase0_body_filter.v` is unchanged. The fixed
controller change is a 1-line localparam edit. No new state, no
new combinational depth, no new biquad stage.

B1 testability: **GOOD**. The reduced-voice golden TB at velocity
0x4000 will change because the body filter sits in the audio path
and the body_mix multiplier inside the voice now passes more
content; the golden reference will need to be re-snapshotted. The
M2 velocity-layer TB (`phase1_reduced_voice_velocity_tb`) drives
the voice in isolation with the existing body_mix wire, so its
metrics will change too. We need to update both TBs' golden
references rather than expect bit-exactness.

This is the only M3 candidate that touches the existing golden TB.
The decision is intentional: M3 is the first slice that
deliberately changes the audible signature of the soft (layer 0)
voice. The verifier already accepted that the soft layer is
byte-identical to M7 in M2; M3 explicitly breaks that to add
warmth uniformly. The trade-off is acceptable because the soft
layer is currently the weakest audible region.

### E (loop-loss filter shape)

Audible value: **HIGH for short-decay complaint**. Replacing the
simple `damp_mix` lerp with a one-pole low-pass inside the
waveguide loop would let upper harmonics decay faster than the
fundamental, mimicking real piano string behavior and audibly
extending the perceptible musical decay (because the fundamental
+ low harmonics last longer).

LE/timing risk: **MEDIUM-HIGH**. Adds a new pole filter inside the
audio loop where instability is possible. Setup slack +4.551 ns
is moderate; a new IIR section in the voice core could push the
worst path closer to the +4.0 ns gate.

Testability: **HARDER**. Loop-loss instability is hard to bound in
simulation; must run extensive sweeps over loop_gain / damp_mix /
disp_coeff combinations to confirm bounded output for all valid
parameter ranges.

Defer to M4 unless B1 doesn't address the short-decay complaint.

### D (pre-strike noise component)

Audible value: **MEDIUM**. M2 already addressed attack character
with the brilliant layer. Adding noise on top might just add grit.

LE/timing risk: **MEDIUM-HIGH**. New noise generator + envelope
shaper + mix point inside the voice core.

Defer to M4+.

### Audio capture chain noise-floor improvement

Audible value: **NONE for hardware**. Pure measurement infrastructure.

LE/timing risk: **N/A** (host-tool only).

Testability: **HIGH** but unrelated to the user's voice-quality goal.

This is a measurement infrastructure improvement; its value is
unlocking lower-velocity A/B tests later. Defer to a measurement
slice if the verifier reports continued blockers from noise floor;
B1 can be evaluated using the cleanly capturable high-velocity
cells (2, 5, 8, 11) without requiring this fix.

### No-op / defer

Available but not justified. M2 closed a real timbral gap
(brightness); the next-most-audible weakness (dryness / warmth) is
a real open issue with a clear, low-risk path forward. M3 should
proceed.

## 4. M3 recommended slice (B1)

### Files touched

| Path | Change | Lines |
| --- | --- | ---: |
| `rtl/control/phase0_fixed_control.v` | Raise `voice_body_mix` from `16'd8192` to `16'd12288` | 1 line |
| `rtl/audio/phase0_body_filter.v` | Retune biquad 2 from peaking @ 200 Hz +3 dB to peaking @ 1500 Hz +3 dB Q~1.5 | 5 coefficient localparams |
| `rtl/audio/phase1_reduced_voice_tb.v` | Update golden samples / peak reference to reflect new body content. New peak/RMS expected, but loop_len 106 first-nonzero unchanged. | small |
| `rtl/audio/phase1_reduced_voice_velocity_tb.v` | Update peak / early-energy expected ranges (the velocity TB validates inequality, so most assertions still hold; the brilliant-vs-bright margin stays). | small |
| `reports/phase6_m3_body_warmth_impl.md` (new) | M3 implementation report | new |

### Files NOT touched (out of scope)

- `rtl/audio/phase1_reduced_voice.v` (waveguide loop, hammer ROM)
- `rtl/control/phase0_uart_command.v` (no new command)
- `rtl/peripherals/phase0_uart_status_tx.v`
- `rtl/top/piano_phase0_top.v`
- `quartus/phase0/piano_phase0_top.qsf`
- `obsolete/`

### UART command surface

**No change.** The B1 slice uses fixed body coefficients and a
fixed body_mix preset baked into the controller. A runtime knob
(B2) is intentionally deferred.

### Resource and timing budget

| Gate | Target |
| --- | --- |
| LE delta vs M2 (4,917) | <= +50 (target), <= +150 (hard) |
| Setup slack slow-85C `sys_clk_50m` | >= +4.0 ns hard, >= +4.2 ns preferred |
| Hold slack | clean |
| All TNS | 0 |
| M9K | 5 (unchanged) |
| DSP9 | 26 (unchanged) |
| PLL | 1 (unchanged) |
| Quartus errors / warnings | 0 / 16 (unchanged) |

The biquad coefficient retune does NOT change the structure of the
biquad pipeline, so combinational depth is identical to M2. New
coefficients land in the same multiplier path. LE delta should be
near zero; the <= +50 LE target is a safety margin.

Setup slack should remain near M2's +4.551 ns; the biquad path is
identical except for which numeric constants land in the M9-bit
multipliers, which can affect MUX selection in the LUTs but should
not move the worst path significantly.

The body_mix change in the fixed controller is a localparam value
change (8192 -> 12288); it does not even add a register.

### Test plan

1. Re-run `phase1_reduced_voice_tb`. The golden snapshot at
   velocity 0x4000 / loop_len 106 will produce a new
   `peak` value because the audio path now contains more body
   content. Update `peak=3952` to whatever the new value is;
   re-snapshot the 4096 golden samples in
   `phase1_reduced_voice_golden_samples.hex`. Document the new
   peak as the M3 reference.
2. Re-run `phase1_reduced_voice_velocity_tb`. Most assertions are
   inequalities (early_energy monotonic, brilliant > 1.5*soft,
   peak within velocity scaling, no clip) and should still hold.
   The `peak_at_0x4000 == 3952` assertion will need its expected
   value updated to the new M3 peak. The
   `first_nonzero_at_0x4000 == 106` assertion is unchanged.
3. Re-run regression TBs (`phase0_uart_command_tb`,
   `phase0_fixed_control_isolation_tb`,
   `phase0_uart_status_tx_tb`); these are control-path TBs and
   are unaffected.
4. Quartus full compile.
5. Bench-driven A/B capture in isolation mode against the M2 SOF
   on cells 2, 5, 8, 11 (the cleanly capturable high-velocity
   cells from M2 validation). Live A/B compares M3 vs M2 audio
   captures.

### Hardware acceptance criteria

The M3 verifier task should compare M3 captures against the
accepted M2 captures (`reports/phase6_m2_voice_baseline.csv`)
focusing on:

- **Mid-frequency presence**: FFT 1-3 kHz band energy should
  increase by 3-5 dB in M3 vs M2 for the same cell.
- **Bass warmth**: 50-200 Hz band should also increase modestly
  (the existing low-shelf is unchanged but body_mix gain is
  higher).
- **No brightness regression**: 4-7 kHz energy should stay within
  ~1 dB of M2 (M2's brilliant layer's brightness contribution is
  in the voice core, downstream of the body filter, but the
  retuned biquad 2 will dampen some 200 Hz region content; we
  must NOT lose the M2 brightness improvement).
- **No clipping at the audio output**: the increased body_mix
  could push the mix-sum saturator harder; cells that were clean
  in M2 should remain clean. The saturator is in
  `phase0_audio_path.v`'s mix tree (unchanged).
- **Subjective check**: M3 should sound "warmer / fuller / less
  dry" than M2 on cells 2, 5, 8, 11. Cells 9 (vel 0x2000) should
  also gain warmth even if the strike attack remains modest.

### NO-GO triggers

- LE delta > +150.
- Setup slack < +4.0 ns.
- Brightness regression > 2 dB in any 4-7 kHz band on cells 2, 5,
  8, 11.
- New clipping on cells that were clean in M2.
- Listener reports M3 as "muddier" or "boomy" rather than
  "warmer".

## 5. Implementer task text (orchestrator-ready)

> Implement Phase 6 M3 candidate B1: body-mix preset increase plus
> mid-range body-filter retune.
>
> Read first:
> - reports/phase6_m3_next_voice_quality_scope.md
> - reports/phase6_m2_velocity_brightness.md and validation
> - rtl/control/phase0_fixed_control.v (only the body_mix line
>   changes; everything else stays)
> - rtl/audio/phase0_body_filter.v (read full; biquad 2 retunes)
> - rtl/audio/phase1_reduced_voice.v (no change)
>
> Required deliverables:
>
> 1. Modify rtl/control/phase0_fixed_control.v: change the
>    `voice_body_mix` static assignment from `16'd8192` to
>    `16'd12288`. Document the change inline.
>
> 2. Modify rtl/audio/phase0_body_filter.v: retune biquad 2 from
>    a 200 Hz peaking filter (+3 dB Q~1.0) to a 1500 Hz peaking
>    filter (+3 dB Q~1.5). The biquad pipeline structure
>    (saturating multipliers, state registers, sample_tick gating)
>    stays unchanged; only the five Q2.14 coefficients (B2_B0,
>    B2_B1, B2_B2, B2_A1, B2_A2) change. Recompute the coefficients
>    using the standard cookbook formulae for a peaking biquad at
>    Fs=46875 Hz, fc=1500 Hz, Q=1.5, gain=+3 dB. Document the
>    formula and computed coefficients in the new biquad header
>    comment.
>
> 3. Update rtl/audio/phase1_reduced_voice_tb.v (and the golden
>    samples hex if used): re-snapshot the peak and the 4096
>    golden samples at velocity 0x4000 / loop_len 106 to reflect
>    the new body filter and body_mix. Document the new peak and
>    why it changed. The first_nonzero_sample = 106 must remain
>    bit-exact (loop_len pre-roll is unchanged).
>
> 4. Update rtl/audio/phase1_reduced_voice_velocity_tb.v: re-record
>    the per-velocity peak/early/RMS info lines and update the
>    `peak_at_0x4000 == 3952` expected value to the new M3 number.
>    All inequality assertions (early_energy monotonic,
>    brilliant > 1.5*soft, brilliant peak within naive scaling,
>    clip_seen low) should still PASS without modification.
>
> 5. Run regression TBs:
>    - phase0_uart_command_tb (no change expected)
>    - phase0_fixed_control_isolation_tb (no change expected)
>    - phase0_uart_status_tx_tb (no change expected)
>    All three must PASS unchanged.
>
> 6. Run Quartus full compile. Targets:
>    - 0 errors
>    - LE delta vs M2 baseline 4,917 <= +50 target / <= +150 hard
>    - Setup slow-85C sys_clk_50m >= +4.0 ns hard
>    - Hold/TNS clean
>    - M9K 5, DSP9 26, PLL 1 unchanged
>    - Warnings <= 16 cosmetic baseline
>
> 7. New report reports/phase6_m3_body_warmth_impl.md documenting:
>    - Coefficient computation derivation (with cookbook formula)
>    - body_mix delta rationale (8192 -> 12288 is +50% body content)
>    - New peak value and golden re-snapshot rationale
>    - Per-TB output
>    - Quartus resource/timing summary vs M2 baseline
>    - Hardware deferral note: live A/B capture is the verifier's
>      task per project discipline rule
>
> Hard validation gates:
> - No CPU/firmware/MMIO/register-file revival.
> - No new UART command syntax.
> - No new biquad stage (do not add a third biquad to the body
>   filter; only retune biquad 2).
> - No change to phase1_reduced_voice.v's waveguide / hammer ROM.
> - No QSF change.
> - Four physical phase1_reduced_voice instances preserved.
> - ASCII-only on touched files.
> - Do not touch verifier-protected untracked artifacts or
>   .kiro/.
>
> Stop-and-report (NO-GO) triggers:
> - Setup slack falls below +4.0 ns.
> - LE delta exceeds +150.
> - Any audio path TB shows a structural failure (vs the expected
>   golden re-snapshot delta).
>
> Live A/B hardware capture is deferred to the M3 verifier task per
> project discipline rule.
>
> Refs: `task-f080de76` (this scope).

## 6. Verifier task text (orchestrator-ready)

> Validate the implementer's Phase 6 M3 body-warmth slice.
>
> Required:
>
> 1. Read reports/phase6_m3_body_warmth_impl.md and confirm the
>    biquad 2 coefficient computation is correct (independently
>    re-derive at least one coefficient).
> 2. Confirm `git show --stat <commit>` shows only the expected
>    files (controller, body filter, two voice TBs, report); no
>    QSF, no obsolete, no firmware, no parser/status/audio path
>    changes.
> 3. Re-run all four sim TBs:
>    - phase1_reduced_voice_tb at the new golden peak (PASS at the
>      new value)
>    - phase1_reduced_voice_velocity_tb (7 assertions PASS)
>    - phase0_uart_command_tb (no change)
>    - phase0_fixed_control_isolation_tb (no change)
> 4. Re-run Quartus full compile. Confirm 0 errors, LE in budget,
>    setup >= +4.0 ns, all TNS 0.
> 5. Program M3 SOF on hardware. Record SOF sha256.
> 6. Run M2-vs-M3 A/B audio captures:
>    - Use the same isolation-mode original profile that produced
>      reports/phase6_m2_voice_baseline.csv.
>    - Capture cells 2, 5, 8, 9, 11 explicitly.
>    - Compute FFT-based 500 Hz band comparisons for each cell.
> 7. Verify acceptance criteria from M3 scope section 4:
>    - 1-3 kHz band gains 3-5 dB in M3 vs M2 (warmth indicator).
>    - 50-200 Hz band gains modestly.
>    - 4-7 kHz band stays within ~1 dB of M2 (no brightness
>      regression).
>    - No new clipping on cells clean in M2.
>    - Subjective listener report: warmer/fuller, not muddier.
> 8. Submit reports/phase6_m3_body_warmth_validation.md with
>    PASS/CONDITIONAL_PASS/NO-GO verdict and per-cell band table.
>
> If the warmth gain is too small to be subjectively reliable, the
> verifier should note it and recommend an M4 follow-up: either
> raising body_mix further (preserving fixed approach) or moving to
> the runtime body knob (B2).
>
> If the brightness regression is > 1 dB at 4-7 kHz, NO-GO; the
> retuned biquad 2 has stolen too much high content. Recommend a
> revert and a finer-tuned coefficient set.

## 7. Out of scope for this scope task

- No RTL/QSF/scripts edits in this scope task.
- No CPU/firmware/MMIO/register-file revival.
- No polyphony feature work.
- No edits to verifier-protected untracked artifacts or `.kiro/`.

## 8. Honest assessment

This M3 slice is conservative. The strongest argument for it: M2
closed the brightness gap definitively (1.7-2.7x energy gain in
the 4-7 kHz bands), and the verifier's listening notes converge
on "dryness / lack of body warmth / short decay" as the next
single most-audible weakness. The body filter is the most direct
RTL handle for warmth, and a fixed retune is the lowest-risk way
to adjust it without introducing a new UART command or a new
biquad stage.

The weakness of this M3: warmth is harder to measure than
brightness because it lives in the 1-3 kHz band where strikes,
body resonance, and chain noise all overlap. The acceptance
criteria above lean on FFT band comparisons rather than the
analyzer's centroid, which the M2 verifier already noted is
unreliable at this SNR. A second weakness: the soft-layer
golden bit-exact preservation that M2 maintained will explicitly
break in M3, requiring a re-snapshot. The trade-off is
intentional and the implementer report should document the new
golden number clearly.

If the M3 verifier finds the warmth gain unconvincing, M4 should
either:
- continue with B (raise body_mix further or add a runtime knob),
  or
- pivot to candidate E (loop-loss differential decay) for the
  short-decay complaint.

The decision belongs to whichever data path the M3 verifier
captures.

ASCII-only by construction.
