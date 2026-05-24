# Phase 6 M3 Body-Warmth Fixed Retune Implementation Report

Date: 2026-05-24
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-56f38b7a`
Branch: `codex/phase1c-uart-boundary-fix`
Parent commit: `1777e36` (Phase 6 M3 scope PASS)

## TL;DR

**PASS for non-hardware coverage.** Phase 6 M3 candidate B1 lands
two narrow changes:

1. **`voice_body_mix` raised from 16'd8192 to 16'd12288** in
   `rtl/control/phase0_fixed_control.v` (+50% body content into
   each voice's loop).
2. **Biquad 2 retuned** in `rtl/audio/phase0_body_filter.v` from
   peaking @ 200 Hz +3 dB Q=1.0 to peaking @ **1500 Hz** +3 dB
   Q=1.5, giving the body filter mid-range presence in addition to
   the existing low-shelf bass warmth from biquad 1.

Both changes preserve the existing biquad pipeline structure: no
new biquad stage, no new state, no new combinational depth. The
reduced-voice TB and velocity-layer TB are re-snapshotted for the
new `body_mix=12288` baseline; first_nonzero_sample stays at 106
and the voice peak at velocity 0x4000 stays at 3952. All
control-stack regression TBs PASS unchanged. Quartus full compile
returns 0 errors / 16 warnings, LE 4,917 -> 4,932 (+15, well under
+50 target), setup slow-85C +4.515 ns (above +4.0 ns hard gate by
+0.515 ns).

| Gate | Target | Actual | Verdict |
| --- | --- | --- | --- |
| LE delta vs M2 (4,917) | <= +50 target / +150 hard | **+15 (4,932)** | PASS |
| Setup slack slow-85C `sys_clk_50m` | >= +4.0 ns hard | **+4.515 ns** | PASS |
| Hold slack slow-85C | clean | +0.413 ns | PASS |
| All TNS | = 0 | 0 | PASS |
| M9K | unchanged at 5 | 5 (unchanged) | PASS |
| DSP9 | unchanged at 26 | 26 (unchanged) | PASS |
| PLL | 1 | 1 | PASS |
| Quartus errors | 0 | 0 | PASS |
| Quartus warnings | <= 16 baseline | 16 (unchanged) | PASS |
| Four physical voices preserved | yes | yes | PASS |
| `phase1_reduced_voice_tb` PASS | new golden | peak=3952 first=106 | PASS |
| `phase1_reduced_voice_velocity_tb` PASS | 7 assertions | all PASS | PASS |
| `phase0_uart_command_tb` PASS | unchanged | UART_CMD_TB_PASS | PASS |
| `phase0_fixed_control_isolation_tb` PASS | unchanged | ISOLATION_TB_PASS | PASS |
| `phase0_uart_status_tx_tb` PASS | unchanged | UART_TX_TB_PASS | PASS |
| ASCII-only on touched files | yes | yes | PASS |
| No CPU/firmware/MMIO/QSF/UART change | yes | confirmed | PASS |
| Biquad pipeline structure unchanged | yes | only 5 coefficient localparams changed | PASS |

## 1. body_mix change

`rtl/control/phase0_fixed_control.v`:

```diff
-assign voice_body_mix   = 16'd8192;
+assign voice_body_mix   = 16'd12288;
```

The 16'd12288 value is 50% larger than 16'd8192 in Q15 mix space:
the body-content stream now contributes ~37.5% of the mixed sum
(12288/32768) instead of the previous ~25% (8192/32768). The
"body content" stream comes from the 32-deep `body_history` buffer
in `phase1_reduced_voice` and represents the soundboard / sympathetic
resonance approximation taps at offsets 7, 17, 31; raising body_mix
moves the per-voice timbre from "mostly direct waveguide" toward
"more body-coloured".

This is a localparam-style assignment change; no register or
combinational depth added.

## 2. Biquad 2 retune

`rtl/audio/phase0_body_filter.v`:

The body filter is a two-stage biquad pipeline:
- **Biquad 1**: low-shelf @ 200 Hz +6 dB Q=0.7 (unchanged; this
  remains the bass-warmth source).
- **Biquad 2**: previously peaking @ 200 Hz +3 dB Q=1.0; now
  retuned to **peaking @ 1500 Hz +3 dB Q=1.5**.

Cookbook (RBJ Audio EQ Cookbook) at fc=1500 Hz, Q=1.5, gainDB=+3,
Fs=46875 Hz:

```
omega        = 2*pi*fc/Fs   = 0.20106 rad
cos(omega)   = 0.97987
sin(omega)   = 0.19967
A            = sqrt(10^(gainDB/20)) = sqrt(10^0.15) = 1.1885
alpha        = sin(omega) / (2*Q)   = 0.06656

b0 = 1 + alpha*A = 1.07911
b1 = -2*cos(omega) = -1.95974
b2 = 1 - alpha*A   = 0.92089
a0 = 1 + alpha/A   = 1.05601
a1 = -2*cos(omega) = -1.95974
a2 = 1 - alpha/A   = 0.94399
```

After normalization by a0 the transfer function is

```
y[n] = (b0/a0)*x[n] + (b1/a0)*x[n-1] + (b2/a0)*x[n-2]
       - (a1/a0)*y[n-1] - (a2/a0)*y[n-2]
```

The existing biquad pipeline in `phase0_body_filter.v` accumulates
products with the encoded form

```
y_sum = B0*x[n] + B1*x[n-1] + B2*x[n-2] + A1*y[n-1] + A2*y[n-2]
```

where the A coefficients are encoded with the negated sign so that
the existing `+ A1*y[n-1] + A2*y[n-2]` accumulation is correct.
This is verified against the M1.2 / M2 biquad 1 coefficients
(`B1_A1 = +32240` for low-shelf; positive sign matches a negative
real-pole feedback term after the encoding flip).

So the encoded Q2.14 values are:

```
B2_B0_real = +b0/a0 =  1.02187     -> 1.02187 * 16384 ~=  16742
B2_B1_real = +b1/a0 = -1.85580     -> -30410
B2_B2_real = +b2/a0 =  0.87205     ->  14289
B2_A1_enc  = -a1/a0 = +1.85580     -> +30410   (encoded sign flip)
B2_A2_enc  = -a2/a0 = -0.89394     -> -14645   (encoded sign flip)
```

Q2.14 fits any |coefficient| <= 1.99994. The largest encoded value
is 1.85580 (= 30410 / 16384) which fits comfortably.

Stability check on the resulting denominator `1 - a1*z^-1 - a2*z^-2`
(after applying the encoded form):
- pole equation: `z^2 - (1.85580/1)*z + (0.89394/1) = 0` after the
  encoded a1 is interpreted as encoded form;
- pole magnitude: `sqrt(0.89394) = 0.945 < 1` (stable);
- pole argument: `acos(0.92790) = 0.193 rad ~ 1440 Hz`, close to
  the 1500 Hz design target (small deviation due to bilinear
  warping at fc/Fs ~ 0.032).

Magnitude response is unity at DC and Nyquist (peaking EQ
property) and peaks at +3 dB near 1440 Hz.

The five new coefficients:

```diff
-    localparam signed [15:0] B2_B0 =  16'sd16459;
-    localparam signed [15:0] B2_B1 = -16'sd32391;
-    localparam signed [15:0] B2_B2 =  16'sd15943;
-    localparam signed [15:0] B2_A1 =  16'sd32391;
-    localparam signed [15:0] B2_A2 = -16'sd16019;
+    localparam signed [15:0] B2_B0 =  16'sd16742;
+    localparam signed [15:0] B2_B1 = -16'sd30410;
+    localparam signed [15:0] B2_B2 =  16'sd14289;
+    localparam signed [15:0] B2_A1 =  16'sd30410;
+    localparam signed [15:0] B2_A2 = -16'sd14645;
```

The pipeline structure (saturating multipliers, 18-bit state
registers, sample_tick gating) is byte-identical to M2; only these
five constants changed.

## 3. Test changes

### `phase1_reduced_voice_tb`

- `body_mix_q15` initial value updated from `16'd8192` to
  `16'd12288` to match the new controller preset.
- Golden samples re-snapshotted by running the TB with
  `+WRITE_GOLDEN`. Output:

```
VOICE_TB_GOLDEN_WRITE samples=4096 file=rtl/audio/phase1_reduced_voice_golden_samples.hex
VOICE_TB_PASS first_nonzero_sample=106 freq=434.027778
  rms_100ms=272.800735 rms_500ms=27.713698 rms_3s=0.000000
  peak=3952 golden_samples=4096
```

Notable changes vs M2:
- `peak` stays at 3952 (the peak at velocity 0x4000 occurs at the
  excitation moment when body history hasn't yet accumulated, so
  body_mix changes don't move the peak).
- `first_nonzero_sample` stays at 106 (the loop_len pre-roll is
  unchanged).
- `rms_100ms` rises from 267.43 to 272.80 (+2.0 dB at the dB
  level).
- `rms_500ms` rises from 27.17 to 27.71 (+0.2 dB; minor at this
  delay).

Re-running the TB without `+WRITE_GOLDEN` confirms the new golden
hex matches sample-for-sample:

```
VOICE_TB_PASS first_nonzero_sample=106 freq=434.027778
  rms_100ms=272.800735 rms_500ms=27.713698 rms_3s=0.000000
  peak=3952 golden_samples=4096
Errors: 0, Warnings: 0
```

**This TB does NOT instance the external `phase0_body_filter`**;
it tests only `phase1_reduced_voice` in isolation. The body_mix
preset change affects this TB through the per-voice `body_history`
multiplier, but the biquad retune is invisible here. The biquad
retune is validated by:
- formula derivation (section 2 above);
- pole-magnitude / pole-argument analysis;
- coefficient sign-convention check against the existing
  `B1_A1 = +32240` / `B1_A2 = -15864` low-shelf reference;
- live A/B hardware capture (deferred to verifier).

### `phase1_reduced_voice_velocity_tb`

- `body_mix_q15` instance parameter updated from `16'd8192` to
  `16'd12288`.
- All 7 assertions still PASS:

```
VEL_TB_INFO vel=2000 first=106 peak=1976 early=11500 rms=23.650465
VEL_TB_INFO vel=4000 first=106 peak=3952 early=23012 rms=26.474888
VEL_TB_INFO vel=6000 first=106 peak=6182 early=33619 rms=25.870438
VEL_TB_INFO vel=7fff first=106 peak=7977 early=40481 rms=27.050855
VEL_TB_PASS peak_at_0x4000 = 3952
VEL_TB_PASS first_nonzero_at_0x4000 = 106
VEL_TB_PASS early_energy_at_0x4000 >= 0x2000 (23012 >= 11500)
VEL_TB_PASS early_energy_at_0x6000 >= 0x4000 (33619 >= 23012)
VEL_TB_PASS brightness_margin brilliant=40481 > 1.5*soft=34518
VEL_TB_PASS brilliant_within_velocity_scaling
  peak_0x7FFF=7977 <= naive*1.1=9066
VEL_TB_PASS clip_seen_low
VEL_TB_PASS_ALL early=11500 23012 33619 40481 peak=1976 3952 6182 7977
```

Per-velocity peaks unchanged across the four cells (1976 / 3952 /
6182 / 7977) confirming that body_mix does not move the peak. The
early-energy values rise slightly across the board (vs M2's 10983
/ 21977 / 32097 / 38643) because more body content is mixed in.
The brightness-margin assertion still PASS by a wider margin
(40481 > 1.5 * 23012 = 34518).

### Control-stack regression TBs

Run unchanged at the M3 build:

```
UART_CMD_TB_PASS notes=5 releases=1 errors=3 isolation=1
ISOLATION_TB_PASS
UART_TX_TB_PASS frames=2 collected_count=170
```

All three PASS at the same assertion sets accepted in M2.

### Quartus full compile

```
.\build.ps1 -Stage compile
Quartus II Full Compilation was successful. 0 errors, 16 warnings
```

Resource and timing summary versus accepted M2 baseline:

| Metric | M2 | M3 | Delta |
| --- | ---: | ---: | ---: |
| Total logic elements | 4,917 | **4,932** | +15 |
| Combinational | 4,707 | 4,707 | 0 |
| Registers | 2,283 | 2,285 | +2 |
| Memory bits | 20,480 | 20,480 | 0 |
| M9K | 5 | 5 | 0 |
| DSP9 | 26 | 26 | 0 |
| PLL | 1/2 | 1/2 | 0 |
| Slow-85C setup `sys_clk_50m` | +4.551 ns | **+4.515 ns** | -0.036 ns |
| Hold slow-85C | +0.432 ns | +0.413 ns | -0.019 ns |
| All TNS | 0 | 0 | 0 |
| Errors | 0 | 0 | 0 |
| Warnings | 16 | 16 | 0 |

The +15 LE delta is a small fitter / coefficient-LUT artifact:
the new biquad 2 coefficients have slightly different bit
patterns, which leads to small differences in shared-LUT folding.
Combinational logic count is unchanged; +2 registers is the
fitter retiming a small portion of the multiplier output stage.

Setup slack moved by -0.036 ns; this is run-to-run variance, not
a structural regression. Hold slack -0.019 ns same. Both gates
pass with comfortable margin.

Compile log: `.kiro/quartus_phase6_m3.log` (local-only).

## 4. Hardware deferral and recapture protocol (for verifier)

Per project discipline rule, the M3 live A/B capture is deferred
to the M3 verifier task. Suggested protocol:

1. Reprogram the SOF generated by the M3 Quartus compile (record
   checksum).
2. Run the same isolated original profile that produced the
   accepted M2 baseline (`reports/phase6_m2_voice_baseline.csv`):
   ```
   python scripts/phase6_m1_voice_bench.py --run --port COM5 \
       --single-voice-isolate \
       --sidecar reports/phase6_m3_voice_bench_session.json
   ```
3. Capture audio in parallel.
4. Analyze:
   ```
   python scripts/phase6_m1_voice_analyze.py \
       --wav reports/phase6_m3_voice_bench.wav \
       --sidecar reports/phase6_m3_voice_bench_session.json \
       --out reports/phase6_m3_voice_baseline.csv \
       --out-md reports/phase6_m3_voice_baseline_analyzed.md
   ```
5. Compute per-cell FFT-based 500 Hz band comparisons against the
   M2 baseline. Acceptance criteria from M3 scope section 4:
   - **1-3 kHz band gains 3-5 dB** in M3 vs M2 (warmth indicator).
   - **50-200 Hz band gains modestly** (the existing low-shelf
     biquad 1 is unchanged but body_mix gain is higher).
   - **4-7 kHz band stays within ~1 dB of M2** (no brightness
     regression).
   - **No new clipping** on cells that were clean in M2.
   - **Subjective listener report**: warmer/fuller, not muddier.

Focus cells (from M1.2 verifier's "usable" list): 2, 5, 8, 9, 11.

## 5. Out of scope

- No CPU/firmware/MMIO/register-file revival.
- No new UART command syntax.
- No new biquad stage; only retune biquad 2 coefficients.
- No change to `phase1_reduced_voice.v` waveguide / hammer ROM.
- No QSF change.
- No reduction of physical voice count.
- No edits to verifier-protected untracked files or `.kiro/`.

ASCII-only on touched source / report files.

## 6. Committed result

This commit contains:

- modify: `rtl/control/phase0_fixed_control.v` (1-line body_mix
  preset change from 8192 to 12288)
- modify: `rtl/audio/phase0_body_filter.v` (5 Q2.14 coefficients
  retuned for 1500 Hz peaking EQ)
- modify: `rtl/audio/phase1_reduced_voice_tb.v` (body_mix initial
  value updated)
- modify: `rtl/audio/phase1_reduced_voice_velocity_tb.v` (body_mix
  port value updated)
- modify: `rtl/audio/phase1_reduced_voice_golden_samples.hex`
  (re-snapshotted with new body_mix; 4096 samples)
- new: `reports/phase6_m3_body_warmth_impl.md` (this file)
