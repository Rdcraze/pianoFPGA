# Phase 6 M6 Body-Mix Sweep Host Harness Implementation

Date: 2026-05-27
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-0eb95de4`
Branch: `codex/phase1c-uart-boundary-fix`
Parent commit: `297e85b` (M6 verifier handoff after M5 PASS)
Scope reference: `reports/phase6_m6_next_voice_quality_scope.md`
section 6 (M6 implementer task text).

## TL;DR

**PASS, host-tool-only.**

- Added `scripts/phase6_m6_body_mix_sweep.py`: a stdlib-plus-pyserial
  harness that drives the accepted M5 `!B<vvvv>` runtime knob across
  a configurable body_mix x pitch grid using only the existing
  M2/M5 UART command syntax (`!I1`, `!B`, `!F`, `!N`, `!I0`).
- `--self-check` PASS (`PHASE6_M6_BODY_MIX_SWEEP_PASS cells=14`).
  Validates command-stream generation, range rejection, pacing,
  command-count predictions for verifier P5M2 telemetry, sidecar
  schema round-trip, and grid parsers. Hardware/pyserial not
  required.
- `--plan` prints the full byte sequence (with visible `\r\n`
  framing), session duration, and expected device command counts.
- No RTL, QSF, firmware, obsolete-archive, or generated-output
  changes. No new UART syntax. ASCII-only on touched files. No
  edits to `scripts/phase6_m1_voice_bench.py` or
  `scripts/phase6_m1_voice_analyze.py`; the harness reuses
  `scripts/phase6_m1_voice_analyze.py` as-is via subprocess in
  `--analyze` mode by staging a v1->v2 sidecar copy.

## 1. Files

Two files only:

- `scripts/phase6_m6_body_mix_sweep.py` (new, ASCII-only).
- `reports/phase6_m6_body_mix_sweep_impl.md` (this file, new,
  ASCII-only).

LE/timing/RTL impact. None.

## 2. Behavior

### 2.1 Default grid

Mirrors `reports/phase6_m6_next_voice_quality_scope.md` section 6:

```
body_mix grid : [0x1000, 0x2000, 0x3000, 0x4000, 0x6000, 0x8000, 0xC000]
pitch grid    : [A4 loop_len 106, C5 loop_len 89]
velocity      : 0x7FFF
```

Total cells: 7 body_mix x 2 pitch = 14.

### 2.2 Per-cell pacing

Per cell:

1. If body_mix changed since the previous cell, send `!B<vvvv>\r\n`
   once and wait `body_mix_settle_s = 0.10 s` for the runtime
   register update to propagate.
2. Send `!F\r\n` (silences any prior ringing; in single-voice
   isolation mode this is also a hard reset of voice0 per accepted
   M1.2 reset-on-!F semantics).
3. Wait `settle_s = 1.0 s`.
4. Record send timestamp (relative to session start) into the
   sidecar.
5. Send `!N<loop_len><velocity>\r\n` to strike the cell.
6. Wait `capture_s = 4.0 s` for analog audio capture.
7. Wait `pause_s = 1.0 s` before the next cell.

Pre/post:

- Pre, when `--single-voice-isolate` is on (default):
  `!I1\r\n`, then 0.10 s for the isolation-mode flag to latch.
- Post: trailing `!F\r\n` to silence the last ring; then, if
  isolation was enabled, `!I0\r\n` to leave isolation mode.

### 2.3 Configurability

- `--body-mix-grid 0x1000,0x2000,...` overrides the default body_mix
  list. Each token is a 16-bit value (hex with `0x` prefix or
  decimal).
- `--pitch-grid` overrides the default pitch list. Each token is
  either `NAME:LOOPLEN` (e.g. `A4:106`) or a bare loop_len. Range
  enforced to 32..127.
- `--velocity` (decimal or hex) overrides 0x7FFF; range 0..0x7FFF.
- `--no-isolate` skips the `!I1`/`!I0` framing (e.g. for sanity
  baselines without isolation).
- `--settle-s`, `--capture-s`, `--pause-s`, `--body-mix-settle-s`
  override the defaults if needed.

### 2.4 Sidecar schema (v1)

The v1 sweep sidecar mirrors the per-cell shape of the M4-era v2
voice-bench sidecar: each cell has a `send_t_session_s` that is a
list of relative session times. The current sweep emits exactly
one strike per cell (length-1 list); a future repeated-capture
extension can emit K>1 timestamps without changing the shape.

```
{
  "schema": "phase6_m6_body_mix_sweep.v1",
  "port": "...",
  "baud": 115200,
  "settle_s": 1.0,
  "capture_s": 4.0,
  "pause_s": 1.0,
  "body_mix_settle_s": 0.1,
  "single_voice_isolate": true,
  "session_start_unix": 1700000000.0,
  "body_mix_grid": ["0x1000", ..., "0xC000"],
  "pitch_grid": [{"loop_len": 106, "pitch_name": "A4"}, ...],
  "velocity_hex": "0x7FFF",
  "pre_commands":  [{"command": "!I1", "send_t_session_s": ...},
                    {"command": "!B1000", "send_t_session_s": ...}, ...],
  "cells": [
    {"index": 0, "body_mix": 4096, "body_mix_hex": "0x1000",
     "loop_len": 106, "velocity": 32767, "pitch_name": "A4",
     "command": "!N006A7FFF", "send_t_session_s": [3.234]},
    ...
  ],
  "post_commands": [{"command": "!F", ...}, {"command": "!I0", ...}]
}
```

### 2.5 Analyze mode

`--analyze --wav PATH --sidecar PATH [--out CSV] [--out-md MD]`
invokes `scripts/phase6_m1_voice_analyze.py` over the captured
WAV. Implementation detail:

- The analyzer accepts schemas `phase6_m1_voice_bench.v1` and
  `phase6_m1_voice_bench.v2`. Our v1 sweep sidecar carries a
  compatible per-cell shape but a different schema string, so the
  harness writes a temporary staged copy with
  `schema = phase6_m1_voice_bench.v2` and `repeats = 1` next to
  the original sidecar, runs the analyzer against it, and removes
  the staged file on success.
- After the analyzer writes its CSV, the harness rewrites that
  CSV in place to splice `body_mix_hex` in as the second column.
  This keeps the resulting row format aligned with section 6 of
  the M6 scope:
  ```
  index,body_mix_hex,pitch_name,loop_len,velocity_hex,command,
  repeats,snr_db,peak_abs,peak_dbfs,rms_100ms_dbfs,rms_500ms_dbfs,
  rms_3s_dbfs,attack_ms,decay_db_per_s,spectral_centroid_hz,
  clipping_count,silence_after_ms
  ```
- The accepted M1 analyzer's `silence_after_ms` and `clipping_count`
  satisfy the scope's "silence_after_ms" and "clipping_count"
  fields. The analyzer's `snr_db` (per-cell strike-vs-noise ratio
  computed from a 0.4 s pre-strike window) acts as the
  `chain_noise_floor_dbfs` / "above-or-below-noise" classifier:
  cells with low or near-zero `snr_db` are exactly the cells
  whose strike RMS is at or below the chain noise floor and which
  the M6 scope says must be flagged rather than used for
  FFT-band claims. We did not introduce a new
  `classified_above_or_below_noise` boolean column to avoid
  editing the analyzer; the equivalent classification is a
  threshold on `snr_db` that the verifier can apply directly to
  the CSV.

## 3. Validation

### 3.1 --self-check (host-only, no hardware)

Command:

```
python scripts/phase6_m6_body_mix_sweep.py --self-check
```

Output (verbatim):

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

Exit code: 0.

### 3.2 --plan (host-only, no hardware)

Command:

```
python scripts/phase6_m6_body_mix_sweep.py --plan
```

Output (verbatim):

```
Phase 6 M6 body_mix sweep: 7 body_mix x 2 pitch = 14 cells, total ~84.9 s (isolation_mode=ON)
  pacing: body_mix_settle 0.10s, per-cell settle 1.0s, capture 4.0s, pause 1.0s
  expected device command counts: !I1=1 !B=7 !F=15 !N=14 !I0=1 (total 38 valid; X expected 0)

pre:  !I1\r\n  (enable single-voice isolation mode)

idx  body_mix  pitch    loop_len  velocity  byte_sequence
---  --------  -------  --------  --------  -------------------
        0x1000                                !B1000\r\n
  0  0x1000    A4            106  0x7fff    !F\r\n then !N006A7FFF\r\n
  1  0x1000    C5             89  0x7fff    !F\r\n then !N00597FFF\r\n
        0x2000                                !B2000\r\n
  2  0x2000    A4            106  0x7fff    !F\r\n then !N006A7FFF\r\n
  3  0x2000    C5             89  0x7fff    !F\r\n then !N00597FFF\r\n
        0x3000                                !B3000\r\n
  4  0x3000    A4            106  0x7fff    !F\r\n then !N006A7FFF\r\n
  5  0x3000    C5             89  0x7fff    !F\r\n then !N00597FFF\r\n
        0x4000                                !B4000\r\n
  6  0x4000    A4            106  0x7fff    !F\r\n then !N006A7FFF\r\n
  7  0x4000    C5             89  0x7fff    !F\r\n then !N00597FFF\r\n
        0x6000                                !B6000\r\n
  8  0x6000    A4            106  0x7fff    !F\r\n then !N006A7FFF\r\n
  9  0x6000    C5             89  0x7fff    !F\r\n then !N00597FFF\r\n
        0x8000                                !B8000\r\n
 10  0x8000    A4            106  0x7fff    !F\r\n then !N006A7FFF\r\n
 11  0x8000    C5             89  0x7fff    !F\r\n then !N00597FFF\r\n
        0xC000                                !BC000\r\n
 12  0xC000    A4            106  0x7fff    !F\r\n then !N006A7FFF\r\n
 13  0xC000    C5             89  0x7fff    !F\r\n then !N00597FFF\r\n

post: !F\r\n  (final release)
post: !I0\r\n  (disable isolation mode)
```

Exit code: 0.

### 3.3 Expected device telemetry behavior (P5M2)

Verifier should expect, on the live device, after a full default
session with `--single-voice-isolate`:

- Q advances by exactly **38** (one `!I1` + 7 `!B` + 15 `!F` +
  14 `!N` + one `!I0`).
- X remains **0** (the harness emits no malformed commands).

For `--no-isolate`, Q advances by exactly **36** (no `!I1`/`!I0`).

These counts are exposed by `--plan` and validated in `--self-check`
so the orchestrator/verifier P5M2 telemetry gate from M6 verifier
section 7 of the scope can be checked deterministically.

## 4. Expected runtime

Default session, with isolation enabled:

- Per cell: `settle (1.0s) + capture (4.0s) + pause (1.0s) = 6.0 s`.
- Per body_mix row: `body_mix_settle (0.10s) + 2 cells x 6.0s =
  12.10 s`.
- 7 body_mix rows: 84.7 s.
- Plus `PRE_AFTER_I1 (0.10s) + POST_BEFORE_I0 (0.05s) = 0.15 s`.
- Total: about **84.85 s** (matches `--plan` output).

Add a fixed 3.0 s pre-roll inside `--run` for the operator to start
analog audio capture and record the audio start unix time.

## 5. Pre- vs post-isolator acceptance framing

This harness produces structured evidence that is useful in both
regimes. The interpretation rule is the same as the M6 scope:

### 5.1 Pre-isolator (chain still ground-loop limited)

Per `reports/phase6_chain_noise_debug.md` and the M5/M5.1 history,
the current capture chain is hum/ground-loop limited with median
floor ~ -78 to -85 dBFS. In this regime:

- Cells whose strike RMS is within ~3 dB of the chain noise floor
  cannot support precise FFT-band claims. The analyzer's
  per-cell `snr_db` (computed from a 0.4 s pre-strike window) is
  the right operational classifier: cells with low or near-zero
  `snr_db` should be reported but not used for FFT-band
  comparisons.
- Body_mix steps of >= 0x2000 (4096 units) typically produce
  >6 dB of intra-run warmth swing, which is comfortably above
  the chain noise variance of ~1-3 dB across cells. The user can
  pick a preferred warmth setpoint subjectively.
- The harness is therefore acceptance-ready as a subjective tool
  pre-isolator. Objective FFT-band acceptance is deferred.

### 5.2 Post-isolator (after M5.1 acceptance)

When the verifier accepts the user's passive 3.5 mm transformer
isolator under `task-cbbeea61` / M5.1 protocol, the same harness
runs unchanged:

- Reuse `--single-voice-isolate` and the default grid.
- For coherent-averaged objective A/B, a future repeated-capture
  M6.x slice can extend the harness to emit K>1 timestamps per
  cell and the existing analyzer `--coherent-average` flag will
  produce the +10*log10(K) dB SNR gain. The current v1 sidecar
  is already shape-compatible with that extension (see 2.4).
- Acceptance gate after M5.1 (per scope section 6 verifier task
  text): body_mix differences should produce monotonically
  increasing 1-3 kHz band energy as body_mix grows from 0x1000
  to 0x8000, with the trend at least partially visible above the
  chain noise.

## 6. Scope guards (re-confirm)

- No RTL change.
- No QSF, SDC, PLL, firmware, or obsolete-archive change.
- No new UART command syntax. The harness only emits `!I1`,
  `!I0`, `!B<vvvv>`, `!F`, and `!N<loop><vel>`, all already
  accepted by M2/M5.
- `scripts/phase6_m1_voice_bench.py` and
  `scripts/phase6_m1_voice_analyze.py` are not modified. The
  harness reuses the analyzer via subprocess only.
- ASCII-only on the script and this report.
- Verifier-protected untracked files (`.kiro/`, prior-phase UART
  captures, `reports/phase6_m5_hardware_uart.txt`, etc.) are not
  touched.
- Hardware capture/programming was not attempted; live capture
  belongs to verifier per project discipline.

## 7. ASCII check

```
scripts/phase6_m6_body_mix_sweep.py            non_ascii=0
reports/phase6_m6_body_mix_sweep_impl.md       non_ascii=0
```

## 8. Residual risks

- The analyzer's CSV does not currently expose a literal
  `chain_noise_floor_dbfs` column; the equivalent information is
  in `snr_db` (strike RMS minus pre-strike noise RMS). If
  verifier needs the literal column name from the M6 scope, that
  is the smallest possible analyzer extension and can be added
  in a focused follow-up without changing the bench/analyze
  contract.
- Analyzer interop relies on staging the M6 sidecar with the v2
  schema string. If a future analyzer change rejects unknown
  fields (`body_mix`, `body_mix_hex`, `pitch_grid`,
  `body_mix_grid`, etc.) instead of ignoring them, the staged
  copy could fail; today the analyzer reads only `cells` and
  `session_start_unix` so this is safe.
- Pre-isolator FFT-band claims are explicitly out of scope; the
  harness honestly carries the SNR signal forward so verifier
  can suppress unreliable cells.

## 9. Hardware deferral

Per project discipline, implementer-side live hardware capture
remains stubbed/declined. The verifier is the owner of:

- Programming the accepted M5 SOF
  (`SOF SHA-256 CAB259BC697ABB5F76AD48120AE4CD65AB1FD4311FC9AEA59F620868E3F3D7F5`,
  programmer checksum `0x005F102E`) or the latest accepted
  variant if newer.
- Running `scripts/phase6_m6_body_mix_sweep.py --run`,
  capturing 16-bit PCM analog audio over the full session,
  recording the audio start unix time, and supplying the WAV
  + sidecar to `--analyze` (or to the analyzer directly).
- Asserting the P5M2 Q/X command-count gate from section 3.3.
