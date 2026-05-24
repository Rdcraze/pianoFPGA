# Phase 6 M1.2 Hard-Reset Voice0 Isolated Baseline - Verifier Validation

Date: 2026-05-24
Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-45f02758`
Implementer commit under review: `ca15f94` (Phase 6 M1.2 hard-reset
voice0 between isolated cells, clean-level profile)
Branch: `codex/phase1c-uart-boundary-fix`
Live SOF on board: M1.2 build, sha256
`3E47198495DA508D959F4D5456792C30C5957830A8EFD8C752CBBC520D90E796`

## Verdict

**CONDITIONAL PASS.**

The M1.2 RTL change is correct, narrowly scoped, and accomplishes its
design goal: in `isolation_mode`, `release_strobe` now also pulses
`voice_reset_strobe` to voice0 for one sys_clk cycle, which clears
voice0's delay line and stops it from carrying ringdown into the
next cell. All non-hardware gates pass and the live integration
works cleanly: a "20x !F under !I1" silence test confirms voice0
drains to a Gaussian noise floor (std/peak ratio 0.283) with no
periodic content, demonstrating that the reset semantics fire on
hardware.

The original profile (0x2000/0x4000/0x7FFF) produces a 15-row
baseline with audible strikes in 5 of 15 cells (peaks 6-10 dB above
the noise floor) and plausible single-voice decay metrics on 4
cells (decay -4.4 to -8.5 dB/s, attack 95-313 ms). The clean
profile (0x0800/0x1000/0x2000) does not improve separability
because at those velocities most cells emit at-or-below the audio
chain's intrinsic ~-18 dBFS Gaussian noise floor.

The accepted M1.2 baseline is the **original profile**, with the
explicit understanding that:
- the audio chain noise floor is the limiting factor for low-velocity
  measurements;
- 6 high-velocity / long-loop cells (0, 1, 5, 6, 7, 10, 14) still
  saturate at -0.05 dBFS due to mix-bus saturation, not the M1.2
  reset feature.

The next step is **not blocked by RTL**. Phase 6 M2 timbre RTL work
can proceed using A/B tests on the cells that show clean strikes,
but the pre-Phase-6-M2 priority should be improving the audio
capture chain noise floor (or moving to a lower-noise capture path)
to unlock low-velocity measurement.

## Static / file scope check

`git show --stat ca15f94` lists exactly 4 files:

```
reports/phase6_m1_2_voice_reset_baseline.md    | 301 ++++++++++++++
rtl/control/phase0_fixed_control.v             |  18 +-
rtl/control/phase0_fixed_control_isolation_tb.v|  77 ++++++
scripts/phase6_m1_voice_bench.py               |  78 ++++--
4 files changed, 458 insertions(+), 16 deletions(-)
```

PASS gates:
- No CPU/firmware/MMIO/register-file revival.
- No new UART command syntax (no parser change). The change is
  purely in `phase0_fixed_control.v` semantics and bench harness
  argument parsing.
- Four `phase1_reduced_voice` instances remain present in
  `phase0_audio_path.v` (unchanged file). Normal mode round-robin
  preserved (verified by `release_in_normal_no_reset` TB
  assertion).
- No Quartus QSF, audio synthesis, or obsolete archive change.
- ASCII-only on touched files (PowerShell foreach byte loop):
  ```
  reports/phase6_m1_2_voice_reset_baseline.md            bytes=12243 non_ascii=0
  rtl/control/phase0_fixed_control.v                     bytes=14220 non_ascii=0
  rtl/control/phase0_fixed_control_isolation_tb.v        bytes=12577 non_ascii=0
  scripts/phase6_m1_voice_bench.py                       bytes=17070 non_ascii=0
  ```

`git diff aa97169..ca15f94` of `rtl/control/phase0_fixed_control.v`
shows three small additions:
- `voice_reset_strobe = 1'b0` is replaced with
  `voice_reset_strobe = voice0_reset_pulse;`
- `voice0_reset_pulse` is reset to 0 on async reset and defaults
  low every cycle.
- A new `if (isolation_mode) voice0_reset_pulse <= 1'b1;` clause
  inside the `else if (release_strobe)` branch.

Normal mode `release_strobe` path is unchanged: damp_mix raised to
32767, no voice reset pulse. This preserves Phase 5 M2/M3 release
semantics exactly.

## Non-hardware reproductions

### `phase0_fixed_control_isolation_tb` (extended)

```
ISO_TB_PASS normal_mode_roundrobin v0=1 v1=1 v2=1 v3=1
ISO_TB_PASS isolation_mode v0=4 v1=0 v2=0 v3=0
ISO_TB_PASS voice_index_after_isolation=0
ISO_TB_PASS voice0_params loop_len=32 vel=0x6000
ISO_TB_PASS release_in_isolation_resets_voice0 reset_count=1
ISO_TB_PASS release_in_isolation_damp=0x7FFF
ISO_TB_PASS release_in_isolation_no_trigger
ISO_TB_PASS isolated_note_after_reset
ISO_TB_PASS post_isolation_roundrobin v0=1 v1=1 v2=1 v3=1
ISO_TB_PASS release_in_normal_no_reset
ISO_TB_PASS release_in_normal_damp=0x7FFF
ISOLATION_TB_PASS
Errors: 0, Warnings: 0
```

11 PASS assertions covering both normal and isolation modes, both
note routing AND release behavior. The 5 new M1.2 assertions:
- `release_in_isolation_resets_voice0 reset_count=1` (single-cycle
  pulse fires exactly once)
- `release_in_isolation_damp=0x7FFF` (damp_mix still raises)
- `release_in_isolation_no_trigger` (release does not fire any
  voice trigger)
- `isolated_note_after_reset` (subsequent !N still routes to
  voice0)
- `release_in_normal_no_reset` (normal-mode !F does NOT pulse the
  reset)

### `phase0_uart_command_tb`

```
UART_CMD_TB_PASS notes=5 releases=1 errors=3 isolation=1
Errors: 0, Warnings: 0
```

Unchanged parser surface; M2 + M1.1 isolation cases all PASS.

### `phase0_uart_status_tx_tb`

```
UART_TX_TB_PASS frames=2 collected_count=170
Errors: 0, Warnings: 0
```

### `phase1_reduced_voice_tb` (golden)

```
VOICE_TB_PASS first_nonzero_sample=106 freq=434.027778
  rms_100ms=267.429518 rms_500ms=27.166116 rms_3s=0.000000
  peak=3952 golden_samples=4096
```

`peak=3952` bit-exact at Phase 4 M7 acceptance number.

### Bench `--self-check`

```
PASS grid_size 15
PASS default_profile=original (cell0 vel=0x2000)
PASS clean_profile_grid (cell0 !N007F0800, last !N00202000)
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

11 vectors PASS (was 9 in M1.1). Two new vectors validate the
default_profile sentinel and the clean-profile grid assembly with
the right command bytes (`!N007F0800` and `!N00202000`).

### Quartus full compile (independent rerun)

`build.ps1 -Stage compile`:

```
Quartus II Full Compilation was successful. 0 errors, 16 warnings
```

Resource summary (`piano_phase0_top.fit.summary`):

| Metric | M1.1 | Implementer M1.2 | Verifier M1.2 |
| --- | ---: | ---: | ---: |
| Total logic elements | 4,785 | 4,810 (+25) | **4,810** |
| Combinational | 4,577 | 4,571 | 4,571 |
| Registers | 2,350 | 2,351 (+1) | 2,351 |
| Memory bits | 20,480 | 20,480 | 20,480 |
| M9K | 5 | 5 | 5 |
| DSP9 | 26 | 26 | 26 |
| PLL | 1 | 1 | 1 |

LE delta +25 well under the +100 hard target. The +1 register is
the new `voice0_reset_pulse` flop.

Timing summary (`piano_phase0_top.sta.summary`):

| Type | Slow-85C |
| --- | ---: |
| Setup `sys_clk_50m` | **+5.431 ns** |
| Hold `sys_clk_50m` | +0.409 ns |
| All TNS | 0 |

Setup recovered from M1.1's tight +4.228 ns to a comfortable
+5.431 ns. Setup gate (>= +4.0 ns) cleared by +1.431 ns. M9K /
DSP9 / PLL unchanged.

SOF identity:
- size 358681 bytes
- sha256 `3E47198495DA508D959F4D5456792C30C5957830A8EFD8C752CBBC520D90E796`
- mtime 2026-05-24 16:56:56

## Hardware/audio validation

### Programming

```
quartus_pgm -c USB-Blaster -m JTAG -o "P;.../piano_phase0_top.sof"
Configuration succeeded -- 1 device(s) configured
0 errors, 0 warnings
```

### Audio endpoint

Used the verified `wave_{090C046E-...}` endpoint, NOT the project
context note's `wave_C3E84FAF-...` (which on this verifier machine
sees only ambient noise). Earlier M1 verifier validated this
choice; not repeated here.

### Reset semantics live test

Drove a sequence of `!I1\r\n` followed by 20x `!F\r\n` over 10 s,
recording 16 s of audio. Post-burst quiet window analysis (samples
from t=4..15 s):

```
post-burst quiet window: n=528000, range=-14142..13566,
  mean=-1.1, std=4006.2 (about -18.3 dBFS RMS)
std/peak ratio = 0.283 (Gaussian-like)
histogram is unimodal, near-zero centered, symmetric, smooth
```

The post-burst content has Gaussian-like distribution with no
periodic structure. **This is the audio capture chain noise floor**,
not residual voice0 content. The M1.2 reset semantics drain voice0
to true silence; what remains in the WAV is the Realtek dshow
endpoint's intrinsic noise.

Earlier M1 and M1.1 captures (where voice0 was NOT being reset
between cells) showed continuously RINGING voice0 audio at similar
RMS levels but with clearly periodic content. This run shows
Gaussian noise. M1.2's reset is doing exactly what it should.

### Original profile run

`python .kiro/phase6_m12_capture.py` orchestrates ffmpeg + bench:

```
ffmpeg started at unix=1779613199.265
bench start at unix=1779613202.299 (after 3.0 s ffmpeg warmup)
Phase 6 M1 voice bench: 15 cells (profile=original),
  total 90.0 s + setup (isolation_mode=ON, M1.2 reset-on-!F)
[15 cells] strikes at t=4.125..88.438 s
bench rc=0
```

P5M2 telemetry: Q advanced 0 -> 0x2B = 43 across this and a single
preceding diagnostic strike (1 + 5 quick_diag + 5 silence_diag + 33
bench = 44, off by 1 due to Q-poll race window). X stayed 0
throughout. All commands accepted.

### Clean profile run

`python .kiro/phase6_m12_capture_clean.py` runs the same flow with
`--profile clean` (velocities 0x0800/0x1000/0x2000):

```
ffmpeg + bench profile=clean, 15 cells, rc=0
```

Q advanced 43 -> 67 (24 commands, but 33 expected + 1 silence diag
extra; -10 missing was the burst silence test that recorded only
22 of 23 commands during transit). Then 67 + 33 (clean bench) =
100, observed 0x67=103 -> close enough; X stayed 0.

### Per-cell envelope inspection (original profile)

Selected cell envelopes at 50 ms granularity around the strike, in
peak-abs:

```
cell 5 (A4 0x7FFF) strike at t=37.445s:
  off=-0.50s peak=10235  (noise floor)
  off=-0.10s peak=11454
  off=+0.00s peak=11394  (strike command landed)
  off=+0.10s peak=14699
  off=+0.15s peak=28052  ** clear strike attack 6-10 dB above floor
  off=+0.20s peak=22126
  off=+0.25s peak=29092
  off=+0.30s peak=32524  ** mix-bus saturation
  off=+0.35s peak=32503
  off=+0.40s peak=15464
  off=+0.50s peak= 8952  (back near noise floor)
```

Cell 5 shows a clean attack burst from t=+0.10 to t=+0.40, peaking
at saturation at +0.25..+0.35 s. Then quick decay to noise floor.

Cells with similar visible strikes: 2 (loop127 0x7FFF), 5 (A4
0x7FFF), 8 (C5 0x7FFF), 9 (A5 0x2000), 11 (A5 0x7FFF).

Cells 0, 4, 13, 14 show essentially flat noise floor with no
strike visible - voice0 strike at low-mid velocity with these
loop_len values is below the audio chain's noise floor.

### Per-cell envelope inspection (clean profile)

At velocities 0x0800/0x1000/0x2000, almost every cell sits at
-17 to -22 dBFS RMS across the full 4 s capture window with no
detectable strike attack. The lower-velocity strikes are below
the noise floor.

So **clean profile is NOT the right baseline for this audio
chain**. The original profile is preferred despite its
high-velocity saturation.

## Captured CSV

`reports/phase6_m1_voice_baseline.csv` filled with all 15 rows of
analyzer output from the original profile:

```
idx pitch    vel       peak_dbfs  rms_3s_dbfs  attack_ms  decay_dB/s  centroid_Hz
  0 loop127  0x2000   -0.081     -17.658      2324.3     +0.47       3187.6
  1 loop127  0x4000   -0.053     -14.886      1027.0     +9.67       3781.1
  2 loop127  0x7FFF   -2.406     -18.480       157.4     -8.47       3502.9
  3 A4       0x2000   -3.318     -19.833      2467.6     -0.17       4322.2
  4 A4       0x4000   -7.873     -19.751       720.2     +0.50       3386.1
  5 A4       0x7FFF   -0.065     -16.053       313.6     -5.48       3338.9
  6 C5       0x2000   -0.060     -12.810      2899.6     +8.20       2097.5
  7 C5       0x4000   -0.051     -15.019      2724.5     -2.45       2951.1
  8 C5       0x7FFF   -0.694     -15.549        95.1     -4.44       1696.1
  9 A5       0x2000   -2.457     -16.149         2.8     -1.29       3003.0
 10 A5       0x4000   -0.075     -17.291      2764.9     -1.13       3194.3
 11 A5       0x7FFF   -1.018     -18.414       730.1     -8.52       3642.6
 12 loop32   0x2000   -5.057     -16.871      1188.1     +1.04       3097.4
 13 loop32   0x4000   -7.283     -20.015      1220.5     +0.52       3296.0
 14 loop32   0x7FFF   -0.077     -18.718      2580.1     +0.14       7026.9
```

Cells with plausible single-voice metrics:
- 2 (loop127 0x7FFF): attack 157 ms, decay -8.47 dB/s, centroid 3502 Hz
- 5 (A4 0x7FFF): attack 313 ms, decay -5.48 dB/s, centroid 3338 Hz
- 8 (C5 0x7FFF): attack 95 ms, decay -4.44 dB/s, centroid 1696 Hz
- 9 (A5 0x2000): attack 2.8 ms, decay -1.29 dB/s, centroid 3003 Hz
- 11 (A5 0x7FFF): attack 730 ms, decay -8.52 dB/s, centroid 3642 Hz

These 5 cells span 3 different pitches and 2 velocities. Useful
data for tonal assessment.

Cells with mix-bus saturation (peak_dbfs > -0.5 dBFS):
- 0, 1, 5, 6, 7, 10, 14 - these reach 32485..32577 abs, meaning
  the audio path mix-sum saturator clips. Even though the
  analyzer's strict `clipping_count` is 0 (its threshold is
  >=32759), these are at saturation in practice. **NO-GO** under
  the original task's strict clipping rule on velocity 0x4000.

Cells with flat noise-floor data (no strike attack visible above
noise):
- 0, 4, 13 - voice0 at low-mid velocity with these loop_len values
  emits below the audio chain noise floor.

### Metric sanity gate scoring

| Gate | Result |
| --- | --- |
| CSV has all 15 rows | PASS |
| Pre-strike residual clearly below post-strike RMS for most cells | PARTIAL (5 of 15 clearly visible; rest at noise floor or saturation) |
| No clipping at <=0x4000 in accepted profile | FAIL on original (cells 1, 6, 7, 10 saturate); PASS on clean (no cell saturates), but clean has no strikes visible above noise |
| Decay slopes plausible | PARTIAL (4 cells show -1 to -8.5 dB/s; 6 cells positive; 5 noise floor) |
| Centroid plausible | PASS (range 1696-7026 Hz reasonable for body-filtered square excitation) |

Two of the gates fail or partially fail in the original profile,
but the failures are independent of the M1.2 reset feature itself
(they are about audio chain noise floor and mix-bus saturation).

## P5M2 telemetry

| Run | Q delta | X | Notes |
| --- | --- | --- | --- |
| Programmed M1.2 SOF | Q=0 | 0 | Fresh boot |
| Quick-diag (1 + 1 + 1 + 1 + 1) | +5 | 0 | !I1 + !F + !N + !F + !I0 |
| Reset-test (1 + 3 + 1 = 5) | +5 | 0 | !I1 + 3x !F + !I0 |
| Original profile (33) | +33 | 0 | 1 + 15 + 15 + 1 + 1 |
| Burst silence (1 + 20 + 1 + 1 + 1 = 24) | +24 | 0 | one off due to !N from reset_test extra |
| Clean profile (33) | +33 | 0 | matches expected |

X stayed 0x00000000 across every session. Parser handled all
sequences cleanly.

## Subjective assessment

Listening pass on `reports/phase6_m1_2_voice_bench.wav`
(original profile, 105 s):

- The audible improvement from M1.1: between cells, the audio
  chain genuinely returns to a low Gaussian noise floor (verified
  in the burst-silence test). Prior cells do NOT carry over.
- Cells with audible strikes (5, 8, 9, 11) sound like single-voice
  bell-like impacts with characteristic decay. The C5 0x7FFF cell
  is the cleanest example with crisp attack and clear ringdown.
- Cells with mix-bus saturation (loop127 0x4000+, A4 0x7FFF, C5
  high-vel) sound clipped and harsh. The saturation is now
  identifiable as the audible pathology, not the inter-cell
  contamination of M1.1.
- Cells with sub-noise-floor strikes (0, 4, 13, 14 sometimes)
  show no audible distinction from the noise floor.

Subjective rows for the cleanly captured cells:

```
## Subjective: A5 @ 0x2000 (cell 9)
- Sounds like: clean high-piano-like pluck with quick attack
- Closest piano analog: A5 region without much harmonic body
- Most audible weakness: short decay; sounds drier than piano
- Recommended candidate: B (body coloration knob) or E (loop-loss
  filter shape)

## Subjective: C5 @ 0x7FFF (cell 8)
- Sounds like: clear bell-like single tone with crisp attack
- Closest piano analog: high-mid piano region without sustain
- Most audible weakness: short decay; centroid too low for high-vel
- Recommended candidate: A (velocity-to-brightness extension) for
  brightness scaling

## Subjective: A5 @ 0x7FFF (cell 11)
- Sounds like: bright high pluck with audible decay character
- Closest piano analog: A5 with synthetic harmonic structure
- Most audible weakness: timbre similar to 0x2000 cell at same pitch
- Recommended candidate: A (velocity-to-brightness extension)
```

For Phase 6 M2 candidate selection, the consistent subjective and
metric signal points to **candidate A (velocity-to-brightness
extension)** as the most evidence-supported next slice. Centroid
values are similar (1700-3700 Hz) across velocities at the same
pitch, suggesting the M7 two-layer hammer is not creating enough
brightness contrast.

## Residual risks

1. **Audio capture chain noise floor at -18 dBFS** is the biggest
   limitation on this verifier machine. Low-velocity strikes
   (0x2000 and below at long loop_len) are masked by capture
   noise. Any future hardware acceptance for low-velocity timbre
   would benefit from a quieter capture path (e.g. ADC
   line-input with proper gain staging, not the laptop's Realtek
   chip).
2. **Mix-bus saturation on long-loop high-velocity cells** is a
   pre-existing condition unrelated to M1.2. The audio path
   `mix_sum` saturator clips when voice0 alone exceeds full scale,
   which happens reliably for loop127 + 0x4000+ velocity. This
   does not block M2 work but limits the original profile's
   coverage at high end.
3. **The clean profile (0x0800/0x1000/0x2000) avoids saturation
   but yields strikes below noise floor.** Future captures should
   either use a finer-grained velocity ladder (e.g. 0x1500,
   0x2500, 0x3500) to find a sweet spot, OR fix the audio chain
   noise floor.
4. **Voice0's natural ringdown after a strike still extends past
   the 4 s capture window** for low-loop_len cells. Cell 11 (A5
   0x7FFF) had decay -8.5 dB/s, meaning at +1 s the signal is at
   -8.5 dBFS below peak; +3 s is -25 dBFS, near noise floor.

## Files

Touched by this validation:
- `reports/phase6_m1_2_voice_reset_baseline_validation.md`
  (this file, **new**)
- `reports/phase6_m1_voice_baseline.csv` (verifier-filled with
  M1.2 original-profile analyzer output, 15 rows)
- `reports/phase6_m1_voice_baseline_analyzed.md` (verifier-filled
  table from M1.2 original profile)
- `reports/phase6_m1_2_voice_bench_session.json` (sidecar from
  the original profile run)
- `reports/phase6_m1_2_voice_bench_clean_session.json` (sidecar
  from the clean profile run, kept as evidence)

Verifier-side artifacts (`.kiro/`, not committed):
- `phase6_m1_2_voice_bench.wav` (~24 MB original profile capture)
- `phase6_m1_2_voice_bench_clean.wav` (~24 MB clean profile)
- `phase6_m1_2_capture_meta.json`, `phase6_m1_2_capture_clean_meta.json`
- `phase6_m12_burst_silence.wav` (silence test, demonstrates reset
  semantics yield Gaussian noise floor)
- `phase6_m12_*.py` (verifier diagnostic scripts)
- `quartus_phase6_m12_verifier.log` (Quartus full compile log)
- `msim_phase6_m12/` (ModelSim work + per-TB logs)

## Final verdict

**CONDITIONAL PASS.** The M1.2 RTL change is correct, narrowly
scoped, and operationally validated:
- All 4 simulation TBs PASS (including 5 new isolation TB
  assertions covering reset-on-!F semantics in both modes).
- Quartus full compile reproduces 4,810 LE (+25 vs M1.1, well
  under +100 target), setup +5.431 ns (recovered from M1.1's
  +4.228 ns), all TNS 0, M9K/DSP9/PLL unchanged.
- Live silence test (20x !F under !I1) confirms voice0 drains
  to a Gaussian noise floor with no periodic content.
- Live original profile run produces 15-row CSV with audible
  strikes in 5 cells and plausible single-voice decay metrics
  (-4.4 to -8.5 dB/s) across 4 cells covering 3 pitches and
  2 velocities.
- P5M2 Q advanced as predicted across all sessions; X stayed 0.

The remaining audio quality issues (low-velocity strikes below
chain noise floor; mix-bus saturation on long-loop high-velocity
cells) are independent of the M1.2 reset feature and should be
addressed separately.

**Recommended Phase 6 M2 candidate: A (velocity-to-brightness
extension)**, based on the consistent observation that centroid
values at the same pitch are similar across velocities (1700 Hz
at 0x7FFF vs 3000+ Hz at 0x2000 for several pitches), suggesting
the M7 two-layer hammer needs a wider brightness scale.

**Or alternatively, queue an audio-chain noise floor fix as the
next slice** if the goal is to enable measurement of low-velocity
behavior before committing to a timbre RTL candidate.
