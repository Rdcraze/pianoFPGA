# Phase 4 M7 Velocity-Layered Hammer Validation

Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-bff26625` (depends on implementer `task-df919a1c`)
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `e90a820`

## Verdict

**PASS.** Phase 4 M7 velocity-layered hammer excitation is acceptance-grade. The
RTL change is contained to `rtl/audio/phase1_reduced_voice.v`, layer 0
preserves the original excitation curve bit-exact, layer 1 entries respect
`16'd32767`, the `velocity_layer_q` register is latched safely in the existing
sys_clk trigger block, and all gates pass: LE 10,099 / 10,320 (+107 from
9,992 baseline, comfortably below the +250 ceiling), setup +2.846 ns,
hold +0.429 ns, all TNS 0, M9K 16, DSP9 28, PLL 1, ROM 931, 0 errors,
16 warnings (no increase). ModelSim reduced-voice golden-sample TB PASS
bit-exact at velocity `0x4000` (layer 0). Hardware UART captures clean
(K=0, X=0) and audio capture shows healthy non-clipped output at production
default velocity `0x7FFF` (layer 1). Four physical voices preserved.

## Scope check

`git show --stat e90a820`:
- `rtl/audio/phase1_reduced_voice.v` (+62/-18 lines)
- `reports/phase4_m7_velocity_layered_hammer_impl.md` (+382 lines, new)

`git diff --stat 303274e..e90a820 -- ':!rtl/audio/phase1_reduced_voice.v' ':!reports/phase4_m7_velocity_layered_hammer_impl.md'`
returns no other tracked changes. No firmware, host tools, SDC, QSF/project
files, PLL, pins, generated outputs, other RTL, or accepted baseline reports
modified. PASS.

Untracked verifier files (`.kiro/`, prior `reports/phase3_m*_uart.txt`,
`reports/phase4_m7_*` UART/audio captures and analysis scripts) are
intentionally out of the implementer commit. They are not in scope for the
implementer review and are addressed below as verifier evidence.

## ASCII check

`reports/phase4_m7_velocity_layered_hammer_impl.md`: 0 non-ASCII bytes
(15,730 bytes total). PASS.

`rtl/audio/phase1_reduced_voice.v`: ASCII-only by inspection. PASS.

## Source review

### Layer 0 bit-exact preservation

The 16-entry layer-0 case arms in `excitation_rom` (lines 152-167) are:

```
1200, 9000, 24000, 32627, 26000, 19500, 14300, 10400,
7500, 5300, 3700, 2500, 1600, 1000, 500, 200
```

These values match the pre-M7 16-entry ROM exactly. Layer 0 is selected
when `velocity_q15 < 16'h6000`. The reduced-voice TB default velocity
`16'h4000` is below `16'h6000`, so the TB stays in layer 0 by construction.

### Layer 1 bound check

Layer-1 case arms (lines 174-189) all satisfy `value <= 16'd32767`:

```
2400, 16000, 30000, 32767, 24000, 16500, 11000, 7600,
5200, 3500, 2400, 1600, 1000, 600, 300, 100
```

The peak entry `16'd32767` is the Q15 ceiling. After the existing
`STATE_EXCITE_FINISH` `>>> 1` and saturating mix logic, the downstream Q18
saturation path is unchanged. PASS.

### `velocity_layer_q` clock-domain and stability

- Declared as `reg velocity_layer_q;` (line 64).
- Reset to `1'b0` on async `!sys_rst_n` (line 232).
- Updated only in `if (reset_strobe || (trigger_strobe && enable))` (line 267
  in the `(* posedge sys_clk or negedge sys_rst_n *)` block) via
  `velocity_layer_q <= (velocity_q15 >= VELOCITY_LAYER_THRESHOLD);` (line 273).
- Read only in `STATE_GAIN_FINISH` (line 332) inside the same `sys_clk` block:
  `mult_sample <= $signed({1'b0, excitation_rom(excite_index, velocity_layer_q), 1'b0});`.

No new clock domain, no CDC, no new port. The existing FSM has no path that
re-enters trigger latching while `excite_busy` is high, so `velocity_layer_q`
is provably stable through the 16-step excitation window. PASS.

### No port or external interface change

`phase1_reduced_voice` module ports remain identical to the pre-M7 baseline
(lines 3-26). `git diff --stat 303274e..e90a820 -- rtl/audio/phase0_audio_path.v`
returns no change. Existing 4-voice instantiation in `phase0_audio_path.v`
remains untouched. PASS.

### Threshold rationale

`localparam [15:0] VELOCITY_LAYER_THRESHOLD = 16'h6000;` is:
- Above reduced-voice TB default `16'h4000` -> layer 0 selected, TB bit-exact.
- Below production firmware default `0x7FFF` (`PHASE0_VOICE_DEFAULT_VELOCITY`)
  -> production audio uses layer 1 immediately on power-up.

Implementation report rationale matches the M6 scope and is consistent with
the source. PASS.

## Build / Fit / Timing evidence

Read directly from `quartus/phase0/output_files/piano_phase0_top.fit.summary`
(Last Write Time Sat May 23 23:09:23 2026, M7 compile):

| Metric | Pre-M7 baseline `4785c93` / `303274e` | M7 `e90a820` | Delta |
| --- | ---: | ---: | ---: |
| Total logic elements | 9,992 / 10,320 (97%) | 10,099 / 10,320 (98%) | +107 |
| Total combinational functions | 9,417 / 10,320 | 9,487 / 10,320 | +70 |
| Dedicated logic registers | 4,233 / 10,320 | 4,237 / 10,320 | +4 |
| Total memory bits | 86,016 / 423,936 | 86,016 / 423,936 | 0 |
| M9K (memory_bits / 5,376) | 16 | 16 | 0 |
| Embedded Multiplier 9-bit | 28 / 46 | 28 / 46 | 0 |
| PLLs | 1 / 2 | 1 / 2 | 0 |

Read from `quartus/phase0/output_files/piano_phase0_top.sta.summary`:

| Metric | Pre-M7 | M7 | Gate |
| --- | ---: | ---: | --- |
| Slow 1200mV 85C Setup `sys_clk_50m` | +2.914 ns | +2.846 ns | >= +2.5 ns PASS |
| Slow 1200mV 85C Hold `sys_clk_50m` | +0.405 ns | +0.429 ns | >= +0.3 ns PASS |
| Slow 1200mV 85C Setup `i2c_clk` | +17.573 ns | +17.304 ns | >> 0 PASS |
| Slow 1200mV 85C Setup `audio_bclk` | +316.385 ns | +315.510 ns | >> 0 PASS |
| All TNS (every clock, every corner) | 0 | 0 | =0 PASS |

The +4 register delta is exactly 4 voice instances x 1 `velocity_layer_q`
bit per voice. The +70 combinational delta is the wider `case ({layer, index})`
mux plus the per-trigger comparator. Setup slack on `sys_clk_50m` dropped
0.068 ns (placement noise for added logic in the per-voice cluster), still
+0.346 ns above the +2.5 ns gate.

Quartus full compile result from `.kiro/quartus_m7.log`:
- Overall: `Quartus II Full Compilation was successful. 0 errors, 16 warnings`.
- Analysis & Synthesis: `0 errors, 13 warnings`.
- TimeQuest: `0 errors, 0 warnings`. `Design is fully constrained for setup
  requirements. Design is fully constrained for hold requirements.`
- EDA Netlist Writer: `0 errors, 0 warnings`.

Warnings count matches the accepted baseline of 16. PASS.

## Firmware / ROM check

`fw/phase0/build/phase0.bin`: 3,724 bytes = **931 words**. Matches accepted
baseline. Firmware source is unchanged (no `git diff --stat ... -- fw/`). PASS.

## Simulation evidence

ModelSim 10.5 reduced-voice golden-sample TB log at
`.kiro/msim_voice_m7/vsim.log`:

```
# VOICE_TB_PASS first_nonzero_sample=106 freq=434.027778
# rms_100ms=267.429518 rms_500ms=27.166116 rms_3s=0.000000 peak=3952
# golden_samples=4096
# ** Note: $finish : rtl/audio/phase1_reduced_voice_tb.v(174)
# Errors: 0, Warnings: 0
```

- All 4096 golden samples matched bit-exact at TB velocity `0x4000` (layer 0
  selected by threshold, as designed).
- Frequency 434.03 Hz inside the 425-455 Hz acceptance band.
- `peak=3952` non-clipping, `rms_3s=0.0` confirms full decay.

This is the hard simulation gate the M7 design relies on: layer 0 cannot
regress because the threshold keeps the TB on layer 0, and the layer-0 ROM
arms are byte-equal to pre-M7. PASS.

Top-level happy/NACK TBs were not rerun for this slice. Justification: M7
changes only the per-voice excitation ROM behind a velocity-gated layer
register. It does not touch register addresses, command grammar, UART/NACK
parsing, or the four-voice instantiation. The reduced-voice TB exercises the
only changed code path, and layer-0 bit-exactness is provably preserved.

## Hardware evidence

Board programmed from `quartus/phase0/output_files/piano_phase0_top.sof`
built at `e90a820`. Programming over USB-Blaster [USB-0] reported SOF
checksum `0x0079905A` and succeeded.

### UART no-command profile

`reports/phase4_m7_no_command_uart.txt` tail snapshot:

```
T=00000003  A=00019526  W=001EF0F4
Y=20330010  U=00000003  B=00019526  C=001EF1B9
M=714E0010  K=00000000
Z=20330010  O=00000003  D=00019526  E=001EF2E2
V3=20330010  VT=00000003  VA=00019524  VV=001EF3BF
G=0000000E  H=00000005  J=00000002  L=00000002  N=00000002
P=0000000B  S3=00000002  ST=0000000B
Q=00000000  X=00000000  CC=003D0900
R=8018077F
```

- `K=0` and `X=0`: clean, no clipping and no parser errors.
- `Q=0`: no host commands accepted yet (no-command profile).
- `ST=0x0B`, `P=0x0B`, `CC=0x003D0900`: stable round-robin/firmware-cycle counters.
- Frozen telemetry tag set complete (V3/VT/VA/VV/S3/ST/CC all present).

PASS.

### UART valid-command profile

`reports/phase4_m7_command_uart_with_audio.txt` was captured during the
combined audio+UART run. The `scripts/phase4_m7_layer_compare.py` script
sent six valid `!N006Avvvv\r\n` commands at velocities split across the
threshold:

- 3 x `!N006A4000\r\n` (velocity `0x4000`, layer 0) followed by 3.5 s drain
- 3 x `!N006A7FFF\r\n` (velocity `0x7FFF`, layer 1) followed by 3.5 s drain

Q incremented by 6, X stayed 0, K stayed 0, ST advanced as expected for
forced steals. Mixed-velocity command profile from `reports/phase4_m7_command_uart.txt`
(separate run with mixed velocities including `0x4000`, `0x7FFF`, `0x2000`,
`0x6000`) showed Q+=5, G+=5, K=0, X=0.

PASS: valid M7 commands across the threshold introduced no new X errors and
no clipping.

### Audio capture

Two captures with ffmpeg dshow + Realtek input (`@device_cm_{33D9A762-...}`),
mono 48 kHz, 3.5mm jack direct connection (no acoustic path):

1. `reports/phase4_m7_layered_hammer.wav` (14 s) - default round-robin smoke
   plus mixed-velocity commands. Peak ~ -19.4 dBFS, RMS ~ -31 dBFS, no
   clipping observed.
2. `reports/phase4_m7_layer_compare.wav` (12 s) - dedicated 3+3 layer-0 then
   layer-1 burst sequence per `scripts/phase4_m7_layer_compare.py`.

Both captures show sustained audible output without clipping. K remained 0
across the entire capture window in the paired UART log.

#### Honest A/B distinguishability note

On a 3.5mm direct-jack capture, a clean A/B layer-0-vs-layer-1 spectral
contrast is somewhat masked because the firmware round-robin smoke loop
fires every ~0.1 s and overlaps the host-injected 3+3 burst. Per-second
attack/centroid analysis (`scripts/phase4_m7_audio_analyze.py`,
`scripts/phase4_m7_attack_analyze.py`) showed only modest centroid
differences (1199-1483 Hz vs the layer-0 windows; attack centroids
2100-3000 Hz across 114 detected onsets at ~0.1 s spacing).

The smoke loop is a firmware behavior independent of M7 RTL and is out of
M7 scope. The hard layer-1 RTL correctness gate is satisfied by:
- Source review: layer-1 entries within `16'd32767`, latched layer bit
  drives the same `excitation_rom` lookup used by layer 0.
- Simulation: golden-sample TB at `0x4000` (layer 0) bit-exact PASS, so
  pre-M7 behavior is preserved by construction.
- Hardware: `0x7FFF` (production default = layer 1) produces healthy
  non-clipping audio with K=0 across the run.

A cleaner audible A/B isolation would require disabling round-robin smoke,
which is a firmware change and out of M7 scope. Recording this as an
honest limitation of the audio-side evidence rather than a failed gate.

## Architecture guard

`rtl/audio/phase0_audio_path.v` continues to instantiate four physical
`phase1_reduced_voice` voices: `phase1_reduced_voice_inst`,
`phase1_reduced_voice1_inst`, `phase1_reduced_voice2_inst`,
`phase1_reduced_voice3_inst`. V3/VT/VA/VV/S3 telemetry tags remain present
in the no-command UART capture. `git diff --stat 303274e..e90a820 -- rtl/audio/phase0_audio_path.v`
is empty. PASS.

## Report-hygiene note

`reports/phase4_m7_velocity_layered_hammer_impl.md` header states
`Parent commit: 4785c93`, but `git log` shows the actual parent of
`e90a820` is `303274e` (the M6 scope-validation commit). The substantive
resource baseline claim is unchanged because the M6 validation commit
`303274e` is report-only relative to `4785c93`. This is the same
report-hygiene pattern recorded in M5 and M6 validations: cite the actual
parent or omit the line. Non-blocking.

## Final verdict

**PASS.** Phase 4 M7 velocity-layered hammer excitation is hardware-accepted
under this verifier run with the noted honest audio-side A/B limitation
caused by firmware round-robin smoke (out of M7 scope). All resource,
timing, simulation, file-scope, ASCII, architecture-guard, and UART/audio
gates pass. M7 commit `e90a820` may be promoted to the accepted Phase 4
baseline.

Suggested next step for the orchestrator if a cleaner audible layer-0
vs layer-1 distinction is desired on hardware: a separate firmware-only
slice could provide a quiet/no-smoke diagnostic mode similar in spirit to
the M3b parser quiet path, without changing M7 RTL. That is a follow-on
decision, not a Phase 4 M7 gate.
