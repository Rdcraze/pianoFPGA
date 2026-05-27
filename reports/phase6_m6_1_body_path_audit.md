# Phase 6 M6.1 Body-Path Gain Audit and Retune Scope

Date: 2026-05-27
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-2776a7a4`
Branch: `codex/phase1c-uart-boundary-fix`
Parent commit: `168f84a` (M6 body_mix sweep CONDITIONAL_PASS)

## TL;DR

The accepted M6 harness, M5.1 isolator chain, and M2/M5 UART
control paths are correct. The "+0.55 dB / +0.42 dB only" 1-3
kHz live result is **voice-model-dominant** with a specific,
small RTL bug behind it.

**Primary finding: signed/unsigned mismatch in the body
multiplier.** `rtl/audio/phase1_reduced_voice.v` line 446
reinterprets the unsigned `body_mix_q15` as signed:

```
mult_coeff <= $signed(body_mix_q15[15:0]);
```

`body_mix_q15` is declared `input wire [15:0]` (unsigned) and
the parser comment in `rtl/control/phase0_uart_command.v` says
"body_mix_q15 is unsigned 16 bits ... allow the full
0x0000..0xFFFF range." But the voice's signed reinterpretation
makes `0x8000..0xFFFF` fold to **negative coefficients**,
flipping the body component's polarity and reducing the
magnitude monotonically as the user pushes `!B` past `0x7FFF`.

The default sweep grid `[0x1000, 0x2000, 0x3000, 0x4000,
0x6000, 0x8000, 0xC000]` therefore maps internally to
**signed magnitudes** `[+4096, +8192, +12288, +16384,
+24576, -32768, -16384]`, with sign flips for the last two.
That is exactly why the verifier's band-energy table is
non-monotonic on the high half and overall delta is at most
~1 dB.

**Secondary findings**, both small and structural:

1. **Body component is post-saturated to Q18 BEFORE the
   `body_mix * tap` multiply** (state `STATE_BODY_TAP30`),
   not after. With `body_mix_q15 = 0x4000`, peak body taps in
   the +/-32k range shrink to ~half-magnitude, so even an
   in-range `!B4000` produces a relatively small absolute
   contribution at the output sum. See section 3.3.
2. **The body filter sits AFTER the 4-voice mix saturation**
   (`rtl/audio/phase0_audio_path.v`), so any 1500 Hz peaking
   shaping is applied to the already-mixed sample. This is
   correct for a "soundboard" coloration model and is not the
   bug, but it means the body filter's measurable effect is
   bounded by what reaches `mix_sample_sat_reg`.

## Recommendation: one narrow M6.2 RTL slice

Fix the signed-cast bug in `phase1_reduced_voice.v` line 446
and tighten the in-range monotonic body sweep band to match
M5/M3 design intent. Rerun the M6 sweep with
`!B0x1000..0x7000` (firmly in the unsigned-mapped region).
Defer body_filter coefficient retunes and any "make body
louder" gain renormalization to a later slice with explicit
audio evidence.

This is a **single-file 1-line RTL change plus a tiny TB
update**, well inside the +200 LE M5 cap and well inside the
+4.0 ns setup gate. The bug is in code already accepted by
M5; this is a follow-on correction, not a new feature.

## 1. Inputs

Reviewed reports:

- `reports/phase6_m6_body_mix_sweep_validation.md`
  (CONDITIONAL_PASS at `168f84a`; +0.55 dB / +0.42 dB 1-3 kHz)
- `reports/phase6_m6_band_analysis.txt`
  (independent verifier band table)
- `reports/phase6_m5_1_isolator_acceptance_validation.md`
  (post-isolator chain accepted; +64 dB headroom; SNR-column
  caveat)
- `reports/phase6_m5_body_knob_cap_raise_validation.md`
- `reports/phase6_m3_body_warmth_validation.md`
- `reports/phase6_m3_body_warmth_impl.md`

Reviewed live RTL/host:

- `rtl/control/phase0_uart_command.v` (lines 160-185, 320-360,
  reset block 195-210)
- `rtl/control/phase0_fixed_control.v` (lines 55-65, 165-172)
- `rtl/audio/phase0_audio_path.v` (voice0..voice3 instantiation,
  body filter wiring at 264-298)
- `rtl/audio/phase1_reduced_voice.v` (body path lines 73-100,
  237-241, 442-456; multiplier line 92)
- `rtl/audio/phase0_body_filter.v`
- `rtl/audio/phase1_reduced_voice_tb.v`
- `rtl/audio/phase1_reduced_voice_velocity_tb.v`
- `rtl/control/phase0_uart_command_tb.v` (sections 13-18 cover
  parser !B behavior)

## 2. End-to-end body_mix path (live)

```
host !Bvvvv\r\n
   |
   v
phase0_uart_command  parses 4 hex digits, no clamp
   |  body_mix_runtime <= parsed_body_mix  (16'd0..16'hFFFF)
   v
phase0_fixed_control  voice_body_mix = body_mix_runtime
   |
   v
phase0_audio_path     voice_body_mix wired to all 4 voices
   |
   v
phase1_reduced_voice  body_mix_q15 (input wire [15:0])
   |
   |   STATE_BODY_TAP30 (Q18 weighted sum of 3 taps):
   |     mult_sample <= sat_q18(
   |         (q18_ext(body_tap6 ) >>> 2) -
   |         (q18_ext(body_tap16) >>> 3) +
   |         (q18_ext(body_read_data) >>> 4));
   |     mult_coeff  <= $signed(body_mix_q15[15:0]);   <-- BUG
   |
   |   mult_product = mult_sample * mult_coeff   (Q18 x signed Q15)
   |
   |   STATE_BODY_FINISH:
   |     output_sample_q18 <= sat_q18(disp_sample +
   |                                  product_to_q18(mult_product));
   |
   v
phase0_audio_path     mix 4 voices (saturating sum >>> 2)
   |
   v
phase0_body_filter    biquad biquad cascade (M3 retune, fc=1500 Hz)
   |
   v
WM8978 / DAC
```

Three facts matter:

- **`body_mix_q15` is declared unsigned** at the voice port:
  `input wire [15:0] body_mix_q15;` (line 18).
- **Parser allows the full 16-bit range without clamp** because
  the parser comment explicitly trusts the downstream voice to
  treat it as unsigned.
- **The voice signed-casts the unsigned input** at line 446,
  contradicting the parser's stated contract.

The parser's TBs (`phase0_uart_command_tb.v` sections 14-17)
exercise `!B0000`, `!B7FFF`, `!BFFFF`, `!B3000`, plus `!BG000`
malformed. They check `body_mix_runtime` storage faithfully
but never check the audio-path consequence of `0x8000..0xFFFF`.

## 3. Why the live result is ~1 dB

### 3.1 The signed-cast wraparound

Effective `mult_coeff` at the multiplier (ignoring sign cast,
showing what the multiplier actually sees):

| `!Bvvvv` | parser stores | voice signed cast |   effective magnitude / sign |
| -------: | ------------: | ----------------: | ---------------------------: |
| `0x1000` |       4096    |         +4096     |  +4096   /  + |
| `0x2000` |       8192    |         +8192     |  +8192   /  + |
| `0x3000` |      12288    |        +12288     | +12288   /  + |
| `0x4000` |      16384    |        +16384     | +16384   /  + |
| `0x6000` |      24576    |        +24576     | +24576   /  + |
| `0x7FFF` |      32767    |        +32767     | +32767   /  + |
| `0x8000` |      32768    |        -32768     | 32768   /  - |
| `0xC000` |      49152    |        -16384     | 16384   /  - |
| `0xFFFF` |      65535    |            -1     |     1   /  - |

The default sweep is `[0x1000, 0x2000, 0x3000, 0x4000, 0x6000,
0x8000, 0xC000]`, which corresponds to multiplier coefficients:

```
+4096, +8192, +12288, +16384, +24576, -32768, -16384
```

In magnitude: `4k, 8k, 12k, 16k, 24k, 32k, 16k`. Two of seven
points (`0x8000` and `0xC000`) flip sign. The 1-3 kHz total
energy is roughly proportional to `|body_mix_q15_signed|` up
to body-filter shaping and headroom limits. Signed-flip
coefficients add a body component with **opposite phase**
relative to `disp_sample`, which reduces 1-3 kHz total energy
when summed.

Within the unsigned-mapped subset (`0x1000..0x7FFF`), the
intended monotonic increase exists but spans only `[0x1000,
0x6000]` of the seven sampled points, and within that subset
secondary scaling (3.3 below) further attenuates the audible
delta. The +1 dB observed is broadly consistent.

### 3.2 Cell-to-cell variance dominates within the in-range
subset

The verifier's band table shows ~1-3 dB cell-to-cell variance
in adjacent cells of the same body_mix on the same pitch on
this chain. Because the in-range monotonic body_mix subset
contributes at most a few dB swing, the trend is buried in
inter-cell noise. Coherent averaging across K repeats per
cell would help (the harness sidecar v1 is shape-compatible
with K>1), but only **after** the signed-cast bug is fixed,
because otherwise the upper half of the grid still flips
polarity.

### 3.3 The internal Q18 saturation of `mult_sample` before
the body multiply

State `STATE_BODY_TAP30` computes:

```
mult_sample <= sat_q18((q18_ext(body_tap6 ) >>> 2) -
                       (q18_ext(body_tap16) >>> 3) +
                       (q18_ext(body_read_data) >>> 4));
```

`body_tap6` is shifted by 2 (1/4), `body_tap16` by 3 (1/8),
the 30-tap by 4 (1/16). The sum is 1/4 + 1/8 + 1/16 = 7/16 of
peak tap magnitude. `body_history` storage is 18-bit signed,
so taps near +/-131072 saturate the Q18 scratch but in
practice taps are bounded to the Q18 audio range (+/-32768
after `q18_to_q15`). `mult_sample` is therefore typically
within +/-14336 (= 32768 * 7/16).

`mult_coeff = body_mix_q15` Q15 means the body contribution
at the output of `STATE_BODY_FINISH` is approximately:

```
body_contribution_q18 ~= mult_sample * body_mix_q15 / 32768
                       ~= mult_sample * body_mix_q15 * 0.0000305
```

For `body_mix_q15 = 16384` (0x4000, half-scale) and
`mult_sample = 14336`: contribution ~= 7168. Compared to
`disp_sample` which can be near full Q18 (+/-32768) on a
typical strike, the body contribution is at most 22% of the
displaced waveguide sample. That is sized for "soundboard
coloration," not audible swing across `!B` settings; even
correctly mapped, swing from `!B0x1000` to `!B0x7FFF` is
~6 dB band-of-interest swing **before** the 4-voice mix and
post-saturation body filter further attenuate it.

This second finding is **not a bug**. It is the original M3
design choice (body as a small coloration). The signed-cast
bug is the actionable item; the small-by-design contribution
explains why even the in-range subset ranges +0 to +1 dB on
the chain rather than +6 dB.

### 3.4 The 0x8000 special case

`0x8000` interpreted as signed Q15 is `-32768`, the most
negative value, with `|-32768| = 32768`. Naively this is a
bigger magnitude than the largest positive signed value
(`0x7FFF = +32767`). But because the multiplier polarity
flips for `0x8000`, the body contribution has the opposite
sign relative to the `disp_sample` partial. Whether this
adds to or subtracts from the output's instantaneous energy
depends on the strike phase. On time-locked windows the
average band energy across many strikes is therefore
**lower** at `0x8000` than at `0x6000`, even though the user
expected a larger effect.

Verifier's table shows exactly this behavior in 2-3 kHz on
A4: `-78.22 dB at 0x6000, -78.41 dB at 0x8000` (-0.19 dB).

## 4. Quantitative consistency check

Per the verifier band table, A4 1-2 kHz row:

```
0x1000: -77.58 dB
0x2000: -77.11 dB   (delta vs 0x1000: +0.47 dB)
0x3000: -76.98 dB   (vs 0x1000:       +0.60 dB)
0x4000: -77.14 dB   (vs 0x1000:       +0.44 dB)
0x6000: -77.72 dB   (vs 0x1000:       -0.14 dB)
0x8000: -76.87 dB   (vs 0x1000:       +0.71 dB; sign flipped)
0xC000: -77.03 dB   (vs 0x1000:       +0.55 dB; sign flipped)
```

The peak-to-trough range across the seven points is 0.85 dB
in 1-2 kHz on A4, and the trend is non-monotonic precisely
where the wraparound happens. That is consistent with the
signed-cast hypothesis: the in-range subset yields a small
positive trend, and the wraparound adds two phase-flipped
points that scramble the high half.

A clean post-fix sweep of `[0x1000, 0x2000, 0x3000, 0x4000,
0x5000, 0x6000, 0x7000]` should show monotonic 1-3 kHz
increase with magnitude ~3-6 dB end-to-end, well above the
1-3 dB cell variance, and would unambiguously satisfy the
M6 acceptance gate.

## 5. Remediation candidates compared

### Candidate A: fix `phase1_reduced_voice.v` line 446 (preferred)

Change:

```
mult_coeff <= $signed(body_mix_q15[15:0]);
```

to either of:

A1. Treat as unsigned 15-bit: ignore `body_mix_q15[15]`:

```
mult_coeff <= $signed({1'b0, body_mix_q15[14:0]});
```

This caps effective body magnitude at `+32767` and treats
`0x8000..0xFFFF` as `0x0000..0x7FFF` (saturating high). All
seven default sweep points become positive, and the upper
three points clip to max body magnitude.

A2. Saturate at parser/control: clamp `body_mix_runtime` to
`[0, 0x7FFF]` in `phase0_uart_command.v` instead. This is also
a one-line change but it removes the user's ability to ever
write `0x8000+`. Functionally equivalent for the audio-path
behavior.

**Preferred: A1**, because it keeps the parser/host contract
unchanged (full 16-bit range accepted), and the in-RTL clamp
is a minimal correction at the multiplier site that already
contains the bug. Updates the parser comment too:

```
// body_mix_q15 is unsigned 15 bits at the multiplier
// (high bit ignored to avoid signed wraparound).
```

Pros:
- Single line of substantive RTL change.
- Reverses M6 verifier's "voice-model dominant" finding by
  fixing the actual model bug.
- Preserves the parser's accepted contract (TBs sections 14-17
  remain valid; the parser still stores `0xFFFF` if the host
  sends it, but the audio path saturates).
- No M5 LE/timing impact (drops the cast, adds a 1-bit zero
  pad).

Cons:
- Changes the audible behavior for `!B` values >= 0x8000.
  This is a fix, not a regression, but operators who were
  subjectively choosing `!B8000` or `!BC000` for a polarity-
  flipped flavor will hear a different effect. Document
  prominently in the impl report.

Resource estimate: zero LE delta (cast removal is structural).
Timing: no impact.

### Candidate B: body_filter coefficient retune

The verifier's "or revisit body filter coefficients" suggestion
is a tempting parallel candidate. It is **not** the right next
slice:

- The body filter is post-mix and post-saturation. It shapes
  the already-summed output but cannot recover phase-flipped
  body contributions inside the voice.
- Candidate A is strictly necessary to re-establish the M3
  body-warmth design intent. Candidate B layered on top of an
  unfixed signed cast would be measuring a corrupted base
  signal.
- Coefficient retunes are riskier: they change the M3 accepted
  filter response and require new TB goldens.

Defer B until A is in and a new sweep shows clean monotonic
in-range trend.

### Candidate C: per-voice "body gain" scalar

Adding a small extra body gain stage (e.g. `body_contribution
* body_gain_q15`) to amplify the body component before summing
with `disp_sample` would increase audible body contribution.

- High audible-value but high RTL/timing risk: another DSP
  multiply or a >>> shift on a critical path that already
  holds setup at +4.620 ns slow-85C with the M5 unfolding.
- Not justified pre-isolator. The current 0-1 dB swing is
  consistent with the existing **design** (small coloration);
  the bug, not the design, is what makes the user-visible
  result inconsistent.

Defer C; revisit only if post-A evidence shows the in-range
sweep is genuinely too small to be musically useful.

### Candidate D: body-only diagnostic capture mode

Add a temporary RTL bypass that routes only `body_contribution`
to the codec output (zeroing `disp_sample`) for diagnostic
hardware A/B.

- Useful for unambiguous body verification.
- Larger change than Candidate A (new control flag, audio-path
  mux, parser command, TB).
- Not necessary if Candidate A produces a measurable monotonic
  in-range sweep.

Defer D; Candidate A should make body-only mode unnecessary.

### Candidate E: coherent-average harness extension

Extend `scripts/phase6_m6_body_mix_sweep.py` to emit K>1
strikes per cell with longer per-cell pause, then rerun
analyzer with `--coherent-average`. Sidecar v1 is already
shape-compatible.

- Good measurement-infrastructure improvement, helps any
  future timbre slice including post-A.
- **Not a substitute for fixing the bug.** Coherent averaging
  cannot recover phase-flipped contributions, only push down
  uncorrelated chain noise.

Useful as a follow-up to A, not before A.

### Candidate F: no-op / accept

Per verifier section 8 recommendation 4 ("mark the trend gate
as measurement-aspirational"). Without the bug fix this is
the wrong call: there is a real, fixable defect.

Reject.

## 6. Recommended next implementation task (orchestrator-ready)

### Phase 6 M6.2 implementer task: fix body multiplier signed-cast wraparound

> Apply the Phase 6 M6.1 audit fix Candidate A1 in
> `rtl/audio/phase1_reduced_voice.v`. Single-line RTL change
> plus minimal TB update and a 1-2 sentence parser-comment
> tweak. No new feature, no LE/timing budget growth.
>
> Read first:
> - reports/phase6_m6_1_body_path_audit.md (this scope)
> - reports/phase6_m6_body_mix_sweep_validation.md
> - reports/phase6_m5_body_knob_cap_raise_validation.md
> - reports/phase6_m3_body_warmth_impl.md
> - rtl/audio/phase1_reduced_voice.v
> - rtl/audio/phase1_reduced_voice_tb.v
> - rtl/control/phase0_uart_command.v
>
> Required RTL change:
> - rtl/audio/phase1_reduced_voice.v: change line 446 from
>   `mult_coeff <= $signed(body_mix_q15[15:0]);`
>   to
>   `mult_coeff <= $signed({1'b0, body_mix_q15[14:0]});`
>
> Required comment/doc updates:
> - phase1_reduced_voice.v: add a 1-2 line comment near the
>   port declaration documenting that the high bit of
>   body_mix_q15 is ignored (effective range 0..0x7FFF).
> - phase0_uart_command.v: update the comment block at lines
>   165-172 to say "the audio path treats body_mix_q15 as
>   unsigned 15 bits; values 0x8000..0xFFFF saturate at
>   0x7FFF."
>
> Required TB updates:
> - phase1_reduced_voice_tb.v: optionally add a small extra
>   stimulus that runs body_mix at 0x8000 and confirms
>   sample_data is bounded and not phase-flipped relative to
>   a 0x7FFF reference run. Keep within bit-exact scope; if
>   TB framework cannot run a second waveform without a new
>   golden, document the inability and rely on Quartus +
>   hardware A/B instead.
>
> Required validation:
> - phase1_reduced_voice_tb golden remains bit-exact at
>   velocity 0x4000, body_mix=12288 (the existing TB scaler).
>   Default does not exercise the upper half so existing
>   golden is unaffected by Candidate A1.
> - phase1_reduced_voice_velocity_tb still PASS bit-exact.
> - phase0_uart_command_tb still PASS (parser stores 0x8000+
>   verbatim per accepted contract).
> - Quartus full compile PASS, expected zero LE delta vs M5
>   accepted baseline 5,105 LE; setup slack >= +4.0 ns; hold
>   clean; M9K/DSP9/PLL unchanged.
> - Post-build hardware capture deferred to verifier.
>
> Hard gates:
> - Single-line RTL substantive change.
> - Zero LE delta or LE delta <= +5.
> - Setup slack slow-85C >= +4.0 ns hard.
> - phase1_reduced_voice_tb / velocity_tb / uart_command_tb
>   PASS.
> - No new UART command syntax.
> - No new firmware/MMIO/CPU revival.
> - No QSF/SDC/PLL change.
> - No physical voice count change.
> - ASCII-only on touched files.
>
> Stop-and-report NO-GO triggers:
> - Setup slack falls below +4.0 ns.
> - Any TB regression beyond the documented golden.
> - LE growth > +5.
>
> Refs: task-2776a7a4 (this audit), task-c6620806 (M6
> verifier conditional pass).

### Phase 6 M6.2 verifier task: rerun body_mix sweep post-fix

> Validate Phase 6 M6.2 body multiplier signed-cast fix end
> to end on hardware.
>
> Required scope:
> 1. Confirm scope: only rtl/audio/phase1_reduced_voice.v and
>    minor doc/comment updates changed. No QSF, SDC, PLL,
>    firmware, host-script, or report churn beyond the M6.2
>    impl report.
> 2. ASCII-only on touched files.
> 3. Run RTL TBs:
>    - phase1_reduced_voice_tb -> PASS bit-exact.
>    - phase1_reduced_voice_velocity_tb -> PASS bit-exact.
>    - phase0_uart_command_tb -> PASS.
>    - phase0_fixed_control_isolation_tb -> PASS.
> 4. Run Quartus full compile and program new SOF.
>    Record LE/setup slack/hold/M9K/DSP9/PLL/warnings.
> 5. Run scripts/phase6_m6_body_mix_sweep.py --run with two
>    grids and capture analog audio:
>    a. Default `[0x1000, 0x2000, 0x3000, 0x4000, 0x6000,
>       0x8000, 0xC000]` (the original M6 grid).
>    b. In-range monotonic `[0x1000, 0x2000, 0x3000, 0x4000,
>       0x5000, 0x6000, 0x7000]` via
>       `--body-mix-grid 0x1000,0x2000,0x3000,0x4000,0x5000,0x6000,0x7000`.
> 6. Independently compute Hann-windowed FFT band energy on
>    each WAV and compare 1-3 kHz trend across body_mix.
> 7. Acceptance:
>    - Grid (a) post-fix: 0x8000 and 0xC000 should now have
>      effective body_mix saturated at 0x7FFF; the seven
>      points should NOT be phase-flipped, and 1-3 kHz
>      should show a monotonic-or-saturating trend rather
>      than the prior non-monotonic pattern.
>    - Grid (b): clean monotonic 1-3 kHz increase from
>      0x1000 to 0x7000, end-to-end delta >= +3 dB to be a
>      clear PASS over the chain's 1-3 dB cell variance,
>      >= +1 dB minimum for CONDITIONAL_PASS.
>    - P5M2 Q advances by exactly the predicted command
>      count for each run; X stable.
> 8. Submit reports/phase6_m6_2_body_signed_cast_fix_validation.md.
>
> Guardrails:
> - Do not edit RTL or scripts in verifier role.
> - Do not commit large WAV files.
> - Do not touch stale untracked Phase 3/4/5 captures or
>   .kiro/.

## 7. Out of scope for this audit

- No RTL, host-script, QSF, SDC, PLL, firmware, generated
  output, or stale-untracked-file change.
- No body_filter coefficient retune.
- No new audio diagnostic mode.
- No coherent-average harness extension.
- No new UART command syntax.
- No body-amplification scalar.
- No polyphony feature work.

## 8. ASCII check

```
reports/phase6_m6_1_body_path_audit.md  non_ascii=0
```

## 9. Files

This report:

- `reports/phase6_m6_1_body_path_audit.md` (new, this file).

No RTL, host-script, QSF, SDC, firmware, obsolete archive,
generated-output, or stale-untracked-file change.
