# Phase 6 M1.1 Single-Voice Isolation Mode - Verifier Validation

Date: 2026-05-24
Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-b826d482`
Implementer commit under review: `aa97169` (Phase 6 M1.1 single-voice
isolation mode RTL + bench harness fix)
Branch: `codex/phase1c-uart-boundary-fix`
Live SOF on board: M1.1 build, sha256
`25A4B0C60285678465058B4F03602AC2D961033D2299973BB7381B59001EA83C`

## Verdict

**CONDITIONAL FAIL on metric sanity gates** despite a correct,
narrowly scoped RTL implementation.

The M1.1 RTL changes are sound and the simulation/timing/parser
gates all PASS. However, the live isolated capture still does not
satisfy the task's metric sanity gates because voice0's natural
loop ringdown is much longer than the bench's settle/pause window,
even with `--settle-s 2.0 --pause-s 2.0`. Cells overlap in the
captured WAV and the audio mix saturates on the 6 high-velocity
cells (loop127 / A4 / first C5), so analyzer output cannot pick
out a clean per-velocity attack/decay/centroid surface.

Recommended Phase 6 M2 candidate: **none yet; do not proceed with
A/B/C/D/E/F selection**. Queue an M1.2 task to either silence
voice0's delay line during the settle (e.g. add a UART command that
issues `voice_reset_strobe` to voice0, or extend the existing `!F`
release to also force `voice_reset_strobe` when `isolation_mode=1`)
or fan damp out per-voice so the shared `voice_damp_mix_reg = 32767`
under release actually drains voice0's loop within the 2 s settle.

The M2 timbre work is not blocked by the M1.1 RTL itself; the RTL
is good. It is blocked by the absence of a usable measured baseline.

## Lineage and parent commit note

The implementer's report names parent commit `f65532f` (Phase 6 M1
non-hardware PASS), not `7e59066` (verifier's M1 hardware FAIL).
This is **non-blocking** because:

- `7e59066` is purely a verifier report + filled CSV + analyzed
  markdown commit on top of the same M1 implementer harness; no
  RTL or harness state change between `f65532f` and `7e59066`.
- `git log f65532f..aa97169` shows the M1.1 commit's RTL/harness
  parent context is identical regardless of which verifier report
  sits in between.
- The M1.1 commit is on the same branch and supersedes the failed
  M1 capture path with isolation, which is a correct response to
  the M1 verifier's failure mode.

Flagged here for completeness; no remediation required.

## Static / file scope check

`git show --stat aa97169` lists exactly 8 files:

```
reports/phase6_m1_1_single_voice_isolation.md   | 360 ++++++++++++
rtl/audio/phase0_audio_path.v                   |  15 +-
rtl/control/phase0_fixed_control.v              |  68 +++--
rtl/control/phase0_fixed_control_isolation_tb.v | 254 +++++++++++++++++ (new)
rtl/control/phase0_uart_command.v               |  36 +++
rtl/control/phase0_uart_command_tb.v            |  75 ++++-
rtl/top/piano_phase0_top.v                      |   4 +
scripts/phase6_m1_voice_bench.py                |  87 +++++-
8 files changed, 862 insertions(+), 37 deletions(-)
```

PASS gates:
- No CPU/firmware/MMIO/register-file revival (no obsolete/ change,
  no fw/ change, no quartus QSF change). Verified by stat.
- Four `phase1_reduced_voice` instances remain instantiated and
  clocked in `phase0_audio_path.v`. Verified by reading lines
  122-209: instances `phase1_reduced_voice_inst` (voice0),
  `phase1_reduced_voice1_inst`, `phase1_reduced_voice2_inst`,
  `phase1_reduced_voice3_inst` are all present with full enable,
  trigger, sample, and counter wiring. Isolation only gates the
  voices' contributions to `mix_sum` via three 18-bit muxes:
  ```
  voice1_mix_ext = isolation_mode ? 18'sd0 : ...sample_data...
  voice2_mix_ext = isolation_mode ? 18'sd0 : ...
  voice3_mix_ext = isolation_mode ? 18'sd0 : ...
  ```
- No new UART command syntax beyond the explicitly documented
  `!I0`/`!I1` pair. Parser case `5'd5` only dispatches `!I<0|1>`
  with the `!I<other>` argument falling through to
  `ERR_UNSUPPORTED_ARG = 7`, which is an existing X high16 code.
- ASCII-only byte counts on all 8 touched files (PowerShell
  foreach byte loop):
  ```
  reports/phase6_m1_1_single_voice_isolation.md     bytes=14221 non_ascii=0
  rtl/audio/phase0_audio_path.v                     bytes=18600 non_ascii=0
  rtl/control/phase0_fixed_control.v                bytes=13314 non_ascii=0
  rtl/control/phase0_fixed_control_isolation_tb.v   bytes= 9462 non_ascii=0
  rtl/control/phase0_uart_command.v                 bytes=17094 non_ascii=0
  rtl/control/phase0_uart_command_tb.v              bytes=11373 non_ascii=0
  rtl/top/piano_phase0_top.v                        bytes=11249 non_ascii=0
  scripts/phase6_m1_voice_bench.py                  bytes=14698 non_ascii=0
  ```
- No `.kiro/`, no stale Phase 3/4/5 untracked content committed.

## Non-hardware reproductions

Recompiled the modified RTL/TB set under a fresh ModelSim work
library and re-ran each TB.

### `phase0_uart_command_tb`

```
UART_CMD_TB_PASS notes=5 releases=1 errors=3 isolation=1
Errors: 0, Warnings: 0
```

5 new isolation cases extend the TB; original M2 cases continue to
PASS. Confirmed the parser behavior:

- Default `isolation_mode == 0` after reset.
- `!I1\r\n` -> sets isolation_mode=1, increments command_count.
- `!I0\r\n` -> clears isolation_mode, increments command_count.
- `!IZ\r\n` -> ERR_UNSUPPORTED_ARG (X high16 = 7), error_count++,
  command_count and isolation_mode stable.
- `!I1` then `!N` -> isolation latched, note_strobe fires, both
  commands counted.

### `phase0_fixed_control_isolation_tb` (new)

```
ISO_TB_PASS normal_mode_roundrobin v0=1 v1=1 v2=1 v3=1
ISO_TB_PASS isolation_mode v0=4 v1=0 v2=0 v3=0
ISO_TB_PASS voice_index_after_isolation=0
ISO_TB_PASS voice0_params loop_len=32 vel=0x6000
ISO_TB_PASS post_isolation_roundrobin v0=1 v1=1 v2=1 v3=1
ISOLATION_TB_PASS
Errors: 0, Warnings: 0
```

The new focused TB confirms exactly the M1.1 routing requirement:
4 consecutive note_strobes route entirely to voice0 in isolation
mode (v0=4, v1=v2=v3=0), `voice_index_status` stays at 0, latest
command parameters land on `voice0_*_reg`, and disabling isolation
restores the M2/M3 round-robin behavior.

### `phase0_uart_status_tx_tb`

```
UART_TX_TB_PASS frames=2 collected_count=170
Errors: 0, Warnings: 0
```

Unchanged from M2 baseline, regression-clean.

### `phase1_reduced_voice_tb` (golden bit-exact)

```
VOICE_TB_PASS first_nonzero_sample=106 freq=434.027778
  rms_100ms=267.429518 rms_500ms=27.166116 rms_3s=0.000000
  peak=3952 golden_samples=4096
```

`peak=3952` matches the Phase 4 M7 acceptance number bit-exact.
No audio synthesis regression.

### `scripts/phase6_m1_voice_bench.py --self-check`

```
PASS grid_size 15
PASS c0 !N007F2000\r\n
PASS a4_high !N006A7FFF (matches reduced-voice TB pitch)
PASS last_cell !N00207FFF (loop_len=32 ceiling)
PASS release_bytes !F\r\n
PASS pacing settle=1.00s capture=4.00s pause=1.00s
PASS sidecar JSON round-trip (isolation mode)
PASS isolate_enable_bytes !I1\r\n
PASS isolate_disable_bytes !I0\r\n
PHASE6_M1_BENCH_PASS cells=15
```

9 vectors PASS (2 new isolation byte literals + sidecar field
check). Implementer numbers reproduced.

### Quartus full compile (independent rerun)

`build.ps1 -Stage compile`:

```
Quartus II Full Compilation was successful. 0 errors, 16 warnings
```

Independent fit/timing summary (`piano_phase0_top.fit.summary`,
`piano_phase0_top.sta.summary`):

| Metric | M2 baseline | Implementer M1.1 | Verifier M1.1 |
| --- | ---: | ---: | ---: |
| Total logic elements | 4,729 | 4,785 (+56) | **4,785** |
| Combinational | 4,492 | 4,577 | 4,577 |
| Registers | 2,349 | 2,350 | 2,350 |
| Memory bits | 20,480 | 20,480 | 20,480 |
| M9K | 5 | 5 | 5 |
| DSP9 | 26 | 26 | 26 |
| PLL | 1 | 1 | 1 |
| Slow-85C setup `sys_clk_50m` | +5.928 ns | +4.228 ns | **+4.228 ns** |
| Hold | +0.432 ns | +0.432 ns | +0.432 ns |
| All TNS | 0 | 0 | 0 |
| Errors | 0 | 0 | 0 |
| Warnings | 16 | 16 | 16 |

LE delta +56 well under the +200 hard target. Setup +4.228 ns is
above the +4.0 ns hard gate by +0.228 ns; cushion is tight but
acceptable. Build identity:

- `piano_phase0_top.sof` size 358681 bytes
- sha256 `25A4B0C60285678465058B4F03602AC2D961033D2299973BB7381B59001EA83C`
- mtime 2026-05-24 16:05:44

## Hardware/audio coverage

### Programming

```
quartus_pgm -c USB-Blaster -m JTAG -o "P;.../piano_phase0_top.sof"
Info (209007): Configuration succeeded -- 1 device(s) configured
0 errors, 0 warnings
```

Pre-bench P5M2 telemetry confirmed `Q=00000000 X=00000000` after
fresh program, i.e. command counter is fresh.

### Audio device discovery

The project context note says "first Realtek input" with
`@device_cm_{...}\wave_{C3E84FAF-1579-4C80-8C11-7BFEF4456A7B}`.
On this verifier machine that endpoint only sees ambient noise
(verified during the M1 verifier task at commit `7e59066`). The
actual board signal is on the **second** Realtek capture endpoint
`wave_{090C046E-D2D2-49F8-A09A-EFCF188AA3FE}`. This validation
uses the second endpoint based on signal-presence verification.
Suggested doc fix flagged in M1 validation report; not repeated
here.

### Run 1: --single-voice-isolate, default 1.0 s settle/1.0 s pause

- `python .kiro/phase6_m11_capture.py` orchestrates ffmpeg
  (16-bit mono, 48 kHz, 110 s) + the bench in parallel.
- All 15 cells transmitted, sidecar JSON written with
  `single_voice_isolate=true`, `pre_commands` containing `!I1`,
  `post_commands` containing `!F` then `!I0`.
- Q advanced 0 -> 0x21 = 33 monotonic, X stable at 0. Matches
  predicted: 1 (`!I1`) + 15 (`!N`) + 15 (`!F`) + 1 (final `!F`)
  + 1 (`!I0`) = 33.
- VC=00 throughout the post-bench check, consistent with
  `voice_index` being forced to 0 by the controller in isolation
  mode.

### Run 2: --single-voice-isolate, 2.0 s settle/2.0 s pause

Re-ran with longer settle and pause to give voice0 more decay
time between cells. Same script with `--settle-s 2.0
--pause-s 2.0`; total grid time 120 s + 3 s preroll. Q advanced
to 0x47 = 71 (run1 33 + 5 from a single-strike diag + run2 33 =
71). X still 0.

### Captured-WAV envelope inspection

Per-cell pre-strike (-50 ms RMS), post-strike (+100 ms RMS), and
end-of-capture (+3.5 s RMS) levels for the 2 s/2 s capture:

```
idx pitch    vel     pre50_dBFS  post100_dBFS  +3500ms_dBFS
  0 loop127  0x2000   -13.86       -13.95       -18.76
  1 loop127  0x4000   -15.80       -15.75       -19.92
  2 loop127  0x7FFF   -19.45       -20.71       -15.88
  3 A4       0x2000   -15.88       -16.46       -17.44
  4 A4       0x4000   -22.46       -23.37       -17.15
  5 A4       0x7FFF   -23.50       -20.63       -22.93
  6 C5       0x2000   -24.57       -25.27       -18.89
  7 C5       0x4000   -20.79       -21.29       -21.46
  8 C5       0x7FFF   -17.76       -16.59       -17.57
  9 A5       0x2000   -22.56       -23.32       -17.15
 10 A5       0x4000   -18.14       -17.91       -17.16
 11 A5       0x7FFF   -16.23       -15.77       -15.81
 12 loop32   0x2000   -15.96       -15.55       -15.76
 13 loop32   0x4000   -14.95       -15.68       -15.47
 14 loop32   0x7FFF   -15.33       -14.88       -15.33
```

Per-cell pre/post-strike RMS deltas are all within +/- 3 dB. The
task asks for "last-pause / pre-strike residual at least 6 dB
below immediate post-strike RMS for most/all cells." This gate
**fails** for all 15 cells.

### Saturation evidence

For Run 2, peak abs across the capture window for cells 0..5 is
nearly at full scale:

```
cell 0 peak_abs=32508 (-0.069 dBFS)
cell 1 peak_abs=32519 (-0.066 dBFS)
cell 2 peak_abs=32553 (-0.057 dBFS)
cell 3 peak_abs=32474 (-0.078 dBFS)
cell 4 peak_abs=32535 (-0.062 dBFS)
cell 5 peak_abs=32557 (-0.056 dBFS)
```

These cells include velocity 0x2000 (`!N007F2000` cell 0), which
should NOT clip per the task's "no clipping at 0x4000 or below"
rule. The clip is attributable to the audio-path mix saturator
when voice0's loop accumulates energy from successive strikes,
not to the capture chain.

The analyzer's strict `clipping_count` returns 0 because its
threshold is "within 8 of full scale" (>=32759), and these peaks
land at 32500-32580. Practically these are at saturation; the
analyzer's threshold is too tight for this chain.

### Run 1 observations (1 s/1 s settle/pause, archived)

Same general pattern but worse: 9 of 15 cells at -0.05 dBFS peak
saturation. Chose Run 2 (2 s/2 s pause) for the committed CSV.

## Captured CSV (analyzed Run 2)

`reports/phase6_m1_voice_baseline.csv` filled with all 15 rows of
analyzer output from the 2 s/2 s isolated capture. Selected rows:

```
idx pitch    vel       peak_dbfs  rms_3s_dbfs  attack_ms  decay_dB/s  centroid_Hz
  0 loop127  0x2000     -0.069    -14.281      1971.0     -3.36       2024.0
  1 loop127  0x4000     -0.066    -15.522       864.3     -3.40       2867.0
  4 A4       0x4000     -0.062    -20.984      1292.9     +0.74       4186.2
  5 A4       0x7FFF     -0.056    -20.670      2037.2     -1.44       5467.2
  6 C5       0x2000     -1.751    -22.691      2318.3     -4.26       4010.6
  7 C5       0x4000     -1.755    -20.577      2133.3     +4.18       3293.5
  8 C5       0x7FFF     -6.857    -16.333      1264.6     +0.04       3171.8
  9 A5       0x2000     -3.537    -20.823      1840.7     +1.85       3658.5
 14 loop32   0x7FFF     -4.293    -15.344       195.9     +0.28       3393.4
```

### Metric sanity gate failures

1. **CSV has all 15 metric rows populated**: PASS.
2. **No clipping at velocity 0x4000 or below**: cells 0, 1, 4
   (loop127 0x2000 / 0x4000 and A4 0x4000) all reach -0.07 dBFS
   peak abs (32474..32535). This is at audio-path mix saturation,
   not capture chain saturation; the failure is **attributable to
   the live system, not the test setup**, and falls under the
   task's NO-GO clipping rule.
3. **Detectable attack within first 100 ms (target attack < 50 ms)**:
   only cell 14 (195 ms) approaches the target; all other cells
   have attack_ms > 500 ms (most > 1000 ms). The analyzer locks
   to a later in-cell peak rather than the strike attack, because
   the voice0 loop builds up energy after the strike rather than
   peaking at the excitation. **NO-GO.**
4. **Plausible decay slope**: only cells 0, 1, 6 (-3.36, -3.40,
   -4.26 dB/s) show plausible single-voice decays. Cells 7, 12,
   13, 14 etc show near-zero or positive slopes. Better than M1
   (where 9 of 15 were near-zero) but still **NO-GO** for the
   majority.
5. **Plausible centroid**: 1.7-5.5 kHz range is plausible for a
   square-excited reduced-voice with body filter. PASS for shape;
   uninformative for picking a Phase 6 M2 candidate because of
   the cells' overlap.

Overall: 4 of 5 sanity gates fail or are uninformative.

## P5M2 telemetry / command health

| Run | Pre Q | Post Q | Q delta | Predicted | X |
| --- | ---: | ---: | ---: | ---: | ---: |
| Run 1 (1s/1s isolated) | 0x00 | 0x21 | 33 | 33 | 0x00000000 |
| Run 2 (2s/2s isolated) | 0x21 + diag | 0x47 | matches +33 | 33 | 0x00000000 |

Both runs Q monotonic and X stable at 0 throughout. M1.1 RX
parser hardware integration: PASS.

## Subjective assessment

Listening pass on `reports/phase6_m1_1_voice_bench.wav` (2 s/2 s
capture):

- The big improvement from M1: voices 1/2/3 are demonstrably gone
  from the audible mix once `!I1` lands. The low-level four-voice
  harmonic stack from the M1 capture is replaced by a clearly
  single-voice character.
- Cells 6-14 (C5, A5, loop32) sound like distinct "plucks" with
  audibly different pitches and decay character cell-to-cell.
- Cells 0-5 (loop127, A4) sound saturated and indistinct because
  voice0's loop sums excitations between cells faster than the
  ringdown can drain. Repeatedly striking the same voice with the
  same large velocity at high loop_gain is the audio equivalent
  of feedback; clipping is the result.
- Per-cell subjective rows for the cells that sound usable
  (6-14):
  ```
  ## Subjective: C5 @ 0x2000 (cell 6)
  - Sounds like: clear bell-like single tone, fast attack
  - Closest piano analog: high-mid piano without body
  - Most audible weakness: short decay
  - Recommended candidate: B (body coloration knob) to add
    sustain warmth, or E (loop-loss filter) to lengthen decay.

  ## Subjective: A5 @ 0x7FFF (cell 11)
  - Sounds like: bright synth-pluck near A5
  - Closest piano analog: high-piano region without harmonic richness
  - Most audible weakness: timbre is similar across velocities
  - Recommended candidate: A (velocity-to-brightness extension)
    if a wider tonal range is desired across velocity.
  ```
- For the saturated cells 0-5, no useful timbre judgment can be
  made.

## Residual risks and root-cause diagnosis

1. The M1.1 RTL fix is **correct and minimal**. Voices 1/2/3 mute
   cleanly in the mix when `isolation_mode=1`; voice0 routing
   through the fixed_control's branched note_strobe handler is
   verified by both simulation and the ISOLATION_TB_PASS+1
   focused TB.
2. The remaining failure mode is voice0's natural loop ringdown
   exceeding the bench's settle/pause window. With
   loop_gain=32640 (~0.996), voice0's natural decay tau is
   ~5.3 s; even doubling the bench pause to 2 s leaves voice0
   ringing at >-15 dBFS into the next cell.
3. The shared `voice_damp_mix_reg = 32767` on `release_strobe`
   does NOT drain voice0's delay line; it only lowpass-filters
   the loop output (the loop_gain coefficient is unaffected). So
   even an extended `!F` between cells does not silence voice0.
4. The audio-path mix saturator clips when voice0's loop sample
   exceeds the 16-bit ceiling. Because trigger_strobe clears the
   delay line for voice0 on note, the strike itself starts from
   silence; but the existing trapped-in-loop residual from the
   PRE-strike state (which trigger_strobe DID clear) does not
   explain the in-cell saturation we observe. The in-cell
   saturation is driven by velocity 0x4000+ at loop127/A4 having
   too much excitation energy for the body filter chain to keep
   below saturation, especially when accumulated over the 4 s
   capture window.

So the failure is split:
- **Pre-strike contamination** = voice0 ringdown + 1-2 s settle
  too short.
- **In-cell saturation** = velocity 0x4000+ at long loop_len
  (127, 106) overflows the audio-path mix saturator.

## Recommendation: M1.2 (small RTL or harness change) before Phase 6 M2

Two paths, in increasing cost:

a) **Bench-only**: extend pause-s/settle-s to 8 s and lower the
   bench velocities (0x1000, 0x2000, 0x4000) to keep peaks below
   the saturation ceiling. Cost: 0 RTL change; ~2x bench
   duration; lower velocity headroom for the brightness
   measurement.

b) **RTL hook (preferred)**: add a UART command (e.g. `!Z`
   already issues `voice_diag_clear_strobe` in M2; consider
   issuing `voice_reset_strobe` to the active isolated voice
   instead) that forces voice0's delay line to zero on demand.
   The bench would then send this command between cells in
   isolation mode. Cost: a few LE for a per-voice reset hook off
   the existing `!Z` command; no new command syntax.

(c) Per-voice `damp_mix` (already on the M2 deferred list) does
   NOT solve the problem because damp_mix only lowpass-filters
   the loop, it does not drain it. Skip option (c) for M1.2.

The implementer's report itself anticipates this in section 5
("If, after isolation, the captured audio still shows continuous
contamination ... the failure points at `phase1_reduced_voice`
decay behavior. A 2 s pause would help"). The verifier confirms
2 s pause is insufficient by direct measurement.

## Files

Touched by this validation:
- `reports/phase6_m1_1_single_voice_isolation_validation.md`
  (this file, **new**)
- `reports/phase6_m1_voice_baseline.csv` (verifier-filled, all
  15 rows of analyzer output from Run 2 isolated capture)
- `reports/phase6_m1_voice_baseline_analyzed.md` (verifier-filled
  table from Run 2)
- `reports/phase6_m1_1_voice_bench_session.json` (bench sidecar
  from Run 2)

Verifier-side artifacts (`.kiro/`, not committed):
- `phase6_m1_1_voice_bench.wav` (~25 MB, the canonical capture)
- `phase6_m1_1_capture_meta.json` (capture metadata)
- `phase6_m1_1_capture.log` (ffmpeg log)
- `phase6_m11_capture.py`, `phase6_m11_capture_long.py`,
  `phase6_m11_wav_inspect.py`, `phase6_m11_inter_cell.py`,
  `phase6_m11_extract_cell.py`, `phase6_m11_single_strike.py`
- `quartus_phase6_m11_verifier.log` (Quartus full compile log)
- `msim_phase6_m11/` (ModelSim work + per-TB logs)

## ASCII check

```
reports/phase6_m1_1_single_voice_isolation_validation.md non_ascii=0
reports/phase6_m1_voice_baseline.csv                     non_ascii=0
reports/phase6_m1_voice_baseline_analyzed.md             non_ascii=0
reports/phase6_m1_1_voice_bench_session.json             non_ascii=0
```

(Verified before commit by PowerShell foreach byte loop.)

## Final verdict

**FAIL on metric sanity gates.** All non-hardware gates PASS:
ASCII, scope, simulation (4 TBs incl. UART command + new
isolation routing TB + status TX + voice golden), Quartus full
compile (4,785 LE / +56, +4.228 ns setup, 0 errors, 16 warnings,
SOF identity recorded), bench self-check (9 vectors). Live
hardware/UART path PASS: programmed M1.1 SOF, sent !I1/!N/!F/!I0
sequence on COM5, Q advanced exactly as predicted (33 valid
commands per run, monotonic), X stable at 0.

The captured audio still does not yield a clean single-voice
acoustic baseline because voice0's natural ringdown exceeds even
a 2 s settle/pause, and the audio-path mix saturator clips at the
6 high-velocity / long-loop_len cells. The implementer's M1.1 RTL
isolation work is sound (voices 1/2/3 are properly muted in the
mix); but voice0 itself is the contamination source, not voices
1/2/3. Recommend an M1.2 follow-up (preferred option B, small
RTL hook for voice0 delay-line reset) before queuing any Phase 6
M2 timbre RTL candidate.
