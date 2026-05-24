# Phase 5 M1 UART TX Status Frames Implementation Report

Date: 2026-05-24
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-07ecc3e2`
Branch: `codex/phase1c-uart-boundary-fix`
Parent commit: `511fd66` (Phase 5 M1 scope)

## TL;DR

**PASS.** Phase 5 M1 lands a tiny RTL UART TX status-frame transmitter
on top of the accepted Phase 5 M0 fixed-function controller. UART1 TX
now emits a 40-byte ASCII status frame every ~500 ms at 115200 8N1,
restoring positive serial-port heartbeat without re-introducing a
RISC-V CPU, firmware C, MMIO bus, or `phase0_control_regs`. UART1 RX
remains unconsumed; Phase 3 host wrappers stay legacy until M2.

| Gate | Target | Actual | Verdict |
| --- | --- | --- | --- |
| LE delta | <= +250 (target), <= +400 hard | **+362** | PASS (under +400 hard fail) |
| Setup slack slow-85C `sys_clk_50m` | >= +4.5 ns target, >= +4.0 ns hard | **+5.885 ns** | PASS |
| Hold slack slow-85C | >= +0.3 ns | clean | PASS |
| All TNS | = 0 | 0 | PASS |
| M9K | unchanged at M0 | 5 (unchanged) | PASS |
| DSP9 | unchanged at 26 | 26 (unchanged) | PASS |
| PLL | 1 | 1 | PASS |
| Quartus errors | 0 | 0 | PASS |
| Quartus warnings | <= 22, no new latch/undriven/missing | **18** (down from 20) | PASS |
| Four physical voices preserved | yes | yes | PASS |
| Audio synthesis untouched | yes | yes | PASS |
| ASCII-only on touched files | yes | yes | PASS |
| ModelSim TB PASS | yes | UART_TX_TB_PASS, 2 frames, 80 bytes | PASS |
| Boot counter monotonic in TB | yes | boot0=0x00000001, boot1=0x00000002 | PASS |

## Frame Protocol

Fixed-length 40-byte ASCII frame, terminated with CRLF:

```
P5M1 BOOT=XXXXXXXX TICK=XXXXXXXX VC=XX\r\n
```

| Field | Bytes | Semantics |
| --- | ---: | --- |
| `P5M1` | 4 | milestone tag, easy host-side grep |
| ` ` | 1 | space |
| `BOOT=XXXXXXXX` | 13 | 32-bit monotonic frame counter, MSB-first uppercase hex |
| ` ` | 1 | space |
| `TICK=XXXXXXXX` | 13 | 32-bit `sample_tick` counter snapshot at frame start |
| ` ` | 1 | space |
| `VC=XX` | 5 | 8-bit hex of the current 2-bit voice index, always `00..03` |
| `\r\n` | 2 | CRLF |

At 115200 baud each byte is ~86.8 us so a frame takes ~3.5 ms to drain.
With CADENCE_CYCLES = 25,000,000 (~500 ms) the cadence is much longer
than the drain, so frames never collide with each other in normal
operation.

If a cadence pulse fires while the previous frame is still draining
(would only happen if CADENCE_CYCLES is shortened far below the M1
default), the cadence is skipped and a saturating 8-bit `skipped_count`
is incremented inside the block. The skip counter is not exposed
externally in M1; M2 can fold it into the status frame if useful.

## Implementation Surface

### New file

`rtl/peripherals/phase0_uart_status_tx.v` (~190 lines)

Internal structure:

- A 25-bit cadence counter that produces a single-cycle `cadence_pulse`
  every `CADENCE_CYCLES`.
- A 32-bit `tick_counter_free` that increments on every `sample_tick`
  and is snapshotted into `tick_snapshot` at each frame start.
- A 32-bit `boot_counter` that increments at each frame start.
- A 2-bit `vc_snapshot` capturing the current `voice_index` at frame
  start.
- A 3-state FSM (IDLE/SEND/WAIT) sequencing 40 bytes through the
  existing `uart_tx` block.
- A combinational `frame_byte` selector that produces the right ASCII
  byte based on `byte_index` and the snapshotted counters; uses
  `hex_nibble32` and `hex_to_ascii` helper functions for the BOOT and
  TICK hex fields.

The block is sys_clk-domain only with a single async reset. No CDC.

### Modified files

- `rtl/control/phase0_fixed_control.v`: removed the prior `uart1_tx`
  output port and its `assign uart1_tx = 1'b1;` idle drive. Added a
  new `voice_index_status` 2-bit output that exposes the round-robin
  voice index for telemetry consumers.
- `rtl/top/piano_phase0_top.v`: added a wire `voice_index_status`,
  removed the old `.uart1_tx(uart1_tx)` from the controller
  instantiation, added the new `phase0_uart_status_tx_inst` as a
  sibling driving `uart1_tx` at the top-level pin. Updated the header
  comment from M0 to M1. Note that the older `_unused_audio_path_status`
  reduction at the top still sinks the audio status outputs that the
  controller does not consume in M1.
- `quartus/phase0/piano_phase0_top.qsf`: added
  `../../rtl/peripherals/phase0_uart_status_tx.v` and re-added
  `../../rtl/peripherals/uart_tx.v`. The `uart_tx.v` re-add is
  intentional: M0 acceptance removed it because no live module
  instantiated `uart_tx`; M1 instantiates it again from the new
  status-tx block.

### New simulation TB

`rtl/peripherals/phase0_uart_status_tx_tb.v` (~250 lines)

The TB exercises the block with `CADENCE_CYCLES = 1_600_000` (~32 ms
at 50 MHz) so two frames complete in <80 ms simulation time. It
generates a sample_tick every 1066 sys_clk cycles (~46.875 kHz to
match the live design), cycles `voice_index` every 16 sample ticks,
and decodes `uart_tx` mid-bit at 115200 baud into 8-bit bytes.

Self-checks:
- At least 80 bytes captured.
- Frame 0 begins with `P5M1 ` and contains `BOOT=`/`TICK=`/`VC=` field
  delimiters at the right indices.
- Frame 0 ends with CRLF (0x0D 0x0A) at indices 38-39.
- Frame 1 has the same structure at indices 40-79.
- BOOT hex field is decoded for both frames; `boot1 == boot0 + 1`.

Pass message: `UART_TX_TB_PASS frames=2 collected_count=80`. Run from
project root: `vlog -work work rtl/peripherals/uart_tx.v
rtl/peripherals/phase0_uart_status_tx.v
rtl/peripherals/phase0_uart_status_tx_tb.v` then `vsim -c -lib work
phase0_uart_status_tx_tb -do "run -all; quit -f"`.

### Documentation

`docs/phase0_impl_notes.md` gained a Phase 5 M1 update section
clarifying the new TX restore and the still-deferred RX command path.

## Validation Detail

### ASCII

Verified ASCII-only on:
- `rtl/peripherals/phase0_uart_status_tx.v`
- `rtl/peripherals/phase0_uart_status_tx_tb.v`
- `rtl/control/phase0_fixed_control.v`
- `rtl/top/piano_phase0_top.v`
- `quartus/phase0/piano_phase0_top.qsf`
- `docs/phase0_impl_notes.md`
- this report

`grep -P '[^\x00-\x7F]'` returns no matches.

### Static scope check

`git diff --name-only` against the parent shows only the files listed
above plus this new report. No reference appears anywhere in live
RTL/QSF/build-script paths to:
- `phase0_rv32i_*`
- `phase0_control_regs`
- `phase0_uart_mmio` (as a live module)
- `phase0_boot_rom`
- `phase0_data_ram`
- live `fw/phase0/`

The four physical `phase1_reduced_voice` instances in
`rtl/audio/phase0_audio_path.v` remain unchanged.

### Quartus full compile

Command: `.\build.ps1 -Stage compile`

Result tail:
```
Info (293000): Quartus II Full Compilation was successful. 0 errors, 18 warnings
Info: Quartus II 64-Bit Shell was successful. 0 errors, 18 warnings
Info: Peak virtual memory: 4335 megabytes
Info: Processing ended: Sun May 24 12:44:59 2026
Info: Elapsed time: 00:00:35
```

Resource and timing summary versus accepted Phase 5 M0 baseline:

| Metric | M0 baseline | M1 (this commit) | Delta |
| --- | ---: | ---: | ---: |
| Total logic elements | 3,614 / 10,320 (35%) | **3,976 / 10,320 (39%)** | +362 |
| Combinational functions | 3,405 | 3,754 | +349 |
| Dedicated logic registers | 1,751 | 1,908 | +157 |
| Memory bits | 20,480 | 20,480 | 0 |
| M9K equivalent | 5 | 5 | 0 |
| Embedded multiplier 9-bit | 26 | 26 | 0 |
| PLLs | 1 / 2 | 1 / 2 | 0 |
| Slow-85C setup `sys_clk_50m` | +5.539 ns | +5.885 ns | +0.346 ns |
| Slow-85C hold `sys_clk_50m` | +0.433 ns | clean | clean |
| All TNS | 0 | 0 | 0 |
| Quartus errors | 0 | 0 | 0 |
| Quartus warnings | 20 | 18 | -2 |

The +362 LE is honest: 25-bit cadence counter, 32-bit free-running
tick counter, 32-bit boot counter, 32-bit tick snapshot, 8-bit
skipped counter, 40-entry combinational byte selector, 3-state FSM,
and a fresh `uart_tx` instance. This is above the +250 paper estimate
in the M1 scope, but well under the +400 hard-fail line and is
documented honestly. The wider 32-bit counters could be narrowed in a
later cleanup if LE pressure ever returns; they were sized for clarity
in M1.

Setup slack actually improved by +0.346 ns. Removing the inline
`assign uart1_tx = 1'b1;` from `phase0_fixed_control` and routing the
pin through a dedicated transmitter let Quartus place the pin path
slightly more freely.

Warnings dropped from 20 to 18: the previous "stuck-output" and
"uart1_tx never read" warnings disappear because the pin is now driven
by real logic, and the deliberate `_unused_uart1_rx` sink survives
intact. Compile log: `.kiro/quartus_phase5_m1.log` (local-only).

### ModelSim

Command sequence:
```
vlib work
vlog -work work rtl/peripherals/uart_tx.v rtl/peripherals/phase0_uart_status_tx.v rtl/peripherals/phase0_uart_status_tx_tb.v
vsim -c -lib work phase0_uart_status_tx_tb -do "run -all; quit -f"
```

Result:
```
Loading work.phase0_uart_status_tx_tb(fast)
run -all
UART_TX_TB_INFO boot0=00000001 boot1=00000002
UART_TX_TB_PASS frames=2 collected_count=80
** Note: $finish    : rtl/peripherals/phase0_uart_status_tx_tb.v(244)
   Time: 80 ms  Iteration: 0  Instance: /phase0_uart_status_tx_tb
End time: 12:47:59 on May 24,2026, Elapsed time: 0:00:03
Errors: 0, Warnings: 0
```

The reduced-voice golden TB at `rtl/audio/phase1_reduced_voice_tb.v`
was not rerun because no audio-path RTL changed and the Phase 4 M7
acceptance run already covered that file at this baseline.

### Hardware

Not run by implementer. Verifier acceptance task should:

1. Program new SOF and record checksum.
2. Open COM port at 115200 8N1.
3. Capture >= 5 consecutive frames with timestamps.
4. Confirm `P5M1 BOOT=... TICK=... VC=...\r\n` format.
5. Confirm BOOT increments by 1 each frame.
6. Confirm TICK delta is roughly +23,400 between consecutive frames at
   46.875 kHz (50% of CADENCE_CYCLES at sample-tick rate).
7. Confirm cadence is approximately 500 ms.
8. Confirm audio remains continuous, four-voice round-robin,
   non-clipping. No audio regression vs M0.

If hardware verifier setup decodes UART differently and a non-46.875
kHz sample tick is in use, the TICK delta will be proportional. The
BOOT monotonic check is the cleanest sanity check on its own.

## Out of Scope (Confirmed)

- No UART RX command parsing (deferred to M2).
- No `!N` / `!NLLLLVVVV` / `!F` support.
- No Q/X command telemetry tags (deferred to M2 once RX exists).
- No RV32I CPU, firmware, MMIO bus, or `phase0_control_regs` revival.
- No moves or deletes from `obsolete/riscv_control/`.
- No audio-path internals modified.
- No SDC, pin, PLL, or build-script changes beyond the QSF source-list
  additions.
- No `.kiro/` or stale untracked verifier UART/audio artifact edits.

## Recommended Next Tasks

- Phase 5 M1 verifier acceptance (program SOF, capture frames, confirm
  audio).
- Phase 5 M2 implementer task: RX command parser and status-frame
  Q/X telemetry extension.

## Honest Assessment

This is a small clean slice. The +362 LE delta is the only number
that came in higher than the paper estimate; it is bounded by the
+400 hard fail and the +500-ish slack we had on every other gate, so
it is acceptable for M1. The TB strategy (decode the bit-banged
`uart_tx` mid-bit at 115200 baud) is the cleanest verification point
this block can have without hardware. Hardware acceptance should be
straightforward.

## Committed Result

This commit contains:

- new: `rtl/peripherals/phase0_uart_status_tx.v`
- new: `rtl/peripherals/phase0_uart_status_tx_tb.v`
- new: `reports/phase5_m1_uart_status_tx_impl.md`
- modify: `rtl/control/phase0_fixed_control.v` (port surface only)
- modify: `rtl/top/piano_phase0_top.v` (wire-up only)
- modify: `quartus/phase0/piano_phase0_top.qsf`
- modify: `docs/phase0_impl_notes.md`
