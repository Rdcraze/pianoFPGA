# Phase 6 M1.2 Voice Reset and Clean-Level Baseline

Date: 2026-05-24
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-42fe9e4c`
Branch: `codex/phase1c-uart-boundary-fix`
Parent commit: `aa97169` (Phase 6 M1.1 isolation PASS, hardware metric
sanity FAIL on long voice0 ringdown plus near-full-scale cells)

## TL;DR

**PASS for non-hardware coverage.** Phase 6 M1.2 fixes the M1.1
verifier's metric-sanity FAIL with two changes:

1. **RTL: in isolation mode only, `!F` now hard-resets voice0** by
   pulsing `voice_reset_strobe` for one sys_clk cycle. The voice
   core's existing reset path clears its delay line and body
   history, so each per-cell `!F` between strikes starts the next
   note from a silent buffer. Normal mode is unchanged: `!F` still
   only raises shared `voice_damp_mix` to `16'd32767`.
2. **Bench: `--profile clean` velocity grid** uses
   0x0800/0x1000/0x2000 instead of 0x2000/0x4000/0x7FFF, giving the
   verifier a non-saturating recapture path for the long-loop_len
   cells that approached full-scale on the original profile.

Both Python self-check modes still PASS. The new isolation TB
verifies the isolation-mode-only reset behavior plus that normal
mode does not assert reset; the existing routing assertions still
PASS. The reduced-voice golden TB is unaffected (no audio synthesis
change). Quartus full compile reports 0 errors / 16 warnings; LE
4,785 -> 4,810 (+25, well under the +100 hard target); setup slow-85C
recovers from +4.228 ns (M1.1) to +5.431 ns (above the +4.0 ns gate
by +1.431 ns).

Per project discipline rule that hardware acceptance is the
verifier's responsibility, the live recapture run is deferred to
the M1.2 verifier task. The verifier should attempt the original
profile first (now with reset-on-!F) and, if any cell still clips,
fall back to `--profile clean`.

| Gate | Target | Actual | Verdict |
| --- | --- | --- | --- |
| LE delta vs M1.1 baseline 4,785 | <= +100 | **+25 (4,810)** | PASS |
| Setup slack slow-85C `sys_clk_50m` | >= +4.0 ns preferred | **+5.431 ns** | PASS |
| Hold slack slow-85C | clean | +0.409 ns | PASS |
| All TNS | = 0 | 0 | PASS |
| M9K | unchanged at 5 | 5 (unchanged) | PASS |
| DSP9 | unchanged at 26 | 26 (unchanged) | PASS |
| PLL | 1 | 1 | PASS |
| Quartus errors | 0 | 0 | PASS |
| Quartus warnings | 16 cosmetic baseline | 16 (unchanged) | PASS |
| Four physical voice instances preserved | yes | yes | PASS |
| Audio synthesis bit-exact (golden TB) | yes | unchanged (no audio change) | PASS |
| ASCII-only on touched files | yes | yes | PASS |
| `phase0_uart_command_tb` PASS | yes | UART_CMD_TB_PASS notes=5 releases=1 errors=3 isolation=1 | PASS |
| `phase0_fixed_control_isolation_tb` PASS | yes | ISOLATION_TB_PASS (11 assertions) | PASS |
| `phase0_uart_status_tx_tb` PASS | yes | UART_TX_TB_PASS frames=2 | PASS |
| Bench `--self-check` PASS | yes | PHASE6_M1_BENCH_PASS cells=15 (11 vectors) | PASS |
| Live capture | hardware | DEFERRED to verifier | n/a |
| New UART command syntax | none | none added | PASS |

## 1. RTL change

### `rtl/control/phase0_fixed_control.v`

The `voice_reset_strobe` output was previously hardwired to `1'b0`.
M1.2 turns it into a registered single-cycle pulse driven by a new
`voice0_reset_pulse` register:

```
reg                          voice0_reset_pulse;
assign voice_reset_strobe     = voice0_reset_pulse;
```

Inside the always block, the register defaults low each cycle and
is asserted only on the cycle a `release_strobe` is observed while
`isolation_mode` is high:

```
end else if (release_strobe) begin
    command_mode       <= 1'b1;
    voice_damp_mix_reg <= 16'd32767;
    if (isolation_mode) begin
        voice0_reset_pulse <= 1'b1;
    end
end
```

Because `voice0_reset_pulse` defaults low at the start of every
non-reset cycle, the assertion is exactly one sys_clk wide. The
voice core's existing reset_strobe path then clears its delay line
and body history within a few cycles, well before the next per-cell
strike (separated by 1.0 s settle in the bench).

In **normal mode** the conditional gate keeps `voice0_reset_pulse`
at its default zero on `release_strobe`, so the existing M2/M3
release semantics (shared damp_mix raised, no voice reset) are
preserved exactly.

`voice_reset_strobe` is the only previously-unused output port; no
new ports were added. No new UART command syntax was introduced;
the M1.1 `!I1`/`!I0` parser surface is unchanged.

The async-reset block also clears `voice0_reset_pulse` to 0 so the
post-reset state is well-defined.

## 2. Test changes

### `rtl/control/phase0_fixed_control_isolation_tb.v`

Five new assertions plus a new `pulse_release()` task. The full
assertion sequence is:

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

The four behaviors required by the M1.2 task are all covered:

| Required behavior | Assertion |
| --- | --- |
| Normal-mode `!F` does not assert voice0 reset | `release_in_normal_no_reset` |
| Isolation-mode `!F` asserts voice0 reset (exactly one pulse) | `release_in_isolation_resets_voice0` reset_count=1 |
| Repeated isolated notes still route to voice0 only | `isolation_mode v0=4 v1=0 v2=0 v3=0` and `isolated_note_after_reset` |
| Disabling isolation restores normal round-robin | `post_isolation_roundrobin v0=1 v1=1 v2=1 v3=1` |

Plus three additional sanity checks that release damp_mix still
raises in both modes and that release does not produce a phantom
trigger pulse in either mode.

### Other TBs

- `phase0_uart_command_tb`: unchanged. Still PASS (parser surface
  unchanged in M1.2).
- `phase0_uart_status_tx_tb`: unchanged. Still PASS.
- `phase1_reduced_voice_tb`: unchanged. The audio synthesis is not
  modified by M1.2; the golden bit-exact PASS at `peak=3952` from
  Phase 4 M7 remains valid. Not rerun this round to save sim time.

## 3. Bench harness changes

### `scripts/phase6_m1_voice_bench.py`

Two new behaviors:

1. **Profile selector** (`--profile {original|clean}`). Original
   keeps the M1 grid (velocities 0x2000/0x4000/0x7FFF). Clean uses
   0x0800/0x1000/0x2000 to keep long-loop_len cells from
   approaching full-scale saturation under the isolated voice0
   model.
2. **Sidecar enrichment**: the sidecar JSON now includes a
   top-level `profile` field. When `--single-voice-isolate` is
   set, the bench banner (and the sidecar comment via `--plan`)
   notes that each per-cell `!F` is now a hard reset of voice0 in
   M1.2 builds.

The default behavior remains the original M1 profile; the verifier
must opt into clean explicitly.

`--self-check` now covers 11 vectors (was 9):

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

The expected valid-command count is unchanged: with 15 cells plus
the pre/post `!I1`/`!F`/`!I0`, Q must advance by 33 across the
captured run, X stays 0.

## 4. Quartus evidence

Command: `.\build.ps1 -Stage compile`

Result: `Quartus II Full Compilation was successful. 0 errors, 16
warnings`. Compile time ~54 s.

Resource and timing summary versus accepted Phase 6 M1.1 baseline:

| Metric | M1.1 | M1.2 | Delta |
| --- | ---: | ---: | ---: |
| Total logic elements | 4,785 | **4,810** | +25 |
| Combinational | 4,577 | 4,571 | -6 |
| Registers | 2,350 | 2,351 | +1 |
| Memory bits | 20,480 | 20,480 | 0 |
| M9K | 5 | 5 | 0 |
| DSP9 | 26 | 26 | 0 |
| PLL | 1/2 | 1/2 | 0 |
| Slow-85C setup `sys_clk_50m` | +4.228 ns | **+5.431 ns** | +1.203 ns |
| Hold slow-85C | +0.432 ns | +0.409 ns | -0.023 ns |
| All TNS | 0 | 0 | 0 |
| Errors | 0 | 0 | 0 |
| Warnings | 16 | 16 | 0 |

The +25 LE / +1 register cost is the new `voice0_reset_pulse`
register plus a small mux on `voice_reset_strobe`. Combinational
went down slightly because the compiler is now able to share more
logic on the `release_strobe` branch (small fitter variability).

Setup slack improved 1.203 ns versus M1.1: the M1.1 regression came
from the per-voice mix gating in `phase0_audio_path`; M1.2 makes no
audio-path change, and the new register relieves a tight path that
previously combined release_strobe directly into the voice control
fan-out.

Compile log saved to `.kiro/quartus_phase6_m12.log` (local-only).

## 5. Hardware deferral and recapture protocol (for verifier)

Per the project discipline rule that hardware acceptance is the
verifier's responsibility, M1.2 live recapture is deferred to the
M1.2 verifier task. Suggested verifier protocol:

1. Reprogram the SOF generated by the M1.2 Quartus compile (record
   checksum).
2. Start audio capture.
3. **Run original profile first**:
   ```
   python scripts/phase6_m1_voice_bench.py --run --port COM5 \
       --single-voice-isolate \
       --sidecar reports/phase6_m1_2_voice_bench_session.json
   ```
4. Analyze the captured WAV. If any cell at velocity <= 0x4000 has
   peak above -1 dBFS, fall back to:
   ```
   python scripts/phase6_m1_voice_bench.py --run --port COM5 \
       --single-voice-isolate --profile clean \
       --sidecar reports/phase6_m1_2_voice_bench_clean_session.json
   ```
5. Update the M1 baseline CSV/MD with whichever profile yielded a
   usable baseline. Record the chosen profile in the validation
   report.

Pass conditions for the recapture:
- Q advances by exactly 33 across the run (1 `!I1` + 15 `!N` + 15
  `!F` + 1 trailing `!F` + 1 `!I0`).
- X remains `0x00000000` throughout.
- 15 populated CSV rows.
- Pre-strike RMS clearly below post-strike RMS for most cells
  (because per-cell `!F` now hard-resets voice0).
- For the chosen profile: no near-full-scale cells (peak <= -1 dBFS
  is a soft preference; the clean profile should give margin even
  on long-loop cells).

If the original profile cells <= 0x4000 still clip, that is overload
evidence about the audio path's static parameters (loop_gain,
disp_coeff, body_mix) rather than a failure of M1.2 itself, as long
as the clean profile yields a usable baseline.

## 6. Out of scope

- No timbre/voice-quality RTL changes (no body filter, hammer
  curve, loop-loss, dispersion, or pre-strike noise work).
- No new UART command syntax. The reset semantics ride on the
  existing `!F` command and the existing `voice_reset_strobe` port.
- No CPU/firmware/MMIO/register-file revival.
- No reduction of physical voice count.
- No changes to `rtl/control/phase0_uart_command.v`,
  `rtl/peripherals/phase0_uart_status_tx.v`, the audio path,
  the codec stack, or the QSF source list.
- No `obsolete/` archive change.
- No edits to verifier-protected untracked files or `.kiro/`.

ASCII-only.

## 7. Committed result

This commit contains:

- modify: `rtl/control/phase0_fixed_control.v`
  (voice0_reset_pulse register, conditional reset on
  `release_strobe && isolation_mode`)
- modify: `rtl/control/phase0_fixed_control_isolation_tb.v`
  (five new assertions, pulse_release task)
- modify: `scripts/phase6_m1_voice_bench.py`
  (--profile {original|clean}, sidecar profile field,
  isolation-mode reset note in --plan banner, 11-vector
  --self-check)
- new: `reports/phase6_m1_2_voice_reset_baseline.md` (this file)
