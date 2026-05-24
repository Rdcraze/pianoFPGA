# Phase 6 M1 Voice-Quality Baseline - Verifier Validation

Date: 2026-05-24
Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-dcf4d097`
Implementer commit under review: `f65532f` (Phase 6 M1 voice-quality
baseline harness, non-hardware coverage)
Branch: `codex/phase1c-uart-boundary-fix`
Live board image: M2 SOF (commit `5ee0c7c`)

## Verdict

**CONDITIONAL FAIL.** Implementer harness PASSes static scope and both
self-checks. Live hardware run executed end-to-end and the UART
command path validated as expected (Q advanced 0x00 -> 0x4D
monotonically across all sessions, X stayed 0). However, the
captured audio does NOT yield a usable single-voice baseline. The
bench's 1.0 s per-cell `!F` settle is too short relative to the
natural decay of the four voices that are already ringing from the
autonomous round-robin (loop_gain = 32640 = 0.996), and
`voice_damp_mix_reg` is shared across all voices and snaps back to
16384 the moment the next `!N` fires, so prior voices keep ringing
through every cell. The resulting WAV contains a stacked 4-voice sum
with frequent saturation rather than the requested single-voice
acoustic behavior.

Per the task acceptance gates ("Each cell has a detectable attack and
non-silent first 100 ms window. Attack, decay, centroid, RMS, and
peak values are internally plausible"), the metric sanity check
fails: cell-level pre/post-strike RMS deltas are within +/- 1 dB,
attacks land all over the 4 s capture window (17 ms to 2998 ms), and
decay_db_per_s clusters near zero with several positive (rising)
slopes. These are not single-voice attack/decay shapes; they are the
envelope of a continuous polyphonic round-robin.

Recommended Phase 6 M2 candidate: **no candidate; recapture** after a
small M1.1 follow-up that cleanly isolates a single voice.

## Static scope check

`git diff --stat 1907fc8..f65532f` shows only the 4 expected files:

```
reports/phase6_m1_voice_baseline.csv |  22 ++
reports/phase6_m1_voice_baseline.md  | 248 +++++++++++
scripts/phase6_m1_voice_analyze.py   | 496 ++++++++++++++++++++++
scripts/phase6_m1_voice_bench.py     | 353 ++++++++++++++++
4 files changed, 1119 insertions(+)
```

PASS:
- No RTL / QSF / firmware / obsolete change.
- No new UART command syntax (bench uses only `!F` and `!NLLLLVVVV`).
- No `.kiro/` content committed by implementer.
- No stale Phase 3/4/5 captures touched.

## ASCII check

Byte-level non-ASCII counter on the four touched files:

```
reports/phase6_m1_voice_baseline.csv bytes=1127  non_ascii=0
reports/phase6_m1_voice_baseline.md  bytes=9508  non_ascii=0
scripts/phase6_m1_voice_analyze.py   bytes=17717 non_ascii=0
scripts/phase6_m1_voice_bench.py     bytes=11946 non_ascii=0
```

PASS.

## Self-check reproductions

### `python scripts/phase6_m1_voice_bench.py --self-check`

```
PASS grid_size 15
PASS c0 !N007F2000\r\n
PASS a4_high !N006A7FFF (matches reduced-voice TB pitch)
PASS last_cell !N00207FFF (loop_len=32 ceiling)
PASS release_bytes !F\r\n
PASS pacing settle=1.00s capture=4.00s pause=1.00s
PASS sidecar JSON round-trip
PHASE6_M1_BENCH_PASS cells=15
```

### `python scripts/phase6_m1_voice_analyze.py --self-check`

```
PASS v1 peak_dbfs=-12.092
PASS v1 decay_db_per_s=-17.372
PASS v1 spectral_centroid_hz=463.0
PASS v1 attack_ms=2.833
PASS v1 clipping_count=0
PASS v2 clipping_count=4800
PASS v3 silence_after_ms=2000.0
PHASE6_M1_ANALYZE_PASS vectors=3
```

Both pure-Python harnesses pass without hardware. Self-check vectors
are mathematically sound. The analyzer correctly identifies decay
slope on a synthesized 440 Hz exponentially decaying sine, and the
peak / centroid / attack / clipping / silence calculators behave as
documented.

### `python scripts/phase6_m1_voice_bench.py --plan`

Confirmed grid prints exactly as specified in the implementer report:
15 cells, total ~90.0 s, settle 1.0s / capture 4.0s / pause 1.0s,
loop_len in {127, 106, 89, 53, 32} x velocity in {0x2000, 0x4000,
0x7FFF}.

## Hardware coverage

### Pre-flight P5M2 telemetry

```
P5M2 BOOT=000022AC TICK=0C664DF9 VC=01 Q=00000000 X=00000000
```

Q=0, X=0 confirmed before any bench traffic, so the run starts from
a clean command-counter baseline. Note the absence of malformed
counter activity validates earlier sessions were closed cleanly.

### Run 1: original audio device (wave_C3E84FAF)

Attempted with the audio device documented in the project context
note (`wave_{C3E84FAF-1579-4C80-8C11-7BFEF4456A7B}`). Captured 15
strikes with 105 s of audio. Diagnostic at 1-second granularity
showed flat ~1500-2400 abs noise floor with no per-strike modulation.
Per-cell post-strike RMS delta against 50 ms pre-strike RMS averaged
+/- 0.2 dB, well below any attack signature.

Per-strike pre/post 50 ms RMS comparison (selected):
```
idx pitch    vel       post_rms_dbfs  pre_rms_dbfs  delta
  4 A4       0x4000    -34.45         -34.48        +0.03 dB
  5 A4       0x7FFF    -37.63         -37.38        -0.25 dB
```

Verdict on Run 1: the dshow endpoint advertised first by ffmpeg on
this machine (`wave_C3E84FAF`) captures only ambient ADC noise; the
board's 3.5 mm output is wired to the second Realtek capture node
(`wave_090C046E`). Diagnostic via `!F` then `!N006A7FFF` confirmed
the second endpoint sees ~10 kabs signal vs. the first endpoint's
~1.7 kabs noise floor. **Methodology finding for the team: the
"first Realtek input" assumption in the project context note is not
correct on this verifier machine.**

### Run 2: corrected audio device (wave_090C046E)

Re-captured 15 strikes, 135 s audio (30 s pre-bench `!F`-burst settle
+ 5 s margin + 90 s grid + 10 s tail). Bench rc=0, all 15 cells
successfully transmitted, sidecar JSON written, ffmpeg log clean.

Post-bench Q telemetry: `Q=0000004D X=00000000`. 0x4D = 77 across all
sessions executed on this board image (Run 1: 31, three diagnostics:
~9, Run 2 pre-bench: 7, Run 2 bench: 31 -> total approximately 78).
Q monotonic and X clean confirms the M2 RX command parser accepted
every frame.

### Audio shape findings

Overall WAV statistics across the 135 s capture:
- peak_abs across full file: 32575 (dBFS = -0.05)
- 98.11 % of samples have |s| >= 100 (continuous activity, not
  silence-bounded)
- Per-second peak abs frequently saturates at +/- 32500 throughout
  the bench window

`!F` decay test: a single `!F` followed by 15 s of audio capture
shows peaks falling from ~19000 at t=2s to ~7000 at t=7s and only
slowly settling toward ~6000 over 12-15 s. Even a second `!F` does
not return the board to silence within 8 s. This means the 1.0 s
per-cell settle in the bench is far too short to flush prior voices
before the next strike.

### Per-cell strike isolation

Pre-strike 50 ms RMS vs post-strike 100 ms RMS (corrected Run 2):
```
idx pitch    vel       post_rms_dbfs  pre_rms_dbfs  delta
  0 loop127  0x2000    -19.28         -19.87        +0.59 dB
  3 A4       0x2000    -19.31         -20.93        +1.62 dB
  4 A4       0x4000    -17.27         -17.65        +0.38 dB
  5 A4       0x7FFF    -15.74         -16.64        +0.90 dB
  7 C5       0x4000    -20.56         -21.15        +0.58 dB
 11 A5       0x7FFF    -18.45         -18.70        +0.25 dB
 14 loop32   0x7FFF    -17.97         -17.38        -0.59 dB
```

A single fresh strike is contributing < 1 dB of new energy on top of
3 already-ringing voices in command_mode. The signal of interest
(the new note) is buried under the residual of prior cells. This is
not a usable single-voice baseline.

### Root cause

`rtl/control/phase0_fixed_control.v` line ~155:

```
end else if (release_strobe) begin
    command_mode       <= 1'b1;
    voice_damp_mix_reg <= 16'd32767;
end
```

`voice_damp_mix_reg` is **shared across all four voices** (the M2
implementer comment in the same file explicitly notes "M2 release
raises shared damp_mix for all voices"). When the next `note_strobe`
fires, the comment-stated semantics restore damp_mix to 16'd16384
for all voices, so the fresh strike voice and the three ringing
neighbors all return to nominal damping. With loop_gain = 32640 =
~0.996, ringing voices take many seconds to decay naturally even at
nominal damp.

The bench harness assumed `!F` would silence the board within 1.0 s.
That assumption holds for an idle board, but not for a board that
is mid-round-robin with 4 voices all actively ringing.

## Captured metrics (CSV)

`reports/phase6_m1_voice_baseline.csv` filled with all 15 rows of
analyzer output from the corrected Run 2 capture. Selected rows:

```
idx pitch    vel       peak_dbfs  rms_3s_dbfs  attack_ms  decay_dB/s  centroid_Hz
  0 loop127  0x2000    -8.227     -21.039      1390.7     -1.77       3395.9
  1 loop127  0x4000    -1.339     -16.870       756.5     +1.98       3684.2
  3 A4       0x2000    -7.983     -19.048       409.7     -0.31       6882.6
  4 A4       0x4000    -0.107     -16.432      2043.9     +0.26       3725.8
  5 A4       0x7FFF    -0.142     -16.408       296.6     -0.39       5230.3
  7 C5       0x4000   -10.947     -21.379        17.1     -0.24       3638.7
  9 A5       0x2000    -7.653     -16.356       834.9     +1.25       3176.1
 14 loop32   0x7FFF    -6.429     -19.359       497.9     -0.24       3440.5
```

### Metric sanity gate failures

1. **No clipping at 0x4000 or below**: cells 4 (A4 0x4000) and 5 (A4
   0x7FFF) have peak_dbfs of -0.107 / -0.142 dBFS - effectively at
   sample saturation. The analyzer's strict `clipping_count` (within
   8 of full scale) returns 0 for these cells but the file-wide peak
   inspection shows samples reaching 32575 (-0.05 dBFS) which is
   indistinguishable from full-scale clipping at 16-bit resolution.
   Saturation occurs because 4 voices are summing simultaneously.
   This is **attributable to the multi-voice stack rather than the
   capture chain**, so it is a **NO-GO** under the task's clipping
   rule.

2. **Detectable attack within first 100 ms**: cell attack times range
   17 ms (cell 7) to 2998 ms (cell 4). Cells 0, 1, 4, 5, 6, 8, 9,
   11, 12, 14 have peaks landing more than 200 ms after the strike,
   inconsistent with a single-strike acoustic shape. **NO-GO.**

3. **Plausible decay slope**: 9 of 15 cells show decay_db_per_s near
   zero (between -1 and +2). Several show positive (rising) slope
   over the t=0.1s to t=1.0s window (cells 1, 4, 8, 9, 11, 12, 13).
   Real piano-like decay should be uniformly negative and on the
   order of -1 to -10 dB/s for the loop_gain in use. **NO-GO.**

4. **Plausible centroid**: 3000-7000 Hz is plausible for a stack of
   reduced-voice square excitations but does not let us pick out
   per-pitch brightness behavior because of voice stacking. **GO,
   but uninformative.**

5. **All 15 rows populated**: GO.

Overall: 3 of 5 sanity gates fail. The dataset cannot be used to
pick a Phase 6 M2 candidate from the M0 scope's A/B/C/D/E/F list.

## P5M2 telemetry result

- Pre-bench: `Q=00000000 X=00000000`. Clean baseline.
- Post-Run-1 (31 commands): `Q=0000001F X=00000000` -> matches 31
  exact (15 leading `!F` + 15 `!N` + 1 trailing `!F`).
- Post-Run-2 (38 more commands across pre-settle + bench + 9 from
  diagnostics): `Q=0000004D X=00000000` -> 0x4D = 77, off by 1 from
  the predicted ~78 because the 3-second uart_check window may have
  missed a single in-flight increment. Within tolerance.
- X stayed 0 across every session: zero malformed input, parser
  accepted everything as expected.

PASS on the M2 RX command parser hardware integration.

## Subjective assessment

Listening pass on the corrected Run 2 WAV:

- Audio is continuously active throughout the 135 s capture, with
  envelope swells but no crisp per-cell attack-decay shape.
- Velocity and pitch differences are obscured by the always-on
  background ringing.
- Frequent audible saturation, especially around the high-velocity
  cells. This is not a useful reference for tonal A/B testing.

Per-cell subjective rows (from M0 scope template):

```
## Subjective: <pitch> @ <velocity>
- Sounds like: continuous polyphonic ring with occasional swell;
  individual strikes are not separable from the background.
- Closest piano analog: not piano-like; closest analog is a
  resonator chord held under a sustain pedal.
- Most audible weakness: continuous saturation; no per-strike
  identity.
- Recommended candidate from section 4 of M0 scope: none; recapture
  after voice-isolation methodology fix.
```

The same row applies to all 15 cells. There is no per-cell
differentiation visible (or audible) in the current capture.

## Residual risks

1. Phase 6 M2 candidate selection is currently uninformed. Picking
   any A/B/C/D/E/F candidate without a clean single-voice baseline
   would be design-by-guess, not design-by-evidence.
2. The shared damp_mix semantics are a known M2 deferral, but the
   M1 bench design did not account for them. This is a harness
   design gap rather than an RTL gap.
3. Audio device enumeration on this verifier machine differs from the
   project context note. Future hardware tasks should validate the
   correct dshow endpoint against the live board signal before
   trusting capture results.
4. The 4-voice round-robin baseline (loop_gain=32640, fixed
   defaults) is itself producing a usable polyphonic test signal,
   confirming that polyphony as **regression infrastructure** is
   working. This is the only positive signal from the M1 capture.

## Recommendation: M1.1 (small) before Phase 6 M2

Before Phase 6 M2 RTL candidates, queue a small M1.1 task that
isolates a single voice cleanly. Three options of increasing cost:

a) **Bench-only**: extend per-cell `!F` settle from 1.0 s to >= 8.0 s
   so prior voices have time to decay naturally, and use a long
   warm-up `!F` plus a fresh-power-cycle baseline before the grid
   starts. Cost: ~120 s extra per run; no RTL change. Caveat: cells
   would still see a low-level residual from prior voices.

b) **RTL bench-mode**: add a small RTL hook that disables voices
   1/2/3 (e.g. `voiceX_enable = 0`) for the duration of the
   single-voice baseline run, gated by a new UART command or a
   build-time tie-off. Cost: ~30 LE; M1.1 RTL change.

c) **Per-voice damp** (which is on the M2 "deferred" list anyway):
   split `voice_damp_mix_reg` into 4 per-voice copies driven by
   `voice_index + 1`. Cost: ~40 LE plus retest; this is functionally
   the M2 release-isolation feature pulled forward.

Option (b) is the cheapest path to a usable single-voice baseline
without committing to (c) before evidence justifies it. Option (a)
keeps M1 strictly non-RTL but yields a noisier baseline.

## Files

- `scripts/phase6_m1_voice_bench.py` (implementer, unchanged)
- `scripts/phase6_m1_voice_analyze.py` (implementer, unchanged)
- `reports/phase6_m1_voice_baseline.md` (implementer, unchanged)
- `reports/phase6_m1_voice_baseline.csv` (verifier-filled with all
  15 rows of live analyzer output from corrected Run 2)
- `reports/phase6_m1_voice_baseline_analyzed.md` (verifier, table of
  per-cell metrics from the corrected capture)
- `reports/phase6_m1_voice_bench_session.json` (sidecar from Run 2)
- `reports/phase6_m1_voice_bench.wav` (135 s, 16-bit mono, 48 kHz,
  ~20.2 MB; preserved on the verifier worktree as the canonical
  capture but **not committed** because of size)
- `.kiro/phase6_m1_capture_meta.json` (capture metadata: audio
  device, audio_start_unix, bench_start_unix, schema)
- `.kiro/phase6_m1_capture.log` (ffmpeg log)
- `.kiro/phase6_m1_*.py` (verifier diagnostic / capture scripts;
  retained for reproducibility)

## ASCII check on this report

```
reports/phase6_m1_voice_baseline_validation.md non_ascii=0
reports/phase6_m1_voice_baseline.csv           non_ascii=0
reports/phase6_m1_voice_baseline_analyzed.md   non_ascii=0
```

(Verified before commit by PowerShell foreach byte loop.)

## Final verdict

**FAIL.** Implementer harness static scope, ASCII, and self-check
gates all PASS. Live hardware run executed successfully and the M2
UART command path validated. The captured audio baseline does **not**
meet the metric sanity gates because shared damp_mix + 1.0 s per-cell
settle yields a 4-voice stack rather than a single-voice signal, so
peak/attack/decay/centroid metrics describe polyphony rather than
single-note quality. Recommend **M1.1** small follow-up before any
Phase 6 M2 RTL candidate is queued.
