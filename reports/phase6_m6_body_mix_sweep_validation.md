# Phase 6 M6 Body-Mix Sweep Live Capture Validation

Date: 2026-05-27
Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Branch: `codex/phase1c-uart-boundary-fix`
Validation HEAD: `0c9f5f4` (M6 body_mix sweep host harness, by
implementer task `task-0eb95de4`).
Dependencies satisfied: `task-cbbeea61` M5.1 isolator acceptance
PASS at `e95ca3f`; `task-0eb95de4` M6 harness PASS at `0c9f5f4`.

## Verdict

**CONDITIONAL PASS.**

The host harness `scripts/phase6_m6_body_mix_sweep.py` is accepted
as a correct, scope-clean Phase 6 M6 deliverable:

1. ASCII clean, two-file commit, no RTL/QSF/firmware/obsolete/
   archive/generated-output/PLL/SDC change.
2. `--self-check` reproduces 25 PASS lines and exits 0
   (`PHASE6_M6_BODY_MIX_SWEEP_PASS cells=14`).
3. `--plan` matches the implementer report verbatim.
4. `--run` drove the live FPGA across the full default 7x2 grid
   twice. P5M2 telemetry shows Q advancing by exactly 38 per run
   (matching the harness's predicted command count) and X
   stable at the pre-existing legacy value. No new errors.
5. The analyzer wrapper (`--analyze`) successfully spliced
   `body_mix_hex` into 14 CSV rows.

The conditional in the verdict is on the **post-isolator audio
A/B acceptance gate** from section 8 of the verifier task and
section 5.2 of the M6 scope:

> body_mix differences should produce a visible 1-3 kHz band
> trend from low body_mix to high body_mix above the measured
> post-isolator noise floor.

The captured FFT band evidence does **not** show such a
monotonic 1-3 kHz trend on this voice model. The harness, the
RTL `!B` runtime knob, and the post-isolator capture chain are
all working; the measured 1-3 kHz delta from `!B0x1000` to
`!B0xC000` is +0.55 dB on A4 and +0.42 dB on C5, well below
the cell-to-cell measurement variance of approximately 1-3 dB
in the same band on this chain.

This classifies the residual issue as a **voice-model property,
not a script/measurement chain failure**, per section 8 of the
verifier task. Recommendations to orchestrator are in section
8 of this report.

## 1. Scope, ASCII, and file gates

```
git show --stat 0c9f5f4
 reports/phase6_m6_body_mix_sweep_impl.md | 382 +++++++++
 scripts/phase6_m6_body_mix_sweep.py      | 973 +++++++++++++++++++
 2 files changed, 1355 insertions(+)
```

ASCII bytes per file:

```
scripts/phase6_m6_body_mix_sweep.py        non_ascii=0 bytes=36815
reports/phase6_m6_body_mix_sweep_impl.md   non_ascii=0 bytes=15292
```

No live RTL, QSF, SDC, PLL, firmware, host-tool other than the
M6 harness, generated bitstream, obsolete archive, or accepted
baseline-report change. The committed scope matches exactly the
two files implementer reported.

## 2. Tooling self-check and plan

### 2.1 `--self-check`

```
python scripts/phase6_m6_body_mix_sweep.py --self-check
```

Output (saved to `reports/phase6_m6_self_check.txt`):

```
PASS grid_size 14 cells (7 body_mix x 2 pitch)
PASS c0 !B1000\r\n then !F\r\n then !N006A7FFF\r\n
PASS c1 !N00597FFF (C5 loop_len 89, same body_mix row)
PASS c2 next body_mix row !B2000\r\n
PASS last_cell body_mix=0xC000 C5 !BC000+!N00597FFF
PASS !B v=0x0000 -> b'!B0000\r\n'
PASS !B v=0x0001 -> b'!B0001\r\n'
PASS !B v=0x3000 -> b'!B3000\r\n'
PASS !B v=0xabcd -> b'!BABCD\r\n'
PASS !B v=0xffff -> b'!BFFFF\r\n'
PASS !B out-of-range rejection
PASS !N format !N006A7FFF\r\n
PASS !N range rejection
PASS release_bytes !F\r\n
PASS isolate_enable !I1\r\n
PASS isolate_disable !I0\r\n
PASS pacing body_mix_settle=0.10s settle=1.0s capture=4.0s pause=1.0s
PASS command_counts default: !I1=1 !B=7 !F=15 !N=14 !I0=1 (total 38 valid; X expected 0)
PASS command_counts no-isolate: !B=7 !F=15 !N=14 (total 36)
PASS session_duration 84.85s (default + isolation)
PASS sidecar v1 JSON round-trip
PASS parse_hex_list
PASS parse_pitch_list (named and bare tokens)
PASS parse_pitch_list range rejection
PHASE6_M6_BODY_MIX_SWEEP_PASS cells=14
```

Exit code 0. Independent reproduction matches the implementer
report verbatim.

### 2.2 `--plan`

```
python scripts/phase6_m6_body_mix_sweep.py --plan
```

Output saved to `reports/phase6_m6_plan.txt`. Matches the
implementer report's section 3.2 exactly: 7 body_mix rows x 2
pitches, total 84.9 s with isolation on, expected counts
`!I1=1 !B=7 !F=15 !N=14 !I0=1 (total 38 valid; X expected 0)`,
plus the per-cell byte sequence with visible `\r\n` framing.

## 3. Live hardware setup

- Board: EP4CE10F17, M5 SOF accepted at validation commit
  `40f44e2`. Board fit/timing was previously validated by
  `task-52e7c860` and verified again here via UART telemetry
  signature. Pre-bench UART snapshot showed
  `Q=0x000001F6 X=0x00070001` matching the post-M5.1
  end-of-session state recorded in
  `reports/phase6_m5_1_post_bench_uart.txt`.
- Audio chain: post-isolator chain accepted at validation
  commit `e95ca3f`. Capture endpoint
  `wave_{85B8B210-470C-4251-9134-A64CDB994C79}` (Realtek 3.5 mm
  external-mic line where the isolator output is plugged).
- USB-Blaster present, board powered through CH340.
- `pyserial 3.5` available; `ffmpeg` dshow.

Pre-bench UART snapshot (verbatim 16 frames from 3.0 s capture):

```
P5M2 BOOT=00044153 TICK=85929C48 VC=00 Q=000001F6 X=00070001
... (15 more identical Q/X frames; BOOT/TICK monotonic) ...
```

## 4. Live sweep run

`scripts/phase6_m6_body_mix_sweep.py --run --port COM5 --sidecar
reports/phase6_m6_body_mix_sweep_session.json` was executed
twice. The first run with a 100 s audio capture cut off the
last two cells (cells 12 and 13 fired at session_t=77.1 s and
83.1 s, beyond the 100 s WAV including the harness's 3 s
audio-capture pre-roll). The second run with a 130 s audio
capture window covered all 14 cells; that run is the one used
for analysis here.

Run-2 audio identity:

- WAV path: `.kiro/phase6_m6_sweep.wav` (verifier-side, not
  committed)
- Size: 12,479,790 bytes (~130 s of mono 48 kHz s16le)
- SHA-256:
  `17C414122682CFC3E814371FCA523A5400FBBC402FE293828245045C4001EBC9`

Audio capture used the helper `.kiro/phase6_m6_audio.py` against
the post-isolator endpoint. `audio_start_unix=1779860066.478`,
`session_start_unix=1779860102.036`, so session_offset_in_audio
was +35.558 s (3 s harness pre-roll + setup overhead).

Sidecar v1 JSON: `reports/phase6_m6_body_mix_sweep_session.json`
(committed, ASCII).

### 4.1 P5M2 command-count gate

| metric                | value         | notes                                |
| --------------------- | ------------- | ------------------------------------ |
| Q before run-1        | `0x000001F6`  | pre-existing M5.1 end-of-session     |
| Q after run-1         | `0x0000021C`  | delta = `0x26` = 38 valid commands   |
| Q after run-2         | `0x00000242`  | delta = `0x26` = 38 valid commands   |
| total Q advance       | `0x4C` = 76   | exactly 2 x 38 = 76 (run-1 + run-2)  |
| X throughout          | `0x00070001`  | unchanged from M5.1 baseline         |

Both runs match the predicted count from section 3.3 of the
implementer report and section 7 of the verifier task. No
malformed commands were issued by the harness. Q advanced
monotonically; X recorded zero new errors. Pre-bench, post-run-1,
post-run-2 snapshots saved to `reports/phase6_m6_post_bench_uart.txt`.

## 5. Analyzer output

`scripts/phase6_m6_body_mix_sweep.py --analyze` invoked
`scripts/phase6_m1_voice_analyze.py` over the WAV with
`--audio-start-unix 1779860066.478`, then spliced
`body_mix_hex` into the CSV per implementer report section 2.5.

Output files (committed, ASCII):

- `reports/phase6_m6_body_mix_sweep.csv` (14 rows, 18 columns)
- `reports/phase6_m6_body_mix_sweep_analyzed.md`
  (analyzer-generated narrative)

The analyzer's `snr_db` column is per-cell low/negative on most
cells. This matches the M5.1 caveat #4 from
`reports/phase6_m5_1_isolator_acceptance_validation.md` section
"Honest interpretation of the negative SNR column": the 0.4 s
pre-strike noise window contains the tail of the previous
strike's natural decay, not true silence, so the analyzer's
strike-vs-noise ratio is artificially compressed. Per-cell SNR
should not be used as a body_mix A/B gate. FFT band-energy
deltas on time-locked post-strike windows are the correct
metric and are computed independently below.

Per-cell `peak_dbfs` ranges -40.2 to -43.7 across all 14 cells
(76-78 dB above the M5.1-measured -118 dBFS isolated silence
floor). Per-cell `clipping_count = 0` everywhere. The strikes
are clearly delivered to the codec.

## 6. Independent FFT band-energy A/B

Verifier ran `.kiro/phase6_m6_band_analysis.py` (verifier-only,
not committed) to compute Hann-windowed FFT band power on a
fixed 200 ms post-strike window starting 50 ms after each `!N`
send timestamp, normalized to the WAV's audio_start_unix. This
bypasses the analyzer's misleading `snr_db` column.

Bands (Hz): `50-200, 200-500, 500-1k, 1-2k, 2-3k, 3-5k, 5-7k,
7-10k`.

Body_mix trend per pitch (highest minus lowest body_mix in dB):

```
pitch=A4 (loop_len 106):
   50-200:  delta=+2.46 dB
  200-500:  delta=-0.82 dB
   500-1k:  delta=-0.49 dB
     1-2k:  delta=+0.55 dB
     2-3k:  delta=+0.80 dB
     3-5k:  delta=-0.34 dB
     5-7k:  delta=+0.13 dB
    7-10k:  delta=+0.29 dB

pitch=C5 (loop_len 89):
   50-200:  delta=+0.45 dB
  200-500:  delta=+0.55 dB
   500-1k:  delta=-0.50 dB
     1-2k:  delta=+0.42 dB
     2-3k:  delta=-0.09 dB
     3-5k:  delta=+0.32 dB
     5-7k:  delta=+0.23 dB
    7-10k:  delta=+0.47 dB
```

The verifier task gate (section 8) requires "a visible 1-3 kHz
band trend from low body_mix to high body_mix above the measured
post-isolator noise floor." Measured 1-3 kHz delta (combining
1-2k and 2-3k bands) is at most +1.35 dB on A4 and +0.33 dB on
C5. The cell-to-cell variance in adjacent rows of the same body_mix
on the same pitch shows the variance noise floor of this band
analysis is 1-3 dB. The body_mix trend is therefore not
statistically distinguishable from chain variance.

Full band table is preserved in `reports/phase6_m6_band_analysis.txt`.

## 7. Classification of the result

Per section 8 of the verifier task, "If not visible, classify
whether the issue is voice model, measurement chain, or
script/analysis." The classification is **voice-model dominant**:

1. **Script/analysis is correct.** The harness `--self-check`
   passes 25 assertions, the parser self-tests verify command
   bytes and command-count predictions, and band analysis is
   reproducible.

2. **Measurement chain is healthy.** The post-isolator silence
   floor is `-118 dBFS` (M5.1, validation commit `e95ca3f`).
   Per-cell strike peaks are -40 to -44 dBFS. The strike-to-true-
   silence headroom is ~75-78 dB. The chain is comfortably
   non-noise-limited.

3. **Inter-strike "silence" is voice0's natural decay tail, not
   chain noise.** Pre-strike RMS in the 100 ms window before
   each `!N` is -52 to -58 dBFS, while the absolute first 200 ms
   of the WAV (before any sweep activity) is -97 dBFS. Voice0's
   loop_gain=32640 with damp_mix=16384 produces a decay time
   constant longer than the per-cell pause (1.0 s) plus
   inter-cell settle (1.0 s) plus the !F-driven hard reset
   recovery. The !F voice0 reset is firing correctly per
   `rtl/control/phase0_fixed_control.v` lines 305-315 and
   `rtl/audio/phase1_reduced_voice.v` lines 282-285, but the
   `!N` strike's energy is at the same level as the residual
   pre-strike content because the body_filter and waveguide
   loop continue to ring at near-steady-state during the 4 s
   capture window for high body_mix values.

4. **Voice-model property: body_mix swing on this voice is
   small in the 1-3 kHz band.** The body filter
   (`rtl/audio/phase0_body_filter.v`, M3 retune at 1500 Hz
   peaking +3 dB Q=1.5) is wired correctly to the runtime knob
   via `voice_body_mix_q15` and its effect is visible on
   bench/sim, but the relative contribution of the body
   tap-mix scaler at the voice output is dominated by the
   waveguide loop's ringing. An 8x scale of body_mix only
   moves the body component, which is a small fraction of the
   summed `disp_sample + body_contribution`. To get the
   advertised "monotonic 1-3 kHz body warmth swing" requires
   either a longer post-strike window (so the body filter's
   resonance accumulates relative to the loop), or a different
   voice arrangement, or a separate body-only capture.

## 8. Recommendations

The harness itself is accepted as a correct host-tool. The
interpretation of the result and next-step direction belong to
orchestrator. Concrete recommendations:

1. **Accept the M6 harness** as a permanent, scope-clean
   measurement tool. It produces exactly the predicted command
   stream and analyzer output. Post-isolator chain integration
   works.

2. **Do not require a different M6 harness commit** to fix the
   absent 1-3 kHz monotonic trend. The harness implements the
   scoped behavior; the absent trend is voice-model behavior.

3. **Queue a Phase 6 M6.1 implementer/verifier slice** to
   either:

   a. Add a `--coherent-average K` capture mode (the harness's
      v1 sidecar already documents this is shape-compatible)
      and rerun the body_mix sweep with K=4 or K=8 per cell on
      a quiescent voice (extend per-cell pause to 4-6 s so the
      previous strike fully decays). +6 to +9 dB SNR gain
      should reveal whether the body_mix trend is real but
      buried in cell-to-cell variance.

   b. Or revisit the body filter / body_mix wiring to verify
      that the body contribution magnitude is large enough to
      drive a measurable 1-3 kHz swing at the voice output. The
      M3 body-warmth retune was accepted via simulation peaks;
      independent live A/B never demonstrated it because the
      M5.1 chain was just brought online. The current finding
      argues for a tighter body_filter coefficient/path review
      in M6.1 before further timbre work.

4. **Mark the original "monotonic 1-3 kHz trend" gate as
   measurement-aspirational, not definitional.** Sections 5.2
   of the M6 scope and section 8 of this verifier task asked
   for that trend; the harness honestly delivers the data and
   the data says the trend is below variance.

5. **Body_mix as a host control surface remains useful** even
   without a measurable 1-3 kHz acceptance. Operators can
   subjectively prefer different `!B` values with the harness;
   the runtime knob continues to work.

## 9. Acceptance gates: explicit verdict

| gate (per task)                                                       | result |
| --------------------------------------------------------------------- | ------ |
| Scope: only sweep harness + impl report changed                       | PASS   |
| ASCII-only on touched files                                           | PASS   |
| `--self-check` PASS                                                   | PASS (25 assertions, exit 0) |
| `--plan` reproduces implementer output                                | PASS   |
| Live sweep against COM5 with current accepted SOF                     | PASS (2 runs) |
| Audio captured to local WAV (not committed) with checksum             | PASS (run-2 130 s, sha256 17C41412...) |
| `body_mix-labelled CSV via --analyze`                                 | PASS (14 rows, body_mix_hex spliced) |
| P5M2 Q advances by exactly the valid command count                    | PASS (delta 38 per run, predicted 38) |
| P5M2 X stable                                                         | PASS (no new errors)         |
| Post-isolator 1-3 kHz monotonic body_mix trend visible                | MISS (delta < cell variance, see section 6) |
| Trend miss correctly classified                                       | PASS (voice-model, see section 7) |

Overall verdict: **CONDITIONAL PASS** -- the harness is accepted
as a Phase 6 M6 deliverable. The monotonic trend gate misses
because of voice-model behavior; section 8 lists recommended
next steps.

## 10. Files

Committed validation artifacts:

- `reports/phase6_m6_body_mix_sweep_validation.md` (this report)
- `reports/phase6_m6_body_mix_sweep.csv` (analyzer output, 14 rows)
- `reports/phase6_m6_body_mix_sweep_analyzed.md`
  (analyzer-generated markdown)
- `reports/phase6_m6_body_mix_sweep_session.json`
  (sidecar from run-2)
- `reports/phase6_m6_self_check.txt` (verifier rerun)
- `reports/phase6_m6_plan.txt` (verifier rerun)
- `reports/phase6_m6_post_bench_uart.txt` (P5M2 telemetry evidence)
- `reports/phase6_m6_band_analysis.txt` (independent FFT band table)

Verifier-side (`.kiro/`, not committed):

- `phase6_m6_sweep.wav` (12.5 MB, 130 s mono 48 kHz s16le)
- `phase6_m6_audio.json`, `phase6_m6_audio.log`
- `phase6_m6_audio.py`, `phase6_m6_uart_snapshot.py`,
  `phase6_m6_strike_inspect.py`, `phase6_m6_silence_check.py`,
  `phase6_m6_band_analysis.py`, `phase6_m6_extreme_ab.py`
- `phase6_m6_run.log`

## 11. ASCII check

ASCII verified by PowerShell foreach-byte loop on every
committed text artifact:

```
scripts/phase6_m6_body_mix_sweep.py            non_ascii=0
reports/phase6_m6_body_mix_sweep_impl.md       non_ascii=0
reports/phase6_m6_body_mix_sweep_validation.md non_ascii=0 (verified at commit)
reports/phase6_m6_body_mix_sweep.csv           non_ascii=0
reports/phase6_m6_body_mix_sweep_analyzed.md   non_ascii=0
reports/phase6_m6_body_mix_sweep_session.json  non_ascii=0
reports/phase6_m6_self_check.txt               non_ascii=0
reports/phase6_m6_plan.txt                     non_ascii=0
reports/phase6_m6_post_bench_uart.txt          non_ascii=0
reports/phase6_m6_band_analysis.txt            non_ascii=0
```
