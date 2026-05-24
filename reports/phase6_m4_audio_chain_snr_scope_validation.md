# Phase 6 M4 Audio-Chain SNR Scope - Verifier Validation

Date: 2026-05-24
Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-c5c9aab8`
Implementer commit under review: `0c38ce3` (Phase 6 M4 scope:
software-only repeated-capture coherent averaging)
Branch: `codex/phase1c-uart-boundary-fix`

## Verdict

**PASS.** The implementer's M4 scope is well-reasoned, honest
about the limits of what software averaging can fix, technically
sound on the math, and orchestrator-ready. The recommendation
(software-only repeated-capture coherent averaging in the
existing host tools) directly addresses the chain-SNR limitation
that left M3 verifier CONDITIONAL_PASS. Resource cost: zero RTL
LE, zero new UART surface, zero new hardware.

The orchestrator may queue the M4 implementer task with the
section 5 task text as written. No corrections required.

## Static / file scope check

`git show --stat 0c38ce3`:

```
reports/phase6_m4_audio_chain_snr_scope.md | 477 +++++++++++++++++
1 file changed, 477 insertions(+)
```

PASS gates:
- Single-file scope-only commit. No RTL/QSF/scripts/firmware/
  obsolete change.
- ASCII-only: byte count 19565, non_ascii=0 (PowerShell foreach
  byte loop).
- The scope explicitly forbids itself from script edits ("Out of
  scope for this scope task: ... no edits to .kiro/ or
  verifier-protected untracked artifacts ... no RTL change").

## Reasoning vs evidence

The scope's chain of reasoning:

1. M3 verifier CONDITIONAL_PASS at commit `9c3bf62` documents the
   exact limitation: chain noise floor ~-15 to -18 dBFS Gaussian
   masks 3-5 dB body-warmth deltas.
2. M2 verifier PASS at commit `27f7228` had a much larger band
   delta (4-7 kHz at +6 dB / 2x energy) that exceeded chain
   noise variance, hence statistical visibility.
3. Future timbre slices (B2 runtime knob, E loop-loss filter,
   D pre-strike noise) will produce smaller deltas than M2's
   brightness gain and need the same SNR margin M3 lacked.
4. Software coherent averaging at K=16 gives +12 dB SNR,
   sufficient for those future slices.

This chain matches the M3 validation report's conclusion
verbatim. PASS on reasoning.

## Coherent-averaging math review

The scope's claim: K coherent-averaged time-locked strikes give
`+10*log10(K) dB` SNR for time-locked signal + uncorrelated
Gaussian noise.

Independent derivation:

Let `s_i[n]` for `i in [0,K)` be the K captured strike windows,
each of length W samples, where:
- `s_i[n] = x[n] + e_i[n]` with `x[n]` deterministic (signal),
  `e_i[n]` uncorrelated Gaussian noise with variance `sigma^2`.

Coherent average:
- `avg[n] = (1/K) * sum_i s_i[n] = x[n] + (1/K) * sum_i e_i[n]`.

Noise term variance after averaging:
- The K `e_i[n]` are uncorrelated, each with variance `sigma^2`.
- Sum has variance `K * sigma^2`.
- Divided by K: variance `sigma^2 / K`, i.e. RMS `sigma/sqrt(K)`.

Signal stays at amplitude `x[n]` (peak unchanged).

SNR ratio gain: `sigma / (sigma/sqrt(K)) = sqrt(K)`.

In dB: `20*log10(sqrt(K)) = 10*log10(K)`.

At K=16: `10*log10(16) = 12.04 dB`.
At K=32: `10*log10(32) = 15.05 dB`.

Math: PASS. The scope's claim is correct.

Caveat correctly captured in section 8 of the scope: if the
chain noise is time-locked (e.g. 60 Hz hum, SMPS spikes at
predictable frequencies), it will NOT average away. The
scope's noise-floor characterization deliverable (script 3) is
specifically designed to detect this case and trigger an M5
fallback decision. PASS on caveat handling.

## Feasibility check

### Stimulus mechanics

Per cell at K=16: 16 events x (1 s settle + 4 s capture + 1 s
pause) = 96 s. Five cells: 480 s = 8 min per A/B run. Acceptable
for verifier work.

The reset+strike primitive uses ONLY existing M1.2 commands:
`!I1` once per session, `!F` per event (which now triggers
voice0 reset on the M3 SOF), `!NLLLLVVVV` per event. No new
UART surface.

The audio-chain capture is the existing ffmpeg dshow flow used
in M1.2/M2/M3. No new tooling.

### Sidecar schema bump (v1 -> v2)

The proposal: each cell records a list `send_t_session_s[]` of K
timestamps instead of a single value. Backward compatibility:
v2 sidecar with K=1 produces a single-element list, which the
analyzer handles in the same code path. PASS.

The implementer task text correctly requires the analyzer to
detect schema version and to treat a v2 sidecar with K=1 as
identical to v1. PASS.

### Per-cell SNR metric

`snr_db = 20*log10(strike_window_rms / silence_window_rms)`

Strike window: 100 ms post-strike. Silence window: 100 ms
pre-strike (after !F drains). At K=16 averaging, expected SNR
is the K=1 SNR + 12 dB.

Cells with `snr_db >= 10` are usable for FFT band comparisons;
cells with `snr_db >= 20` are usable for individual A/B without
averaging.

Math is correct; threshold values are pragmatic. PASS.

### Noise-floor characterization

`scripts/phase6_m4_noise_floor.py`:
- Captures 30 s of pure silence.
- Reports overall RMS dBFS, spectral magnitudes at power-grid
  harmonics (50, 60, 100, 120, 180, 240 Hz), Gaussian-fit
  chi-squared.
- Outputs a one-line classification.

This is the right diagnostic. If the chain is hum-dominated, the
scope explicitly states coherent averaging will not help and M5
fallback (external ADC or B2 runtime knob) should be invoked.
PASS.

## Deliverable / task text completeness

### Section 5 (implementer task text)

Covers:
- Required reading.
- Three scripts to modify/create (bench, analyzer, noise floor).
- Sidecar schema v2 specification with backward compatibility.
- Self-check requirement for all three scripts.
- Coherent-averaging synthetic test must demonstrate +12 dB at
  K=16 within 0.5 dB.
- Hard validation gates (no RTL/QSF/firmware/obsolete change,
  no new UART syntax, ASCII-only).
- Stop-and-report NO-GO triggers (synthetic shows < +12 dB at
  K=16, sidecar JSON round-trip fails).

Complete and orchestrator-ready.

### Section 6 (verifier task text)

Covers:
- Static file scope check.
- Re-run all 3 self-checks.
- Run noise-floor characterization on verifier machine.
- K=16 capture against M3 SOF on 5 focus cells.
- Run analyzer with --coherent-average; record per-cell SNR.
- FFT band comparison against M2 baseline.
- (Recommended) Run K=16 vs K=16 A/B by reprogramming M2 SOF.
- Variance gate: 3 K=16 captures of one cell, FFT variance <= 1
  dB.
- NO-GO classification: "noise floor exceeds software averaging
  capability" -> M5 = external ADC, OR "M4 software is buggy"
  -> back to implementer.

Complete and orchestrator-ready.

## Risk / fallback handling

### Risks correctly identified in scope

1. **Time-locked structured noise** (60 Hz hum, SMPS spikes):
   coherent averaging preserves it. Detection: noise-floor
   classifier. Mitigation: M5 = external ADC.
2. **External-ADC purchase**: deferred to M5 unless M4 fails.
3. **B2 runtime body knob**: deferred to M5 fallback if K=16
   software averaging is insufficient.
4. **Stronger excitation**: rejected because it re-introduces
   M2-era saturation.

### Critical observation about the bigger picture

Section 8 honestly notes M4 is **measurement infrastructure**,
not voice quality. The user's priority is voice quality. The
scope's argument for spending an M4 cycle on measurement is
that the next 3-5 voice-quality slices will be blocked on the
same SNR problem if M4 is skipped. This is the correct
trade-off given the M3 conditional pass.

The scope does NOT overpromise: it does not claim software
averaging will fix the audio chain itself, only that it will
provide K-fold SNR margin for time-locked signals. PASS.

## Independent technical concerns

### Concern 1: Audio chain stability across K=16 captures

If the audio chain noise floor drifts over the 8-minute run, the
last K strikes have a different noise profile than the first K.
The coherent average's noise sum becomes `sigma * sqrt(K)`
weighted by drift, NOT a clean `sigma / sqrt(K)`. The scope's
variance gate (3 K=16 runs, FFT variance <= 1 dB) catches this
case if the drift is faster than per-strike. The scope does not
explicitly call this out but the variance gate is sufficient.

Recommendation to orchestrator (non-blocking): the M4 verifier
report could optionally include a "long-term stability" note
comparing the first 8 strikes' coherent-average against the last
8 strikes' coherent-average within a single K=16 run.

### Concern 2: Voice0 state between K strikes

The M1.2 reset-on-!F clears voice0 delay line. After the !F at
the start of each event, voice0 is silent. The M3 build adds
body_mix=12288 + retuned biquad 2; the body filter biquad has
its own state but converges to zero quickly with zero input.
After the per-cell 1.0 s settle, both voice0 and biquad state
should be at noise floor. K iterations should produce identical
strike conditions. PASS by construction.

### Concern 3: Sidecar schema v1/v2 dual code path

The implementer must thread `--repeats` through both bench and
analyzer. The bench writes the sidecar; the analyzer reads it.
Backward compatibility (v1 sidecar -> analyzer treats K=1)
requires the analyzer to detect schema and convert internally.
The implementer task text section 5 correctly requires this.
PASS.

## Out of scope for this scope task

- No RTL change (correctly forbidden).
- No QSF change (correctly forbidden).
- No script edits in this scope task (verifier respects this).
- No CPU/firmware/MMIO revival.
- No new UART command surface.
- ASCII-only validation report.

## ASCII check

```
reports/phase6_m4_audio_chain_snr_scope_validation.md non_ascii=0
```

(Verified before commit by PowerShell foreach byte loop.)

## Final verdict

**PASS.** Phase 6 M4 scope is approved for implementer queueing
as written.

The scope:
- Correctly identifies audio chain SNR as the blocker for future
  voice-quality A/B work.
- Recommends the lowest-cost path (software-only K-fold coherent
  averaging in existing host tools).
- Validates the math (independently re-derived: +10*log10(K) dB
  for time-locked signal + uncorrelated Gaussian noise).
- Designs the noise-floor classifier as a guard against the
  case where averaging cannot help (time-locked structured
  noise).
- Provides complete, orchestrator-ready implementer + verifier
  task text with concrete acceptance gates.
- Honestly frames the trade-off (this is measurement
  infrastructure, not voice quality, but unblocks future voice
  quality slices).

The orchestrator may queue the M4 software-only implementer task
at this scope's section 5 text without modification.
