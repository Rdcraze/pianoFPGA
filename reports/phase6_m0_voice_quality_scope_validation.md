# Phase 6 M0 Voice-Quality-First Scope Validation

Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-6dd3c632` (depends on implementer `task-add5dc68`)
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `fa5a443`

## Verdict

**PASS.** The Phase 6 M0 voice-quality-first scope report is
acceptance-grade as a planning artifact. Commit `fa5a443` is single-
file and report-only, ASCII-only. The recommendation that Phase 6
M1 should be a no-RTL voice-quality benchmark and audio-capture
tooling slice (with RTL voice-quality experiments deferred to M2+)
matches the user's "voice quality over polyphony" direction exactly,
respects the accepted Phase 5 fixed-function architecture without
reviving any obsolete CPU/firmware/MMIO paths, and produces an
evidence baseline that any future RTL slice can A/B against.

The proposed benchmark grid (5 pitches x 3 velocities), the metric
set (peak/RMS/attack/decay/spectral centroid/clipping/silence), and
the ranked candidate list for M2+ are all reasonable and bounded.
The report does not over-promise polyphony and explicitly keeps the
four physical voice instances as overlap/stress infrastructure,
matching the user's direction.

## Scope check

`git show --stat fa5a443`:

```
reports/phase6_m0_voice_quality_scope.md | 431 +++++++++++++++++++++
1 file changed, 431 insertions(+)
```

`git diff fa5a443^..fa5a443 -- ':!reports/phase6_m0_voice_quality_scope.md'`
returns no other diff. No RTL, QSF, SDC, firmware, host tools,
generated outputs, scripts, or `obsolete/` files modified. PASS.

## ASCII check

`reports/phase6_m0_voice_quality_scope.md`: 0 non-ASCII bytes
(21,240 bytes total). PASS.

## Architecture / accepted-baseline alignment

The report's Phase 5 baseline summary matches my own Phase 5
closeout validation findings:
- Live control plane is `phase0_fixed_control` plus
  `phase0_uart_command` (RX) plus `phase0_uart_status_tx` (TX),
  sys_clk-domain only, no CDC.
- Old RV32I + firmware C + MMIO + register-file stack remains
  archived under `obsolete/riscv_control/`, not revived.
- Four physical `phase1_reduced_voice` instances preserved in
  `rtl/audio/phase0_audio_path.v` (verified live: 4 instance
  declarations).
- Existing M2 UART command surface `!N` / `!NLLLLVVVV` / `!F` and
  P5M2 status frame Q/X are the only host-side touchpoints; the
  scope explicitly avoids broadening that surface in M1.

Static voice-parameter quotes (`loop_gain_q15 = 16'd32640`,
`damp_mix_q15 = 16'd16384`, `disp_coeff_q15 = 16'sd9952`,
`body_mix_q15 = 16'd8192`, M7 layer-1 threshold 0x6000) match
`phase0_fixed_control.v` source as reviewed in M2 validation. The
runtime-writable note on `damp_mix_q15` (raised to `16'd32767` on
`!F` and restored on next `!N`) matches M2 source as well.

Audio-relevant module descriptions (delay-line M9K, body filter
biquads, body-history M9K with taps at 7/17/31, M7 velocity layer
threshold) match the Phase 4 M7 acceptance baseline. PASS.

## M1 path assessment

The report's case for "no-RTL benchmark first" is compelling and
matches my own observation across M0..M3 audio captures:
- All four M0/M1/M2/M3 captures produced room-mic peak around
  -24 dBFS and RMS around -35 dBFS with no per-cell breakdown.
- The captures were sufficient to confirm "control plane works,
  no clipping, no silence" but cannot drive specific
  voice-quality decisions.
- Building the benchmark harness first lets every future Phase 6
  RTL slice be measured against a structured baseline rather than
  guessed against vibes.

The harness is bounded:
- Pure-Python (stdlib + pyserial), ASCII-only, two scripts (bench
  + analyze) plus a CSV plus a markdown narrative report.
- Uses the existing M2 UART command surface unchanged.
- No new command syntax, no RTL touchpoints.
- `--self-check` modes for both scripts, plus a synthetic test
  vector for the analyze pipeline.

Honest limitations called out in the report:
- The clamp at `loop_len <= 127` means the lowest-pitch cell is
  ~370 Hz, not actually A2 (110 Hz). The report names this
  explicitly.
- P5M2 Q/X are used only as command-health telemetry, not as
  audio evidence. This avoids the trap of over-interpreting
  status counters.
- Subjective assessments are required to follow a strict format
  ("Sounds like / Closest piano analog / Most audible weakness /
  Recommended candidate") rather than free-form vibes.

PASS.

## Benchmark grid / metric coverage assessment

| Item | Coverage | Verdict |
| --- | --- | --- |
| Reference loop_len 106 (A4) | included | PASS |
| Lower pitch (loop_len 127) | included with honest A2-clamp note | PASS |
| Higher pitch (loop_len 32) | included | PASS |
| Mid-range pitch (loop_len 89, 53) | included | PASS |
| Low velocity (0x2000) | included | PASS |
| TB-default velocity (0x4000) | included | PASS |
| Full-scale velocity (0x7FFF, M7 layer 1) | included | PASS |
| Peak amplitude metric | included | PASS |
| RMS over multiple windows | included (100 ms / 500 ms / 3 s) | PASS |
| Attack transient | included (time-to-peak) | PASS |
| Decay envelope | included (dB/s over 100 ms-1 s window) | PASS |
| Spectral brightness | included (FFT centroid over first 250 ms) | PASS |
| Clipping count | included | PASS |
| Silence-after-strike count | included | PASS |
| Subjective assessment format | structured, honest, includes "none observed" option | PASS |
| Honest limit on M1 conclusion | report explicitly allows "no obvious weakness; defer M2 selection to a separate listening test" | PASS |

The 5x3 grid plus 8 metrics is the right amount of structure: rich
enough to expose specific weaknesses, small enough to capture in
a single hardware session (~75 s of audio total). PASS.

## M2+ candidate list assessment

The ranking does not over-promise polyphony or speculative RTL
work. Each candidate row has:
- Audible-value qualitative call.
- LE estimate.
- Risk class.
- Testability call.
- Recommended position relative to M1 baseline evidence.

| Candidate | Audible value | LE | Position |
| --- | --- | ---: | --- |
| A. Velocity-to-brightness curve (extend M7) | High | +50-150 | M2 frontrunner if velocity dynamics flat |
| B. Body filter coefficient runtime knob | Medium-high | +200-300 | M3+ if listener wants tunable coloration |
| C. Loop-gain / damp-mix runtime knob | High for sustain control | +150-250 | M2 if decay too short/long |
| D. Pre-strike noise component | Moderate | +200-400 | M3+ if attack unconvincing |
| E. Loop-loss filter shape | High for mid-range realism | +150-300 | M2/M3 if uniform decay |
| F. Per-voice independent release | Low for voice quality | +100-200 | NOT recommended for Phase 6 |

This list is appropriately conservative. Three candidates (A, C, E)
are direct voice-quality improvements that ride on the existing
audio path with bounded LE/timing risk. F is correctly demoted.
The report does not claim any one of them will succeed; it makes
selection contingent on M1 baseline evidence. PASS.

## Polyphony discipline check

The report's section 1 explicitly states:
> Conservative on polyphony: the four physical voices remain in
> place as overlap/stress infrastructure. Polyphony count is not a
> product feature for Phase 6 and should not appear in any Phase 6
> acceptance criterion.

The report's section 8 also states:
> No claim about polyphony as a product feature. Four voices remain
> as overlap/stress infrastructure; polyphony count does not appear
> in any Phase 6 acceptance criterion.

This matches the user's direction precisely. The report does not
revive LRU stealing, per-voice release, or any polyphony-feature
proposal. PASS.

## CPU / firmware / MMIO discipline check

The report does not propose firmware revival, MMIO bus, or CPU
re-introduction. Section 1 states "no CPU revival" explicitly:
> Phase 6 must remain inside the fixed-function control
> architecture. UART command extensions (like a runtime body_mix
> knob) are acceptable; firmware/MMIO/register-file revival is not.

Candidates B (body coefficient knob) and C (loop-gain / damp-mix
knob) extend the protocol surface only via new tiny RTL command
parser additions, not via firmware. PASS.

## Implementer / verifier task split assessment

Section 7's proposed M1 implementer task description is bounded
and concrete. It covers:
- Read-list (M0 scope, M5 closeout, M7 hammer impl, voice and body
  filter source for parameter ranges).
- Three new files (two scripts + one report) plus a CSV.
- Hard validation gates (both Python `--self-check` PASS, full grid
  capture, per-cell CSV complete, recommended next-candidate or
  "no candidate; recapture", ASCII-only).
- Stop-and-report (NO-GO) triggers covering hardware unavailable,
  self-check failures, persistent clipping at low velocity.
- Explicit deferral of the hardware capture run to the verifier
  if implementer cannot reach hardware, matching project
  discipline.

The proposed verifier task is symmetric: re-run self-checks, run
the full grid against the live M2 board, confirm per-cell CSV
sanity, confirm Q/X behavior, submit a validation report, recommend
the M2 RTL slice (or "none; recapture").

Both tasks are implementer-ready and verifier-ready. PASS.

## Honest assessment / non-blocking notes

- The M1 acceptance gate "Captured audio shows non-clipping at all
  velocities except where explicit clipping was the goal (none
  expected in this baseline)" implicitly assumes the current
  velocity 0x7FFF + M7 layer 1 + body-filter passband does not
  clip on the analog path. M0/M1/M2/M3 captures so far did not
  clip, but the M3 captures used the autonomous round-robin
  scheduler which fires only one voice at a time. The benchmark
  harness sends one strike per cell with `!F` settle between, so
  the four-voice cap is irrelevant; clipping risk is per-strike,
  not per-overlap. Non-blocking; the harness should still report
  clipping count per cell so the verifier sees it if it happens.
- The mid-range pitch row labelled "C5 (loop_len 89)" is approximate;
  loop_len 89 corresponds to `46875 / 89 ~ 526 Hz`, which is C5
  (523.25 Hz) within ~1%. The report should not be cited as a
  precise tuning reference, but for benchmark purposes the
  approximation is fine. Non-blocking.
- The M5 host wrapper (`scripts/phase3_m5_keyboard.py`) already
  has the MIDI-to-loop_len math; the M1 bench could either reuse
  it or hand-code the grid. The report leaves this as an
  implementer choice, which is correct.
- Section 7's verifier task references "SOF as accepted at HEAD
  `5ee0c7c` checksum `0x0037620B`". The M3 verifier validation
  used this exact image. If the implementer's M1 run reproduces
  the build, the checksum should still be `0x0037620B` because no
  RTL/firmware change is allowed in M1. Non-blocking; verifier can
  reprogram and confirm at run time.

None of these affect the verdict.

## Recommended next task text

If the orchestrator accepts this scope, the recommended Phase 6 M1
implementer task description is the one in section 7 of the M0
report. Quoting the key parameters here for orchestrator
convenience:

- Required deliverables:
  1. `scripts/phase6_m1_voice_bench.py` (new, pure-Python with
     `--self-check`).
  2. `scripts/phase6_m1_voice_analyze.py` (new, pure-Python with
     `--self-check`).
  3. `reports/phase6_m1_voice_baseline.md` (new).
  4. `reports/phase6_m1_voice_baseline.csv` (new).
- Hard gates: both `--self-check` modes PASS; full pitch x
  velocity grid captured; per-cell CSV complete; report includes
  recommended candidate (one of A/B/C/D/E/F or "no candidate;
  recapture"); ASCII-only on touched files; no RTL/QSF/firmware/
  obsolete change.
- Verifier responsibility: hardware capture run if implementer
  defers, plus per-cell sanity check and M2-candidate
  recommendation review.

## Final verdict

**PASS.** Phase 6 M0 voice-quality-first scope is acceptance-grade.
The orchestrator may queue the proposed Phase 6 M1 implementer
task as written in section 7 of the report. The benchmark harness
will produce a structured single-voice baseline that any future M2+
RTL voice-quality slice can be measured against, exactly as the
user's "voice quality first" direction asks.

Validation commit will include only this report.
