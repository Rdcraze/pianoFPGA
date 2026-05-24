# Phase 5 M2 UART RX Command Parser Validation

Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-a7fa4bd0` (depends on implementer `task-b56a8983`)
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `5ee0c7c`

## Verdict

**PASS with documented LE-target overrun.** Phase 5 M2 RTL UART RX
command parser is acceptance-grade. New `rtl/peripherals/uart_rx.v` is
a self-contained 8N1 receiver lifted cleanly from
`obsolete/riscv_control/rtl/peripherals/phase0_uart_mmio.v` with no
MMIO baggage. New `rtl/control/phase0_uart_command.v` parses
`!N\r\n`, `!NLLLLVVVV\r\n`, and `!F\r\n` into single-cycle note and
release strobes plus parameter wires. `rtl/control/phase0_fixed_control.v`
correctly latches command parameters into the next-fire voice and
suppresses autonomous round-robin once a command arrives. The
`phase0_uart_status_tx.v` block emits a 62-byte P5M2 frame that adds
Q (command_count) and X (last_error << 16 | error_count). Four
physical voice instances and audio path internals are untouched.

Independent Quartus full compile reproduces implementer numbers:
LE 4,729 / 10,320 (39%, +753 vs M1), comb 4,492, regs 2,349, M9K 5,
DSP9 26, PLL 1, slow-85C setup `sys_clk_50m` +5.928 ns, hold +0.432 ns,
all TNS 0, 0 errors, 16 warnings (down 2 from M1; previous unused-rx
warning is gone now that `uart1_rx` is consumed).

ModelSim TBs PASS:
- `phase0_uart_command_tb`: `UART_CMD_TB_PASS notes=4 releases=1 errors=2`,
  0 errors, 0 warnings.
- `phase0_uart_status_tx_tb`: `UART_TX_TB_PASS frames=2 collected_count=170`
  with decoded `q0=12345678 x0=00030007`, 0 errors, 0 warnings.

Hardware acceptance ran clean. SOF programmed (checksum `0x0037620B`).
P5M2 frames captured with monotonic BOOT, monotonic TICK, VC in
00..03. Sent `!N`, `!N006A4000`, `!N006A7FFF`, `!F`, then malformed
`!Z`. Q delta = 4 across the send phase (4 valid commands accepted),
X low16 delta = 1 (one malformed command counted), X high16 last_error
= 0x0002 = ERR_UNKNOWN_OPCODE after the malformed `!Z`. After
reprogramming to clear command_mode, autonomous four-voice audio
remains continuous and non-clipping (peak -24.37 dBFS over 6 s).

The LE delta is +753, above the +600 target from the M2 task gate
but below the +800 hard NO-GO. I am explicitly accepting this
overrun because:
- every other gate passes with margin (setup +5.928 ns, +1.93 ns
  above the M1 baseline target),
- four physical voices and audio path internals are preserved,
- M9K/DSP/PLL counts unchanged,
- warnings reduced by 2 vs M1 (only cosmetic warnings remain),
- the extra cost is honest: a real RX primitive, a real CRLF parser
  with overlong/error/discard handling, a status-frame extension
  with new Q and X fields, and command_mode integration in
  fixed_control. None of this is hidden gold-plating.

A future cleanup could narrow the line buffer (16 -> 12 bytes), the
free-running tick counter (32 -> 24 bits), or the Q/X snapshots if
LE pressure ever returns. Not required for M2 acceptance.

## Scope check

`git show --stat 5ee0c7c`:
- new: `rtl/peripherals/uart_rx.v` (+118)
- new: `rtl/control/phase0_uart_command.v` (+330)
- new: `rtl/control/phase0_uart_command_tb.v` (+266)
- new: `reports/phase5_m2_uart_rx_command_impl.md` (+371)
- modify: `rtl/control/phase0_fixed_control.v` (+155 / parts replaced)
- modify: `rtl/peripherals/phase0_uart_status_tx.v` (+147 / parts replaced)
- modify: `rtl/peripherals/phase0_uart_status_tx_tb.v` (+165 / parts replaced)
- modify: `rtl/top/piano_phase0_top.v` (+61 / parts replaced)
- modify: `quartus/phase0/piano_phase0_top.qsf` (+2)
- modify: `docs/phase0_impl_notes.md` (+24)

10 files changed, no other live RTL/firmware/scripts/sim/obsolete
files modified. PASS.

## ASCII check

All implementer-touched files verified ASCII-only via byte-level scan
(0 non-ASCII bytes each). PASS.

## Source review

### `rtl/peripherals/uart_rx.v` (new)

- 8N1 receiver, parameterized `CLK_FREQ_HZ` (default 50 MHz) and
  `BAUD_RATE` (default 115200). Computes `BAUD_DIV` and uses mid-bit
  sampling.
- Double-flop synchronizer (`rx_meta`/`rx_sync`) on `uart_rx`. Both
  stagels reset to `1'b1` (idle line) under `!sys_rst_n`.
- 4-state FSM (IDLE / START / DATA / STOP). On STOP if `rx_sync`
  is high, presents `rx_data` and pulses `rx_valid` for one cycle;
  otherwise pulses `frame_error`.
- Sys_clk-domain only; no MMIO, no FIFO, no register-bus baggage.
  Matches the standalone primitive at obsolete
  `phase0_uart_mmio.v` line 245+ as planned by the M1 scope.

PASS.

### `rtl/control/phase0_uart_command.v` (new)

- Instantiates `uart_rx` directly. CRLF-terminated line accumulator
  with 16-byte buffer (line_len 0..16).
- Overlong recovery: if a non-CRLF byte arrives with `line_len == 14`
  or 15, the parser records ERR_OVERLONG (3), increments `error_count`
  with saturation at 0xFFFF, drops the line, sets `discarding`, and
  resyncs at the next CRLF.
- Frame-error from the RX primitive: records ERR_FRAME (4), drops
  partial line, enters discard until CRLF.
- 4-byte commands: `!N\r\n` -> `cmd_loop_len=106`, `cmd_velocity=0x7FFF`,
  `note_strobe` pulse; `!F\r\n` -> `release_strobe` pulse; `!X\r\n`
  for unknown X -> ERR_UNKNOWN_OPCODE (2); other -> ERR_MALFORMED (1).
- 12-byte commands: `!NLLLLVVVV\r\n` -> hex-decoded into
  `parsed_loop_full` and `parsed_vel_full` combinationally with
  `is_hex` and `decode_hex` helpers (case-insensitive). Loop length
  clamped to 32..127, velocity clamped to <= 0x7FFF. On invalid hex
  records ERR_UNSUPPORTED_ARG (7).
- Other CRLF-terminated lengths: classified as
  ERR_UNSUPPORTED_ARG/UNKNOWN_OPCODE/MALFORMED depending on prefix.
- All output strobes are single-cycle pulses; parameter wires hold
  the most recent valid values.
- Commands counted via `command_count` (32-bit, monotonic), errors
  via `error_count` (16-bit saturating), with `last_error` set per
  category.

PASS.

### `rtl/control/phase0_fixed_control.v` (modified)

- New input ports: `note_strobe`, `release_strobe`, `cmd_loop_len[6:0]`,
  `cmd_velocity[15:0]`. Other ports unchanged.
- `audio_enable`/`tone_enable`/`wave_sel`/`phase_step`/`gain`/
  `decay_step`/`codec_cfg_*`/voice enables/bypass/strobes/static voice
  parameters (`voice_loop_gain`, `voice_disp_coeff`, `voice_body_mix`)
  preserved byte-identical to M1 baseline.
- Per-voice `loop_len`/`velocity` are now registers
  (`voice0_loop_len_reg`/...). Default values on reset are 7'd106 and
  16'h4000 respectively, so no-command behavior matches M0/M1
  bit-identically.
- `voice_damp_mix` is now a register, default 16'd16384, raised to
  16'd32767 on `release_strobe`. The next `note_strobe` restores
  16'd16384 before triggering. Confirmed in source.
- `command_mode` register: cleared on reset, set on first
  `note_strobe` or `release_strobe`. While `command_mode` is set,
  the `sample_tick`-driven autonomous round-robin path is gated off
  (`if (sample_tick && !command_mode)`).
- On `note_strobe`: `voice_index` post-increments, the per-voice
  registers for the post-incremented voice receive `cmd_loop_len`
  and `cmd_velocity`, `tick_counter` resets, and `trigger_pulse`
  fires for one cycle.
- The per-voice `voice*_trigger_strobe` outputs are unchanged; they
  still compare `trigger_pulse && (voice_index == N)`.
- `voice_index_status` exposes the round-robin index unchanged.

Audio defaults, voice instances, and audio path semantics are
preserved. Command behavior is correct: a bare `!N` post-release
restores damp_mix to 16384 before triggering. PASS.

### `rtl/peripherals/phase0_uart_status_tx.v` (modified)

- New input ports: `command_count[31:0]`, `error_count[15:0]`,
  `last_error[15:0]`. Other ports unchanged.
- Frame length grows from 40 to 62 bytes. Format:
  `P5M2 BOOT=........ TICK=........ VC=.. Q=........ X=........\r\n`.
  M0/M1 `P5M1` tag becomes `P5M2`.
- New snapshots `q_snapshot` and `x_snapshot` captured at frame
  start (`x = {last_error[15:0], error_count[15:0]}`).
- 62 bytes at 115200 baud is ~5.4 ms drain, well under the 500 ms
  cadence. Skipped-cadence saturating counter still present.
- Byte selector now uses 7-bit `byte_index` and a 62-entry case;
  byte placements match the contract above.

PASS.

### `rtl/top/piano_phase0_top.v` (modified)

- Removes the `_unused_uart1_rx` sink. `uart1_rx` is now consumed by
  the new `phase0_uart_command_inst` block.
- Adds wires for `cmd_note_strobe`, `cmd_release_strobe`,
  `cmd_loop_len`, `cmd_velocity`, `cmd_command_count`,
  `cmd_error_count`, `cmd_last_error`.
- Instantiates `phase0_uart_command_inst` upstream of
  `phase0_fixed_control_inst`.
- Updates `phase0_fixed_control_inst` port map with the new command
  inputs.
- Updates `phase0_uart_status_tx_inst` port map with the new Q/X
  inputs.
- Audio path, codec stub, reset sync instantiations and their
  bindings are byte-identical to M1.

PASS.

### `quartus/phase0/piano_phase0_top.qsf` (modified)

- Adds `../../rtl/peripherals/uart_rx.v` and
  `../../rtl/control/phase0_uart_command.v`.
- Pin assignments unchanged. No obsolete RV32I/MMIO/firmware sources
  reintroduced.

PASS.

### Architecture guard

Four physical `phase1_reduced_voice` instances preserved in
`rtl/audio/phase0_audio_path.v` (no change to that file). Audio path
internals unchanged. PASS.

## Build / Fit / Timing evidence

Independent Quartus 13.0.1 full compile. Log saved to
`.kiro/quartus_phase5_m2_verify.log`.

| Metric | M1 baseline | M2 (this commit) | Delta |
| --- | ---: | ---: | ---: |
| Total logic elements | 3,976 / 10,320 | **4,729 / 10,320 (46%)** | +753 |
| Combinational | 3,754 | 4,492 | +738 |
| Registers | 1,908 | 2,349 | +441 |
| Memory bits | 20,480 | 20,480 | 0 |
| M9K | 5 | 5 | 0 |
| DSP9 | 26 | 26 | 0 |
| PLL | 1 / 2 | 1 / 2 | 0 |
| Setup slow-85C `sys_clk_50m` | +5.885 ns | **+5.928 ns** | +0.043 ns |
| Hold slow-85C `sys_clk_50m` | clean | +0.432 ns | clean |
| Setup `i2c_clk` | +994.629 ns | +993.949 ns | -0.680 ns |
| Setup `audio_bclk` | +315.938 ns | +315.427 ns | -0.511 ns |
| All TNS | 0 | 0 | 0 |
| Errors | 0 | 0 | 0 |
| Warnings | 18 | 16 | -2 |

The +753 LE comes from:
- ~120 LE for the `uart_rx` primitive plus its synchronizers
- ~400 LE for `phase0_uart_command` line buffer, hex helpers,
  parser FSM, `command_count`/`error_count`/`last_error` registers,
  and overlong/discard recovery
- ~120 LE for the per-voice `loop_len`/`velocity` registers and
  command-mode plumbing in `phase0_fixed_control`
- ~110 LE for the extended P5M2 frame (Q and X 8-char hex fields,
  wider byte_index, two more 32-bit snapshot registers)

This breakdown is honest. The LE budget remains comfortable: 5,591
LE free vs M2 4,729 used.

Setup slack improved slightly (+0.043 ns) versus M1 because the
extra registers gave the fitter a little more flexibility on the
existing critical path. No new timing pressure introduced.

Warnings dropped from 18 to 16 because `uart1_rx` is now consumed,
so the previous "input pin not driving logic" warning is gone, and
the `_unused_uart1_rx` reduction is no longer needed at the top.

## Quartus warnings adjudication

The 16 remaining warnings are the expected cosmetic baseline:
- Unused signal sinks at the top (`_unused_audio_path_status`).
- M9K RAM-inference info on the four reduced-voice delay lines.
- PLL clkena/extclkena inputs not connected (preexisting).
- PLL output routing on `audio_mclk` (preexisting).

No latch inference, no missing-case, no undriven nets. PASS.

## ModelSim evidence

Compiled and ran under `.kiro/msim_m2/`:

```
vlib work
vlog -quiet rtl/peripherals/uart_rx.v rtl/peripherals/uart_tx.v rtl/peripherals/phase0_uart_status_tx.v rtl/peripherals/phase0_uart_status_tx_tb.v rtl/control/phase0_uart_command.v rtl/control/phase0_uart_command_tb.v
vsim -c -lib work phase0_uart_command_tb -do "run -all; quit -f"
vsim -c -lib work phase0_uart_status_tx_tb -do "run -all; quit -f"
```

### `phase0_uart_command_tb`

```
# UART_CMD_TB_PASS notes=4 releases=1 errors=2
# ** Note: $finish    : rtl/control/phase0_uart_command_tb.v(257)
# Errors: 0, Warnings: 0
```

4 valid note commands accepted, 1 release accepted, 2 errors counted
(matches the malformed/overlong injection pattern in the TB).

### `phase0_uart_status_tx_tb`

```
# UART_TX_TB_INFO boot0=00000001 boot1=00000002
# UART_TX_TB_INFO q0=12345678
# UART_TX_TB_INFO x0=00030007
# UART_TX_TB_PASS frames=2 collected_count=170
# ** Note: $finish    : rtl/peripherals/phase0_uart_status_tx_tb.v(321)
# Errors: 0, Warnings: 0
```

Two complete 62-byte P5M2 frames decoded mid-bit at 115200 baud, with
correct BOOT increment, decoded `q0=0x12345678` (driven test value)
and `x0=0x00030007` (last_error 3, error_count 7 - matches stimulus).

The reduced-voice golden TB at `rtl/audio/phase1_reduced_voice_tb.v`
was not rerun; M2 makes no audio-path changes and that TB was last
accepted at the Phase 4 M7 acceptance run. Justification matches
implementer report.

## Hardware acceptance

JTAG and COM5 visible (`USB-Blaster [USB-0]`, `COM5`).

### UART command session

Programmed M2 SOF (`0x0037620B`). Captured COM5 at 115200 8N1 with
`.kiro/phase5_m2_uart_session.py`. Sequence: 1.5 s pre-command
capture, send `!N`, `!N006A4000`, `!N006A7FFF`, `!F`, `!Z` with
~150 ms spacing, 3 s post-command capture. Saved to
`reports/phase5_m2_uart.txt`.

Decoded P5M2 frames:

| phase | t (s) | BOOT | TICK | VC | Q | X |
| --- | ---: | --- | --- | --- | --- | --- |
| PRE  | 0.578 | 0000003C | 00157512 | 01 | 00000000 | 00000000 |
| PRE  | 1.094 | 0000003D | 0015D09F | 03 | 00000000 | 00000000 |
| PRE  | 1.594 | 0000003E | 00162C2D | 00 | 00000000 | 00000000 |
| POST | 2.594 | 0000003F | 001687BA | 03 | 00000002 | 00000000 |
| POST | 2.594 | 00000040 | 0016E348 | 00 | 00000004 | 00020001 |
| POST | 3.078 | 00000041 | 00173ED5 | 00 | 00000004 | 00020001 |
| POST | 3.594 | 00000042 | 00179A63 | 00 | 00000004 | 00020001 |
| POST | 4.094 | 00000043 | 0017F5F0 | 00 | 00000004 | 00020001 |
| POST | 4.594 | 00000044 | 0018517E | 00 | 00000004 | 00020001 |
| POST | 5.094 | 00000045 | 0018AD0B | 00 | 00000004 | 00020001 |

Checks:
- BOOT increments by exactly 1 each frame: PASS
- TICK strictly monotonic, ~0x5B8D delta per 500 ms frame: PASS
- VC stays in 00..03: PASS
  - In the PRE phase (autonomous mode), VC walks 01->03->00 as the
    round-robin advances every ~350 ms.
  - After the first command, command_mode goes high and autonomous
    cadence is suppressed. Final VC = 00 reflects that the
    post-command voice_index has wrapped through 0..3 and parked at
    0 because the trigger from `!F` does not advance voice_index;
    matches the design.
- Q delta across send phase = 4: matches 4 valid commands
  (`!N`, `!N006A4000`, `!N006A7FFF`, `!F`)
- X low16 delta = 1: matches 1 malformed command (`!Z`)
- X high16 last_error = 0x0002 (ERR_UNKNOWN_OPCODE) after `!Z`: PASS

Frame cadence stable at 0.5000 s across post-command intervals.
PASS.

### Audio capture

After the command session ended in command_mode (autonomous off,
last action was release), the audio path is correctly damped. To
verify command_mode does not introduce a regression in the
autonomous path, the board was reprogrammed (clearing command_mode)
and 6 s of analog audio captured at the 3.5 mm jack into
`reports/phase5_m2_autonomous_audio.wav`.

Per-second analysis:

| s | peak | peak (dBFS) | RMS | RMS (dBFS) |
| ---: | ---: | ---: | ---: | ---: |
| 0 | 1892 | -24.77 | 488.2 | -36.54 |
| 1 | 1954 | -24.49 | 588.8 | -34.91 |
| 2 | 1728 | -25.56 | 492.3 | -36.46 |
| 3 | 1910 | -24.69 | 525.1 | -35.90 |
| 4 | 1932 | -24.59 | 623.8 | -34.41 |
| 5 | 1981 | -24.37 | 601.5 | -34.72 |

Overall peak -24.37 dBFS, RMS -35.41 dBFS. No clipping anywhere.
Continuous output across the entire 6 s capture, consistent with the
autonomous round-robin sequencer. Level matches M1 (-24.94 dBFS)
within mic-input variation. No regression from M0/M1.

A second 6 s capture during the command session
(`reports/phase5_m2_audio.wav`) shows peak -23.94 dBFS, RMS
-35.75 dBFS, also non-clipping; the audio responds to commands and
the `!F` release damping does not cause silence within the 6 s
capture window because the post-command voice was still ringing.

PASS.

## LE-target overrun adjudication

Target was <= +600; actual is +753; hard NO-GO was +800.

Considerations:
- The +153 overrun is honest paper-vs-actual variance: the M2 task
  paper estimate was for "small RX command parser plus Q/X status
  frame extension". Implementation includes:
  - Real RX primitive (~120 LE)
  - Full CRLF parser FSM with overlong/discard recovery and 16-byte
    line buffer (~400 LE)
  - Per-voice loop_len/velocity registers and command_mode logic
    in `phase0_fixed_control` (~120 LE)
  - 22 extra ASCII frame bytes plus two new 32-bit snapshot
    registers in the status TX (~110 LE)
- Setup slack improved (+0.043 ns above M1). No timing pressure.
- Quartus warnings are net lower (16 vs 18). No new warning categories.
- M9K, DSP9, and PLL counts all unchanged.
- Counter widths and the line buffer can be narrowed in a future
  cleanup if pressure returns: line buffer 16->12 saves ~30 LE,
  free-running tick counter 32->24 saves a small amount, etc.
- Hardware command-and-error behavior is correct end-to-end on the
  first verifier hardware run.

I accept the overrun for M2 because every other gate is comfortable
and the function delivered (real RX command parsing with end-to-end
hardware verification) is the right M2 behavior.

## Compatibility / next steps

- Phase 3 host wrappers (`scripts/phase3_m5_keyboard.py`,
  `scripts/phase3_m6_live_play.py`,
  `scripts/phase3_m7_track_release.py`,
  `scripts/phase3_m9_interactive.py`) now have a working board to
  drive again. The M2 status-frame Q/X tags map cleanly to the
  command-count/error-count semantics the host wrappers were
  originally designed against.
- Per-voice independent release and LRU/voice-stealing semantics
  remain deferred (M3+).
- The status frame still does not expose `skipped_count` from the
  TX block; if audible-cadence drops are ever observed, that field
  could be folded into the next frame revision.

## Final verdict

**PASS with LE-target overrun adjudication.** Phase 5 M2 RTL UART RX
command parser is acceptance-grade. The hardware now accepts CRLF
commands `!N`, `!NLLLLVVVV`, and `!F` and correctly increments Q on
valid commands and X on malformed input, with last_error coded as
specified. Audio remains continuous and non-clipping in both
autonomous and command-driven modes.

Validation commit will include only this report. Orchestrator may
queue Phase 5 M3 (per-voice release and/or LRU stealing, plus any
desired counter cleanup) without revisiting M2.
