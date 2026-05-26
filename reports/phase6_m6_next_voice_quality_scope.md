# Phase 6 M6 Next Voice-Quality Scope (Post-M5 Body Knob)

Date: 2026-05-25
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-0072201e`
Branch: `codex/phase1c-uart-boundary-fix`
Parent commit: `40f44e2` (Phase 6 M5 cap-raise validation PASS)
Implementer report under review: this scope (no RTL/host-script
changes).

## TL;DR

**Recommendation: Phase 6 M6 splits cleanly into two narrow
workstreams.**

1. **Immediate workstream (this milestone, ASAP):** add a small
   host-side body_mix sweep harness that drives the newly accepted
   `!B<vvvv>\r\n` knob across a controlled grid, captures audio
   under the existing `--single-voice-isolate` + `!F` reset
   methodology, and produces A/B reference data at multiple
   warmth set-points. No RTL change. Designed to produce useful
   evidence today (intra-run sweeps create deltas large enough
   for the user's own subjective listening) and to become an
   immediate post-isolator measurement protocol the verifier can
   rerun in minutes.
2. **Hardware-arrival workstream (queued behind isolator
   delivery):** verifier-only acceptance of the user-ordered
   passive 3.5 mm transformer ground-loop isolator, followed by
   rerun of M4 K=16 coherent-averaged A/B between contrasting `!B`
   values to objectively grade M2 brightness, M3 warmth, and M5
   body-mix range on a clean chain.

**Explicit deferral:** Candidate E (loop-loss / differential
decay) and Candidate D (pre-strike noise) remain blocked. E is
specifically risky because it adds a new IIR pole *inside* the
waveguide loop-loss path, the worst place to attack with only
+0.620 ns of slow-85C setup margin remaining and after M5 already
unfolded four per-voice multipliers. These are M7+ candidates
behind isolator-validated audible evidence.

| M6 immediate (this slice) | M6 hardware-arrival follow-up |
| --- | --- |
| Host-tool only (Python script + report) | Verifier-only hardware acceptance |
| Add `scripts/phase6_m6_body_mix_sweep.py` | Reuse `scripts/phase6_m4_noise_floor.py` + bench |
| Drive `!B` grid + isolated strike per cell | Confirm `GAUSSIAN_CLEAN` post-isolator |
| Capture/CSV + A/B summary report | Rerun K=16 A/B between `!B3000` and `!B6000` |
| RTL change: NONE | RTL change: NONE |
| LE/timing risk: NONE | LE/timing risk: NONE |
| Hardware gate: useful intra-run warmth deltas captured | Hardware gate: chain SNR clean and timbre A/B decisive |
| Honest acceptance: pre-isolator data may still be noise-bound; classify accordingly. | Acceptance: M2/M3/M5 timbre slices objectively graded. |

## 1. Phase 6 state at end of M5

Accepted live point at commit `40f44e2`:

| Metric | Value | Headroom |
| --- | ---: | ---: |
| Total logic elements | 5,105 / 10,320 (49%) | 5,215 free |
| Combinational LEs | 4,843 | - |
| Registers | 2,305 | - |
| M9K blocks | 8 | - |
| DSP9 elements | 26 / 46 (57%) | - |
| PLL | 1 / 2 (50%) | 1 free |
| Setup slow-85C `sys_clk_50m` | +4.620 ns | +0.620 ns above +4.0 ns hard gate |
| Hold slow-85C | +0.414 ns | clean |
| All TNS | 0 | - |
| Quartus errors / warnings | 0 / 16 | - |

Live capabilities now include:

- Four physical `phase1_reduced_voice` instances (preserved).
- Three-layer velocity-to-brightness hammer (M2 / M7).
- M3 retuned body filter biquad 2 at 1500 Hz +3 dB Q=1.5.
- Default body_mix on reset = 0x3000 (M3 preset preserved).
- M3a-accepted parser: `!N`, `!NLLLLVVVV`, `!F`, `!I0`, `!I1`,
  and now `!B<vvvv>` (M5).
- M4 measurement infrastructure: `--repeats K`, coherent
  averaging in the analyzer, `phase6_m4_noise_floor.py`
  classifier. All `--self-check` modes pass; ready for
  post-isolator use.

Live capability gaps and binding constraints:

- **Audio capture chain is USB-ground-loop limited.** Per
  `reports/phase6_chain_noise_debug.md`, both USB-UART and
  USB-Blaster inject the same 82 / 329 / 410 Hz spectral peaks;
  the median floor sits about -78 to -85 dBFS while the legacy
  sample.wav baseline was -95 dBFS. M5 final audio A/B is
  explicitly deferred until the user-ordered passive 3.5 mm
  transformer isolator arrives.
- **Setup slack +4.620 ns is moderate.** Future RTL slices that
  add combinational depth inside the waveguide loop will tend to
  shave this margin. The floor is +4.0 ns hard, leaving only
  +0.620 ns of tolerance for placement variance and deeper
  pipelines.
- **Body multiplier path is now per-voice unfolded.** M5 paid
  +173 LE specifically because making body_mix runtime-variable
  removed constant folding on four `body_mix_q15 *
  body_history_tap` multipliers. Any candidate that further
  parameterises a per-voice path will hit a similar intrinsic
  cost.

## 2. Plausible next-step candidates

### M5.1: Isolator acceptance + rerun M4/M5 A/B (verifier-only)

What it is. The user has ordered a passive transformer isolator
to break the laptop's USB ground loop. When it arrives, verifier
captures 30 s of silence with the isolator inserted, runs
`scripts/phase6_m4_noise_floor.py`, and confirms classification
moves from `HUM_60HZ_DOMINATED` to `GAUSSIAN_CLEAN` with median
floor <= -90 dBFS. After acceptance, verifier reruns the M4
K=16 protocol with two contrasting `!B` values and grades the
warmth/brightness deltas objectively.

Pros.

- Zero RTL/host-tool risk. Pure verifier hardware procedure.
- Resolves the M3/M5 measurement-chain blocker that has produced
  CONDITIONAL_PASS / inconclusive A/B verdicts since M3.
- Unblocks the entire remaining Phase 6 slice list (E, D, F)
  with a measurable evidence base.

Cons / risks.

- Cannot start until isolator arrives.
- If isolator does not break the loop (rare for transformer
  designs), need a backup capture path (external USB ADC). Scope
  must define the fallback.

When to queue. As a verifier-only task the moment the isolator
hardware lands. Implementer should not block on it.

### Candidate E: Loop-loss / differential decay (RTL)

What it is. Replace the current single-coefficient `damp_mix`
mixer inside the loop-loss path with a small one-pole IIR (or
biquad) so that upper harmonics decay faster than the
fundamental. This is a real piano-string behaviour and has high
audible value once measurable.

Pros.

- High audible value. Verifier reports across M2/M3/M5 explicitly
  flag short, uniform-rate decay as the next perceptual weakness
  after dryness.

Cons / risks.

- **Adds an IIR pole inside the waveguide feedback loop.** This
  is the single highest-risk place in the design to add depth.
  Stability requires careful coefficient selection; sub-optimal
  coefficients can produce limit cycles, low-frequency growl, or
  outright self-oscillation at the loop boundary.
- **Setup margin is the binding constraint.** The new pole adds
  one more multiplier and adder pair into the per-voice
  STATE_DAMP_A/B chain, which is already part of the 11-state
  per-sample FSM. Estimated setup-slack hit is -0.3 to -0.6 ns;
  with only +0.620 ns of margin above the +4.0 ns hard gate,
  this candidate is plausibly NO-GO without floorplan or
  pipeline restructuring.
- **Validation is hard without a clean chain.** The audible
  improvement from differential decay is a per-frequency-band
  effect. With the current capture chain, FFT band comparisons
  are noise-bound at exactly the 1-3 kHz / 3-7 kHz bands where
  the effect lives.

When to queue. Earliest appropriate point is M7 or later, after
isolator acceptance + M5.1 grading produces a clean baseline. If
the M5.1 A/B confirms M2 brightness and M3 warmth are working,
candidate E becomes the obvious next slice.

### Candidate D: Pre-strike noise / attack texture (RTL)

What it is. Add a 1-2 ms shaped noise burst before the existing
hammer ROM excitation, modelling the small mechanical thud of a
real piano hammer striking the string. M2 and M3 listening notes
flag attack as already brighter / cleaner; the residual weakness
is the slightly synthetic / clinical character of the strike
instant.

Pros.

- Modest audible value. M2 already addressed brightness.
- Simulation-friendly: the audible delta is in the first
  ~10 ms, which is easily windowed in the M1 analyzer.

Cons / risks.

- **New state in `phase1_reduced_voice.v`.** Either a small
  noise generator (LFSR ~16 bits) plus an envelope shaper, or a
  short pre-strike ROM. Both add ~80-150 LE per voice path, but
  in practice may be shareable across voices, dropping to
  ~60-100 LE total.
- **New mix point.** The pre-strike noise must mix into the
  excitation path before the body filter, requiring care so it
  does not break the M2 `excitation_rom` golden TB.
- **Polyphony interaction unclear.** If the noise generator is
  per-voice it scales linearly; if shared, multiple
  simultaneously-triggered voices produce identical noise
  bursts (acceptable; piano-realistic).

When to queue. M7 or M8 candidate. Lower priority than E because
the audible weakness M2/M3 listeners flagged is sustain
character, not attack texture. Re-rank after M5.1 A/B evidence.

### Candidate B-prime: Body-mix sweep protocol (host-tool only)

What it is. Build a small Python script that uses the now-live
`!B<vvvv>` runtime knob to sweep body_mix across a chosen grid
within a single capture session. For each grid point, send `!B`
to set the body mix, then run a small subset of the existing M1
isolated-strike protocol (e.g. A4 0x7FFF, C5 0x7FFF). Aggregate
results into a CSV labelled by body_mix value and produce an
A/B summary.

Pros.

- **Zero RTL risk.** Pure host-tool addition; no LE/timing/PLL
  impact whatsoever. Setup slack is preserved exactly.
- **Useful pre-isolator.** Intra-run body_mix deltas of 4096-8192
  units (out of 16384) produce >6 dB of audible warmth swing,
  which is comfortably above the current chain noise variance
  (~1-3 dB across cells). The user can listen and pick a
  preferred warmth setpoint today, even on the noisy chain.
- **Becomes the canonical post-isolator A/B protocol.** Same
  script runs unchanged after isolator arrival, producing
  objective FFT-band deltas in addition to subjective evidence.
- **Reuses M4 infrastructure.** `--repeats K` and the analyzer's
  `--coherent-average` flag work as-is once the chain is clean.

Cons / risks.

- Pre-isolator results will still be CONDITIONAL on chain noise.
  The script must classify cells whose strike RMS is at-or-below
  the noise floor and report them honestly rather than fabricate
  precise deltas.
- Adds a small new committed script and report; no behaviour
  regression risk.

When to queue. **Now.** This is the recommended M6 immediate
workstream.

### No-op / wait for isolator

What it is. Pause new RTL or host-tool work until the isolator
arrives.

Pros.

- Zero risk.
- Concentrates all measurement effort on a clean post-isolator
  baseline.

Cons.

- Wastes the immediate window before isolator delivery.
- Loses the opportunity to use M5's runtime knob for any
  evidence-gathering (subjective listening, intra-run sweeps).
- The body_mix sweep harness is also useful AFTER the isolator,
  so building it now is not throwaway work.

Verdict. Strictly inferior to the body-mix sweep protocol; the
sweep harness is small and useful in both pre- and
post-isolator regimes.

## 3. Recommendation

### Immediate M6 workstream: body-mix sweep harness

**Add `scripts/phase6_m6_body_mix_sweep.py`** as a small
Python harness that:

1. Opens the existing UART (default `COM5`) at 115200 8N1.
2. Sends `!I1\r\n` to enter single-voice isolation mode.
3. For each body_mix value in a configurable grid (default
   `[0x1000, 0x2000, 0x3000, 0x4000, 0x6000, 0x8000, 0xC000]`):
   a. Send `!B<vvvv>\r\n` to set runtime body_mix.
   b. Wait 100 ms for register update to propagate.
   c. For each pitch in a small subset (default A4 loop_len 106
      and C5 loop_len 89, both at velocity 0x7FFF):
      i. Send `!F\r\n` (which under isolation also resets
         voice0).
      ii. Wait 1.0 s settle.
      iii. Send `!N<loop>7FFF\r\n`.
      iv. Capture analog audio for 4 s starting at the send
          moment.
      v. Pause 1 s.
4. Send `!I0\r\n` to leave isolation mode.
5. Optionally invoke `scripts/phase6_m1_voice_analyze.py` over
   the resulting WAV (with sidecar JSON that labels each cell by
   body_mix value).

Provide a `--self-check` mode that exercises the command-stream
generation without hardware (proves grid parsing, valid `!B`
hex, and CRLF framing).

Provide a `--plan` mode that prints the total session duration
and the exact byte sequence so verifier can confirm before
running hardware.

Output. CSV row format:

```
body_mix_hex,pitch,loop_len_hex,velocity_hex,peak_dbfs,
rms_100ms_dbfs,rms_500ms_dbfs,attack_ms,decay_db_per_s,
spectral_centroid_hz,clipping_count,silence_after_ms,
chain_noise_floor_dbfs,classified_above_or_below_noise
```

The `classified_above_or_below_noise` column flags cells where
strike RMS is within 3 dB of the chain noise floor; pre-isolator
those cells are reported but not used for FFT-band claims.

Report. `reports/phase6_m6_body_mix_sweep_impl.md` with file
scope, command syntax, expected runtime, sample sweep transcript
(from --plan), and explicit framing of pre- vs post-isolator
acceptance.

Files touched. Exactly two:

- `scripts/phase6_m6_body_mix_sweep.py` (new, ASCII-only).
- `reports/phase6_m6_body_mix_sweep_impl.md` (new, ASCII-only).

LE/timing/RTL impact. None.

### Hardware-arrival workstream: M5.1 isolator acceptance

When the isolator hardware lands, queue a verifier task that:

1. Inserts the isolator on the analog audio path.
2. Captures 30 s of silence.
3. Runs `scripts/phase6_m4_noise_floor.py` and records the
   classification, median floor, and per-frequency hum
   magnitudes.
4. Acceptance gate: classification = `GAUSSIAN_CLEAN` AND
   median floor <= -90 dBFS AND worst hum-to-floor <= +6 dB.
5. If accepted, immediately rerun the M6 body_mix sweep with
   `--repeats 16` and run the analyzer with
   `--coherent-average`. Report per-band FFT deltas between
   `!B3000` and `!B6000` (or whichever pair the M6 immediate
   workstream identified as most useful).
6. Submit `reports/phase6_m5_1_isolator_acceptance_validation.md`.

If isolator does not pass acceptance, fallback to procuring a
small external USB audio interface (USD 50-200 range) and rerun
the same protocol. Document fallback choice in the validation
report.

Files touched. Validation report only; no source changes.

## 4. Honest assessment

### Why not Candidate E now

Setup slack is the binding constraint. The slow-85C `sys_clk_50m`
slack at +4.620 ns has +0.620 ns of margin above the +4.0 ns
hard gate. The waveguide loop-loss path (states
`STATE_DAMP_A_SETUP` -> `STATE_DAMP_A_FINISH` ->
`STATE_DAMP_B_FINISH` -> `STATE_GAIN_FINISH` in
`phase1_reduced_voice.v`) is currently a 4-state pipeline with
one 18-bit signed multiplier shared via `mult_sample` /
`mult_coeff`. Adding a one-pole IIR adds at least one more
multiply-and-accumulate stage; even retimed across an extra
state, fitter placement variance often costs 0.2-0.5 ns.

Beyond timing, an inside-the-loop pole adds a real stability
risk. The waveguide already has `loop_gain_q15 = 16'd32640`, very
close to unity. A poorly-tuned IIR pole at the same node can push
the closed-loop response over unity at some frequency, producing
limit cycles or growth. This is a known difficulty with digital
waveguide loop filters; getting it right requires:

- Coefficient derivation tied to the chosen `loop_gain` and
  target decay rates per harmonic band.
- A standalone module testbench (the current
  `phase1_reduced_voice_tb` is not enough) that exercises stable
  ringdown across the full velocity / loop_len grid, including
  the worst-case loop_len = 32 / 127 boundary cells.
- Hardware A/B that distinguishes the intended differential-decay
  effect from generic muddiness or premature die-off.

The third bullet is exactly what the audio-chain noise floor is
currently masking. Doing E now means risking three different
unknowns in one slice: stability, timing margin, and audible
correctness. Doing E after M5.1 isolator acceptance reduces it
to two, with the third (audible correctness) on a clean
measurement chain.

### Why not Candidate D now

D is moderate audible value (the user already has a brighter,
cleaner attack from M2). It also adds new RTL state, requires
deciding shared-vs-per-voice noise generation, and like E
benefits from clean A/B evidence. Lower priority than E.

### Why this scope is honest about pre-isolator measurement

The body-mix sweep harness will produce structured pre-isolator
data, but the data must be classified honestly:

- Cells where strike RMS is within 3 dB of the chain noise floor
  cannot support precise FFT-band claims.
- The user's own subjective listening is a valid acceptance path
  for an intra-run warmth setpoint preference, especially given
  that body_mix changes of 4096+ units produce >6 dB of warmth
  swing (well above the chain noise variance of ~1-3 dB).
- Final M3/M5 timbre A/B objective evidence remains gated behind
  the isolator. The harness is designed so the same script
  produces objective A/B once the chain is clean.

This is the same discipline the M3 verifier and chain-noise debug
reports applied: do not fabricate precision when the
measurement is noise-bound; document what is achievable and what
is deferred.

## 5. Out of scope for this scope task

- No RTL change.
- No host-script change (the body-mix sweep script is described
  here but lives in the next implementer task).
- No QSF / SDC / PLL / firmware / obsolete archive change.
- No CPU / firmware / MMIO / register-file revival.
- No JTAG command path.
- No on-chip strike scheduler.
- No polyphony feature work.
- No edits to verifier-protected untracked files (`.kiro/`,
  prior-phase UART/audio captures).

ASCII-only on this report.

## 6. Recommended task text (orchestrator-ready)

### Phase 6 M6 implementer task: body_mix sweep host harness

> Implement Phase 6 M6: host-side body_mix sweep harness using
> the accepted M5 `!B<vvvv>` runtime knob.
>
> Read first:
> - reports/phase6_m6_next_voice_quality_scope.md
> - reports/phase6_m5_body_knob_cap_raise_validation.md
> - reports/phase6_chain_noise_debug.md
> - reports/phase6_m4_repeated_capture_validation.md
> - scripts/phase6_m1_voice_bench.py
> - scripts/phase6_m1_voice_analyze.py
> - scripts/phase6_m4_noise_floor.py
>
> Required deliverables:
> 1. New scripts/phase6_m6_body_mix_sweep.py:
>    - pure-Python (stdlib + pyserial), ASCII-only.
>    - Drives !I1, then a configurable body_mix x pitch grid via
>      !B and !N/!F commands, then !I0.
>    - Default grid: body_mix in
>      {0x1000, 0x2000, 0x3000, 0x4000, 0x6000, 0x8000, 0xC000};
>      pitch in {A4 loop_len 106, C5 loop_len 89}; velocity 0x7FFF.
>    - Per-cell pacing: !F + 1.0 s settle, !N strike, 4.0 s
>      capture window, 1.0 s pause.
>    - Sidecar JSON includes body_mix value per cell.
>    - --self-check mode validates command-stream generation
>      without hardware.
>    - --plan mode prints session duration and full byte sequence.
>    - Optional --analyze flag invokes
>      scripts/phase6_m1_voice_analyze.py over the resulting
>      capture if the analyzer supports body_mix-labelled cells.
> 2. New reports/phase6_m6_body_mix_sweep_impl.md documenting
>    file scope, expected runtime, --self-check transcript,
>    --plan transcript, and explicit pre- vs post-isolator
>    acceptance framing.
>
> Hard gates:
> - --self-check PASS.
> - No RTL/QSF/firmware/obsolete change.
> - No new UART command syntax (reuses existing !B/!N/!F/!I0/!I1).
> - ASCII-only on touched files.
> - No edits to scripts/phase6_m1_voice_bench.py or
>   scripts/phase6_m1_voice_analyze.py unless a tiny
>   body_mix-labelling extension is genuinely required and
>   minimal.
>
> Stop-and-report NO-GO triggers:
> - Live capture chain unavailable (no COM5 enumerated).
> - --self-check failure.
>
> Hardware capture is the verifier's responsibility per project
> discipline. Implementer may produce the harness and
> --self-check evidence, then defer the live sweep to verifier.
>
> Refs: task-0072201e (this scope).

### Phase 6 M6 verifier task: body_mix sweep live capture

> Validate Phase 6 M6 body_mix sweep harness and complete the
> live capture.
>
> Required scope:
> 1. Confirm scope: only scripts/phase6_m6_body_mix_sweep.py and
>    reports/phase6_m6_body_mix_sweep_impl.md changed. Fail if
>    RTL, QSF, firmware, obsolete archive, or accepted baseline
>    reports changed unexpectedly.
> 2. Confirm ASCII-only on touched files.
> 3. Re-run --self-check and --plan; record exact output.
> 4. Run live sweep against COM5 with the M5 SOF
>    (sha256 1E59C516502B8E603ED66DB50A4CDEA0ED466F093351C89AF80D2E9EF2BC6F09)
>    or the latest accepted SOF if newer; reprogram if needed
>    and record checksum.
> 5. Capture analog audio over the full sweep duration into a
>    16-bit PCM WAV (verifier-local, not committed; just record
>    path + size + checksum).
> 6. Analyze with scripts/phase6_m1_voice_analyze.py
>    (or the body_mix-labelled extension); produce
>    reports/phase6_m6_body_mix_sweep.csv and
>    reports/phase6_m6_body_mix_sweep_analyzed.md.
> 7. P5M2 telemetry checks: Q advances by exactly the count of
>    valid commands sent (1 + N_body_mix x N_pitch x 2 + 1 =
>    1 + 7 x 2 x 2 + 1 = 30 for the default grid). X remains 0.
> 8. Acceptance:
>    - Pre-isolator: PASS if sweep runs cleanly, P5M2 telemetry
>      matches, and the CSV honestly classifies cells against
>      the chain noise floor.
>    - Post-isolator (if isolator already accepted under M5.1):
>      additionally require that body_mix differences produce
>      monotonically increasing 1-3 kHz band energy as body_mix
>      grows from 0x1000 -> 0x8000, with the trend at least
>      partially visible above the chain noise.
> 9. Submit reports/phase6_m6_body_mix_sweep_validation.md.
>
> Guardrails:
> - Do not implement RTL or scripts in verifier role.
> - Do not commit large WAV files.
> - Do not touch stale untracked Phase 3/4/5 captures or .kiro/.
>
> Refs: task-0072201e (M6 scope).

### Phase 6 M5.1 verifier task (queue when isolator hardware arrives)

> Run the user-ordered passive 3.5 mm transformer ground-loop
> isolator acceptance and post-isolator A/B grading.
>
> Required:
> 1. Insert the isolator on the analog audio chain between the
>    board's headphone jack and the laptop capture endpoint.
> 2. Capture 30 s of silence (board powered, no commands).
> 3. Run scripts/phase6_m4_noise_floor.py against the silence
>    capture. Record classification, total RMS, median floor,
>    50/60/100/120/180/240 Hz hum magnitudes, gaussian_chi2,
>    worst hum-to-floor.
> 4. Acceptance gate: classification = GAUSSIAN_CLEAN AND
>    median floor <= -90 dBFS AND worst hum-to-floor <= +6 dB.
> 5. If accepted: rerun scripts/phase6_m6_body_mix_sweep.py
>    with --repeats 16 and analyze with --coherent-average.
>    Report FFT-band deltas between !B3000 and !B6000 in the
>    1-3 kHz band; expected M3+M5 warmth gain is +3 to +6 dB.
>    Optionally also rerun the M2 vs M3 SOF A/B if older
>    bitstreams are still locally archived.
> 6. If isolator fails acceptance: fallback to procuring a
>    small external USB audio interface and rerun this same
>    procedure. Document the fallback choice and revised noise
>    floor in the same validation report.
> 7. Submit reports/phase6_m5_1_isolator_acceptance_validation.md.
>
> Guardrails:
> - No RTL/host-script changes.
> - Do not commit large WAV files.
>
> Refs: reports/phase6_chain_noise_debug.md.

## 7. Why this is the right next slice

- It produces evidence that is useful before AND after the
  isolator arrives, with no rework.
- It exercises the M5 runtime knob exactly as designed.
- It carries zero RTL/timing/LE risk at a moment when setup
  margin is the binding constraint.
- It is the smallest possible step that gives the user
  immediate feedback (subjective intra-run sweeps today) while
  setting up objective post-isolator A/B with no further code
  work needed.
- It explicitly defers the higher-risk timbre slices (E, D)
  behind clean evidence, which is the same discipline that has
  worked through M2 / M3 / M5.

## 8. Files

This report:

- `reports/phase6_m6_next_voice_quality_scope.md` (new).

No RTL, host-script, QSF, SDC, firmware, obsolete archive,
generated-output, or stale-untracked-file change.

## 9. ASCII check

```
reports/phase6_m6_next_voice_quality_scope.md non_ascii=0
```

(Verified before commit by the standard PowerShell foreach-byte
check.)
