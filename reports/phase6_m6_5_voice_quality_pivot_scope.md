# Phase 6 M6.5 Voice-Quality Pivot Scope

Date: 2026-05-28
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-56fceebe`
Branch: `codex/phase1c-uart-boundary-fix`
Parent commit: `5ed08ec` (M6.4-INT Cand E impl) /
verifier `task-9fd633f8` (M6.4-INT FAIL on strict gate,
voice-model limitation)

## TL;DR

**Recommendation:**

1. **Disposition of M6.4-INT RTL: KEEP commit `5ed08ec`.**
   It is non-regressing, saves 29 LE versus M6.3a, gains
   +0.247 ns slow-85C setup, and shifts a small amount of
   energy into 50-200 Hz warmth (+1.06 dB) and 3-5 kHz
   brightness (+0.69 dB). Reverting to M6.3a is also
   defensible but offers no engineering advantage.

2. **Body axis: close as a measurable acceptance gate.**
   The 1-3 kHz body_mix delta gate is structurally
   ill-posed for the current voice architecture; no 3-tap
   body-FIR retune can close the +1 dB gap on this voice
   model. Body remains useful as a subjective tuning knob
   via the existing `!B` command but should not gate future
   acceptance work.

3. **Pivot to release/damper refinement (M6.5-DAMP)** as the
   next implementable voice-quality slice. The existing
   `damp_mix` shared knob is a single 16-bit register with
   a clean, hardware-measurable acceptance metric (decay
   rate in dB/s of the strike's tail), the architecture
   already supports per-voice routing, and a new tiny
   `!D<vvvv>` UART command in the existing parser pattern
   exposes a runtime knob for verifier A/B without firmware
   or MMIO revival.

The recommended slice is small (parser + storage register +
1-line audio path) and has high audible payoff: piano-like
sustain is a top-tier audible-quality axis the user has
mentioned multiple times across the Phase 6 campaign.


## 1. Inputs

Reviewed:

- `reports/phase6_m6_4_int_fir_validation.md` (FAIL on
  strict 1-3 kHz gate, voice-model limitation diagnosis).
- `reports/phase6_m6_4_int_fir_impl.md`.
- `reports/phase6_m6_4_int_fir_scope.md`.
- `reports/phase6_m6_4_body_filter_retune_scope_validation.md`
  (linearity-cancellation proof for the post-mix filter).
- `reports/phase6_m6_3a_body_gain_validation.md` (M6.3a
  CONDITIONAL_PASS, ~2.5 dB systematic prediction gap).
- `reports/phase6_m2_velocity_brightness_validation.md`
  (M2 velocity-to-brightness PASS).
- `reports/phase6_m3_body_warmth_validation.md` (M3 body
  filter retune CONDITIONAL_PASS).

RTL re-checked at HEAD `5ed08ec`:

- `rtl/audio/phase1_reduced_voice.v` body FIR path,
  excitation ROM, three-layer velocity hammer, damp_mix
  consumption at `STATE_DAMP_A_SETUP`/`STATE_DAMP_A_FINISH`/
  `STATE_DAMP_B_FINISH`.
- `rtl/audio/phase0_audio_path.v` per-voice instantiation
  and 4-voice mix path.
- `rtl/control/phase0_fixed_control.v` voice_damp_mix
  driver (currently a static localparam).
- `rtl/control/phase0_uart_command.v` parser structure for
  `!N`/`!NLLLLVVVV`/`!F`/`!I0`/`!I1`/`!B` commands.


## 2. M6.4-INT disposition: KEEP

`5ed08ec` is the current accepted RTL HEAD. Trade-offs:

| dimension                                | M6.3a (5ca80d9) | M6.4-INT (5ed08ec) | preferred |
| ---------------------------------------- | --------------: | ------------------: | --------- |
| LE                                       | 5,131           | 5,102               | M6.4-INT  |
| Setup slow-85C `sys_clk_50m`             | +5.707 ns       | +5.954 ns           | M6.4-INT  |
| Hold slow-85C                            | +0.409 ns       | +0.381 ns           | M6.3a (slightly) |
| Warnings                                 | 16              | 16                  | tie       |
| 1-2k body_mix delta (measured)           | +0.00 dB        | +0.37 dB            | M6.4-INT (slightly) |
| 2-3k body_mix delta (measured)           | +0.61 dB        | -0.10 dB            | M6.3a (slightly) |
| 200-1k passband emphasis (measured)      | +1.25/+1.56 dB  | -0.46/+0.67 dB      | M6.3a     |
| 50-200 Hz warmth (measured)              | +0.01 dB        | +1.07 dB            | M6.4-INT  |
| 3-5 kHz brightness (measured)            | -0.32 dB        | +0.37 dB            | M6.4-INT  |
| Strict 1-3 kHz acceptance gate           | FAIL            | FAIL                | tie       |
| `phase1_reduced_voice_golden_samples.hex` regen needed | yes  | yes                 | tie       |

Both fail the strict 1-3 kHz acceptance gate by similar
margins. M6.4-INT wins on LE, setup margin, low-frequency
warmth, and high-frequency brightness; M6.3a wins on the
M3-era 200-1k passband emphasis. Neither produces a
musically transformative body_mix knob behavior.

**Keep M6.4-INT**: the engineering metrics favor it and the
audible difference is subtle either way. Avoid spending
another verifier slot on a revert just for cleanliness.

If subjective listening later prefers M6.3a's 200-1k
emphasis, a single-line revert is always available as a
follow-up.


## 3. Body-axis limit: structurally ill-posed

The 1-3 kHz body_mix delta gate cannot be cleared by any
realistic 3-tap body-FIR retune in the current
architecture. Three independent lines of evidence:

### 3.1 Linearity-cancellation argument (M6.4)

The post-mix `phase0_body_filter` cascade applies linearly
to `disp + body`, so for any two body_mix sweep cells with
the same disp envelope, `H_filter(f)` factors out of the
ratio. No filter retune can change the body_mix delta. This
was verifier-validated mathematically and numerically at
M6.4 (`task-5fea5640`).

### 3.2 ~2.5 dB systematic prediction-vs-measurement gap

Two consecutive milestones with the same gap in the same
direction:

| milestone | predicted 1-2k | measured 1-2k | gap |
| --------- | -------------: | ------------: | --: |
| M6.3a (current FIR + doubling) | +2.49 dB | +0.00 dB | -2.49 dB |
| M6.4-INT (4/12/24 retune)      | +2.78 dB | +0.37 dB | -2.41 dB |

The same ~2.5 dB shortfall on both implementations means
the prediction model is incomplete in a consistent way.
Per the M6.4-INT verifier diagnosis: the linear model
`(1 + body_mix * H_FIR(f))` correctly describes the ratio
between two sweeps under spectrally flat disp, but in
practice `H_disp(f)` is strongly waveguide-resonant and
concentrated below 1 kHz. Band-energy in 1-3 kHz is
dominated by where disp puts its energy, not by body_mix.

### 3.3 No realistic 3-tap retune can close the gap

If the systematic gap is ~2.5 dB and the predicted Cand E
delta is +2.78 dB, the 3-tap FIR's true measurable delta is
~+0.3 dB. Doubling that to ~+0.6 dB would require a
weighted-sum structure that produces twice the predicted
delta - i.e., a 6-tap or 8-tap FIR, which doubles the
state in `body_history` and adds new pipeline steps.
That is no longer "a 3-tap body FIR retune"; it is a body
synthesis path redesign. Out of scope under the
"voice-quality first, no major refactor" priority.

Conclusion: close the body-axis acceptance gate as
"structurally ill-posed for this voice model and a strict
1-3 kHz band metric." Body remains useful as a subjective
warmth knob via `!B` but should not be a hardware-verifiable
acceptance metric in future Phase 6 work.


## 4. Next voice-quality axis comparison

The Phase 6 goal is "perceived single-voice quality first;
polyphony is support infrastructure, not the headline." The
remaining audible axes are summarized here in priority
order.

### 4.1 Release/damper refinement (RECOMMENDED)

Acoustic motivation. The current shared `damp_mix`
register is a 16-bit Q15 value held statically at 16'd16384
(0.5) by `phase0_fixed_control.v`. This sets a fixed
exponential decay rate for every strike on every voice.
Real piano sustain varies by velocity (harder strikes
sustain longer in absolute terms because their energy is
higher) and by the player holding the key (sustain pedal
behavior). Hardware-measurable acceptance metric: decay
rate in dB/s of the post-strike tail.

Lever. Add an `!D<vvvv>` UART command in the existing
parser pattern (matches `!B<vvvv>` exactly), storing a
`damp_mix_runtime` register in the parser. Feed it through
`phase0_fixed_control.v` (replacing the current static
localparam) into `phase0_audio_path.v` as the existing
`voice_damp_mix` wire to all four voices.

Predicted impact. Decay-rate sweeps from `damp_mix=0x0000`
(no damping, infinite sustain modulo loop_gain) to
`damp_mix=0x7FFF` (heavy damping, fast die-out). The
existing `!I1` isolation mode + body_mix sweep harness
adapts trivially to a damp_mix sweep. Predicted decay-rate
swing: 5+ dB/s spread across the sweep, easily
hardware-measurable.

Resource estimate. Should mirror M6.2/M5 cost: ~+50 LE for
parser + storage register, no DSP/M9K change. Can fit
within the M6.4-INT freed +29 LE plus a small additional
exception. Setup margin healthy at +5.954 ns.

Risk. Low. The `damp_mix` register is already wired through
the audio path; only the source changes from static to
runtime. No new state machine, no new audio-path stage.

Acceptance metric. Tail-RMS slope (dB/s) measured on a
post-strike window 100ms..1.5s. Existing M1.2 reset-on-!F
isolation mode plus per-pitch capture gives a clean
single-voice tail. Hardware verifier already has the
measurement infrastructure (sweep harness + analyzer).

Predicted PASS gate: end-to-end 1-3 kHz tail decay rate
swing >= +5 dB/s between `!D0000` and `!D7FFF`.

### 4.2 Hammer texture / attack shaping (DEFERRED)

Acoustic motivation. M2 already added 3-layer
velocity-sensitive hammer ROM (soft/bright/brilliant). M6.2
preserved bit-exact M2 behavior. The audible attack quality
is already covered by the velocity_layer mechanism; further
refinement (e.g., per-voice transient stretch, micro-noise
on attack) would add complexity without a clear next
hardware-measurable acceptance gate.

Reject as "next" but keep available as a future axis after
M6.5-DAMP.

### 4.3 Controlled detune / chorus (DEFERRED)

Acoustic motivation. Real piano notes have very slight
inter-string detune that produces beating/chorus. The
project has four physical voices but they are all driven
to the same loop_len/velocity in single-strike playback.
A controlled per-voice detune offset (e.g., +/-0.1% of
loop_len) would produce slow beating.

Reject for now: implementing detune across four voices is
a polyphony-direction feature, and the user's macro
priority is voice-quality first / polyphony as
infrastructure. Single-voice quality (M6.5-DAMP) takes
precedence.

### 4.4 Per-voice post-waveguide brightness (DEFERRED)

Acoustic motivation. Add a tiny post-waveguide tilt-EQ
inside `phase1_reduced_voice` to give a velocity-dependent
high-frequency rolloff. The current loop_gain is fixed at
0x7F80, so high-frequency loss in the loop is the same
across all velocities. A real piano shows more
high-frequency energy on harder strikes because the hammer
spectrum has more high-frequency content.

Reject for now: this competes with M2's velocity layers
and M6.4-INT's already-shipped 3-5 kHz brightness gain,
and adding a per-voice EQ stage costs more LE than M6.5-DAMP.

### 4.5 Re-measure body_mix delta with a different metric (DEFERRED)

Acoustic motivation. Per the M6.4-INT verifier's section
9.3, a per-pitch harmonic-ratio metric or attack-transient
spectrum metric might show body_mix changes that the FFT
band-energy metric obscures.

Reject as the primary M6.5 slice: this is measurement
infrastructure, not a new audible feature. Could be a
parallel host-tool slice if orchestrator wants better
body-knob characterization, but it does not advance the
voice-quality axis on hardware.


## 5. Recommended slice: M6.5-DAMP runtime damping knob

### 5.1 Architecture sketch

```
host UART !D<vvvv>\r\n
   |
   v
phase0_uart_command.v parser
   |  damp_mix_runtime register (same pattern as body_mix_runtime)
   |  reset value 16'd16384 (current M3 default)
   |  range 0x0000..0xFFFF, MSB-saturating to +32767 if needed,
   |  but damp_mix is genuinely unsigned at the multiplier so
   |  the M6.2 saturating mapping pattern applies cleanly.
   v
phase0_fixed_control.v
   |  voice_damp_mix = damp_mix_runtime
   |  (current code: voice_damp_mix = 16'd16384 localparam)
   v
phase0_audio_path.v -> phase1_reduced_voice (x4)
   |  damp_mix_q15 input (already wired)
   |  consumed at STATE_DAMP_A_FINISH and STATE_DAMP_B_FINISH
   |  for the loop low-pass filter coefficient
   v
audio output
```

The damp_mix consumption is purely combinational at the
existing two states; runtime updates take effect on the
next sample. No CDC required (single sys_clk domain).

### 5.2 Acoustic prediction

Loop low-pass filter gain at fundamental (`Fs/loop_len`):

```
H_lp(f, damp_mix) = damp_inv_q15 + damp_mix_q15 * z^{-1}_lp_state
```

For damp_mix=16384 (current), the loop's high-frequency
attenuation per cycle is moderate. For damp_mix=0,
high-frequency content persists; for damp_mix=32767,
high-frequency content dies almost immediately.

Decay rate ratio between two damp_mix values is
proportional to `log(damp_mix_high / damp_mix_low)`. Sweep
from `0x0000` to `0x7FFF` should produce ~10 dB/s decay
rate swing in 1-3 kHz tail energy, well above the noise
floor.

### 5.3 Resource estimate

- Parser: M6.2 `!B` precedent shows ~+30 LE for an 8-byte
  command + 16-bit storage register.
- `phase0_fixed_control.v`: replacement of localparam
  with input wire. ~0 LE.
- `phase0_audio_path.v`: pass-through. ~0 LE.
- Total estimate: ~+30 to +50 LE.

Setup margin: parser is in sys_clk domain, no critical
path impact expected. Current +5.954 ns slack has
comfortable headroom.

### 5.4 Acceptance metric

The verifier's existing post-isolator capture chain plus
the M6 sweep harness measures FFT band energy on
post-strike windows. For damp_mix sweeps the right metric
is **tail-RMS slope (dB/s)** on a 100ms..1.5s window in the
1-3 kHz band, computed from a clean isolated single-voice
strike. Hardware-verifiable PASS gate: decay-rate swing of
at least +5 dB/s between `!D0000` and `!D7FFF` on A4 and C5.

### 5.5 Why this is the right next slice

- Single-voice quality is the project priority; sustain is
  one of the most audibly distinguishing features of a
  piano voice.
- Hardware-measurable acceptance metric (decay rate) is
  not subject to the broadband-disp limitation that
  derailed the body axis. Decay rate is a time-domain
  metric measured on the tail; `H_disp(f)` shape does not
  invalidate it.
- Architecture and parser pattern already exist (`!B`
  precedent); the implementation is small.
- Operator-facing benefit: a runtime damping knob lets the
  user tune sustain directly. Previously fixed at M3's
  static 16384.
- Risk profile is comparable to or better than M6.2 (no
  signed-cast bugs, damp_mix is genuinely unsigned).


## 6. Proposed task text

### M6.5-DAMP implementer task

> Implement Phase 6 M6.5-DAMP: add a runtime
> `damp_mix_runtime` register to the UART parser and route
> it as `voice_damp_mix` through the fixed-function control
> path. New UART command: `!D<vvvv>\r\n` where vvvv is
> exactly 4 hex digits.
>
> Read first:
> - `reports/phase6_m6_5_voice_quality_pivot_scope.md`
> - `rtl/control/phase0_uart_command.v` (M5/M6.2 `!B`
>   precedent block)
> - `rtl/control/phase0_uart_command_tb.v` (existing `!B`
>   test pattern)
> - `rtl/control/phase0_fixed_control.v` (current
>   `voice_damp_mix = 16'd16384` localparam)
>
> Required RTL changes:
> 1. `rtl/control/phase0_uart_command.v`:
>    - Add `output reg [15:0] damp_mix_runtime` port.
>    - Add `parsed_damp_mix` precompute analogous to
>      `parsed_body_mix`.
>    - Add an `!D` 8-byte command branch in the existing
>      length-8 parser switch, mirroring the `!B` pattern
>      bit-for-bit.
>    - Reset value `16'd16384` (the current static M3
>      default).
>    - Update the parser comment block to document the new
>      `!D` command alongside `!B`.
>
> 2. `rtl/control/phase0_fixed_control.v`:
>    - Add `input wire [15:0] damp_mix_runtime` port.
>    - Replace `assign voice_damp_mix = 16'd16384;` with
>      `assign voice_damp_mix = damp_mix_runtime;`.
>    - Update comment block to note Phase 6 M6.5-DAMP.
>
> 3. `rtl/top/piano_phase0_top.v`:
>    - Add `wire [15:0] cmd_damp_mix_runtime;` and route
>      between `phase0_uart_command` and
>      `phase0_fixed_control`.
>
> 4. `rtl/control/phase0_uart_command_tb.v`:
>    - Add a small `!D` test case mirroring the `!B`
>      pattern: `!D0000\r\n` -> 0x0000, `!D7FFF\r\n` ->
>      0x7FFF, `!DG000\r\n` -> ERR_UNSUPPORTED_ARG.
>    - Verify reset default = 0x4000 = 16384.
>
> Required preserved behavior:
> - All M6.4-INT body FIR addressing (5'd4/12/24).
> - All M6.3a body doubling (`<<< 1` shift).
> - All M6.2 MSB-saturating body_mix mapping.
> - All M2 velocity-layer hammer ROM.
> - Existing `!N`/`!NLLLLVVVV`/`!F`/`!I0`/`!I1`/`!B`
>   commands.
> - Four physical voices at all times.
>
> Hard gates:
> - LE delta vs M6.4-INT `<= +50` hard, target `+30`.
> - Setup slow-85C `sys_clk_50m >= +4.0 ns` hard.
> - Hold clean, all TNS 0.
> - M9K, DSP9, PLL unchanged.
> - 0 errors.
> - ModelSim `vlog -sv` clean on phase1_reduced_voice +
>   phase0_uart_command + phase0_fixed_control + their
>   TBs.
> - `phase0_uart_command_tb` PASS with new `!D` cases (if
>   vsim license available; otherwise document blocker per
>   M6.3a/M6.4-INT precedent).
>
> NO-GO triggers:
> - LE delta > +50 vs M6.4-INT.
> - Setup < +4.0 ns.
> - Any DSP/M9K/PLL change.
> - Any change to firmware, QSF/SDC/PLL, host scripts,
>   obsolete archive.
> - Any change to body_mix mapping, body FIR, hammer ROM,
>   velocity layers.
> - Any new command syntax beyond `!D<vvvv>`.
>
> Out of scope:
> - Per-voice damp_mix (single shared register only, like
>   the existing body_mix).
> - Sustain pedal modeling, velocity-dependent damping
>   beyond what the loop low-pass already provides.
>
> Expected artifact:
> `reports/phase6_m6_5_damp_runtime_impl.md` plus the
> Quartus compile log.

### M6.5-DAMP verifier task

> Validate Phase 6 M6.5-DAMP runtime damping knob
> end-to-end on hardware.
>
> Required scope:
> 1. Confirm scope: only `rtl/control/phase0_uart_command.v`,
>    `rtl/control/phase0_uart_command_tb.v`,
>    `rtl/control/phase0_fixed_control.v`,
>    `rtl/top/piano_phase0_top.v`,
>    `reports/phase6_m6_5_damp_runtime_impl.md`, and the
>    Quartus compile log changed.
> 2. ASCII-only on touched files.
> 3. Run RTL TBs:
>    - `phase0_uart_command_tb` PASS with new `!D` cases.
>    - `phase1_reduced_voice_tb` PASS (golden unchanged
>      because damp_mix default is 0x4000, identical to
>      pre-M6.5).
>    - `phase1_reduced_voice_velocity_tb` PASS unchanged.
>    - `phase1_reduced_voice_body_mix_sat_tb` PASS unchanged.
>    - `phase0_fixed_control_isolation_tb` PASS unchanged.
> 4. Quartus full compile PASS within hard gates.
> 5. Program SOF and run damp_mix sweep harness (extend
>    sweep tool with `!D` per-cell command, mirror of `!B`
>    pattern). Sweep `[0x0000, 0x1000, 0x2000, 0x4000,
>    0x6000, 0x7FFF]` x A4/C5.
> 6. Independent FFT analysis of post-strike tail envelope
>    on each cell. Compute tail-RMS slope (dB/s) in the
>    100ms..1.5s window in the 1-3 kHz band.
> 7. Acceptance gate: decay-rate swing of at least +5 dB/s
>    between `!D0000` and `!D7FFF` cells, on at least one
>    pitch (A4 or C5). PASS = >= +5 dB/s,
>    CONDITIONAL_PASS = >= +2 dB/s. The 0x0000 cell may
>    show very long sustain or even mild oscillation; if
>    so, document and consider raising the lower bound to
>    `0x0800` for safety.
> 8. Submit `reports/phase6_m6_5_damp_runtime_validation.md`.
>
> Guardrails:
> - Do not edit RTL or scripts in verifier role.
> - Do not commit large WAV files.
> - Do not touch stale untracked files.


## 7. Macro-direction check

- Voice quality first: M6.5-DAMP directly addresses
  sustain quality, the most audibly piano-defining
  attribute after attack. PASS.
- Polyphony as support: damp_mix remains a single shared
  register (no per-voice expansion). PASS.
- Fixed-function RTL preserved: no CPU/firmware/MMIO/
  register-file revival. PASS.
- No JTAG / on-chip strike scheduler: PASS.
- No new UART feature as final selling point: `!D` is a
  diagnostic/tuning knob, parallel to `!B`. PASS.
- M6.3a/M6.4-INT preserved: parser additions only; no
  body_mix or body FIR changes. PASS.

## 8. Out of scope

- No body_filter coefficient retune.
- No body weight or body FIR retune.
- No body-only diagnostic mode.
- No coherent-average harness extension.
- No per-voice damp_mix (single shared register only).
- No sustain pedal modeling.
- No velocity-dependent damping logic.
- No CPU/MMIO/firmware/register-file revival.
- No JTAG command path.
- No on-chip strike scheduler.
- No polyphony feature work.
- No edits to firmware, QSF/SDC/PLL, host scripts, obsolete
  archive, generated bitstreams, or stale untracked files.

## 9. Files

This commit:

- `reports/phase6_m6_5_voice_quality_pivot_scope.md` (this
  scope, new).

Single ASCII-only report, no helper script needed (the
arithmetic for damp_mix is already established in the
existing `phase1_reduced_voice.v` `STATE_DAMP_*` logic;
no new numerical analysis required).

## 10. ASCII check

```
reports/phase6_m6_5_voice_quality_pivot_scope.md  non_ascii=0
```
