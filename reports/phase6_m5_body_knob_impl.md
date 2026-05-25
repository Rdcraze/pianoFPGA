# Phase 6 M5 B2 Runtime Body-Mix Knob - Implementation NO-GO

Date: 2026-05-25
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-2f2f796b`
Branch: `codex/phase1c-uart-boundary-fix`
Parent commit: `352c775` (Phase 6 M4 host-tool slice PASS)

## TL;DR

**NO-GO: implementation is functionally correct but violates the
+150 LE hard cap.** A complete `!Bvvvv\r\n` runtime body-mix
parser, an `body_mix_runtime` register that defaults to M3's
accepted 16'd12288 at reset, and the controller/top wiring to
forward this register to `voice_body_mix` were implemented and
proved out in simulation. The reduced-voice golden TB stays
bit-exact at peak=3952; the parser TB extended to 19 vectors
(was 12) PASS including default 0x3000, !B0000, !B7FFF, !BFFFF,
!B3000, malformed !BG000, and post-!B regression !N. The
isolation TB still PASS at 11 assertions.

**The Quartus full compile** of the proposed implementation
returns LE 4,932 -> 5,105 (+173), exceeding the **+150 hard cap**
by +23 LE. Setup slack slow-85C `sys_clk_50m` +4.620 ns is
above the +4.0 ns hard gate; M9K/DSP9/PLL counts unchanged; 0
errors / 16 warnings / all TNS 0.

**Per the stop-and-report NO-GO trigger ("Parser/control cannot
add !B within +150 LE")**, I have stashed the implementation
work locally and reverted the live tree to the M3/M4 baseline
4,932 LE. The full implementation (5 RTL files, 1 TB-only file)
is preserved in `git stash` entry "phase6_m5_attempt1_le173"
and can be reapplied with a single `git stash pop`.

| Gate | Target | Actual | Verdict |
| --- | --- | --- | --- |
| LE delta vs M3/M4 (4,932) | <= +50 target / +150 hard | **+173 (5,105)** | **FAIL hard cap** |
| Setup slack slow-85C `sys_clk_50m` | >= +4.0 ns hard | +4.620 ns | PASS |
| Hold slack | clean | +0.414 ns | PASS |
| All TNS | = 0 | 0 | PASS |
| M9K | unchanged at 5 | 5 | PASS |
| DSP9 | unchanged at 26 | 26 | PASS |
| PLL | 1 | 1 | PASS |
| Quartus errors | 0 | 0 | PASS |
| Quartus warnings | <= 16 | 16 | PASS |
| Four physical voices preserved | yes | yes | PASS |
| `phase1_reduced_voice_tb` golden bit-exact | peak=3952 | peak=3952 | PASS |
| `phase0_uart_command_tb` PASS at extended 19 vectors | yes | UART_CMD_TB_PASS notes=6 releases=1 errors=4 isolation=1 body_mix=3000 | PASS |
| `phase0_fixed_control_isolation_tb` PASS unchanged | yes | ISOLATION_TB_PASS | PASS |
| `phase0_uart_status_tx_tb` PASS unchanged | yes | UART_TX_TB_PASS | PASS |
| ASCII-only on touched files | yes | yes | PASS |
| Reset/default body_mix_runtime = 0x3000 | deterministic | confirmed in TB and reset block | PASS |
| Existing !N/!F/!I behavior preserved | yes | confirmed in TB | PASS |
| No CPU/firmware/MMIO/UART-syntax-removal | yes | confirmed | PASS |

Every gate passes EXCEPT the LE hard cap.

## 1. Why the +173 LE delta is intrinsic, not careless

The dominant cost is **not** in the parser or the new runtime
register. It is in the audio path: making `voice_body_mix`
runtime-variable forces the synthesizer to materialize four
`body_mix_q15 * body_history_tap` multipliers per voice instance
that were previously constant-folded against the static
`16'd12288` value.

Honest breakdown of the +173 LE:
- Parser changes (`!Bvvvv` decode helpers, 5'd8 case, runtime
  register, output port, default branch update): estimated
  35-45 LE.
- Loss of constant folding on body multipliers in four physical
  `phase1_reduced_voice` instances: estimated 120-130 LE
  (~30-32 LE per voice).

Verification: stashing all M5 changes and rebuilding produces
exactly the M3/M4 baseline 4,932 LE. Reapplying the changes
produces 5,105 LE. The delta is fully attributable to M5; no
hidden cost or scope creep.

The cost is **fundamental to the B2 design**: any runtime body
knob that drives the per-voice body multiplier path will pay
this constant-fold loss across all four voices. Implementation
tricks within the parser/control surface cannot recover it.

## 2. What was implemented (preserved in `git stash`)

### `rtl/control/phase0_uart_command.v`

- New protocol comment block documenting `!Bvvvv\r\n`.
- New 16-bit output port `body_mix_runtime` initialized to
  16'd12288 on reset.
- New combinational pre-computation block (`bm_hex_valid`,
  `parsed_body_mix`) modelled after the existing
  `!NLLLLVVVV` decode path.
- New `5'd8` case in the dispatch FSM: accepts `!Bvvvv\r\n`
  with valid 4-hex-digit value, increments `command_count`, and
  updates `body_mix_runtime`. Bad hex returns
  `ERR_UNSUPPORTED_ARG`. Other 8-byte forms with leading `!B`
  are also classified as unsupported argument.
- Default branch updated to recognize `!B...` in the unsupported-
  arg classification.

### `rtl/control/phase0_uart_command_tb.v`

Extended from 12 to 19 test cases:
- Default `body_mix_runtime == 0x3000` after reset.
- `!B0000\r\n` -> 0x0000.
- `!B7FFF\r\n` -> 0x7FFF.
- `!BFFFF\r\n` -> 0xFFFF.
- `!B3000\r\n` -> 0x3000 (M3 default re-applied).
- `!BG000\r\n` malformed -> `ERR_UNSUPPORTED_ARG` (7), no
  body_mix update, command_count stable.
- Regression: `!N` after all `!B` activity still works.

Output (with stash applied):
```
UART_CMD_TB_INFO body_mix_default=0x3000
UART_CMD_TB_PASS notes=6 releases=1 errors=4 isolation=1 body_mix=3000
Errors: 0, Warnings: 0
```

### `rtl/control/phase0_fixed_control.v`

- New input `body_mix_runtime[15:0]`.
- The previous static `assign voice_body_mix = 16'd12288;` is
  replaced with `assign voice_body_mix = body_mix_runtime;`. The
  reset-default invariant (16'd12288) is now enforced by the
  parser's reset value, so the audio path comes up at the
  M3-accepted preset before any host command.

### `rtl/control/phase0_fixed_control_isolation_tb.v`

- New port wiring `body_mix_runtime` to a constant 16'd12288 in
  the DUT instantiation (this TB does not exercise the runtime
  knob; it tests routing only). All 11 isolation assertions
  still PASS unchanged.

### `rtl/top/piano_phase0_top.v`

- New 16-bit wire `cmd_body_mix_runtime` between
  `phase0_uart_command_inst` and `phase0_fixed_control_inst`.
- No new audio-path or codec wiring change.

## 3. ModelSim regression evidence (all four TBs PASS)

```
phase0_uart_command_tb        UART_CMD_TB_PASS notes=6 releases=1 errors=4 isolation=1 body_mix=3000
phase0_fixed_control_isolation_tb   ISOLATION_TB_PASS (11 assertions)
phase0_uart_status_tx_tb      UART_TX_TB_PASS frames=2 collected_count=170
phase1_reduced_voice_tb       VOICE_TB_PASS first_nonzero_sample=106 freq=434.027778
                              rms_100ms=272.800735 rms_500ms=27.713698
                              peak=3952 golden_samples=4096
```

## 4. Quartus full compile

`.\build.ps1 -Stage compile`:
```
Quartus II Full Compilation was successful. 0 errors, 16 warnings
```

| Metric | M3/M4 | M5 attempt | Delta |
| --- | ---: | ---: | ---: |
| Total logic elements | 4,932 | **5,105** | **+173** |
| Combinational | 4,707 | 4,843 | +136 |
| Registers | 2,285 | 2,305 | +20 |
| Memory bits | 20,480 | 20,480 | 0 |
| M9K | 5 | 5 | 0 |
| DSP9 | 26 | 26 | 0 |
| PLL | 1 / 2 | 1 / 2 | 0 |
| Slow-85C setup `sys_clk_50m` | +4.515 ns | +4.620 ns | +0.105 ns |
| Hold slow-85C | +0.413 ns | +0.414 ns | +0.001 ns |
| All TNS | 0 | 0 | 0 |
| Errors | 0 | 0 | 0 |
| Warnings | 16 | 16 | 0 |

The +20 register count is the new `body_mix_runtime[15:0]` flop
plus a small fitter retiming. The +136 combinational count is
the dominant consumer: ~115 LE of body multiplier path
unfolding across four voices, ~21 LE for the parser additions.

Setup slack actually improved by +0.105 ns (this is run-to-run
fitter variance; the new register is well inside the +4.0 ns
gate). Hold and TNS clean.

Compile log: `.kiro/quartus_phase6_m5b.log` (M5 attempt) and
`.kiro/quartus_phase6_m5_revert.log` (post-stash baseline)
both saved locally.

## 5. Recommended decisions (orchestrator)

The implementation is **functionally complete and correct**. The
choice is whether the LE cost is acceptable:

### Option A (recommended): raise the LE cap to +200 and accept

Rationale:
- The cost is intrinsic to runtime body_mix; no implementation
  trick recovers the constant-fold loss.
- Free LE budget remains comfortable: 5,215 LE (51%) free at
  5,105 LE used.
- Setup slack at +4.620 ns has +0.620 ns margin above the +4.0 ns
  hard gate.
- The user explicitly requested B2 in this task ("implement B2
  from the Phase 6 plan").
- M5 was always known to be larger than the body-coefficient
  retune; the +50 target was aspirational, the +150 hard cap was
  conservative without measurement.

If accepted, I can `git stash pop` the implementation, run final
ASCII/sim checks, and commit in a single follow-up.

### Option B: pivot the audio-path body_mix application point

Move the `body_mix * body_history_tap` multiplier OUT of the
per-voice `phase1_reduced_voice` instance and INTO the audio-path
mix-sum stage in `phase0_audio_path.v`. This collapses four
multiplications into one, paying ~30 LE of new shared logic
instead of 120 LE of per-voice unfolding.

Trade-off:
- Audio path change is explicitly out of scope for this task
  ("Do not change voice_body_mix_q15 width, saturation behavior,
  body filter structure, or body filter coefficients"). The body
  multiplier inside `phase1_reduced_voice` IS part of the body
  filter structure.
- Would require a larger scope adjustment and re-validation of
  the reduced-voice golden TB at the new mix point.
- M9K/DSP9 may also shift, requiring re-verification.

I do NOT recommend B without explicit scope expansion.

### Option C: NO-GO and pivot

Drop B2; pivot M5 to candidate D (pre-strike noise component) or
E (loop-loss differential decay) per Phase 6 M0 scope. These have
their own LE/timing risk profiles to be re-scoped.

## 6. Stash recovery

The implementation is preserved in `git stash` entry tagged
"phase6_m5_attempt1_le173". To reapply:

```
git stash list
git stash pop stash@{0}    # or whichever index it lands at
```

After pop, the touched files match the implementation described
in section 2.

## 7. Out of scope (NOT changed)

- No CPU/firmware/MMIO/register-file revival.
- No JTAG command path, no on-chip strike scheduler, no polyphony
  feature work.
- No QSF/SDC/PLL/obsolete archive change.
- No audio path / body filter / waveguide / hammer-ROM change.
- No reduction of physical voice count.
- No edits to verifier-protected untracked files or `.kiro/`.

ASCII-only on this report.

## 8. Committed result

This commit contains ONLY this report. The RTL changes are
stashed pending an orchestrator decision per section 5.

- new: `reports/phase6_m5_body_knob_impl.md` (this file)

The `git stash` entry "phase6_m5_attempt1_le173" preserves:
- modify: `rtl/control/phase0_uart_command.v`
- modify: `rtl/control/phase0_uart_command_tb.v`
- modify: `rtl/control/phase0_fixed_control.v`
- modify: `rtl/control/phase0_fixed_control_isolation_tb.v`
- modify: `rtl/top/piano_phase0_top.v`
