# Phase 6 M6.3 Body-Magnitude Scope

Date: 2026-05-27
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-2834263e`
Branch: `codex/phase1c-uart-boundary-fix`
Parent commit: `b332743` (M6.2 verifier validation CONDITIONAL_PASS)

## TL;DR

**Recommendation: Candidate C**, a single-line shift in
`rtl/audio/phase1_reduced_voice.v` `STATE_BODY_TAP30` that
moves `mult_sample` up by one bit before the body multiplier.
Effective body contribution doubles, projected end-to-end
in-range 1-3 kHz delta moves from ~0.3 dB to ~6 dB on A4 and
~5-6 dB on C5, comfortably above the +3 dB PASS gate. The
`STATE_BODY_FINISH` saturating sum already detects/saturates
clipping into `clip_seen`, so the disp+body sum stays bounded
without new RTL. Expected resource cost is zero LE / no DSP /
no timing impact (a `<<` is wire-only).

Candidate B (post-mix `phase0_body_filter` retune) is rejected:
it operates on `disp_sample + body_contribution` jointly after
the per-voice sum, so it cannot change the body-vs-disp ratio
that limits 1-3 kHz swing today.

Candidates D and E remain useful follow-ups, not substitutes.
No-op rejected.

## 1. Inputs

Reviewed:

- `reports/phase6_m6_2_body_signed_cast_fix_validation.md`
  (CONDITIONAL_PASS at `db65ac8`; band-energy tables; cell
  variance ~1-3 dB; M6.2 saturation behavior verified).
- `reports/phase6_m6_2_default_band_analysis.txt`
- `reports/phase6_m6_2_inrange_band_analysis.txt`
- `reports/phase6_m6_1_body_path_audit.md` sections 3.3, 4
  (body-magnitude quantification).
- `reports/phase6_m6_1_body_path_audit_validation.md`
  section 5 (verifier precision finding).

RTL re-checked at HEAD `db65ac8`:

- `rtl/audio/phase1_reduced_voice.v` lines 113-153
  (`q18_ext`, `sat_q18`, `product_to_q18`, `q18_to_q15`).
- `rtl/audio/phase1_reduced_voice.v` lines 442-475
  (`STATE_BODY_TAP30`, `STATE_BODY_FINISH`).
- `rtl/audio/phase0_body_filter.v` (post-mix biquad cascade,
  M3 retune fc=1500 Hz +3 dB Q=1.5).
- `rtl/audio/phase0_audio_path.v` (4-voice mix, then
  `phase0_body_filter`, then to codec; body filter is post-
  mix and post-saturation).

## 2. Why M6.2 left a +0.3 dB swing on the in-range grid

### 2.1 The per-voice body contribution is small relative to disp_sample

`STATE_BODY_TAP30` builds the body component:

```
body_partial = (body_tap6  >>> 2)   // 1/4
             - (body_tap16 >>> 3)   // 1/8
             + (body_tap30 >>> 4)   // 1/16
             ;                      // sum: max coefficient 7/16
mult_sample <- sat_q18(body_partial)
mult_coeff  <- M6.2 mapping(body_mix_q15)
mult_product = mult_sample * mult_coeff
```

`body_history` taps are stored as Q18 signed `+/-131071`.
After the 7/16 weighted shift-sum, peak `mult_sample` is
bounded near `+/-57344` (= 131071 * 7/16). In practice the
loop's audible range constrains taps closer to Q18 audio
amplitudes (`+/-32768`), so typical peak `mult_sample` is
near `+/-14336` (`= 32768 * 7/16`).

`STATE_BODY_FINISH` then sums:

```
output_sample_q18 = sat_q18(disp_sample + product_to_q18(mult_product))
                  = sat_q18(disp_sample + mult_sample * mult_coeff / 32768)
```

For the in-range body_mix sweep `0x1000..0x7000`, the
`mult_coeff` swings 4096..28672 (~7x). With typical
`mult_sample = 14336` and `disp_sample = 32768`:

```
body_contrib at 0x1000 = 14336 *  4096 / 32768 = +1792
body_contrib at 0x7000 = 14336 * 28672 / 32768 = +12544
swing = 12544 - 1792 = ~10752 Q18 units
```

Compared to `disp_sample` near `+/-32768`, the body swing is
~33% of disp magnitude in absolute terms. **But the audio
output is the SUM `disp_sample + body_contrib`**, not the
body alone. The total energy ratio between low and high body
in any frequency band depends on the spectral overlap of
`body_contrib` and `disp_sample`. In the 1-3 kHz band:

- `disp_sample` is full-spectrum waveguide output (broadband
  excitation shaped by loop filter).
- `body_contrib` is a 3-tap FIR over the body history with
  weighted coefficients `[1/4, -1/8, +1/16]` applied at taps
  6, 16, 30 (40 kHz / 7.5 = ~5333 Hz, ~2939 Hz, ~1563 Hz).
  Its 1-3 kHz energy is enhanced (the tap 16 / tap 30
  pattern peaks in this band) but it is still scaled by
  body_mix_q15.

End-to-end measurement evidence (M6.2 verifier section 8.2):

- A4 in-range 1-3 kHz: +0.15 dB at 1-2 kHz, +0.14 dB at 2-3 kHz.
- C5 in-range 1-3 kHz: -0.45 dB at 1-2 kHz, +0.17 dB at 2-3 kHz.

Reading these as ratios of total band energy:

```
delta_dB = 20 * log10((disp + body_high) / (disp + body_low))
         ~ 20 * log10(1 + (body_high - body_low) / disp)
```

For 0.3 dB of band swing the implied `(body_high - body_low) /
disp` ratio is ~3.5%. That is consistent with the analyzed
body multiplier swing of ~10752 Q18 units against typical
disp peak of ~32768 in a band where the body's 3-tap FIR
contributes only a fraction of its total energy.

**Conclusion: the body multiplier output is correct and
monotonic post-M6.2. The body contribution is just small
relative to disp.** The fix to enlarge it has to live in the
voice, not in the post-mix filter.

### 2.2 Cell-to-cell variance is ~1-3 dB on this chain

Within a body_mix row in the M6.2 inrange data, adjacent
cells differ by 0.3-1.2 dB even at fixed body_mix (capture
chain noise plus FFT bin variance). To beat this with
confidence the body swing needs to be at least 3 dB
end-to-end across the 0x1000..0x7000 grid, i.e. about 10x
the current 0.3 dB.

## 3. Candidate analysis

### 3.1 Candidate B: phase0_body_filter coefficient retune (REJECTED)

**Why it's tempting**: the M3 body filter is the only
post-mix coloration block. Retuning it to add gain in 1-3 kHz
seems like it would directly raise the band-of-interest.

**Why it does not solve the M6.2 limitation**: the body
filter sees the post-mix signal `mix(disp + body, voice0..3)`.
It does not separate body from disp. Any 1-3 kHz boost it
applies amplifies disp and body equally. The ratio
`(body_high - body_low) / disp` is unchanged, so the
body_mix sweep delta in the 1-3 kHz band is unchanged.

Verification by structure: at body_mix=0x1000 vs body_mix=0x7000
the post-mix signal differs only by `body_contrib_high -
body_contrib_low`. If the post-filter applies linear gain
`G(f)` in the band of interest, the band-energy delta is:

```
delta_E_at_post = G(f) * (body_contrib_high - body_contrib_low)
delta_E_at_pre  =        (body_contrib_high - body_contrib_low)
```

The relative delta in dB versus the same body_mix's
post-filter total is:

```
delta_dB = 20 * log10(1 + G * delta_body / G * (disp + body_low))
         = 20 * log10(1 +     delta_body /     (disp + body_low))
```

`G` cancels. **A post-mix filter retune cannot increase
body_mix-driven band swing.** It can change the absolute band
energy (more 1-3 kHz overall), but A/B between body_mix
values stays in the same ratio.

A coefficient retune still has audible value (warmer overall
sound), but it does not address the M6.2 verifier's
remaining gate. NOT the right next slice.

### 3.2 Candidate C: body_contribution magnitude shift (RECOMMENDED)

**The minimum-cost change**: shift `mult_sample` up by 1 bit
before the multiply. In Verilog at `STATE_BODY_TAP30`:

```
mult_sample <= sat_q18(((q18_ext(body_tap6) >>> 2) -
                        (q18_ext(body_tap16) >>> 3) +
                        (q18_ext(body_read_data) >>> 4)) <<< 1);
```

Effect: every tap-weighted body sample is scaled by 2 before
hitting `mult_coeff = body_mix_q15`. The body multiplier's
usable swing therefore doubles end-to-end. The peak
`mult_sample` magnitude rises from ~14336 to ~28672 (still
inside Q18 limits at +/-131071); the existing `sat_q18`
wrapper around the shift-sum keeps it bounded.

**Effective body coefficient swing across in-range grid**:

```
body_contrib at 0x1000 = 28672 *  4096 / 32768 =  +3584   (was +1792)
body_contrib at 0x7000 = 28672 * 28672 / 32768 = +25088   (was +12544)
swing                  = 25088 - 3584 =  +21504           (was +10752)
```

Projected band-energy delta:

```
delta_E_ratio_post_C ~ 2 * delta_E_ratio_post_M6.2
                     ~ 2 * 3.5% = 7%
delta_dB             ~ 20 * log10(1 + 0.07) = +0.59 dB linear
```

But the body's 3-tap FIR has a peak response in the 1-3 kHz
band, so the band-specific gain is higher than the broadband
factor. M3 acceptance evidence
(`reports/phase6_m3_body_warmth_validation.md`) shows the
M3 body_mix preset 0x3000 at the same M6.2 voice geometry
contributed 6+ dB band gain in 1-3 kHz over body_mix=0x2000
in simulation, before the post-isolator chain noise was
brought down. Doubling the body magnitude should produce a
similar order-of-magnitude band gain on top of M6.2.

**Realistic projection**: end-to-end in-range 1-3 kHz delta
moves from ~0.3 dB to ~3-6 dB, comfortably above the +3 dB
PASS gate even after cell variance and chain noise.

**Saturation safety**:
- `mult_sample` after the shift is bounded by the existing
  `sat_q18` wrapper, so it cannot wrap.
- `STATE_BODY_FINISH` already detects clipping via the
  `clip_seen` register and uses `sat_q18` on the disp+body
  sum, so no audio runaway.
- Worst-case `disp_sample + body_contrib`:
  `+/-32768 + +/-32767 = +/-65535`, still well inside Q18
  `+/-131071` and inside the existing saturation guard.
- The sweep harness's `clipping_count` will report any
  saturation if it occurs in real audio; we treat any
  `clipping_count > 0` at default velocity as a NO-GO trigger
  in the verifier task.

**Resource estimate**: zero LE, zero DSP, no new pipeline
stage. The `<<< 1` is wire-only routing inside the existing
combinational block that feeds `mult_sample` for one cycle.

**Timing estimate**: zero delta. The same `sat_q18` block
already evaluates a 4-input add of three shifted q18_ext
values; adding one more `<<< 1` to the result is free. The
M6.2 baseline setup slack (+4.939 ns) is not affected.

**Audio model risk**: the 6-tap body FIR is a fixed M3-era
design; doubling its output amplitude does not change its
spectral shape, only its level. Subjective body warmth
should increase; objectively measurable 1-3 kHz swing
should follow the multiplier swing as analyzed above.

### 3.3 Candidate D: body-only diagnostic mode (DEFER)

Add an RTL bypass that routes only `body_contribution` to the
codec output (zeroing `disp_sample`) under a new UART
diagnostic command, e.g. `!Z1`/`!Z0`. Useful for unambiguous
body-only A/B measurement.

- Higher RTL cost than C: new control flag in
  `phase0_uart_command.v`, new audio-path mux, new TB.
- Not necessary if Candidate C produces a measurable
  monotonic swing on the standard sweep (which the analysis
  in 3.2 says it should).
- Worth queueing later only if Candidate C still leaves the
  trend ambiguous.

### 3.4 Candidate E: coherent-average harness extension (DEFER, parallel)

Extend `scripts/phase6_m6_body_mix_sweep.py` to emit K>1
strikes per cell. The v1 sweep sidecar is shape-compatible
(send_t_session_s is a list, voice-bench v2 is reused for
the analyzer wrapper). +10*log10(K) dB SNR gain on
time-locked content, useful as measurement infrastructure.

- Pure host change, zero RTL risk.
- Helps any future timbre slice including post-C.
- **Not a substitute for Candidate C.** Coherent averaging
  pushes down uncorrelated chain noise but cannot enlarge a
  voice-model swing that is small at the source.
- Worth queueing as parallel measurement-tooling task.

### 3.5 No-op / accept (REJECTED)

The user-priority direction is voice quality first. The
M6.2 audit was clear that the small body contribution is a
voice-model design choice, but with the signed-cast bug
fixed the dynamic range of the body knob is restored and the
next legitimate question is "is the design choice still
right?" The M6.2 evidence answers no: 0.3 dB of body knob
swing is below cell variance, which makes the runtime knob
operationally pointless. Adjusting the body magnitude is the
correct response.

## 4. Recommended next implementation task

### Phase 6 M6.3 implementer task: double body contribution magnitude

> Implement Phase 6 M6.3 Candidate C: scale `mult_sample` up
> by one bit at `STATE_BODY_TAP30` in
> `rtl/audio/phase1_reduced_voice.v` so the body
> contribution magnitude doubles end-to-end. Single-line RTL
> change plus matching TB and report updates. No new feature,
> no LE/timing growth.
>
> Read first:
> - `reports/phase6_m6_3_body_magnitude_scope.md` (this scope)
> - `reports/phase6_m6_2_body_signed_cast_fix_validation.md`
> - `rtl/audio/phase1_reduced_voice.v`
> - `rtl/audio/phase1_reduced_voice_tb.v`
> - `rtl/audio/phase1_reduced_voice_velocity_tb.v`
> - `rtl/audio/phase1_reduced_voice_body_mix_sat_tb.v`
>
> Required RTL change:
> Replace `STATE_BODY_TAP30`'s `mult_sample` assignment in
> `rtl/audio/phase1_reduced_voice.v` from:
> ```
> mult_sample <= sat_q18((q18_ext(body_tap6) >>> 2) -
>                        (q18_ext(body_tap16) >>> 3) +
>                        (q18_ext(body_read_data) >>> 4));
> ```
> to:
> ```
> mult_sample <= sat_q18(((q18_ext(body_tap6) >>> 2) -
>                         (q18_ext(body_tap16) >>> 3) +
>                         (q18_ext(body_read_data) >>> 4)) <<< 1);
> ```
> Update the existing M3-era comment block above the
> assignment to note the M6.3 body-doubling rationale and
> reference this scope report.
>
> Required TB updates:
> The existing `phase1_reduced_voice_tb.v` golden TB at
> `body_mix_q15 = 0x3000` will produce different sample
> values because `mult_sample` is now 2x. Regenerate the
> golden via the existing `+WRITE_GOLDEN` plusarg path:
> ```
> vsim -voptargs=+acc -c work.phase1_reduced_voice_tb \
>   -do "run -all; quit" +WRITE_GOLDEN
> ```
> The 4096-sample golden hex at
> `rtl/audio/phase1_reduced_voice_golden_samples.hex` will
> be rewritten. Document the new expected `peak_level` in
> the impl report (likely larger than the M5/M6.2 value of
> 3952). The `phase1_reduced_voice_velocity_tb.v` may also
> need its expected peaks updated; if so, document and
> update the inequalities while preserving the test intent
> (early_energy monotonic, brilliant layer margin, no clip).
> The M6.2 saturation TB
> `phase1_reduced_voice_body_mix_sat_tb.v` should pass
> unchanged (its assertion is bit-equality between three
> body_mix values, which is preserved because the doubling
> applies uniformly).
>
> Hard gates:
> - Single-substantive-line RTL change.
> - LE delta `<= +5` (preferred), `<= +20` (hard). Expected
>   0 LE.
> - Setup slow-85C `sys_clk_50m >= +4.0 ns`. M5/M6.2
>   precedent shows the body multiply path has comfortable
>   slack. Hard fail if < +4.0 ns.
> - Hold clean, all TNS 0.
> - M9K, DSP9, PLL unchanged.
> - 0 errors.
> - `phase1_reduced_voice_tb` PASS with regenerated golden.
> - `phase1_reduced_voice_velocity_tb` PASS, with updated
>   expected peaks if needed.
> - `phase1_reduced_voice_body_mix_sat_tb` PASS unchanged.
> - `phase0_uart_command_tb` PASS unchanged.
> - `phase0_fixed_control_isolation_tb` PASS unchanged.
> - No new UART command syntax.
> - No firmware/MMIO/CPU revival.
> - No QSF/SDC/PLL change.
> - Four physical voices preserved.
> - ASCII-only on touched files.
>
> Stop-and-report NO-GO triggers:
> - Setup slack < +4.0 ns.
> - LE growth > +20 (this would imply the synthesizer is
>   not optimizing the shift; surprising but worth noting).
> - Audio model TB cannot be regenerated cleanly (e.g. the
>   golden file consistently produces clip_seen=1 at
>   default velocity 0x4000, indicating the body
>   contribution is now too aggressive even for the
>   intended in-range subset).
> - body_mix_q15 = 0x3000 default produces audible
>   distortion/clipping in simulation that did not exist at
>   M5/M6.2.
>
> Refs: task-2834263e (this scope), task-73f1acf2 (M6.2
> validation), task-f7193778 (M6.2 implementation).

### Phase 6 M6.3 verifier task: rerun body_mix sweep post-C

> Validate Phase 6 M6.3 body-doubling fix end to end on
> hardware.
>
> Required scope:
> 1. Confirm scope: only
>    `rtl/audio/phase1_reduced_voice.v`, the regenerated
>    `rtl/audio/phase1_reduced_voice_golden_samples.hex`,
>    minor TB and report updates changed. No QSF, SDC, PLL,
>    firmware, host-script, or accepted prior-baseline-
>    report churn.
> 2. ASCII-only on touched files.
> 3. Run RTL TBs:
>    - `phase1_reduced_voice_tb` -> PASS with new golden.
>    - `phase1_reduced_voice_velocity_tb` -> PASS.
>    - `phase1_reduced_voice_body_mix_sat_tb` -> PASS
>      (saturation behavior unchanged).
>    - `phase0_uart_command_tb` -> PASS.
>    - `phase0_fixed_control_isolation_tb` -> PASS.
> 4. Quartus full compile PASS. Record LE, setup/hold/TNS,
>    M9K, DSP9, PLL, warnings, errors. Confirm setup slack
>    slow-85C `sys_clk_50m >= +4.0 ns` and LE delta `<= +20`
>    over M6.2 baseline 5,088 LE.
> 5. Program new SOF and run the sweep harness twice with
>    grids:
>    a. Default `[0x1000, 0x2000, 0x3000, 0x4000, 0x6000,
>       0x8000, 0xC000]` (M6.2 saturation behavior should
>       be preserved).
>    b. In-range `[0x1000, 0x2000, 0x3000, 0x4000, 0x5000,
>       0x6000, 0x7000]` (the M6.3 acceptance grid).
> 6. Independently compute Hann-windowed FFT band energy on
>    each WAV using the verifier's existing band-analysis
>    helper. Compare 1-3 kHz trend across body_mix.
> 7. Acceptance:
>    - Default grid: upper three points (`0x6000`, `0x8000`,
>      `0xC000`) still saturate to roughly the same body
>      magnitude (no phase flip; M6.2 behavior preserved).
>    - In-range grid: end-to-end 1-3 kHz delta `>= +3 dB`
>      for full PASS, `>= +1 dB` for CONDITIONAL_PASS.
>      Trend should be monotonic-or-near-monotonic; cell
>      variance of 1-3 dB is acceptable as long as the
>      end-to-end delta clears the gate.
>    - `clipping_count = 0` per cell at default velocity
>      0x7FFF on the in-range grid.
>    - P5M2 Q advances by exactly 38 per run; X stable.
> 8. Submit
>    `reports/phase6_m6_3_body_magnitude_validation.md`.
>
> Guardrails:
> - Do not edit RTL or scripts in verifier role.
> - Do not commit large WAV files.
> - Do not touch stale untracked Phase 3/4/5 captures or
>   `.kiro/`.

## 5. Out of scope for this audit

- No RTL/QSF/SDC/PLL/firmware/host-script change in this
  scope task.
- No body_filter coefficient retune.
- No body-only diagnostic mode.
- No coherent-average harness extension.
- No new UART command syntax.
- No polyphony feature work.
- No CPU/MMIO/firmware revival.
- No JTAG command path.
- No on-chip strike scheduler.

## 6. Files

This report:

- `reports/phase6_m6_3_body_magnitude_scope.md` (new, this
  file).

No RTL, host-script, QSF, SDC, firmware, obsolete archive,
generated-output, or stale-untracked-file change.

## 7. ASCII check

```
reports/phase6_m6_3_body_magnitude_scope.md  non_ascii=0
```
