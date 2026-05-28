# Phase 6 M6.6 Next Voice-Quality Axis Scope

Date: 2026-05-28
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-ffa01c2a`
Branch: `codex/phase1c-uart-boundary-fix`
Parent commit: `b7203ee` (M6.5-DAMP verifier acceptance)

## TL;DR

**Recommendation: inharmonicity/dispersion tuning via a
runtime `!S<vvvv>` command for `disp_coeff`.**

The existing `disp_coeff_q15` allpass element inside
`phase1_reduced_voice.v` (STATE_AP_FINISH) already provides
string-stiffness dispersion but is currently a static
localparam at 16'sd9952. Making it runtime-variable follows
the exact same pattern as `!B` (body_mix) and `!D`
(damp_mix): parser command + storage register + fixed_control
pass-through. Expected LE cost: ~+30-50 LE (same as `!D`
minus the constant-folding loss, because `disp_coeff` is
already a wire input to the voice, not a register inside
`phase0_fixed_control`). Acceptance metric: spectral
inharmonicity ratio measured on the post-strike FFT.


## 1. Accepted baseline

M6.4-INT + M6.5-DAMP at commit `b7203ee`:

- LE: 5,237 / 10,320 (51%) under raised +150 LE cap.
- Setup slow-85C: +5.213 ns.
- M9K 5, DSP9 26, PLL 1.
- Runtime knobs: `!B` (body_mix), `!D` (damp_mix).
- Velocity layers: 3 (soft/bright/brilliant).
- Body FIR: M6.4-INT Cand E (delays 4/12/24).
- Body magnitude: M6.3a doubling (<<<1 shift).
- Body_mix MSB-saturating mapping (M6.2).
- Damp_mix: runtime, clamped 0..0x7FFF, higher = longer
  sustain. Verifier measured +3.91 dB/s A4 / +3.62 dB/s C5
  decay-rate swing.
- Body-axis 1-3 kHz gate: closed as structurally ill-posed.

## 2. Candidate comparison

### 2.1 Inharmonicity/dispersion tuning (RECOMMENDED)

Acoustic motivation. Real piano strings exhibit
inharmonicity: upper partials are progressively sharper than
integer multiples of the fundamental due to string stiffness.
The existing `disp_coeff_q15` allpass in STATE_AP_FINISH
models this but is fixed at 9952 for all notes. Making it
runtime-variable lets the user (or a future host mapper) set
per-note stiffness, which is the most piano-defining timbral
axis after attack and sustain.

Lever. Add `!S<vvvv>` UART command (same 8-byte pattern as
`!B`/`!D`). `disp_coeff` is already a signed 16-bit wire
input to the voice; the fixed_control currently assigns it
from a localparam. Replace with a runtime register.

Resource estimate. ~+30-50 LE. Unlike `!D`, `disp_coeff` is
already a wire (not a register inside fixed_control), so
there is no constant-folding loss on the voice side. The
cost is purely parser + storage register.

Acceptance metric. Spectral inharmonicity ratio: measure the
frequency of the 2nd and 3rd partials relative to the
fundamental on a post-strike FFT window. With `disp_coeff=0`
(no dispersion) partials should be exactly harmonic; with
`disp_coeff=9952` (current) they should be slightly sharp.
The delta should be measurable on the post-isolator chain.

Risk. Low. The allpass is already in the critical path and
timing-clean at +5.213 ns. No new pipeline stage.

### 2.2 Attack/excitation shaping (DEFERRED)

M2 already added 3-layer velocity-sensitive hammer ROM.
Further refinement (multi-tap excitation, transient noise)
adds new state and ROM, costs more LE, and has a less clear
hardware-measurable acceptance gate than dispersion.

### 2.3 Frequency-dependent loop-loss (DEFERRED)

Adding a one-pole IIR inside the waveguide loop-loss path
(Candidate E from the M6 scope) was explicitly deferred in
the M6.0 scope because setup margin was the binding
constraint at +4.620 ns. Current margin is +5.213 ns, which
is better but still tight for an in-loop IIR pole. Defer
until dispersion is accepted and the user has evidence that
differential decay is the next audible weakness.

### 2.4 Measurement/listening protocol refinement (DEFERRED)

Useful as parallel tooling but not a voice-quality feature.
The existing sweep harnesses (body_mix, damp_mix) plus the
M1 analyzer cover the current measurement needs.

### 2.5 Controlled detune/chorus (DEFERRED)

Per-voice detune uses the four physical voices as a product
feature rather than support infrastructure. Explicitly
deferred per user macro priority.

## 3. Recommended slice: M6.6-DISP runtime dispersion knob

### 3.1 Implementation sketch

Same pattern as M6.5-DAMP:

1. `rtl/control/phase0_uart_command.v`: add `!S<vvvv>`
   command, `disp_coeff_runtime` output port, reset default
   16'sd9952 (current static value). `disp_coeff` is signed
   so the parser stores the full 16-bit value without
   clamping (the allpass is stable for any coefficient in
   [-32768, +32767]).
2. `rtl/control/phase0_fixed_control.v`: add
   `disp_coeff_runtime` input, replace the static
   `assign voice_disp_coeff = 16'sd9952;` with
   `assign voice_disp_coeff = disp_coeff_runtime;`.
3. `rtl/top/piano_phase0_top.v`: add wire and route.
4. TB: add `!S` test cases mirroring `!D`/`!B`.
5. Host helper: `scripts/phase6_m6_6_disp_sweep.py`.

### 3.2 Resource estimate

- Parser: ~+30 LE (same as `!B`).
- Fixed_control: ~0 LE (replacing a localparam assign with
  an input wire is free; no register load path changes
  because `voice_disp_coeff` is a combinational assign, not
  a registered state like `voice_damp_mix_reg`).
- Total: ~+30 LE. Well under any reasonable cap.

### 3.3 Acceptance metric

Spectral inharmonicity ratio on A4 (loop_len 106):

- `!S0000` (no dispersion): 2nd partial at exactly 2x
  fundamental.
- `!S26E0` (current default 9952): 2nd partial slightly
  sharp of 2x.
- `!S7FFF` (max positive): 2nd partial measurably sharper.

PASS gate: measurable frequency shift of the 2nd partial
between `!S0000` and `!S7FFF` of at least +5 Hz on A4
(fundamental ~442 Hz, so 2nd partial shift from ~884 Hz to
~889+ Hz). This is well within the post-isolator FFT
resolution (~3 Hz at 200 ms Hann window).

## 4. Proposed task text

### M6.6-DISP implementer task

> Add `!S<vvvv>` runtime dispersion coefficient command.
> Same 8-byte parser pattern as `!B`/`!D`. Store as signed
> 16-bit `disp_coeff_runtime`, reset default 16'sd9952.
> Replace `assign voice_disp_coeff = 16'sd9952` in
> `phase0_fixed_control.v` with
> `assign voice_disp_coeff = disp_coeff_runtime`.
> Add TB cases, host sweep helper, and impl report.
> LE gate: <= +50 hard, <= +30 target.
> Setup gate: >= +4.0 ns hard.

### M6.6-DISP verifier task

> Program SOF, run dispersion sweep
> `[0x0000, 0x1000, 0x26E0, 0x4000, 0x7FFF]` x A4/C5.
> Measure 2nd partial frequency shift. PASS >= +5 Hz on A4.

## 5. Out of scope

- No body_filter retune, body FIR change, body_mix change.
- No damp_mix change.
- No hammer ROM change.
- No loop-loss IIR.
- No polyphony feature work.
- No CPU/MMIO/firmware revival.
- No JTAG/scheduler.

## 6. Files

- `reports/phase6_m6_6_voice_quality_next_axis_scope.md`
  (this report, new).

## 7. ASCII check

```
reports/phase6_m6_6_voice_quality_next_axis_scope.md  non_ascii=0
```
