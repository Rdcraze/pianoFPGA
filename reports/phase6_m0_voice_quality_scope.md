# Phase 6 M0 Voice-Quality-First Scope

Date: 2026-05-24
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-add5dc68`
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `69302fa` (Phase 5 closeout PASS)

## TL;DR

**Recommendation: Phase 6 M1 = no-RTL voice-quality benchmark and
audio capture tooling slice.** Build a repeatable command-driven
benchmark loop on top of the live M2/M3 UART path, capture the
acoustic baseline of the current single-voice behavior, and produce
honest per-pitch / per-velocity metrics (peak, RMS, decay envelope,
spectral brightness, attack transient). Defer RTL voice-quality
changes to Phase 6 M2 and beyond, where the M1 baseline becomes the
reference each candidate experiment must beat.

Rationale: every Phase 5 audio capture so far measured "non-clipping
non-silent continuous output" at the room-mic level (peak around
-24 dBFS, RMS around -35 dBFS), which is the right gate for the
control plane but is not strong enough evidence to design audible
voice-quality improvements against. The first M1 slice that
produces structured per-pitch / per-velocity audio is more valuable
to the user's "voice-quality first" direction than any speculative
RTL change. Phase 6 M2 then becomes the first RTL slice, picked
from the ranked candidates in section 4 once the M1 baseline shows
the audible weakness most worth addressing.

| M1 (this scope) | M2 (queued, deferred) |
| --- | --- |
| No-RTL: benchmark harness, host-tool only | First RTL voice-quality experiment |
| Add `scripts/phase6_m1_voice_bench.py` | RTL change in `phase1_reduced_voice.v` or `phase0_body_filter.v` or hammer/excitation curve |
| Capture per-pitch / per-velocity audio | Compare against M1 baseline |
| New: `reports/phase6_m1_voice_baseline.md` | New: `reports/phase6_m2_*.md` |
| RTL change: NONE | LE budget target: <= +400 vs M3 |
| Hardware gate: structured baseline captured | Hardware gate: audible improvement vs M1, no regression elsewhere |

## 1. Phase 6 objective in concrete engineering terms

Phase 6 should improve the perceived quality of a single struck
note. Concrete engineering interpretation:

- Audible: a listener can A/B between M1 baseline and an M2+
  candidate and reliably prefer the M2+ output for a representative
  pitch and velocity.
- Measurable: the M1 baseline produces enough structured audio data
  that an M2 candidate's acoustic delta (peak ratio, decay-time,
  spectral centroid, attack transient sharpness) can be quantified
  rather than guessed.
- Conservative on polyphony: the four physical voices remain in
  place as overlap/stress infrastructure. Polyphony count is not a
  product feature for Phase 6 and should not appear in any Phase 6
  acceptance criterion. The four voices stay because shrinking them
  would break Phase 5 M2/M3 acceptance and waste M9K/DSP that the
  current LE budget is comfortable carrying.
- No CPU revival: Phase 6 must remain inside the fixed-function
  control architecture. UART command extensions (like a runtime
  body_mix knob) are acceptable; firmware/MMIO/register-file
  revival is not.

The engineering line is: every Phase 6 milestone produces audible
or measurable evidence about voice quality, with polyphony only as
a regression dimension.

## 2. Live audio-relevant modules (review)

The current live audio path is unchanged from the Phase 4 M7
acceptance baseline. Verifier: `phase1_reduced_voice_tb` golden TB
passes bit-exact at `peak=3952` after every Phase 5 milestone.

### `rtl/audio/phase1_reduced_voice.v`

Per-voice digital-waveguide model:
- 128-deep `delay_line` M9K, addressed by `wr_ptr - loop_len`,
  loop_len 32..127.
- Loop-loss filter (`damp_mix_q15`/`damp_inv_q15` mix) to model
  string decay.
- All-pass dispersion (`disp_coeff_q15`) for inharmonicity.
- 32-deep `body_history` M9K (one per voice) with three taps at
  offsets 7, 17, 31 for a tiny in-voice body coloration.
- Phase 4 M7 velocity-layered hammer: at trigger time the voice
  selects either the original "soft" excitation curve (layer 0,
  used when velocity < 0x6000) or a "bright" curve (layer 1, used
  at velocity >= 0x6000). Production firmware writes 0x7FFF, so
  audible playback is layer 1.
- 16-cycle excitation finite impulse, then sustained ringdown.
- Outputs 16-bit signed `sample_data` and `sample_valid`, plus
  status flags `active`, `excite_busy`, `clip_seen`, `peak_level`.

Important parameter ranges currently held static by
`phase0_fixed_control`:
- `loop_gain_q15 = 16'd32640` (very close to unity feedback)
- `damp_mix_q15 = 16'd16384` default, `16'd32767` on release
- `disp_coeff_q15 = 16'sd9952` (positive coefficient)
- `body_mix_q15 = 16'd8192`

These are runtime-writable via the per-voice ports, but no command
exposes them today. M2 only writes per-voice `loop_len` and
`velocity` on `!N`/`!NLLLLVVVV`; the rest remain at the static
defaults.

### `rtl/audio/phase0_body_filter.v`

Two-biquad body filter (low-shelf + peaking) at the audio-path
output stage. Q2.14 coefficients hardcoded:
- Biquad 1: low-shelf, +6 dB at ~200 Hz, Q ~0.7.
- Biquad 2: peaking, +3 dB at ~200 Hz, Q ~1.0.

This is a single global filter applied to the four-voice mix sum.
There is currently no runtime knob for it.

### `rtl/audio/phase0_audio_path.v`

Wires the four `phase1_reduced_voice` instances into the mix tree,
applies saturation, optionally substitutes `phase0_sample_gen`
output for diagnostic mode (currently disabled in the live build),
and feeds `phase0_body_filter` before the WM8978 transmit path.

### `rtl/control/phase0_fixed_control.v`

Holds the static parameter defaults and the per-voice `loop_len`/
`velocity` registers updated on `!N`/`!NLLLLVVVV`. Adds the new
`command_mode` and `voice_damp_mix_reg` from M2.

## 3. Voice-quality benchmark loop (proposed M1 deliverable)

A repeatable benchmark must drive the live UART command path with
controlled parameter sweeps and capture analog audio that can be
analyzed offline. The proposed harness is a single Python script
plus a structured capture protocol.

### Pitches (loop_len values)

| Pitch | loop_len | Notes |
| --- | ---: | --- |
| A2 | 7'd127 | clamp at maximum loop length; lower-pitch boundary the wrapper allows |
| A4 | 7'd106 | reference; matches reduced-voice TB and M7 acceptance baseline |
| C5 | 7'd89 | mid-range |
| A5 | 7'd53 | one-octave-higher reference |
| A6 | 7'd32 | clamp at minimum loop length; upper-pitch boundary |

(loop_len 127 corresponds to ~370 Hz at the 46.875 kHz sample rate;
not exactly A2 (110 Hz) because the protocol clamp prevents lower
pitches. The benchmark documents this honestly.)

### Velocities

- 16'h2000: low-velocity (layer 0, "soft" hammer curve).
- 16'h4000: TB-default velocity (layer 0).
- 16'h7FFF: full-scale (layer 1, "bright" hammer curve, default
  for production play).

### Per-note capture

For each (pitch, velocity) cell:
1. Send `!F\r\n` to silence any prior ring.
2. Wait 1.0 s for damping to take effect.
3. Send `!N{loop_len_hex}{velocity_hex}\r\n`.
4. Capture analog audio for 4 s starting at the send moment.
5. Pause 1 s before the next cell.

The 4 s capture window is wider than any one strike's audible
decay (typical loop_gain=32640 + damp_mix=16384 yields decay times
in the 1-3 s range at A4) so the entire envelope fits.

### Metrics computed offline per cell

- Peak amplitude (linear and dBFS).
- RMS over 100 ms / 500 ms / 3 s windows.
- Attack transient: time from first non-silent sample to peak.
- Decay envelope: RMS slope between 100 ms and 1 s.
- Spectral centroid (FFT-based) over the first 250 ms (brightness
  proxy).
- Clipping count (samples at +/-32767).
- Silence count after first hit (samples below threshold).

These metrics map directly to "is the voice better" judgments:
- Brighter strike at high velocity = higher spectral centroid in
  the first 100-250 ms.
- Cleaner attack = shorter time-to-peak with no clipping.
- More piano-like decay = monotonic RMS slope, no premature
  silence, no buzzing tail.

### P5M2 telemetry usage

Q (command_count) and X ({last_error, error_count}) are used as
command-health telemetry only:
- Q must increment by exactly the count of valid commands sent
  (PASS).
- X must remain 0 unless an intentional malformed input is
  injected (PASS).

P5M2 frames are NOT used as audio evidence. Audio quality is judged
exclusively from analog captures.

### Output format

`scripts/phase6_m1_voice_bench.py` runs the harness and writes per-
cell rows to `reports/phase6_m1_voice_baseline.csv` (or similar):

```
pitch,loop_len_hex,velocity_hex,peak_dbfs,rms_100ms_dbfs,
rms_500ms_dbfs,attack_ms,decay_db_per_s,spectral_centroid_hz,
clipping_count,silence_after_ms
```

A short prose summary lands in
`reports/phase6_m1_voice_baseline.md` with per-cell observations.

## 4. Candidate voice-quality experiments

Ranked by audible value vs LE/timing risk vs scope. Each row is a
plausible Phase 6 M2+ slice; rank order assumes the M1 baseline
shows non-trivial weakness in the named axis. If M1 shows the
baseline is already clean on an axis, that candidate drops in
priority.

| Candidate | Audible value | LE estimate | Risk | Testability | Recommended position |
| --- | --- | ---: | --- | --- | --- |
| **A. Velocity-to-brightness curve (extend M7)** | High. The M7 hammer already has two layers. Extending to 4 layers (smoother brightness vs velocity) costs ~16 ROM entries per layer and a 2-bit selector. | +50-150 LE | Low. Builds on accepted M7 layer-q register. | Easy in ModelSim with TB stimuli at multiple velocities. | M2 frontrunner if M1 shows velocity dynamics are flat. |
| **B. Body filter coefficient runtime knob** | Medium-high. Body filter is currently fixed; making it command-tunable lets the listener dial coloration. Add a tiny `!B<coef>\r\n` command that updates body biquad coefficients. | +200-300 LE | Medium. New command syntax, parameter store, plus the existing biquad accepts new coefficients. Extends M2 protocol surface. | Good. ModelSim test sweeps coefficients, hardware test A/B presets. | M3+ candidate, depends on whether listener wants tunable coloration. |
| **C. Loop-gain / damp-mix runtime knob** | High for sustained-note tonal control. Currently hardwired loop_gain=32640. Adding a `!G<gain>\r\n` and `!D<damp>\r\n` command pair lets the host shape decay vs sustain. | +150-250 LE | Medium. Requires per-voice or shared registers and command parser additions. | Easy. ModelSim test confirms decay-time changes. | M2 candidate if M1 shows decay is too short or too long. |
| **D. Pre-strike noise component** | Moderate. Real piano hammers produce a small mechanical thud before the string responds. A 1-2 ms shaped noise burst added to the excitation could improve attack realism. | +200-400 LE | Higher. New noise generator, new mix point, new envelope shaper, possibly new state in `phase1_reduced_voice`. | Harder. Subjective listening test. | M3+ candidate. Only justified if M1 attack transient measurements are unconvincing. |
| **E. Loop-loss filter shape** | High for mid-range realism. Currently the loop filter is a simple damp_mix lerp; a one-pole or biquad inside the loop would let upper harmonics decay faster than the fundamental, mimicking real piano string behavior. | +150-300 LE | Medium-high. Changes the physics; risk of instability or clipping. | Important to validate with ModelSim and a controlled audio comparison. | M2/M3 candidate; pick if M1 spectral analysis shows uniform per-frequency decay. |
| **F. Per-voice independent release curve** | Low for voice quality (different from polyphony LRU). Most pianos have shared sustain pedal; per-voice release is musically less audible. | +100-200 LE | Medium. | Easy. | NOT recommended for Phase 6. Defer indefinitely or roll into a sustain-pedal slice. |

Three of the six (A, C, E) are direct voice-quality improvements
that ride on the existing audio path and command parser without
major surface change. B adds a useful protocol knob. D and F are
lower priority.

## 5. Phase 6 M1 first slice

**Pick: M1 = no-RTL voice-quality baseline and benchmark tooling.**

Why no-RTL first:
- The four Phase 5 audio captures (M0/M1/M2/M3) all reported a
  similar room-mic peak around -24 dBFS and RMS around -35 dBFS at
  unspecified pitch/velocity selections. None of them characterize
  the per-pitch attack, the per-velocity brightness, or the decay
  envelope. Without this baseline, any candidate from section 4 is
  speculative.
- The benchmark harness is small, host-side, and ASCII-only. It
  uses the existing M2 UART command path with no RTL change and no
  scope risk.
- Once the harness exists, every future Phase 6 RTL slice has a
  reference baseline to A/B against, and the verifier task for an
  M2 RTL slice becomes "produce the same per-cell capture; show
  audible improvement on a specific metric without regression
  elsewhere".

The M1 deliverables are:
1. `scripts/phase6_m1_voice_bench.py`: pure-Python (stdlib +
   pyserial). Drives the (pitch, velocity) grid through COM5,
   captures audio in parallel using ffmpeg dshow (or whatever
   capture backend the verifier already uses for M0/M1/M2/M3).
   ASCII-only. `--self-check` mode validates the command-stream
   generation without hardware.
2. `scripts/phase6_m1_voice_analyze.py`: pure-Python audio analysis
   harness. Reads a captured WAV, computes per-cell metrics from
   section 3, writes `reports/phase6_m1_voice_baseline.csv` and a
   narrative `reports/phase6_m1_voice_baseline.md`.
3. `reports/phase6_m1_voice_baseline.md`: implementer baseline
   report. Per-cell metrics, honest subjective assessment, and a
   ranked "first audible weakness" recommendation that points at
   one of the candidates A/C/E from section 4.

Out of scope for M1:
- No RTL change, no QSF change, no firmware change.
- No new command syntax (use only `!N`, `!NLLLLVVVV`, `!F`).
- No body_filter coefficient changes (those wait for an M2 RTL
  slice if the baseline justifies them).
- No subjective audio judgments without measurements; if a metric
  is missing, say so explicitly.

## 6. Phase 6 M1 acceptance gates

### Static scope guard
- `git diff` only touches: new `scripts/phase6_m1_voice_bench.py`,
  new `scripts/phase6_m1_voice_analyze.py`, new
  `reports/phase6_m1_voice_baseline.md` (and CSV).
- No reference anywhere in live RTL/QSF to phase0_rv32i_*,
  phase0_control_regs, phase0_uart_mmio, phase0_boot_rom,
  phase0_data_ram, fw/phase0/, or any reduction in physical voice
  count.
- Four `phase1_reduced_voice` instances in
  `rtl/audio/phase0_audio_path.v` unchanged.

### Simulation requirements
- `--self-check` on `scripts/phase6_m1_voice_bench.py` PASS:
  exercises pitch/velocity grid generation, validates command-byte
  output, validates pacing.
- `--self-check` on `scripts/phase6_m1_voice_analyze.py` PASS:
  exercises the metric pipeline against a fixed synthetic test
  vector (sine + decay envelope) to confirm peak/RMS/decay/
  centroid values are computed correctly.
- `phase1_reduced_voice_tb` golden TB optional but if rerun must
  PASS bit-exact at `peak=3952`.

### Quartus
- Not required because no RTL change.

### Hardware audio capture
- Required: at least one full pass of the (pitch x velocity) grid
  captured at the analog jack into a single WAV (or per-cell
  segments concatenated).
- Each cell's audio must be non-clipping at all velocities except
  where explicit clipping was the goal (none expected in this
  baseline).
- Each cell's audio must be non-silent for the full strike + first
  100 ms of decay window (silence after that is acceptable for
  short-decay configurations).
- P5M2 frames captured during the run must show Q advancing
  monotonically with no error fields populated.

### Pass/fail audio criteria
- All cells captured cleanly (no missing strikes, no overlapping
  strikes from prior cell's decay tail).
- Per-cell metrics computed and written to CSV.
- Narrative report identifies at least one observable weakness or
  area for improvement (or honestly states "no obvious weakness
  on this hardware/mic setup; defer Phase 6 M2 selection to a
  separate listening test").
- Honest subjective assessment format:
  ```
  ## Subjective: <pitch> @ <velocity>
  - Sounds like: <one sentence>
  - Closest piano analog: <one sentence>
  - Most audible weakness: <one sentence or "none observed">
  - Recommended candidate from section 4 of M0 scope: <A/B/C/D/E/F or none>
  ```

### NO-GO triggers
- Hardware capture chain unavailable (no COM5 or no audio capture
  hardware).
- Self-check failure on either Python harness.
- Audio capture clips at velocity 0x4000 or below (would indicate
  upstream gain misconfiguration, not a M2 RTL question).

## 7. Recommended next implementer / verifier task split

### Phase 6 M1 implementer task

> Implement Phase 6 M1: voice-quality baseline benchmark and
> capture tooling. No RTL change.
>
> Read first:
> - reports/phase6_m0_voice_quality_scope.md
> - reports/phase5_fixed_function_control_closeout.md
> - reports/phase4_m7_velocity_layered_hammer_impl.md
> - rtl/audio/phase1_reduced_voice.v (no edit; for parameter ranges)
> - rtl/audio/phase0_body_filter.v (no edit; for what is fixed
>   today)
>
> Required deliverables:
> 1. New `scripts/phase6_m1_voice_bench.py`: pure-Python harness
>    that drives the M2 UART command path through COM5 with the
>    (pitch, velocity) grid from section 3 of the M0 scope. Pace
>    each strike with at least 4 s capture window plus 1 s pause
>    plus a leading `!F` settle. ASCII-only. `--self-check` mode
>    validates command-stream generation without hardware.
> 2. New `scripts/phase6_m1_voice_analyze.py`: pure-Python audio
>    analysis harness. Reads a captured WAV (mono or stereo), aligns
>    cells by send timestamps recorded in a sidecar log from the
>    bench, computes per-cell metrics (peak dBFS, RMS dBFS,
>    attack ms, decay dB/s, spectral centroid Hz, clipping count,
>    silence count). Writes a CSV. `--self-check` mode validates
>    the metric pipeline against a fixed synthetic test vector.
> 3. New `reports/phase6_m1_voice_baseline.md` with a per-cell
>    table and a section-6 honest subjective assessment per cell.
> 4. New `reports/phase6_m1_voice_baseline.csv` with the per-cell
>    metric rows.
> 5. No RTL/QSF/firmware/obsolete change.
>
> Hard validation gates:
> - Both Python `--self-check` modes PASS.
> - At least one full hardware run captures the entire pitch x
>   velocity grid; cells are cleanly separable in the WAV.
> - Per-cell CSV is complete and parseable.
> - Report includes at least the recommended candidate (one of
>   A/B/C/D/E/F or "no candidate; recapture") for an M2 RTL slice.
> - ASCII-only on touched files.
>
> Stop-and-report (NO-GO) triggers:
> - Hardware unavailable; report partial coverage and request the
>   verifier complete the hardware run.
> - Self-check failures or the metric pipeline produces values
>   inconsistent with the synthetic test vector.
> - Captured audio shows persistent clipping at low velocity (would
>   indicate upstream chain issue, not a Phase 6 question).
>
> Hardware acceptance is the verifier's responsibility per project
> discipline. The implementer may produce the baseline harness and
> any synthetic-vector validation, then defer the live capture run
> to the verifier.
>
> Refs: `task-add5dc68` (this scope).

### Phase 6 M1 verifier task

> Review the implementer's M1 voice-baseline harness and report.
> If the implementer deferred the hardware capture, perform it.
>
> Required:
> - Confirm both Python `--self-check` modes PASS.
> - Run the full pitch x velocity grid against the live M2 board
>   (SOF as accepted at HEAD `5ee0c7c` checksum `0x0037620B`,
>   reprogram if needed and record checksum).
> - Confirm per-cell CSV completeness and that metrics fall within
>   sane ranges (e.g. attack < 50 ms, decay rate non-zero, no
>   clipping at velocity 0x4000).
> - Confirm P5M2 frames during the run show Q advancing exactly
>   with the count of valid commands and X stable.
> - Submit `reports/phase6_m1_voice_baseline_validation.md`.
> - Recommend whether the implementer's "first audible weakness"
>   selection is well-supported and what M2 RTL slice (one of
>   A/C/E from M0 scope, or none) should be queued.

## 8. Out of scope for this report

- No RTL change. No QSF change. No firmware change. No obsolete
  archive change. No live source files of any kind modified.
- No prediction of what M2/M3+ RTL slices will look like beyond the
  ranking in section 4. The M1 baseline data drives that decision.
- No claim about polyphony as a product feature. Four voices remain
  as overlap/stress infrastructure; polyphony count does not appear
  in any Phase 6 acceptance criterion.

ASCII-only by construction.
