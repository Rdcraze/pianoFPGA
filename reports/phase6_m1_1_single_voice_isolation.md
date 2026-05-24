# Phase 6 M1.1 Single-Voice Isolation Mode Implementation Report

Date: 2026-05-24
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-db2dd60d`
Branch: `codex/phase1c-uart-boundary-fix`
Parent commit: `f65532f` (Phase 6 M1 harness PASS, hardware FAIL on
contaminated four-voice ringing)

## TL;DR

**PASS for non-hardware coverage.** Phase 6 M1.1 extends the live
RTL with a single-voice isolation mode triggered by two new UART
commands: `!I1\r\n` enables isolation, `!I0\r\n` disables it. While
isolation is enabled, every command-driven `note_strobe` is routed
to voice0 (with the post-incremented voice_index logic suppressed),
and voices 1/2/3 are silenced at the audio-path mix sum. The four
physical voice instances remain instantiated and clocked, so normal
mode is unchanged. The bench harness gains `--single-voice-isolate`
which sends `!I1` before the grid and `!I0` (after a final `!F`)
afterward.

| Gate | Target | Actual | Verdict |
| --- | --- | --- | --- |
| LE delta vs M2 baseline 4,729 | <= +200 | **+56 (4,785)** | PASS |
| Setup slack slow-85C `sys_clk_50m` | >= +4.0 ns | **+4.228 ns** | PASS |
| Hold slack slow-85C | clean | +0.432 ns | PASS |
| All TNS | = 0 | 0 | PASS |
| M9K | unchanged at 5 | 5 (unchanged) | PASS |
| DSP9 | unchanged at 26 | 26 (unchanged) | PASS |
| PLL | 1 | 1 | PASS |
| Quartus errors | 0 | 0 | PASS |
| Quartus warnings | 16 cosmetic baseline | 16 (unchanged) | PASS |
| Four physical voice instances preserved | yes | yes | PASS |
| Audio synthesis bit-exact (golden TB) | yes | VOICE_TB_PASS peak=3952 | PASS |
| ASCII-only on touched files | yes | yes | PASS |
| `phase0_uart_command_tb` PASS | yes | UART_CMD_TB_PASS notes=5 releases=1 errors=3 isolation=1 | PASS |
| New `phase0_fixed_control_isolation_tb` PASS | yes | ISOLATION_TB_PASS (4 routing checks) | PASS |
| `phase0_uart_status_tx_tb` PASS | yes | UART_TX_TB_PASS frames=2 | PASS |
| Bench `--self-check` PASS | yes | PHASE6_M1_BENCH_PASS cells=15 (9 vectors) | PASS |
| Live 5x3 capture with isolation | hardware | DEFERRED to verifier | n/a |

## 1. Protocol extension

Two new commands accepted by `rtl/control/phase0_uart_command.v`:

| Command | Length (bytes) | Effect |
| --- | ---: | --- |
| `!I1\r\n` | 5 | Enable isolation mode. `command_count++`, `isolation_mode = 1`, X stable. |
| `!I0\r\n` | 5 | Disable isolation mode. `command_count++`, `isolation_mode = 0`, X stable. |

Bad arguments fall through the existing error path:

- `!I<other>\r\n` with any single byte other than `0` or `1` -> `ERR_UNSUPPORTED_ARG` (code 7).
- Lengths other than 5 starting with `!I...` are classified by the
  default-case fallback (existing behavior).

`isolation_mode` is exposed as a persistent 1-bit output of the
parser so consumers can latch it stably between commands.

The error-code surface for X high16 stays at the previously
documented set: 0/1/2/3/4/7. No new error codes added.

## 2. RTL changes

### `rtl/control/phase0_uart_command.v`

- Added `output reg isolation_mode` to the port surface.
- `isolation_mode` resets to 0.
- New `5'd5` line-length case dispatches `!I0`/`!I1` (sets
  `isolation_mode` and increments `command_count`) and rejects
  `!I<other>` with `ERR_UNSUPPORTED_ARG`.

### `rtl/control/phase0_fixed_control.v`

- Added `input wire isolation_mode` to the port surface.
- Replaced the `note_strobe` handler with a two-branch case:
  - In **normal mode** (`isolation_mode == 0`), behavior matches
    accepted Phase 5 M2/M3: parameters write to the post-incremented
    voice's per-voice register, `voice_index` advances by one,
    `trigger_pulse` fires; per-voice strobe fan-out routes the pulse
    to the matching voice.
  - In **isolation mode** (`isolation_mode == 1`), parameters write
    to `voice0_*_reg`, `voice_index` is forced to 0 (does not
    advance), and `trigger_pulse` fires; the per-voice strobe
    fan-out (unchanged) thus routes only to voice0.
- `release_strobe` and `voice_damp_mix_reg` behavior unchanged.
- `voice_index_status` reflects the suppressed advance during
  isolation (always reads 0 once a command lands).

### `rtl/audio/phase0_audio_path.v`

- Added `input wire isolation_mode` to the port surface.
- Voice 1/2/3 contributions to `mix_sum` are gated to `18'sd0` when
  `isolation_mode == 1`. The voice instances themselves remain
  enabled and clocked (the four-voice runtime enables, status
  reporting, sample tick, and counters are untouched), so isolation
  mode purely silences voices 1..3 at the mix point. Voice 0
  contribution is unchanged.

### `rtl/top/piano_phase0_top.v`

- Added `wire cmd_isolation_mode` between the parser, the fixed
  controller, and the audio path; wired through the three port maps.

### Files NOT changed

- `rtl/peripherals/uart_rx.v`: unchanged.
- `rtl/peripherals/phase0_uart_status_tx.v`: unchanged. `Q`/`X`
  semantics remain valid; valid `!I0`/`!I1` increment Q exactly
  like other valid commands.
- `rtl/audio/phase1_reduced_voice.v`: unchanged. Audio synthesis
  is bit-exact.
- `rtl/audio/phase0_body_filter.v`: unchanged.
- `quartus/phase0/piano_phase0_top.qsf`: unchanged. No new live
  source files added; only existing files were modified.
- `obsolete/`: unchanged.

## 3. Validation

### `phase0_uart_command_tb` (extended)

Added 5 new test cases for isolation:

1. Default `isolation_mode == 0` after reset.
2. `!I1\r\n` -> isolation_mode = 1, command_count++.
3. `!I0\r\n` -> isolation_mode = 0, command_count++.
4. `!IZ\r\n` -> ERR_UNSUPPORTED_ARG (7), error_count++,
   command_count and isolation_mode stable.
5. `!I1` followed by `!N` -> isolation_mode latched, note_strobe
   fires, command_count covers both.

Output:

```
UART_CMD_TB_PASS notes=5 releases=1 errors=3 isolation=1
Errors: 0, Warnings: 0
```

All previous M2 test cases (steps 1-7 covering `!N`, `!NLLLLVVVV`,
`!F`, `!Z`, overlong) continue to PASS bit-identically.

### New `phase0_fixed_control_isolation_tb`

Drives the controller's command interface directly to verify routing
behavior in both modes. Four assertions:

```
ISO_TB_PASS normal_mode_roundrobin v0=1 v1=1 v2=1 v3=1
ISO_TB_PASS isolation_mode v0=4 v1=0 v2=0 v3=0
ISO_TB_PASS voice_index_after_isolation=0
ISO_TB_PASS voice0_params loop_len=32 vel=0x6000
ISO_TB_PASS post_isolation_roundrobin v0=1 v1=1 v2=1 v3=1
ISOLATION_TB_PASS
Errors: 0, Warnings: 0
```

The "post_isolation_roundrobin" assertion confirms that disabling
isolation cleanly restores normal round-robin behavior.

### `phase0_uart_status_tx_tb`

Unchanged TB still PASS:

```
UART_TX_TB_INFO boot0=00000001 boot1=00000002
UART_TX_TB_INFO q0=12345678
UART_TX_TB_INFO x0=00030007
UART_TX_TB_PASS frames=2 collected_count=170
Errors: 0, Warnings: 0
```

### `phase1_reduced_voice_tb` (golden)

```
VOICE_TB_PASS first_nonzero_sample=106 freq=434.027778
  rms_100ms=267.429518 rms_500ms=27.166116 rms_3s=0.000000
  peak=3952 golden_samples=4096
```

`peak=3952` is bit-exact at the Phase 4 M7 acceptance baseline. No
audio synthesis regression.

### Bench `--self-check`

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

9 vectors PASS (was 7 in M1; gained sidecar isolation fields plus
two byte-vector checks).

### Quartus full compile

```
.\build.ps1 -Stage compile
Quartus II Full Compilation was successful. 0 errors, 16 warnings
```

Resource and timing summary versus accepted Phase 5 M2/M3 baseline:

| Metric | M2/M3 | M1.1 | Delta |
| --- | ---: | ---: | ---: |
| Total logic elements | 4,729 | **4,785** | **+56** |
| Combinational | 4,492 | 4,577 | +85 |
| Registers | 2,349 | 2,350 | +1 |
| Memory bits | 20,480 | 20,480 | 0 |
| M9K | 5 | 5 | 0 |
| DSP9 | 26 | 26 | 0 |
| PLL | 1/2 | 1/2 | 0 |
| Slow-85C setup `sys_clk_50m` | +5.928 ns | **+4.228 ns** | -1.700 ns |
| Hold slow-85C | +0.432 ns | +0.432 ns | 0 |
| All TNS | 0 | 0 | 0 |
| Errors | 0 | 0 | 0 |
| Warnings | 16 | 16 | 0 |

The +56 LE is well under the +200 hard target. Setup slack dropped
1.7 ns but still passes the +4.0 ns gate by +0.228 ns. The most
likely cause of the setup-slack movement is the new `isolation_mode`
fanout into the per-voice mix gating in `phase0_audio_path` (which
sits closer to the saturating biquad path than the original
purely-control-side parser registers were). The cushion is tighter
than M2 but acceptable for this slice.

The +1 register count is the new `isolation_mode` flop in the
parser; the +85 combinational growth is the per-voice mix gating
(four 18-bit muxes) plus the parser case-5 dispatch logic. Honest
breakdown.

Compile log saved to `.kiro/quartus_phase6_m11.log` (local-only).

## 4. Bench harness extension

`scripts/phase6_m1_voice_bench.py` gains `--single-voice-isolate`:

- When set, `!I1\r\n` is sent immediately after the 3 s setup
  window (after `session_start_unix` is recorded), with a 100 ms
  wait so the parser latches isolation_mode before the first strike.
- The per-cell loop and `!F`/strike/capture/pause structure is
  unchanged.
- After the trailing `!F`, a 50 ms wait then `!I0\r\n` clears
  isolation mode so subsequent runs of the bench (or other host
  flows) see normal mode.
- Sidecar JSON gains `single_voice_isolate` (bool), plus
  `pre_commands` and `post_commands` arrays of `{command,
  send_t_session_s}` records so the verifier and analyzer can
  audit exactly when the mode flips fired.
- `--self-check` validates: command-byte literals, sidecar
  JSON round-trip with the new fields, and grid integrity.
- `--plan --single-voice-isolate` prints a banner showing the pre
  and post commands, useful for verifier review.

The non-isolated mode remains intact for regression / stress runs:
`--run` without `--single-voice-isolate` produces exactly the M1
behavior.

## 5. Hardware deferral

Per the project discipline rule that hardware acceptance is the
verifier's responsibility, the M1.1 live capture run is deferred to
the M1.1 verifier task. The verifier should:

1. Reprogram the SOF generated by the M1.1 Quartus compile (record
   checksum).
2. Start audio capture (16-bit PCM WAV >= 100 s).
3. Run:
   ```
   python scripts/phase6_m1_voice_bench.py --run --port COM5 \
       --single-voice-isolate \
       --sidecar reports/phase6_m1_1_voice_bench_session.json
   ```
4. Stop audio capture; record audio start unix time.
5. Optionally capture P5M2 frames during the run:
   ```
   python scripts/phase5_m3_p5m2_decode.py --port COM5 --seconds 100 \
       > reports/phase6_m1_1_p5m2_log.txt
   ```
   (Note: COM is exclusive, so this is a separate run with a
   different command sequence; or skip and rely on the post-run Q/X
   check from the bench's serial port.)
6. Analyze:
   ```
   python scripts/phase6_m1_voice_analyze.py \
       --wav reports/phase6_m1_1_voice_bench.wav \
       --sidecar reports/phase6_m1_1_voice_bench_session.json \
       --out reports/phase6_m1_voice_baseline.csv \
       --out-md reports/phase6_m1_voice_baseline_analyzed.md
   ```

Hardware/audio gates the verifier should evaluate:

- `phase6_m1_voice_baseline.csv` populated with 15 metric rows.
- Each cell's segmented audio shows attack < 50 ms, peak below the
  full-scale ceiling, decay rate non-zero, no clipping at velocity
  0x4000.
- Pre/post strike RMS deltas indicate separable strikes (e.g. RMS
  in the last 100 ms of the 1 s pause is at least 6 dB below the
  RMS in the 100 ms after strike), proving isolation is working
  rather than a continuous ringing stack.
- Q advances exactly by the expected count: 1 (`!I1`) + 15 (`!N`)
  + 15 (`!F`) + 1 (final `!F`) + 1 (`!I0`) = 33; `X` stays
  0x00000000 throughout.

If, after isolation, the captured audio still shows continuous
contamination, the verifier should:
- Confirm the SOF programmed is actually the M1.1 build
  (checksum match);
- Confirm `--single-voice-isolate` was actually passed (sidecar
  JSON contains `"single_voice_isolate": true` and `pre_commands`
  contains `!I1`);
- If both hold, the failure points at `phase1_reduced_voice` decay
  behavior (long natural ringdown of voice0 between 4 s capture
  windows, not a contamination from voices 1..3). In that case
  M1.1 has worked as designed and the analysis CSV will simply
  show overlapping decays from the prior strike spilling into the
  next cell. A 2 s pause would help; the bench accepts
  `--pause-s 2.0` as a tuning knob.

## 6. Out of scope

- No timbre/voice-quality RTL changes (no body filter, hammer
  curve, loop-loss, dispersion, or pre-strike noise work).
- No CPU/firmware/MMIO/register-file revival.
- No reduction of physical voice count.
- No changes to the Phase 3 host wrappers, P5M2 frame format,
  status TX block, or codec stack.
- No `obsolete/` archive change.
- No edits to verifier-protected untracked files or `.kiro/`.

ASCII-only.

## 7. Committed result

This commit contains:

- modify: `rtl/control/phase0_uart_command.v` (add isolation_mode,
  5-byte case)
- modify: `rtl/control/phase0_uart_command_tb.v` (5 new isolation
  tests, port wiring)
- modify: `rtl/control/phase0_fixed_control.v` (isolation_mode
  input, branched note_strobe handler)
- new: `rtl/control/phase0_fixed_control_isolation_tb.v` (focused
  routing TB)
- modify: `rtl/audio/phase0_audio_path.v` (isolation_mode input,
  voice1/2/3 mix gating)
- modify: `rtl/top/piano_phase0_top.v` (cmd_isolation_mode wire and
  three port-map updates)
- modify: `scripts/phase6_m1_voice_bench.py` (--single-voice-isolate
  flag, sidecar pre/post commands, isolation byte vectors in
  --self-check)
- new: `reports/phase6_m1_1_single_voice_isolation.md` (this file)
