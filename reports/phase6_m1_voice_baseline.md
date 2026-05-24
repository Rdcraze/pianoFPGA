# Phase 6 M1 Voice-Quality Baseline

Date: 2026-05-24
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-b84a1939`
Branch: `codex/phase1c-uart-boundary-fix`
Parent commit: `fa5a443` (Phase 6 M0 scope PASS)

## TL;DR

**PASS for non-hardware coverage.** Two new pure-Python harnesses
land alongside a CSV stub and this report:

- `scripts/phase6_m1_voice_bench.py`: drives the M2 UART command
  path through `!F` and `!NLLLLVVVV` to step through the M0 5x3
  pitch x velocity grid. `--self-check` PASS (7 vectors).
- `scripts/phase6_m1_voice_analyze.py`: pure-stdlib WAV reader plus
  metric pipeline (peak, RMS at 100/500/3000 ms, attack ms, decay
  dB/s via 100 ms RMS slope, FFT spectral centroid with Hann
  window, clipping count, silence-after ms). `--self-check` PASS
  (3 deterministic synthetic vectors).
- `reports/phase6_m1_voice_baseline.csv`: 15 grid rows with metric
  columns intentionally empty until the live capture lands.

Per the project discipline rule that hardware acceptance is the
verifier's responsibility, the live 5x3 grid hardware capture and
its analysis fill-in are deferred to the M1 verifier task. The
implementer artifacts give the verifier everything it needs to run
the capture in one command and write the analyzed CSV/MD with one
follow-up command.

| Item | Status |
| --- | --- |
| `scripts/phase6_m1_voice_bench.py` `--self-check` | PASS (7 vectors, 15 cells, sidecar round-trip) |
| `scripts/phase6_m1_voice_analyze.py` `--self-check` | PASS (peak / decay / centroid / attack / clipping / silence on synthetic decaying-sine vector) |
| Grid CSV stub | written; 15 rows; metric columns empty until verifier capture |
| Live 5x3 hardware capture | DEFERRED to verifier (project discipline) |
| RTL/QSF/firmware/obsolete | unchanged |
| ASCII | clean on all four touched files |

## 1. Bench self-check

`scripts/phase6_m1_voice_bench.py --self-check`:

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

The harness exposes three modes:

```
python scripts/phase6_m1_voice_bench.py --self-check
python scripts/phase6_m1_voice_bench.py --plan
python scripts/phase6_m1_voice_bench.py --run --port COM5 \
    [--baud 115200] [--sidecar PATH] \
    [--settle-s 1.0] [--capture-s 4.0] [--pause-s 1.0]
```

`--plan` prints the entire 15-cell grid with pitch name, loop_len,
velocity, and exact command bytes (without opening hardware). The
`--run` mode opens the serial port, gives the operator 3 s to start
the audio capture, then walks the grid emitting `!F` + settle +
`!NLLLLVVVV` + capture + pause for every cell, finishing with a
trailing `!F` to silence the last ring. Send timestamps are recorded
in a sidecar JSON for later alignment with the WAV.

The grid is fixed at:

| pitch | loop_len | velocities |
| --- | ---: | --- |
| loop127 | 127 | 0x2000, 0x4000, 0x7FFF |
| A4 | 106 | 0x2000, 0x4000, 0x7FFF |
| C5 | 89 | 0x2000, 0x4000, 0x7FFF |
| A5 | 53 | 0x2000, 0x4000, 0x7FFF |
| loop32 | 32 | 0x2000, 0x4000, 0x7FFF |

A full 5x3 run takes ~90 s of board time (15 cells x 6 s each) plus
3 s of operator setup.

## 2. Analyzer self-check

`scripts/phase6_m1_voice_analyze.py --self-check`:

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

Vector 1: a deterministic 440 Hz decaying sine at sample rate 48000
Hz, raised-cosine attack 2 ms, exponential decay tau=0.5 s, peak
0.25 of full scale. Expected metrics are computed analytically:

- peak_dbfs ~ 20 log10(0.25) = -12.04 dBFS. Observed: -12.092.
- decay_db_per_s for tau=0.5 s = 20 / ln(10) / tau = 17.372 dB/s
  (negative: decaying). Observed: -17.372.
- spectral_centroid_hz for a clean sinusoid should be near 440 Hz;
  with the Hann window in the analyzer the centroid lands at
  463 Hz, well within tolerance for the 250 ms / 48 kHz window.
- attack_ms < 5: observed 2.833.

Vector 2: full-scale alternating clip pattern; clipping_count >
half the segment.

Vector 3: pure silence segment; silence_after_ms >= 1500.

The analyzer uses only `wave`, `struct`, `math`, `csv`, `json`, and
`argparse` from stdlib. No numpy/scipy dependency.

## 3. Hardware capture protocol (for verifier)

The verifier should run, against the live M2 board (commit `5ee0c7c`
SOF checksum `0x0037620B`):

```
# 1. Plan check (no hardware needed):
python scripts/phase6_m1_voice_bench.py --plan

# 2. Start audio capture in a separate process. Either:
#    - existing ffmpeg dshow flow used in M0..M3 hardware acceptance, or
#    - any other 16-bit PCM WAV recorder that runs >= 100 s.
#    Record the audio start unix time (or run the WAV recorder on
#    the same monotonic clock and use the default offset).

# 3. Drive the bench:
python scripts/phase6_m1_voice_bench.py --run --port COM5 \
    --sidecar reports/phase6_m1_voice_bench_session.json

# 4. Analyze:
python scripts/phase6_m1_voice_analyze.py \
    --wav reports/phase6_m1_voice_bench.wav \
    --sidecar reports/phase6_m1_voice_bench_session.json \
    --out reports/phase6_m1_voice_baseline.csv \
    --out-md reports/phase6_m1_voice_baseline_analyzed.md
```

If the audio capture and the bench start at different unix times,
pass `--audio-start-unix` to the analyzer.

The verifier will also want to capture P5M2 frames during the run
to confirm Q advances by 30 (15 valid `!N` commands plus 15 `!F`
release commands plus the 1 trailing `!F` = 31 total Q increments;
exact count depends on whether the trailing `!F` lands within the
capture window). X should remain 0x00000000 because no malformed
input is sent. The existing `scripts/phase5_m3_p5m2_decode.py`
helper handles the frame decoding.

## 4. CSV output

`reports/phase6_m1_voice_baseline.csv` is committed as a stub: 15
grid rows with the index, pitch_name, loop_len, velocity_hex, and
command columns populated, and the metric columns intentionally
empty. The verifier task fills in the metrics by running the
analyzer command above against the captured WAV.

A live verifier-filled example will look like:

```
index,pitch_name,loop_len,velocity_hex,command,peak_abs,peak_dbfs,
rms_100ms_dbfs,rms_500ms_dbfs,rms_3s_dbfs,attack_ms,
decay_db_per_s,spectral_centroid_hz,clipping_count,silence_after_ms
0,loop127,127,0x2000,!N007F2000,1024,-30.10,-32.50,-37.20,
-45.10,3.4,-2.50,420.5,0,150.0
...
```

## 5. Subjective assessment template (for verifier)

Each per-cell row in the analyzed report should include the
section-6 structured format from the M0 scope:

```
## Subjective: <pitch> @ <velocity>
- Sounds like: <one sentence describing timbre>
- Closest piano analog: <one sentence>
- Most audible weakness: <one sentence or "none observed">
- Recommended candidate from section 4 of M0 scope:
  <A/B/C/D/E/F or "none; recapture">
```

The verifier should fill these in by listening to each cell in the
captured WAV.

## 6. Phase 6 M2 candidate recommendation (deferred)

Per project discipline, the implementer cannot recommend a Phase 6
M2 RTL candidate without measured hardware evidence. The candidate
table from `reports/phase6_m0_voice_quality_scope.md` section 4
remains the right list:

- A: velocity-to-brightness curve extension
- B: body coefficient runtime knob
- C: loop-gain / damp-mix runtime knob
- D: pre-strike noise component
- E: loop-loss filter shape
- F: per-voice independent release (NOT recommended)

Once the verifier completes the live capture and fills in the CSV +
subjective rows, the resulting evidence will indicate which
candidate to queue as Phase 6 M2:

- If `decay_db_per_s` magnitudes look uniform across pitches and
  velocities, candidate E (loop-loss filter shape) becomes
  attractive: piano strings normally show faster upper-harmonic
  decay than fundamental decay.
- If `spectral_centroid_hz` is roughly constant across velocity at
  fixed pitch, candidate A (velocity-to-brightness extension)
  becomes attractive: M7's two-layer hammer may not span enough
  brightness range to be musically expressive.
- If decay times are too short or too long for the listener's
  taste, candidate C (runtime loop_gain/damp knob) becomes
  attractive.
- If everything sounds clean and pleasant, candidate B (body
  coloration knob) becomes attractive as a tasteful refinement.

The implementer's M2 recommendation is held in this report's place
until the verifier task lands the live measurements.

## 7. Out of scope

- No RTL change. No QSF change. No firmware change. No obsolete
  archive change.
- No new UART command syntax. The bench harness uses only `!F` and
  `!NLLLLVVVV`.
- No edits to verifier-protected untracked artifacts.

## 8. Committed result

This commit contains four new files:

- `scripts/phase6_m1_voice_bench.py` (~280 lines)
- `scripts/phase6_m1_voice_analyze.py` (~370 lines)
- `reports/phase6_m1_voice_baseline.md` (this file)
- `reports/phase6_m1_voice_baseline.csv` (15-row grid stub)

ASCII-only on all four files.
