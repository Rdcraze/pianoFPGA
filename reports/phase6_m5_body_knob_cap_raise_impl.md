# Phase 6 M5 Body-Knob Reapply Under Revised LE Cap

Date: 2026-05-25
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-3beccc57`
Branch: `codex/phase1c-uart-boundary-fix`
Parent commit: `33e9005` (Phase 6 M5 NO-GO report from
task-2f2f796b)
Original NO-GO report: `reports/phase6_m5_body_knob_impl.md` (kept
as historical evidence, not modified).

## TL;DR

**PASS under the orchestrator-revised +200 LE cap.** The B2
runtime body-mix knob from the NO-GO attempt is recovered from
git stash entry `phase6_m5_attempt1_le173`, reapplied verbatim,
and re-validated end-to-end. Quartus reports LE 4,932 -> 5,105
(+173), now under the revised +200 hard cap by 27 LE. All four
control-side TBs PASS unchanged from the NO-GO attempt; the
reduced-voice golden TB stays bit-exact at peak=3952. Setup,
hold, M9K, DSP9, PLL, errors, warnings all match the NO-GO
attempt's reported numbers exactly.

| Gate | Revised target | Actual | Verdict |
| --- | --- | --- | --- |
| LE delta vs M3/M4 baseline 4,932 | <= +200 hard | **+173 (5,105)** | PASS |
| Setup slack slow-85C `sys_clk_50m` | >= +4.0 ns | +4.620 ns | PASS |
| Hold slack | clean | +0.414 ns | PASS |
| All TNS | = 0 | 0 | PASS |
| M9K | unchanged at 5 | 5 | PASS |
| DSP9 | unchanged at 26 | 26 | PASS |
| PLL | 1 | 1 | PASS |
| Quartus errors | 0 | 0 | PASS |
| Quartus warnings | <= 16 | 16 | PASS |
| Four physical voices preserved | yes | yes | PASS |
| `phase1_reduced_voice_tb` golden bit-exact | peak=3952 | peak=3952 | PASS |
| `phase0_uart_command_tb` extended 19 vectors | PASS | PASS notes=6 releases=1 errors=4 isolation=1 body_mix=3000 | PASS |
| `phase0_fixed_control_isolation_tb` 11 assertions | PASS unchanged | PASS unchanged | PASS |
| `phase0_uart_status_tx_tb` | PASS unchanged | PASS unchanged | PASS |
| ASCII-only on touched files | yes | yes | PASS |
| Reset/default body_mix_runtime = 0x3000 | deterministic | confirmed in TB | PASS |
| Existing !N/!F/!I behavior preserved | yes | confirmed in TB | PASS |
| No CPU/firmware/MMIO revival | yes | confirmed | PASS |
| No QSF/SDC/PLL/obsolete change | yes | confirmed | PASS |

## 1. Stash recovery and identity check

```
git stash list
stash@{0}: On codex/phase1c-uart-boundary-fix: phase6_m5_attempt1_le173

git stash show -p 'stash@{0}' --stat
 rtl/control/phase0_fixed_control.v              | 20 +++++--
 rtl/control/phase0_fixed_control_isolation_tb.v |  1 +
 rtl/control/phase0_uart_command.v               | 68 +++++++++++++++++++++-
 rtl/control/phase0_uart_command_tb.v            | 75 ++++++++++++++++++++++++-
 rtl/top/piano_phase0_top.v                      |  3 +
 5 files changed, 159 insertions(+), 8 deletions(-)
```

Five-file footprint matches the NO-GO report's section 2
exactly. Pop returns clean working tree with the same five
modifications:

```
git stash pop 'stash@{0}'
M rtl/control/phase0_fixed_control.v
M rtl/control/phase0_fixed_control_isolation_tb.v
M rtl/control/phase0_uart_command.v
M rtl/control/phase0_uart_command_tb.v
M rtl/top/piano_phase0_top.v
Dropped stash@{0}
```

No conflicts. The recovered tree is identical to the NO-GO
attempt; no manual edits were made between recovery and
re-validation.

## 2. Re-validation: simulation TBs

`phase0_uart_command_tb` (extended 19 vectors):
```
UART_CMD_TB_INFO body_mix_default=0x3000
UART_CMD_TB_PASS notes=6 releases=1 errors=4 isolation=1 body_mix=3000
Errors: 0, Warnings: 0
```

`phase0_fixed_control_isolation_tb` (11 assertions):
```
ISOLATION_TB_PASS
Errors: 0, Warnings: 0
```

`phase0_uart_status_tx_tb`:
```
UART_TX_TB_INFO boot0=00000001 boot1=00000002
UART_TX_TB_INFO q0=12345678
UART_TX_TB_INFO x0=00030007
UART_TX_TB_PASS frames=2 collected_count=170
Errors: 0, Warnings: 0
```

`phase1_reduced_voice_tb` (golden bit-exact):
```
VOICE_TB_PASS first_nonzero_sample=106 freq=434.027778
  rms_100ms=272.800735 rms_500ms=27.713698 rms_3s=0.000000
  peak=3952 golden_samples=4096
Errors: 0, Warnings: 0
```

All four PASS. The golden TB result is bit-identical to the M3
and M4 baselines because the body_mix_runtime register defaults
to 0x3000 (= 16'd12288) at reset, exactly the M3 preset.

## 3. Re-validation: Quartus full compile

`.\build.ps1 -Stage compile`:
```
Quartus II Full Compilation was successful. 0 errors, 16 warnings
```

Final resource and timing summary versus the M3/M4 baseline:

| Metric | M3/M4 | M5 (this commit) | Delta |
| --- | ---: | ---: | ---: |
| Total logic elements | 4,932 | **5,105** | **+173** |
| Combinational | 4,707 | 4,843 | +136 |
| Registers | 2,285 | 2,305 | +20 |
| Memory bits | 20,480 | 20,480 | 0 |
| M9K | 5 | 5 | 0 |
| DSP9 | 26 | 26 | 0 |
| PLL | 1 / 2 | 1 / 2 | 0 |
| Slow-85C setup `sys_clk_50m` | +4.515 ns | **+4.620 ns** | +0.105 ns |
| Hold slow-85C | +0.413 ns | +0.414 ns | +0.001 ns |
| All TNS | 0 | 0 | 0 |
| Errors | 0 | 0 | 0 |
| Warnings | 16 | 16 | 0 |

These numbers reproduce the NO-GO report's section 4 table
exactly. The +173 LE delta is now within the orchestrator's
revised +200 hard cap.

Compile log: `.kiro/quartus_phase6_m5_final.log` (local-only).

## 4. Why the orchestrator decision is sound

From the NO-GO report's recommendation Option A, accepted as the
orchestrator's path:

- The intrinsic +120-130 LE cost of removing constant folding
  on four per-voice body multipliers is fundamental to the B2
  design. No parser/control trick recovers it.
- Free LE budget remains comfortable: 5,215 LE (51%) free at
  5,105 LE used.
- Setup slack +4.620 ns sits +0.620 ns above the +4.0 ns hard
  gate and is consistent with the NO-GO measurement.
- The runtime knob is operationally useful immediately (host
  can sweep body_mix during a single capture session) and
  remains useful after the upcoming USB ground-loop isolator
  resolves the audio-chain noise issue.

## 5. Final committed scope

This commit re-applies five files plus this new follow-up
report:

- modify: `rtl/control/phase0_uart_command.v`
  - New protocol header for `!Bvvvv\r\n`.
  - New 16-bit output port `body_mix_runtime` resetting to
    `16'd12288`.
  - New combinational `bm_hex_valid` and `parsed_body_mix`
    helpers.
  - New `5'd8` dispatch case accepting valid `!Bvvvv\r\n`
    (increment command_count, update body_mix_runtime),
    rejecting invalid hex (`ERR_UNSUPPORTED_ARG`), other
    8-byte forms with leading `!B` as unsupported, leading
    `!` as unknown opcode, and other as malformed.
  - Default fall-through extended to recognize `!B*` as
    unsupported argument.
- modify: `rtl/control/phase0_uart_command_tb.v`
  - 7 new test cases (default body_mix_runtime = 0x3000;
    !B0000, !B7FFF, !BFFFF, !B3000; malformed !BG000;
    post-!B regression !N).
  - Final `UART_CMD_TB_PASS` line now reports body_mix.
- modify: `rtl/control/phase0_fixed_control.v`
  - New 16-bit input port `body_mix_runtime`.
  - Static `assign voice_body_mix = 16'd12288;` replaced with
    `assign voice_body_mix = body_mix_runtime;`.
- modify: `rtl/control/phase0_fixed_control_isolation_tb.v`
  - New port wiring `body_mix_runtime <= 16'd12288` constant in
    the DUT instantiation; routing-only TB unchanged otherwise.
- modify: `rtl/top/piano_phase0_top.v`
  - New 16-bit wire `cmd_body_mix_runtime` between the parser
    and fixed-control instances.
- new: `reports/phase6_m5_body_knob_cap_raise_impl.md` (this
  file)

The historical NO-GO report
`reports/phase6_m5_body_knob_impl.md` is preserved unchanged.

## 6. Out of scope (not changed)

- No CPU/firmware/MMIO/register-file revival.
- No JTAG command path, no on-chip strike scheduler, no
  polyphony feature work.
- No QSF/SDC/PLL/obsolete archive change.
- No audio path / body filter / waveguide / hammer-ROM change.
- No reduction of physical voice count.
- No edits to verifier-protected untracked files or `.kiro/`.

ASCII-only.

## 7. Recommended verifier hardware capture protocol

Suggested verifier protocol once the SOF is reprogrammed:

1. Reprogram the SOF generated by this M5 Quartus compile
   (record sha256).
2. Confirm the parser accepts the new commands by sending a few
   `!B0000`, `!B3000`, `!B6000`, `!BFFFF` sequences and
   observing `command_count` (Q field) advance one per command
   while `last_error` stays 0.
3. Try a malformed `!BGOOO` and observe `last_error[15:0] = 7`
   (ERR_UNSUPPORTED_ARG) without `command_count` advancing.
4. Optional A/B: with the existing K=16 coherent-averaging bench
   from M4, run two captures using `body_mix=0x3000` and
   `body_mix=0x6000` (or other contrasting values), then compare
   FFT 1-3 kHz band energy between the two. The +50% body-mix
   change should produce an audible warmth difference even on
   the current Realtek capture chain (the knob doubles M3's
   intra-run delta range).
5. Once the USB ground-loop transformer isolator arrives, the
   same protocol can sweep finer body_mix values for more
   precise warmth tuning.
