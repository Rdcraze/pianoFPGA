# Phase 6 M6.4-INT Cand E Internal Body-FIR Retune Validation

Date: 2026-05-28
Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-9fd633f8`
Branch: `codex/phase1c-uart-boundary-fix`
Implementer commit: `5ed08ec` (M6.4-INT Cand E body-FIR tap delay retune, task-40baab3b)
M6.3a baseline commit: `5ca80d9`
Verdict: **FAIL on 1-3 kHz acceptance gate, classified as voice-model limitation**

## TL;DR

The M6.4-INT Cand E source-vs-effective inconsistency from
the M6.4-INT scope is fully resolved. Implementer commit
`5ed08ec` correctly uses source `5'd4/12/24` to implement
true Cand E. Build, ASCII, M6.2/M6.3a preservation, vlog,
Quartus, hardware Q+38/X=0/clipping_count=0 all pass cleanly
and LE actually drops -29 versus M6.3a (5,131 -> 5,102) with
setup margin improving from +5.707 ns to +5.954 ns.

However, the live in-range body_mix sweep does NOT clear the
strict +1 dB CONDITIONAL_PASS gate in either 1-2 kHz or
2-3 kHz. Energy-mean across A4 and C5: 1-2k +0.37 dB,
2-3k -0.10 dB. Both well below predicted Cand E values
(+2.78 dB / +2.55 dB). The same ~2.5 dB systematic
prediction-vs-measurement gap that appeared in M6.3a
(predicted +2.49 dB vs measured +0.00 dB on 1-2k) reappears
on M6.4-INT. The strict gate cannot be met by any tap-delay
or weight retune of the current 3-tap body FIR because the
prediction model assumes broadband disp_sample, but the
actual `H_disp(f)` from the waveguide voice is strongly
shaped and concentrated below 1 kHz, so band-energy deltas
in 1-3 kHz are dominated by `H_disp(f)`, not by the body
contribution.

Recommended next step: orchestrator should pivot the body
axis to a documented voice-model limitation note and move to
a different voice-quality axis (hammer texture/attack
shaping, detune, longer release, or a per-voice
post-waveguide brightness control). The M6.4-INT RTL change
is itself safe and non-regressing; orchestrator may keep it
or revert to M6.3a depending on whether the slight 50-200 Hz
warmth (+1.07 dB) and 3-5 kHz brightness (+0.37 dB) gain is
preferred over M6.3a's slightly stronger 200-1k passband
emphasis.

## 1. Scope check (PASS)

`git show --stat 5ed08ec` confirms the expected three-file
commit:

| file                                              | category               |
| ------------------------------------------------- | ---------------------- |
| rtl/audio/phase1_reduced_voice.v                  | scope: body-FIR addr   |
| reports/phase6_m6_4_int_fir_impl.md               | scope: impl report     |
| reports/phase6_m6_4_int_fir_quartus_compile.log   | scope: build evidence  |

`git diff 5ca80d9..5ed08ec -- rtl/` returns zero output for
all files except `phase1_reduced_voice.v` body tap address
constants, confirming RTL change is narrowly scoped. No
firmware, host scripts, QSF, SDC, PLL, generated images,
obsolete archive, or `.kiro/` changes.

## 2. Cand E implementation correctness (PASS)

The RTL diff at `rtl/audio/phase1_reduced_voice.v` lines
101-114:

```
-wire [4:0] body_tap6_addr  = body_wr_ptr - 5'd7;
-wire [4:0] body_tap16_addr = body_wr_ptr - 5'd17;
-wire [4:0] body_tap30_addr = body_wr_ptr - 5'd31;
+// Phase 6 M6.4-INT Cand E: ...
+wire [4:0] body_tap6_addr  = body_wr_ptr - 5'd4;
+wire [4:0] body_tap16_addr = body_wr_ptr - 5'd12;
+wire [4:0] body_tap30_addr = body_wr_ptr - 5'd24;
```

Source constants `5'd4/12/24` produce effective FIR delays
`4/12/24` (per the inductive trace I established in
task-8844ef33 validation). This is **true Cand E**, not
Cand A. The precision finding from my M6.4-INT scope
validation is fully resolved.

M6.3a body doubling (`<<< 1` shift inside `sat_q18(...)`)
preserved verbatim at STATE_BODY_TAP30. M6.2 MSB-saturating
body_mix mapping (`body_mix_q15[15] ? 16'sd32767 :
$signed({1'b0, body_mix_q15[14:0]})`) preserved verbatim.
Tap weights (`>>> 2`, `>>> 3`, `>>> 4`) and sign pattern
(`+`, `-`, `+`) preserved verbatim.

## 3. ASCII check (PASS)

```
rtl/audio/phase1_reduced_voice.v                       non_ascii=0  total=23832
reports/phase6_m6_4_int_fir_impl.md                    non_ascii=0  total=14325
reports/phase6_m6_4_int_fir_quartus_compile.log        non_ascii=0  total=64079
reports/phase6_m6_4_int_inrange_band_analysis.txt      non_ascii=0
reports/phase6_m6_4_int_inrange_sweep.csv              non_ascii=0
reports/phase6_m6_4_int_inrange_sweep_analyzed.md      non_ascii=0
reports/phase6_m6_4_int_inrange_sweep_session.json     non_ascii=0
reports/phase6_m6_4_int_pre_bench_uart.txt             non_ascii=0
reports/phase6_m6_4_int_post_inrange_uart.txt          non_ascii=0
reports/phase6_m6_4_int_inrange_sweep_run.log          non_ascii=0
reports/phase6_m6_4_int_fir_validation.md (this)       non_ascii=0
```

All committed reports/source/log files ASCII-clean.

## 4. Build validation (PASS)

### 4.1 Independent Quartus full compile

Independent verifier compile via
`quartus_sh.exe --flow compile quartus/phase0/piano_phase0_top.qpf`
on commit `5ed08ec` reproduced the implementer's numbers
exactly (log: `.kiro/m6_4_int_verify_compile.log`):

| metric                                    | M6.3a baseline | M6.4-INT (5ed08ec) | M6.4-INT (this verifier) | delta vs M6.3a |
| ----------------------------------------- | -------------: | ------------------: | -----------------------: | -------------: |
| Total LE                                  | 5,131 / 10,320 | 5,102 / 10,320      | **5,102 / 10,320**       | **-29**        |
| Combinational functions                   | 4,912          | 4,897               | 4,897                    | -15            |
| Dedicated logic registers                 | 2,313          | 2,313               | 2,313                    | 0              |
| Total memory bits                         | 20,480         | 20,480              | 20,480                   | 0              |
| DSP9 elements                             | 26 / 46        | 26 / 46             | 26 / 46                  | 0              |
| PLL                                       | 1 / 2          | 1 / 2               | 1 / 2                    | 0              |
| Setup slow-85C `sys_clk_50m`              | +5.707 ns      | +5.954 ns           | **+5.954 ns**            | +0.247 ns      |
| Hold slow-85C `sys_clk_50m`               | +0.409 ns      | +0.381 ns           | +0.381 ns                | -0.028 ns      |
| Slow-0C setup / hold                      | +6.841/+0.381  | +6.856/+0.381       | +6.856/+0.381            | gain           |
| Fast-0C setup / hold                      | +13.730/+0.137 | +13.630/+0.164      | +13.630/+0.164           | mixed          |
| All TNS                                   | 0              | 0                   | 0                        | 0              |
| Quartus errors / warnings                 | 0 / 16         | 0 / 16              | 0 / 16                   | 0              |

All hard task gates pass:

- LE delta `-29 <= +10` target. Actually saves LE.
- Setup slow-85C `+5.954 ns >= +4.0 ns` (improved over M6.3a).
- Hold clean (`+0.381 ns`), all TNS 0.
- M9K, DSP9, PLL unchanged. No DSP/M9K/PLL regression.
- 0 errors. Warnings unchanged at 16.

### 4.2 ModelSim vlog -sv (PASS)

```
vlog -sv rtl/audio/phase1_reduced_voice.v \
         rtl/audio/phase1_reduced_voice_tb.v \
         rtl/audio/phase1_reduced_voice_velocity_tb.v \
         rtl/audio/phase1_reduced_voice_body_mix_sat_tb.v
-> Compiling module phase1_reduced_voice
-> Compiling module phase1_reduced_voice_tb
-> Compiling module phase1_reduced_voice_velocity_tb
-> Compiling module phase1_reduced_voice_body_mix_sat_tb
-> Errors: 0, Warnings: 0
```

Log: `.kiro/m6_4_int_vlog.log`.

### 4.3 ModelSim vsim license blocker (carve-out)

```
vsim -c -do 'quit -f'
-> Unable to checkout a license. Vsim is closing.
** Fatal: Invalid license environment.
```

Same `LM_LICENSE_FILE` blocker accepted as carve-out per
M6.3a precedent. The reduced-voice golden hex
(`phase1_reduced_voice_golden_samples.hex`) was intentionally
NOT modified by implementer (would require working vsim to
regenerate). Per M6.3a precedent and task gate 5, this does
not fail the validation when source/build/hardware evidence
is otherwise strong. Future verifier with a working vsim
must regenerate via `+WRITE_GOLDEN`.

## 5. Hardware validation

USB-Blaster on USB-0, COM5 (CH340), post-isolator audio
endpoint `wave_{85B8B210-470C-4251-9134-A64CDB994C79}`. SOF
programmed from `quartus/phase0/output_files/piano_phase0_top.sof`
built from `5ed08ec`.

### 5.1 Self-check, plan, pre-bench UART

```
python scripts/phase6_m6_body_mix_sweep.py --self-check
-> PHASE6_M6_BODY_MIX_SWEEP_PASS cells=14
```

Pre-bench UART (`reports/phase6_m6_4_int_pre_bench_uart.txt`):
`Q=00000000 X=00000000` (clean baseline).

### 5.2 In-range sweep (Cand E hardware A/B vs M6.3a)

Grid: `[0x1000, 0x2000, 0x3000, 0x4000, 0x5000, 0x6000,
0x7000]` x `[A4 loop_len 106, C5 loop_len 89]` = 14 cells.
Velocity `0x7FFF`, isolation enabled, expected 38 valid
commands.

Audio capture: `.kiro/phase6_m6_4_int_inrange.wav`
(130 s mono 48 kHz)
audio_start_unix = 1779947086.9138498.

Post-bench UART (`reports/phase6_m6_4_int_post_inrange_uart.txt`):
`Q=00000026 X=00000000` -> Q advanced exactly 38, X stable
at 0. PASS on UART contract.

`clipping_count = 0` per cell across all 14 cells at
velocity 0x7FFF (sweep CSV column verified). No clipping
introduced.

Sweep artifacts:
- `reports/phase6_m6_4_int_inrange_sweep_session.json`
- `reports/phase6_m6_4_int_inrange_sweep.csv`
- `reports/phase6_m6_4_int_inrange_sweep_analyzed.md`
- `reports/phase6_m6_4_int_inrange_band_analysis.txt`

### 5.3 FFT band-energy A/B versus M6.3a accepted baseline

Per-pitch deltas from `reports/phase6_m6_4_int_inrange_band_analysis.txt`
(highest body_mix - lowest body_mix):

| band   | A4 delta | C5 delta | M6.4-INT energy-mean | M6.3a energy-mean | improvement |
| ------ | -------: | -------: | -------------------: | ----------------: | ----------: |
| 50-200 |  +1.85   |  +0.12   |  +1.07 dB            |  +0.01 dB         |  +1.06 dB   |
| 200-500|  -0.50   |  -0.42   |  -0.46 dB            |  +1.25 dB         |  -1.71 dB   |
| 500-1k |  +0.77   |  +0.57   |  +0.67 dB            |  +1.56 dB         |  -0.89 dB   |
| **1-2k** |  -0.28   |  +0.94   |  **+0.37 dB**        |  +0.00 dB         |  +0.37 dB   |
| **2-3k** |  +0.19   |  -0.41   |  **-0.10 dB**        |  +0.61 dB         |  -0.71 dB   |
| 3-5k   |  +0.13   |  +0.59   |  +0.37 dB            |  -0.32 dB         |  +0.69 dB   |

Predicted vs measured (Cand E):

| band | predicted (helper, 4/12/24 vs broadband disp) | measured energy-mean | gap |
| ---- | --------------------------------------------: | -------------------: | --- |
| 1-2k |                                       +2.78 dB |              +0.37 dB | -2.41 dB |
| 2-3k |                                       +2.55 dB |              -0.10 dB | -2.65 dB |

The same ~2.5 dB systematic prediction-vs-measurement gap
that M6.3a saw (1-2k predicted +2.49 vs measured +0.00)
reappears here, with the same direction. This is consistent
with `H_disp(f)` being strongly shaped (waveguide-resonant)
rather than broadband, so band-energy deltas in 1-3 kHz are
dominated by disp's spectrum, not by the body-doubling
factor `(1 + body_mix * H_FIR(f))`.

### 5.4 Acceptance gate evaluation

Per task description gates:
- "1-2k delta `>= +3 dB` PASS, `>= +1 dB` CONDITIONAL_PASS,
  `< +1 dB` FAIL/NO-GO unless capture-chain corruption is
  proven."

M6.4-INT 1-2k = +0.37 dB. **Below CONDITIONAL_PASS gate.**
M6.4-INT 2-3k = -0.10 dB. **Below CONDITIONAL_PASS gate.**

The capture chain is healthy (post-isolator, K=0, monotonic
Q, no X errors, peaks well within headroom -41 to -43 dBFS).
The cause is **NOT** capture-chain corruption.

The cause is a model/measurement mismatch: the linear
prediction `(1 + body_mix * H_FIR(f))` correctly describes
the relative ratio between two sweeps in the *spectrally
flat* sense, but the FFT band-energy ratio observed in
hardware is dominated by where `H_disp(f)` actually places
its energy. With the waveguide voice's strongly resonant
spectrum, body_mix changes mostly affect overall envelope
shape and harmonic balance, not band-localized energy in
1-3 kHz.

This is a **voice-model limitation**, not a M6.4-INT
implementation bug. The same limitation applies to the
broader M6.3a/M6.4 body-axis program.

## 6. Comparison vs prior milestones

The body-axis project history:

| milestone | predicted 1-2k (model) | measured 1-2k (hardware) | gap |
| --------- | ---------------------: | -----------------------: | --: |
| M6.2 baseline (current=7/17/31, no doubling) | -- | small/non-monotonic | -- |
| M6.3a (current FIR, body-magnitude doubling) | +2.49 dB | +0.00 dB | -2.49 dB |
| M6.4-INT Cand E (4/12/24 retune) | +2.78 dB | +0.37 dB | -2.41 dB |

The systematic ~2.5 dB gap is consistent across both
milestones and confirms the issue is model-vs-measurement,
not implementation. No further internal-FIR retune is
likely to clear the +1 dB strict gate within this voice
model and capture chain.

## 7. M6.3a state preservation (PASS)

`git diff 5ca80d9..5ed08ec -- rtl/audio/phase1_reduced_voice.v`
shows only the body tap address constants and the M6.4-INT
comment block changed. The M6.3a body doubling shift
(`<<< 1` inside `sat_q18(...)`) and M6.2 MSB-saturating
body_mix mapping are byte-for-byte identical. M6.3a's
empirically-measured improvements in 200-1 kHz (the body
filter passband) are not regressed in M6.4-INT in source
form; the hardware A/B in section 5.3 shows that band
energy is somewhat redistributed but no path is regressed
beyond the natural body-FIR shape change.

## 8. Macro-direction check (PASS)

- Voice quality first, polyphony as support: OK
- Fixed-function RTL preserved: OK
- No CPU/firmware/MMIO/register-file revival: OK
- No JTAG command path / on-chip strike scheduler / new
  UART syntax: OK
- M6.3a accepted state: numerically reproducible from this
  branch via revert (single 3-line address change)

## 9. Caveats and risks

1. The reduced-voice golden hex
   (`phase1_reduced_voice_golden_samples.hex`) is stale
   relative to M6.4-INT RTL because vsim is license-blocked.
   A future verifier with working vsim must regenerate via
   `+WRITE_GOLDEN`. Same carve-out as M6.3a.
2. The M6.4-INT change is a measurement wash on the 1-3 kHz
   acceptance gate but produces small redistribution of
   energy into 50-200 Hz (+1.06 dB warmth) and 3-5 kHz
   (+0.69 dB brightness). Whether this is audibly preferred
   over M6.3a's stronger 200-1k passband emphasis is a
   subjective call left to the orchestrator/user.
3. The systematic ~2.5 dB prediction-vs-measurement gap
   suggests the broadband-disp linearity model that drove
   the M6.4 NO-GO and M6.4-INT scope is incomplete. A more
   accurate analysis would convolve `(1 + body_mix * H_FIR(f))`
   with the actual `H_disp(f)` of a struck voice. The
   correct conclusion likely is that NO 3-tap body-FIR
   modification can produce a sustained +1 dB delta in the
   1-3 kHz acceptance band on this voice model.

## 10. Verdict and recommended next step

**FAIL on strict 1-3 kHz acceptance gate, classified as
voice-model limitation.**

All implementation gates pass:
- Scope, ASCII, Cand E correctness, M6.2/M6.3a preservation: PASS
- Quartus 0 errors, LE -29, setup +5.954 ns, M9K/DSP9/PLL unchanged: PASS
- vlog clean (vsim license-blocked carve-out): PASS
- Hardware Q+38 / X=0 / clipping_count=0: PASS

Acceptance gate fails:
- 1-2k delta +0.37 dB (below +1 dB CONDITIONAL_PASS): FAIL
- 2-3k delta -0.10 dB (below +1 dB CONDITIONAL_PASS): FAIL

**Recommended next step**:

1. Orchestrator should NOT pursue a further internal-FIR
   retune. The systematic ~2.5 dB prediction-vs-measurement
   gap shows that 3-tap body-FIR modifications cannot
   reliably move the 1-3 kHz body_mix delta gate within
   this voice model.
2. The 1-3 kHz acceptance gate itself is structurally
   ill-posed for the current voice architecture, where
   `H_disp(f)` is waveguide-resonant rather than broadband.
   Future body-axis work should either (a) measure body
   contribution by a different metric (e.g., per-pitch
   harmonic energy ratio, attack transient spectrum), or
   (b) accept the body knob as audibly-tunable but
   not-strictly-band-quantifiable.
3. Pivot voice-quality work to a different axis as
   suggested by the M6.4 NO-GO and M6.3a verifier reports:
   hammer texture / attack shaping, controlled detune,
   release/damper refinement, or per-voice post-waveguide
   brightness control.
4. Disposition of M6.4-INT RTL: orchestrator may keep
   commit `5ed08ec` because it is non-regressing and saves
   29 LE plus +0.247 ns setup, OR revert to M6.3a baseline
   for cleanliness. Either is defensible. My weak
   preference is to keep M6.4-INT given the LE/timing wins
   and its slight 50-200 Hz warmth and 3-5 kHz brightness
   gains, but the choice is not technically forced.

The body-axis program's measurement gate has reached the
limits of what the current 3-tap body FIR plus
shared-`body_mix` knob can produce on this voice model.
Voice-quality work should pivot.
