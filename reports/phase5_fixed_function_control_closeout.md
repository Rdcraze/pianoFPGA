# Phase 5 Fixed-Function Control Closeout

Date: 2026-05-24
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-b19e36cb`
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `a749c64`

## TL;DR

Phase 5 has fully delivered the fixed-function control pivot the
user requested. The RISC-V SoC + firmware C + MMIO bus + register
file control stack has been retired; a small RTL controller plus
two tiny RTL UART blocks now own everything that the legacy CPU
firmware did. UART telemetry and host-driven note commands are both
restored on hardware. The four physical voice instances and the
audio path internals are bit-exact to the accepted Phase 4 M7
baseline.

The four sub-milestones completed since the pivot started are all
hardware-accepted by the verifier:

- M0 (commit `5124dba`, validation `3217b81`): flatten architecture,
  archive RV32I/firmware/MMIO under `obsolete/riscv_control/`.
- M1 (commit `9c976ff`, validation `473b2f3`): tiny RTL UART TX
  emits `P5M1` status frames at ~500 ms cadence.
- M2 (commit `5ee0c7c`, validation `c224cc9`): tiny RTL UART RX
  command parser; status frame extends to `P5M2` with command and
  error fields.
- M3 (commit `f52ac3e`, validation `a749c64`): existing Phase 3
  host wrappers validated unchanged against the live M2 board on
  hardware. No regressions found.

This closeout summarizes the live architecture, accepted protocol,
remaining deferred work, and recommended next steps for any future
phase.

## 1. Live architecture

The current live design (HEAD `a749c64`) consists of these RTL
blocks, all instantiated by `rtl/top/piano_phase0_top.v`:

| Live module | Path | Role |
| --- | --- | --- |
| `phase0_reset_sync` | `rtl/peripherals/phase0_reset_sync.v` | sys_clk reset release |
| `phase0_fixed_control` | `rtl/control/phase0_fixed_control.v` | fixed RTL controller; audio defaults, voice round-robin, command-driven note path, damp-mix register |
| `phase0_uart_command` | `rtl/control/phase0_uart_command.v` | CRLF-terminated command parser FSM; emits note/release strobes plus parameter wires |
| `uart_rx` | `rtl/peripherals/uart_rx.v` | 8N1 115200 receiver; double-flop sync, mid-bit sample, frame-error pulse |
| `phase0_uart_status_tx` | `rtl/peripherals/phase0_uart_status_tx.v` | ~500 ms cadence ASCII frame transmitter; instantiates `uart_tx` |
| `uart_tx` | `rtl/peripherals/uart_tx.v` | 8N1 115200 transmitter |
| `phase0_audio_path` | `rtl/audio/phase0_audio_path.v` | four `phase1_reduced_voice` instances + mix tree + saturation |
| `phase1_reduced_voice` | `rtl/audio/phase1_reduced_voice.v` | digital waveguide reduced voice; instantiated four times as `phase1_reduced_voice_inst`, `phase1_reduced_voice1_inst`, `phase1_reduced_voice2_inst`, `phase1_reduced_voice3_inst` |
| `phase0_body_filter` | `rtl/audio/phase0_body_filter.v` | per-voice body coloration |
| `wm8978_codec_stub` | `rtl/peripherals/wm8978_codec_stub.v` | codec wrapper; instantiates the boot sequencer, I2S TX, and PLL |
| `wm8978_boot_seq` | `rtl/peripherals/wm8978_boot_seq.v` | I2C boot writes |
| `wm8978_i2c_ctrl` | `rtl/peripherals/wm8978_i2c_ctrl.v` | I2C master |
| `wm8978_dac_tx` | `rtl/peripherals/wm8978_dac_tx.v` | I2S DAC TX |
| `phase0_audio_mclk_pll` | `rtl/peripherals/phase0_audio_mclk_pll.v` | PLL for codec MCLK |

### Obsolete / archived components

The following blocks are intentionally removed from the live
top-level and source list and remain only under
`obsolete/riscv_control/` for reference:

| Archived module | Replacement |
| --- | --- |
| `phase0_rv32i_core.v` | gone; control is hardwired or driven from `phase0_uart_command` |
| `phase0_boot_rom.v` | gone; no firmware |
| `phase0_data_ram.v` | gone; no firmware state |
| `phase0_rv32i_soc.v` | gone; no SoC fabric |
| `phase0_control_regs.v` | folded into `phase0_fixed_control` defaults and registers |
| `phase0_uart_mmio.v` | split into `uart_rx`/`uart_tx` primitives plus `phase0_uart_command` and `phase0_uart_status_tx` |
| `fw/phase0/*.c`, `fw/phase0/*.S`, `fw/phase0/*.ld`, `fw/phase0/build.ps1`, `phase0_fw.mif`, `phase0_fw.hex`, `phase0_fw.mem` | no firmware build is part of the live flow; reference command parser semantics live in `obsolete/riscv_control/fw/phase0/phase0_main.c` |

`obsolete/riscv_control/` is preserved with full git history
(`git mv` rename similarity 100%) so any future task can re-read
the legacy stack without recovering it from git history.

### Audio synthesis is intentionally unchanged

The Phase 4 M7 acceptance baseline of the audio path remains the
live audio path. Verified via `phase1_reduced_voice_tb` golden TB
running bit-exact at `peak=3952` after every Phase 5 milestone
(M0, M1, M2). Static voice parameters in `phase0_fixed_control`:

- `loop_gain = 16'd32640`
- `damp_mix = 16'd16384` default (raised to `16'd32767` on `!F`,
  restored to default on next `!N`)
- `disp_coeff = 16'sd9952`
- `body_mix = 16'd8192`
- `phase_step = 24'd157482`
- `gain = 16'd4096`
- `decay_step = 16'd0`
- `wave_sel = 2'b00`
- per-voice `loop_len[6:0]` register (default 7'd106 = ~A4) and
  `velocity[15:0]` register (default 16'h4000). Updated only on
  `!N`/`!NLLLLVVVV` strobes for the post-incremented voice.

## 2. Live UART protocol

### Status frame (board -> host)

Fixed-length 62-byte ASCII frame at ~500 ms cadence on `uart1_tx`
at 115200 8N1:

```
P5M2 BOOT=XXXXXXXX TICK=XXXXXXXX VC=XX Q=XXXXXXXX X=XXXXXXXX\r\n
```

| Field | Semantics |
| --- | --- |
| `P5M2` | milestone tag, easy host grep |
| `BOOT=XXXXXXXX` | 32-bit monotonic frame counter (one increment per emitted frame) |
| `TICK=XXXXXXXX` | 32-bit `sample_tick` counter snapshot at frame start |
| `VC=XX` | 8-bit hex of the round-robin voice index 00..03 (the next voice the sequencer will fire) |
| `Q=XXXXXXXX` | 32-bit `command_count` snapshot |
| `X=XXXXXXXX` | `{last_error[15:0], error_count[15:0]}` snapshot |

### Command grammar (host -> board)

CRLF-terminated ASCII commands on `uart1_rx` at 115200 8N1:

| Command | Length (bytes) | Effect |
| --- | ---: | --- |
| `!N\r\n` | 4 | Note with default parameters: `loop_len = 106`, `velocity = 0x7FFF`. Emits one `note_strobe` pulse to the next voice. |
| `!NLLLLVVVV\r\n` | 12 | Parameterized note. `LLLL` = 4 hex digits of `loop_len`, clamped to 32..127. `VVVV` = 4 hex digits of `velocity`, clamped to 0..0x7FFF. Hex case-insensitive. |
| `!F\r\n` | 4 | Release. Emits one `release_strobe` pulse and raises shared `voice_damp_mix` to `16'd32767`. No trigger. Next `!N` restores default damp. |

### Error codes (X high 16 bits)

| Code | Meaning |
| ---: | --- |
| 0 | none |
| 1 | malformed (no leading `!`) |
| 2 | unknown opcode (`!X` for unrecognized X) |
| 3 | overlong line (>= 16 bytes total before CRLF) |
| 4 | UART RX frame error |
| 7 | unsupported argument (bad hex in `!NLLLLVVVV`) |

### Behavioral notes

- Once any valid command is received, `phase0_fixed_control` latches
  `command_mode` and suppresses the autonomous round-robin
  sequencer. After power-on, the autonomous demo runs until the
  first command, providing a useful "is the board alive" indicator.
- `command_count` is monotonic; `error_count` is saturating at
  `0xFFFF`; `last_error` reads the most recent recorded code.
- Command bytes that arrive faster than the parser drains the line
  buffer (16 bytes including CRLF) trigger ERR_OVERLONG (code 3)
  and resync at the next CRLF. At 80-200 ms inter-command delay
  used by the host wrappers, no overlong has been observed.

## 3. M0..M3 acceptance evidence

Each milestone is recorded in two reports: an implementer report
and a verifier validation. Cite paths only; do not paste large
content here.

### M0 - architecture flatten

- Implementer: `reports/phase5_m0_fixed_control_flattening.md`
- Verifier validation: `reports/phase5_m0_fixed_control_flattening_validation.md`
- Resource impact: LE 10,099 -> 3,614 (-65%); setup slow-85C
  `sys_clk_50m` +2.846 ns -> +5.539 ns; M9K 5; DSP9 26; PLL 1; all
  TNS 0.

### M1 - tiny RTL UART TX status frames

- Implementer: `reports/phase5_m1_uart_status_tx_impl.md`
- Verifier validation: `reports/phase5_m1_uart_status_tx_validation.md`
- Hardware capture: `reports/phase5_m1_uart.txt` (verifier-protected)
- Resource impact: LE 3,614 -> 3,976 (+362); setup +5.539 -> +5.885
  ns; warnings 20 -> 18; M9K/DSP9/PLL unchanged.

### M2 - tiny RTL UART RX command parser plus P5M2

- Implementer: `reports/phase5_m2_uart_rx_command_impl.md`
- Verifier validation: `reports/phase5_m2_uart_rx_command_validation.md`
- Hardware capture: `reports/phase5_m2_uart.txt` (verifier-protected)
- Resource impact: LE 3,976 -> 4,729 (+753; soft target was +600,
  hard cap +800); setup +5.885 -> +5.928 ns; warnings 18 -> 16;
  M9K/DSP9/PLL unchanged.

### M3 - host-wrapper compatibility

- Implementer: `reports/phase5_m3_host_wrapper_validation.md`
- Verifier validation: `reports/phase5_m3_host_wrapper_validation_validation.md`
- New helper: `scripts/phase5_m3_p5m2_decode.py`
- Hardware evidence (cited from verifier validation):
  - All four wrappers' self-checks PASS.
  - Live serial sessions on COM5 (SOF `0x0037620B`):
    - M5 sent 3 commands, Q delta 3, X stable.
    - M6 sent 6 commands, Q delta 6, X stable.
    - M7a sent 3 commands (suppressed `up:A4` during overlap),
      Q delta 3, X stable.
    - M9 sent 5 commands, Q delta 5, X stable.
  - Cross-session Q advanced 0 -> 3 -> 9 -> 12 -> 17 cleanly.
  - 6 s analog audio capture: peak -24.13 dBFS, RMS -35.87 dBFS,
    no clipping, continuous output, no regression vs M0/M1/M2.
- Conclusion: round-robin vs LRU divergence is invisible at the
  4-voice / quick-decay scale of these wrappers' command bursts.

## 4. Final live resource and timing point

After M3 verifier acceptance (no RTL change in M3, so M2 numbers
remain the live numbers):

| Metric | Value |
| --- | --- |
| Total logic elements | 4,729 / 10,320 (46%) |
| Combinational | 4,492 |
| Registers | 2,349 |
| Memory bits | 20,480 |
| M9K equivalent | 5 |
| Embedded multiplier 9-bit | 26 |
| PLL | 1 / 2 |
| Setup slow-85C `sys_clk_50m` | +5.928 ns |
| Hold slow-85C | +0.432 ns |
| All TNS | 0 |
| Quartus errors | 0 |
| Quartus warnings | 16 (cosmetic only) |

Free LE budget: 5,591 (54%). Setup margin above the +4.0 ns hard
target: +1.928 ns. Architecture guard intact: four physical voice
instances in `rtl/audio/phase0_audio_path.v`.

## 5. Validated host wrappers

| Wrapper | Source | Self-check | Live hardware (M3 verifier) |
| --- | --- | --- | --- |
| keyboard MIDI mapper | `scripts/phase3_m5_keyboard.py` | PASS (88 notes + name equiv + release aliases) | PASS (3 commands, Q delta 3) |
| live play sequencer | `scripts/phase3_m6_live_play.py` | PASS (note name, velocity override, release/bare/raw passthrough, CRLF) | PASS (6 commands, Q delta 6) |
| track-and-release | `scripts/phase3_m7_track_release.py` | PASS (overlap, count, panic, repeat, velocity, CRLF, MIDI number) | PASS (3 commands; suppressed up:A4 mid-overlap) |
| interactive stdin | `scripts/phase3_m9_interactive.py` | PASS (sequences, panic, off after off, bare, CRLF, quit-with-active) | PASS (5 commands, Q delta 5) |
| P5M2 decoder | `scripts/phase5_m3_p5m2_decode.py` (new) | PASS (6 vectors) | PASS (re-decoded M2 capture, decoded all 4 wrapper sessions) |

## 6. Deferred / out of scope

The following items were explicitly deferred during M0-M3 and
remain available for future phases:

| Deferred item | Why deferred | Reasonable trigger |
| --- | --- | --- |
| LRU / voice-stealing voice assignment | Round-robin works at 4-voice / quick-decay scale; no audible regression measured | Sustained-chord stress test that produces audible artifacts |
| Per-voice independent release | Shared-damp `!F` matches old firmware and host wrapper M7a/M9 design; per-voice would regress the wrappers | Concrete musical request that needs different release for distinct voices |
| Larger telemetry surface | Old firmware exposed multi-tag debug counters; M2 keeps only BOOT/TICK/VC/Q/X, which suffice for compatibility validation | Specific debug task that needs per-voice diagnostic counters |
| Sustained-chord stress test | Not part of M0-M3 scope; M3 wrappers do not generate >4-voice load | Audible artifact suspected, or pre-feature gate for LRU |
| LE cleanup (line buffer 16->12, counter narrowing) | 50-100 LE plausible savings; current free budget 5,591 LE makes the risk/reward poor | A future feature pushes against an LE gate |
| Body-filter coloration knobs | Not in M0-M3; not host-wrapper-blocking | A future musical-expression slice |
| External SDRAM (Phase 4 plan item) | M7 voice depth and the four-voice mix fit comfortably in on-chip M9K | Voice count or sample-table demand exceeds on-chip memory |
| Display / touch UI (Phase 5+ original plan) | Out of M0-M3 scope; the architecture pivot focused on control-path simplification | A separate phase explicitly scoped for UI |

## 7. Recommended next steps

In decreasing priority:

1. **Closeout / no-op acceptance.** Record M3 acceptance, mark
   Phase 5 as the architectural-pivot milestone, and stage the
   project for a deliberate next-phase scoping decision rather than
   a continuous RTL slice cadence. This closeout report is the
   recommended landing point.
2. **Optional: sustained-chord stress test slice (host-tool only,
   no RTL).** Drive 5+ rapid `!N` commands per second over COM5
   to force voice-stealing conditions and measure whether
   round-robin causes audible artifacts. The result would decide
   whether a future LRU RTL slice is needed. ETA: 0.5-1 day, no LE
   cost, no setup-slack risk.
3. **Optional: feature work driven by concrete musical or
   integration need.** Examples: body-filter coloration knob,
   additional command (volume, voice select), Phase 6 display/touch
   bring-up. Each should be a separate scope task with explicit
   acceptance gates.
4. **Avoid speculative LE cleanup or speculative LRU/per-voice
   release.** The free LE budget (54%) and the absence of M3-side
   audio regression evidence both point against unprompted RTL
   investment.

The current branch `codex/phase1c-uart-boundary-fix` is in a
shippable state: hardware-accepted at M2 (UART RX) and M3 (host
wrapper compatibility), with golden TB still bit-exact and no
audio regression.

## 8. Out of scope for this closeout

- No RTL/QSF/firmware change. No `obsolete/` archive change.
- No host wrapper change. No `scripts/phase5_m3_p5m2_decode.py`
  change.
- No hardware run.
- No Quartus run.

ASCII-only.
