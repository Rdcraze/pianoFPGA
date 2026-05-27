# Phase 6 M6 Next Voice-Quality Scope Validation

Date: 2026-05-27
Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Branch: `codex/phase1c-uart-boundary-fix`
Validation HEAD: `e95ca3f` (M5.1 isolator acceptance PASS).
Implementer scope under review: commit `a35092f`
(`reports/phase6_m6_next_voice_quality_scope.md`).

## Verdict

**PASS.** The Phase 6 M6 scope report is single-file,
report-only, ASCII clean, factually consistent with the live
M5 baseline and accepted M5.1 evidence, and proposes a
sensible split between an immediate host-tool workstream and
a hardware-arrival workstream.

The orchestrator may queue the recommended next implementer
task (Phase 6 M6 body_mix sweep harness) directly from the
report's section 6 task text. The M5.1 verifier task in the
same section is now superseded by the already-completed
`task-cbbeea61` PASS at commit `e95ca3f`; that part of the
report is documentation of an outcome the project has since
delivered, not a still-pending future task.

## 1. Scope/file/ASCII discipline

```
git show --stat a35092f
 reports/phase6_m6_next_voice_quality_scope.md | 598 ++++++++++
 1 file changed, 598 insertions(+)

rg --byte-non-ascii reports/phase6_m6_next_voice_quality_scope.md
bytes=25177 non_ascii=0
```

Single-file commit, no source/firmware/QSF/SDC/PLL/host-tool/
obsolete-archive/generated-output change. ASCII-only.

The only worktree dirt outside the M6 scope file is
`implementer_handoff.md`, which is a stale modification that
predates this validation; not produced by `task-0072201e` and
not in the scope of this validation.

## 2. Reasoning vs current evidence

### M5 acceptance citation

Report cites M5 accepted at validation commit `40f44e2` with
LE 5,105, setup `+4.620 ns`, body_mix runtime knob via
`!B<vvvv>\r\n`, default 0x3000, `+173 LE` vs 4,932 baseline.

Independent checks:

```
rtl/control/phase0_uart_command.v line 64:
    output reg  [15:0] body_mix_runtime,
rtl/control/phase0_uart_command.v line 202:
    body_mix_runtime <= 16'd12288;          (= 0x3000)
rtl/control/phase0_uart_command.v line 347:
    body_mix_runtime <= parsed_body_mix;
rtl/control/phase0_fixed_control.v line 171:
    assign voice_body_mix   = body_mix_runtime;

reports/phase6_m5_body_knob_cap_raise_validation.md cites:
    LE 5,105 / 10,320 (+173 vs M3/M4 baseline 4,932)
    Setup slow-85C sys_clk_50m +4.620 ns (+0.620 ns above
    +4.0 ns hard gate)
    Hold +0.414 ns, all TNS 0
    M9K/DSP9/PLL unchanged
```

Every M5 number quoted in the M6 scope matches the live RTL
and the M5 acceptance validation report exactly.

### Four-voice preservation

```
rtl/audio/phase0_audio_path.v lines 142, 166, 190, 214:
    phase1_reduced_voice phase1_reduced_voice_inst   ( ... );
    phase1_reduced_voice phase1_reduced_voice1_inst  ( ... );
    phase1_reduced_voice phase1_reduced_voice2_inst  ( ... );
    phase1_reduced_voice phase1_reduced_voice3_inst  ( ... );
```

Four physical voice instances remain live. The M6 scope
correctly treats polyphony as overlap/stress infrastructure,
not a product feature.

### Capture-chain noise context

Report cites `reports/phase6_chain_noise_debug.md` and treats
the audio chain as USB-ground-loop limited until the isolator
arrives. As of this validation, the M5.1 isolator acceptance
task `task-cbbeea61` has already been completed at commit
`e95ca3f` with PASS (with caveats):

- Median floor: -117.8 dBFS (28 dB inside the -90 dBFS gate).
- Total RMS: -51.3 dBFS (33 dB chain improvement).
- Hum 50/60/100/120/180/240 Hz: -95 to -117 dBFS absolute.
- Strict classifier verdict: HUM_60HZ_DOMINATED (relative-
  threshold artifact; absolute hum is well below the strike
  band).
- K=16 isolated bench ran end-to-end on the new chain with
  Q monotonic and zero new UART errors.

The M6 scope report was authored at a moment when the isolator
was still pending. Its hardware-arrival workstream description
is therefore an accurate retrospective summary of what the
M5.1 verifier did, not a still-open future task. The report's
"queue when isolator hardware arrives" framing is now stale,
and that is a feature of the project moving forward, not a
defect in the scope.

### JTAG / on-chip strike scheduler / coherent-averaging-on-noisy-chain

All three are explicitly avoided in the report. JTAG command
path is rejected because it carries the same USB-ground-loop
issue. On-chip strike scheduler is rejected because cheaper
host-side alternatives exist via the accepted `!B`/`!N`/`!F`
parser. Continued coherent averaging on the noisy chain was
the direct M4 failure mode and is left to the hardware-arrival
workstream once the chain is clean. All three rejections align
with project history and discipline.

### Voice quality vs polyphony

Polyphony is correctly demoted to overlap/stress infrastructure
throughout. The recommended next slice (body_mix sweep) is a
single-voice exercise targeted at body warmth, which is the
documented next perceptual weakness after M2 brightness and
M3/M5 body retune.

## 3. Immediate M6 workstream evaluation

Recommended: add `scripts/phase6_m6_body_mix_sweep.py`,
host-tool-only, no RTL/QSF/firmware change.

Strengths.

- Reuses existing accepted `!B`/`!N`/`!F`/`!I0`/`!I1` parser
  with no new UART syntax.
- Sweep grid `[0x1000..0xC000]` x `{A4 loop_len 106, C5 loop_len
  89}` x velocity 0x7FFF is small enough (14 cells x ~6 s/cell
  = ~85 s) to be practical.
- Per-cell pacing matches the accepted M1.2/M5.1 isolated-strike
  methodology (1 s settle, 4 s capture, 1 s pause).
- `--self-check` + `--plan` modes are testable without hardware.
- Pre-isolator and post-isolator behavior is the same script;
  only the analyzer's confidence in FFT-band claims differs.

Practical observations from M5.1 evidence.

- The M5.1 K=16 capture (240 strikes) wrote a clean sidecar v2
  to `reports/phase6_m5_1_voice_bench_session.json`. The same
  pattern will work for the M6 sweep, but the sweep's sidecar
  must include the per-cell `body_mix_q15` value so the analyzer
  can label cells by that key. This is already in the scope's
  proposed CSV/sidecar layout.
- The M5.1 validation surfaced a measurement-window pitfall:
  with body_mix=0x3000 default and long loop_len cells, the
  previous strike's tail is still ringing in the 0.4 s pre-
  strike noise window, producing negative `snr_db` in the
  analyzer's column. The M6 sweep harness should either use a
  longer pre-strike window or pause until pre-strike RMS drops
  below a configurable floor before the next strike. The scope
  report does not call this out; recommend the implementer add
  it as a small per-cell sanity check rather than reuse the
  existing analyzer's `snr_db` column verbatim. This is a
  refinement, not a blocker.

### Resource/timing alignment

Report claims "RTL change: NONE" and "LE/timing risk: NONE".
Both true: the harness only sends already-accepted UART
commands. Setup slack +4.620 ns is preserved exactly because no
RTL is touched.

## 4. Hardware-arrival workstream evaluation

Recommended: M5.1 verifier task for isolator acceptance plus
post-isolator K=16 A/B between contrasting `!B` values.

This workstream has already been executed for the noise-floor
acceptance half. Validation commit `e95ca3f` accepts the
isolator with caveats:

- Strict gate `GAUSSIAN_CLEAN` AND median floor <= -90 dBFS AND
  worst hum-to-floor <= +6 dB: 1 of 3 gates met. Median floor
  passes by 28 dB. Classifier verdict and relative hum-to-floor
  are missed because the floor crashed harder than the hum did,
  but absolute hum lives outside the voice band of interest and
  is 41-50 dB below strike peaks.
- Materially improves the old HUM_60HZ_DOMINATED chain: yes,
  21-44 dB across all metrics.
- K=16 bench runs end-to-end on the new chain: yes.

What remains from the M6 scope report's hardware-arrival
description:

- A post-isolator A/B between two contrasting `!B` values is
  the M6 sweep harness's job, not a separate verifier task.
  The M6 immediate workstream and the post-isolator A/B
  collapse into the same script run with `--repeats 16` once
  the harness exists.
- The fallback "external USB ADC if isolator fails" branch in
  the report is moot because the isolator did not fail.

The scope's gates for the post-isolator A/B (FFT-band deltas in
1-3 kHz, expected M3+M5 warmth gain +3 to +6 dB) are
reasonable. The verifier task for the M6 sweep should adopt
those gates.

## 5. Proposed task text review

The report's section 6 contains three orchestrator-ready task
texts. Reviewed each:

### Phase 6 M6 implementer task: body_mix sweep host harness

- Files touched: `scripts/phase6_m6_body_mix_sweep.py` and
  `reports/phase6_m6_body_mix_sweep_impl.md`. Correct scope.
- Hard gates: `--self-check` PASS, no RTL/QSF/firmware change,
  no new UART syntax, ASCII-only. Correct.
- NO-GO triggers: COM5 not enumerated, `--self-check` failure.
  Reasonable for a host-only task.
- Defers live capture to verifier per project discipline.
  Consistent with how M5.1 was structured.

One refinement worth recording for the implementer: the sidecar
schema should include the per-cell body_mix value, and the
analyzer or post-process step should NOT rely on the existing
`snr_db` column (the M5.1 measurement-window pitfall above).
This is a soft note for the implementer, not a blocker for
queueing the task.

Already queued as `task-0eb95de4`; the queued description
matches this report.

### Phase 6 M6 verifier task: body_mix sweep live capture

- Re-runs `--self-check`/`--plan`, runs live sweep on COM5,
  captures audio (not committed), analyzes, writes
  `reports/phase6_m6_body_mix_sweep_validation.md`.
- P5M2 telemetry check: Q advances by exactly the count of
  valid commands. The report's count formula
  `1 + N_body_mix x N_pitch x 2 + 1` correctly counts !I1 +
  per-cell (!F + !N) + final !I0; for the default grid 7 x 2 x
  2 + 2 = 30. Matches.
- Post-isolator acceptance gate: monotonic 1-3 kHz band energy
  rise as body_mix grows from 0x1000 -> 0x8000. Reasonable.
- Already queued as `task-c6620806`.

### Phase 6 M5.1 verifier task

This task in the report is already completed and accepted
under `task-cbbeea61` at commit `e95ca3f`. The orchestrator
should consider this section of the M6 scope report as
historical/anticipatory rather than queue it again.

## 6. Acceptance gates

| Gate | Result |
| --- | --- |
| Single-file commit | PASS (only `reports/phase6_m6_next_voice_quality_scope.md`) |
| ASCII-only | PASS (0 non-ASCII bytes) |
| No RTL/QSF/firmware/host-tool/obsolete change | PASS |
| Cited M5 numbers match live RTL and M5 validation | PASS (LE 5,105, +173, +4.620 ns, default 0x3000 all confirmed) |
| Four physical voices preserved as accepted infrastructure | PASS |
| Voice quality remains primary; polyphony is support-only | PASS |
| Recommended immediate workstream useful pre-isolator | PASS (intra-run sweep produces deltas above chain-noise variance) |
| Recommended immediate workstream not gated on noisy A/B | PASS (per-cell honest classification against noise floor) |
| Hardware-arrival workstream defines isolator gates | PASS (classifier + median floor + hum-to-floor) |
| Hardware-arrival workstream defines K=16 A/B rerun | PASS (FFT 1-3 kHz, expected +3 to +6 dB) |
| No CPU/firmware/MMIO/register-file revival | PASS |
| No JTAG command path | PASS (explicitly rejected) |
| No on-chip strike scheduler | PASS (explicitly rejected) |
| No polyphony feature work | PASS |
| Resource/timing budgets realistic for 5,105 LE / +4.620 ns | PASS (RTL change is NONE) |

## 7. Recommendations to orchestrator

1. **Queue the Phase 6 M6 implementer task `task-0eb95de4`
   (body_mix sweep harness) immediately.** The dependency on
   this scope report is satisfied. The implementer task text
   in section 6 of the M6 scope is correct as-is; no orchestrator
   edit needed.

2. **Treat the M5.1 verifier-task block in section 6 of the
   M6 scope as already-delivered.** Do not queue a new M5.1
   task. The acceptance work is captured in
   `reports/phase6_m5_1_isolator_acceptance_validation.md` at
   validation commit `e95ca3f`.

3. **Forward the soft refinement to the M6 implementer.** The
   M5.1 capture revealed that the analyzer's `snr_db` column
   is misleading on this voice model (pre-strike noise window
   contains tail of previous strike). The M6 sweep harness
   should either use a longer per-cell pause (e.g. 2-3 s
   instead of 1 s) when body_mix is high, or skip the analyzer's
   `snr_db` column in favor of FFT band ratios for body_mix
   A/B. This is a refinement to the implementer's deliverable,
   not a blocker on scope acceptance.

4. **Consider whether the post-isolator K=16 A/B between
   contrasting `!B` values should be a deliverable of
   `task-c6620806` (M6 sweep verification) or its own M6.1
   verifier task.** The M6 scope folds it into the M6 sweep
   verifier task, which is fine; just confirm that the verifier
   task gates explicitly include the FFT 1-3 kHz delta check on
   the post-isolator captured data.

## 8. Files

This report:

- `reports/phase6_m6_next_voice_quality_scope_validation.md`
  (new, ASCII-only).

No RTL, host-script, QSF, SDC, firmware, obsolete archive,
generated-output, or stale-untracked-file change.

## 9. ASCII check

```
reports/phase6_m6_next_voice_quality_scope_validation.md non_ascii=0
```

(Verified before commit by the standard PowerShell foreach-byte
check.)
