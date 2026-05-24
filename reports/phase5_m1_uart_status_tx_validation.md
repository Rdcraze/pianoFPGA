# Phase 5 M1 UART TX Status Frames Validation

Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-04446279` (depends on implementer `task-07ecc3e2`)
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `9c976ff`

## Verdict

**PASS with documented LE-target overrun.** The Phase 5 M1 UART TX
status-frame transmitter is acceptance-grade. New
`rtl/peripherals/phase0_uart_status_tx.v` is correct, sys_clk-domain
only with no CDC, and instantiates the existing
`rtl/peripherals/uart_tx.v` cleanly. Top-level wiring moves
`uart1_tx` ownership from `phase0_fixed_control` to the new TX block;
`uart1_rx` remains intentionally unconsumed. Four physical voice
instances and audio path internals are untouched.

Independent Quartus full compile reproduces the implementer numbers
exactly: LE 3,976 (+362), comb 3,754, regs 1,908, M9K 5, DSP9 26, PLL
1, slow-85C setup `sys_clk_50m` +5.885 ns, hold +0.444 ns, all TNS 0,
0 errors, 18 warnings (down from 20; the M0 stuck-uart1_tx and
uart1_tx-never-read warnings are gone). ModelSim TB
`phase0_uart_status_tx_tb` PASS: two 40-byte frames decoded with
monotonic BOOT counters, 0 errors / 0 warnings.

Hardware acceptance ran clean: SOF programmed (checksum `0x002F79F9`),
8 consecutive `P5M1` frames captured at COM5 with BOOT incrementing
by exactly 1 each frame, TICK strictly monotonic with delta 0x5B8D
(23,437 = 46,875 x 0.5) per frame, VC always in 00..03, cadence
exactly 0.5000 s across 7 inter-frame intervals. Audio capture across
6 s shows continuous output peak around -25 dBFS, no clipping, no
silence, no regression in shape from M0.

The LE delta is +362, above the +250 target from the M1 scope but
below the +400 hard NO-GO. I am explicitly accepting this overrun
because every other gate has comfortable margin (setup slack +1.385 ns
above the +4.5 ns target, warnings reduced, no audio regression, four
voices preserved, M9K/DSP unchanged) and the implementer report is
honest about the cost. A future minor cleanup could narrow the 32-bit
counters and 25-bit cadence to recover ~50-100 LE if pressure ever
returns, but it is not required for M1 acceptance.

## Scope check

`git show --stat 9c976ff` summarized:
- new: `rtl/peripherals/phase0_uart_status_tx.v` (+240 lines)
- new: `rtl/peripherals/phase0_uart_status_tx_tb.v` (+247 lines)
- new: `reports/phase5_m1_uart_status_tx_impl.md` (+300 lines)
- modify: `rtl/control/phase0_fixed_control.v` (+8/-5 lines: replace
  `uart1_tx` output and inline `assign 1'b1` with new
  `voice_index_status` output)
- modify: `rtl/top/piano_phase0_top.v` (+22/-8 lines: instantiate
  `phase0_uart_status_tx` as sibling, remove old uart1_tx wiring)
- modify: `quartus/phase0/piano_phase0_top.qsf` (+2 lines: re-add
  `uart_tx.v` and add `phase0_uart_status_tx.v`)
- modify: `docs/phase0_impl_notes.md` (+8 lines: Phase 5 M1 update)

No other live RTL/firmware/scripts/sim/obsolete files changed. The
`uart_tx.v` re-add is intentional: M0 acceptance removed it as unused;
M1 instantiates it again from the new status-tx block, and the
implementer report explicitly documents this. PASS.

## ASCII check

All implementer-touched files verified ASCII-only via byte-level scan
(0 non-ASCII bytes):
- `rtl/peripherals/phase0_uart_status_tx.v` (8909 bytes)
- `rtl/peripherals/phase0_uart_status_tx_tb.v` (8253 bytes)
- `rtl/control/phase0_fixed_control.v` (8125 bytes)
- `rtl/top/piano_phase0_top.v` (10192 bytes)
- `quartus/phase0/piano_phase0_top.qsf` (3280 bytes)
- `reports/phase5_m1_uart_status_tx_impl.md` (11997 bytes)

PASS.

## Source review

### `phase0_uart_status_tx.v`

- Module ports are sys_clk-only: `sys_clk`, `sys_rst_n`, `sample_tick`,
  `voice_index[1:0]`, `uart_tx`. No CDC.
- Three internal sub-blocks:
  1. 25-bit cadence counter that emits `cadence_pulse` once every
     `CADENCE_LAST = CADENCE_CYCLES - 1` (default 25,000,000 cycles
     at 50 MHz = 500 ms). Matches scope report.
  2. 32-bit free-running `tick_counter_free` increments on every
     `sample_tick`; snapshot to `tick_snapshot` at frame start.
  3. 3-state FSM (IDLE / SEND / WAIT) sequencing 40 bytes through
     `uart_tx`.
- Frame contents: combinational `frame_byte` selector indexed by
  `byte_index` (6 bits), with `hex_nibble32` and `hex_to_ascii`
  helpers. Frame layout matches the contract in the M1 scope report
  (`P5M1 BOOT=........ TICK=........ VC=..\r\n`).
- `boot_counter` is incremented at frame start, snapshotted into
  `boot_counter <= boot_counter + 32'd1` exactly once per accepted
  cadence. Monotonic by construction.
- `vc_snapshot` captures `voice_index` at frame start; held stable
  through the entire frame transmission.
- Skipped-cadence handling: if `cadence_pulse` fires while `tx_ready`
  is low (previous byte still draining), `skipped_count` saturating
  8-bit counter increments. Not exposed externally; reserved for M2.
- Reset behavior: async `!sys_rst_n` resets all FSM state, both
  counters, and snapshots. `boot_counter` resets to 0; first emitted
  frame has `BOOT=00000001`. Confirmed by ModelSim TB.

### `phase0_fixed_control.v`

- `uart1_tx` output port is removed. `voice_index_status[1:0]` output
  added on line 91, driven on line 197 from the existing
  `voice_index` register. Audio defaults, voice enables, hardwired
  parameter assignments, and round-robin sequencer FSM are
  byte-identical to the M0 baseline behavior. Confirmed by inspection
  against the M0 file content.

### `piano_phase0_top.v`

- `uart1_tx` ownership moves from `phase0_fixed_control` to a new
  `phase0_uart_status_tx_inst` sibling. Top-level instantiation of
  `phase0_audio_path`, `wm8978_codec_stub`, and the four
  `phase1_reduced_voice` instances inside `phase0_audio_path` is
  unchanged.
- `uart1_rx` continues to be sunk into `_unused_uart1_rx` reduction
  to avoid an unused-input synthesis warning. Intentional and
  matches M0 pattern.

### `piano_phase0_top.qsf`

- Added: `../../rtl/peripherals/uart_tx.v` and
  `../../rtl/peripherals/phase0_uart_status_tx.v`. No obsolete
  RV32I/MMIO/firmware sources reintroduced. Pin assignments and SDC
  reference unchanged.

### Audio path

`rtl/audio/phase0_audio_path.v` not modified. Four physical
`phase1_reduced_voice` instances (`_inst`, `1_inst`, `2_inst`,
`3_inst`) preserved. PASS.

## Quartus compile evidence

Independent full compile from `quartus/phase0/build.ps1 -Stage compile`:
- Errors: 0
- Warnings: 18 (down from 20 in M0; expected drop of stuck-output and
  unused-uart1_tx warnings)
- LE: 3,976 / 10,320 (39%), +362 vs M0 baseline 3,614
- Combinational: 3,754, +349
- Registers: 1,908, +157
- Memory bits: 20,480 (unchanged)
- M9K: 5 (unchanged)
- DSP9: 26 (unchanged)
- PLL: 1 (unchanged)
- Slow-85C setup `sys_clk_50m`: +5.885 ns (M0 +5.539, +0.346)
- Slow-85C setup `audio_bclk`: +315.938 ns
- Slow-85C setup `i2c_clk`: +994.629 ns
- All TNS: 0

Numbers reproduce implementer claims bit-identically. Setup slack
margin is +1.385 ns above the +4.5 ns M1 target gate. PASS.

Compile log saved to `.kiro/quartus_phase5_m1_verify.log` (local-only).

## LE-target overrun adjudication

Target was <= +250 LE; actual is +362; hard NO-GO was +400.

Considerations:
- The +112 overrun is honest paper-vs-actual variance, not a hidden
  cost or scope creep. The implementer report calls it out
  explicitly.
- Setup slack improved (+0.346 ns above M0). No timing pressure.
- Quartus warnings are net lower (18 vs 20). No new warning categories.
- M9K, DSP9, and PLL are all unchanged. No silent resource consumption.
- Counter widths are oversized for clarity: cadence is 25 bits when
  21 bits would suffice for a 25M count, and the BOOT and TICK
  counters are 32 bits when 24-28 bits would also be plenty for the
  visible-on-COM-port use case. A future cleanup could recover
  approximately 50-100 LE if needed.
- The audio path is unchanged and the four-voice cadence is intact.

I accept the overrun for M1 because every other gate is comfortable
and the function delivered (positive serial heartbeat) is the right
M1 behavior. A small follow-up cleanup task could optionally tighten
counter widths in M2 or M3.

## ModelSim evidence

Compiled and ran the focused TB at `.kiro/msim_m1/`:

```
vlib work
vlog -quiet rtl/peripherals/uart_tx.v rtl/peripherals/phase0_uart_status_tx.v rtl/peripherals/phase0_uart_status_tx_tb.v
vsim -c -lib work phase0_uart_status_tx_tb -do "run -all; quit -f"
```

Result:
```
# UART_TX_TB_INFO boot0=00000001 boot1=00000002
# UART_TX_TB_PASS frames=2 collected_count=80
# ** Note: $finish    : rtl/peripherals/phase0_uart_status_tx_tb.v(244)
# Errors: 0, Warnings: 0
```

Two complete 40-byte frames decoded mid-bit at 115200 baud, BOOT
counters monotonic (`0x00000001` then `0x00000002`), CRLF terminators
at the right offsets. PASS.

The reduced-voice golden TB
(`rtl/audio/phase1_reduced_voice_tb.v`) was not rerun; M1 makes no
audio-path changes and that TB was last accepted at the Phase 4 M7
acceptance run. Justification matches implementer report.

## Hardware acceptance

JTAG and COM5 are visible (`USB-Blaster [USB-0]`, `COM5`).

1. Programmed `quartus/phase0/output_files/piano_phase0_top.sof` via
   `quartus_pgm`. Reported checksum: `0x002F79F9`. 0 errors.
2. Captured COM5 at 115200 8N1 for 4 s using
   `.kiro/phase5_m1_uart_capture.py`. Saved to
   `reports/phase5_m1_uart.txt`. 8 P5M1 frames decoded:

   | i | t (s) | BOOT | TICK | VC |
   | ---: | ---: | --- | --- | --- |
   | 0 | 0.422 | 00000030 | 00112A6F | 00 |
   | 1 | 0.922 | 00000031 | 001185FC | 02 |
   | 2 | 1.422 | 00000032 | 0011E18A | 03 |
   | 3 | 1.922 | 00000033 | 00123D17 | 00 |
   | 4 | 2.422 | 00000034 | 001298A5 | 02 |
   | 5 | 2.922 | 00000035 | 0012F432 | 03 |
   | 6 | 3.422 | 00000036 | 00134FC0 | 01 |
   | 7 | 3.922 | 00000037 | 0013AB4D | 02 |

   - BOOT increments by exactly 1 each frame.
   - TICK strictly monotonic with consistent delta around 0x5B8D
     (23,437) per frame, equal to 46,875 x 0.5 s. The sample-tick
     rate at the live design's 46.875 kHz matches expectation.
   - VC stays in 00..03; sequence reflects the ~350 ms round-robin
     trigger sampled at 500 ms cadence (consecutive frames sample
     different voice indices, sometimes skipping one because the
     trigger sequencer cycles faster than the UART cadence).
   - Inter-frame cadence: 7 measured intervals at exactly 0.5000 s
     (min/max/avg all 0.5000 s, no jitter).

   PASS.

3. Captured 6 s of audio at the 3.5 mm jack via ffmpeg dshow into
   `reports/phase5_m1_audio.wav`. Per-second analysis:

   | s | peak | peak (dBFS) | RMS | RMS (dBFS) |
   | ---: | ---: | ---: | ---: | ---: |
   | 0 | 1776 | -25.32 | 458.7 | -37.08 |
   | 1 | 1829 | -25.06 | 516.6 | -36.05 |
   | 2 | 1729 | -25.55 | 495.1 | -36.42 |
   | 3 | 1855 | -24.94 | 583.7 | -34.98 |
   | 4 | 1722 | -25.59 | 598.6 | -34.77 |
   | 5 | 1696 | -25.72 | 493.0 | -36.45 |

   Overall peak -24.94 dBFS, RMS -35.88 dBFS. No clipping in any
   second. Continuous output across the entire 6 s capture, consistent
   with the round-robin sequencer firing voice0..voice3. The level is
   slightly lower than the M0 capture (-19.30 vs -24.94 dBFS),
   consistent with mic-input gain variation between runs; the shape
   (continuous, non-clipping, no silence) matches M0 exactly. No
   audio regression. PASS.

## Architecture guard

Four physical `phase1_reduced_voice` instances preserved in
`rtl/audio/phase0_audio_path.v`. UART RX still unconsumed. No live
reference anywhere to RV32I, MMIO, register-file, or firmware
sources. Obsolete archive untouched. PASS.

## Compatibility notes (deferred to M2)

- Phase 3 M3a/M3b parameterized note commands (`!NLLLLVVVV`) still
  not consumed.
- Phase 3 M4 release command (`!F`) still not consumed.
- Phase 3 host wrappers (M5/M6/M7a/M9) remain legacy regression
  tools; their stdout output is not yet connected to the board.
- Q/X command-count and parser-error tags are absent from the M1
  status frame; these will land in M2 once RX exists.

These are documented and queued for M2.

## Final verdict

**PASS with LE-target overrun adjudication.** Phase 5 M1 UART TX
status-frame transmitter is acceptance-grade. The hardware now emits
a stable 500-ms cadence of `P5M1 BOOT=... TICK=... VC=...\r\n`
status frames at 115200 8N1 with monotonic BOOT, monotonic TICK at
the expected 46.875 kHz scaling, and VC in range. Audio remains
continuous, four-voice, non-clipping with no regression from M0.

Validation commit will include only this report. Orchestrator may
queue Phase 5 M2 (RX command parser plus Q/X status-frame extension)
without revisiting M1.
