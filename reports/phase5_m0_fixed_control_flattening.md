# Phase 5 M0 Fixed-Function Control Flattening

Date: 2026-05-24
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-67d1d75b`
Branch: `codex/phase1c-uart-boundary-fix`
Parent commit: `e90a820`

## TL;DR

**PASS.** The Phase 5 M0 architecture pivot is complete. The layered
RISC-V SoC + firmware C + MMIO bus + register-file control stack has
been replaced with a single fixed-function RTL controller
(`rtl/control/phase0_fixed_control.v`) that drives the existing audio
and codec wires directly. Quartus 13.0.1 full compile passes with
**LE 3,614 / 10,320 (35%)**, **setup slack +5.539 ns**, no errors, and
20 warnings (all expected: unused-signal sinks, baseline RAM-inference,
stuck-output on idle UART TX, and PLL routing warnings carried over
from the prior baseline).

| Metric | Pre-pivot baseline (`e90a820`) | Post-pivot (this commit) | Delta |
| --- | ---: | ---: | ---: |
| Total logic elements | 10,099 / 10,320 (98%) | **3,614 / 10,320 (35%)** | **-6,485** |
| Combinational functions | 9,487 | 3,405 | -6,082 |
| Dedicated logic registers | 4,237 | 1,751 | -2,486 |
| Memory bits | 86,016 | 20,480 | -65,536 |
| Embedded multiplier 9-bit | 28 | 26 | -2 |
| PLLs | 1 / 2 | 1 / 2 | 0 |
| Slow-85C setup `sys_clk_50m` | +2.846 ns | **+5.539 ns** | +2.693 ns |
| All TNS | 0 | 0 | 0 |
| Quartus errors | 0 | 0 | 0 |
| Quartus warnings | 16 | 20 | +4 (cosmetic, see below) |
| Firmware ROM gate | 931 / 1024 | n/a (firmware archived) | n/a |

The CPU + firmware + MMIO + register-file consumed roughly two-thirds
of the prior LE budget. Removing it returns the project to a comfortable
hardware posture for Phase 4 audio-fidelity work that previously had to
fight the 328-LE margin.

## Architecture Change

### Before

```
sys_clk_50m -> phase0_rv32i_soc (CPU + boot ROM + data RAM + UART MMIO)
                           |
                           v
                phase0_control_regs (register file with addr/decode/strobes/readback)
                           |
                           v
                phase0_audio_path / wm8978_codec_stub
```

Firmware in `fw/phase0/` boots the CPU, programs the WM8978 follow-on
registers, and runs a periodic round-robin trigger loop with telemetry
on UART1. Host tools in `scripts/` can send accepted note commands
back over UART1 RX into `phase0_uart_mmio`.

### After

```
sys_clk_50m -> phase0_fixed_control (RTL constants + small RR sequencer)
                           |
                           v
                phase0_audio_path / wm8978_codec_stub
```

The fixed controller hardwires every signal that `phase0_control_regs`
previously drove and runs a small `sample_tick`-paced round-robin
trigger sequencer over the existing four physical voices. The
`wm8978_codec_stub` boot sequencer continues to own its own I2C
bring-up; the controller therefore ties `codec_cfg_valid` low.

### Files Changed

Live source changes:
- new file: `rtl/control/phase0_fixed_control.v`
- modify: `rtl/top/piano_phase0_top.v`
- modify: `quartus/phase0/piano_phase0_top.qsf`
- modify: `quartus/phase0/build.ps1` (drop firmware build step)

Archived legacy files (preserved, not deleted) under
`obsolete/riscv_control/`:
- `obsolete/riscv_control/rtl/control/phase0_boot_rom.v`
- `obsolete/riscv_control/rtl/control/phase0_data_ram.v`
- `obsolete/riscv_control/rtl/control/phase0_rv32i_core.v`
- `obsolete/riscv_control/rtl/control/phase0_rv32i_soc.v`
- `obsolete/riscv_control/rtl/control/phase0_control_regs.v`
- `obsolete/riscv_control/rtl/peripherals/phase0_uart_mmio.v`
- `obsolete/riscv_control/fw/phase0/` (full firmware tree)

All moves were performed via `git mv`, so git ancestry / blame for the
archived files is preserved.

Other peripheral RTL kept live and untouched: `phase0_reset_sync.v`,
`phase0_audio_mclk_pll.v`, `wm8978_codec_stub.v`, `wm8978_boot_seq.v`,
`wm8978_dac_tx.v`, `wm8978_i2c_ctrl.v`. `rtl/peripherals/uart_tx.v`
remains in the source tree as a reusable peripheral but is no longer
referenced by the live QSF; the M0 controller drives `uart1_tx` idle
high directly.

## Fixed Controller Design

`rtl/control/phase0_fixed_control.v` is a single-file, sys_clk-domain
RTL block. Key design points:

1. **Hardwired audio defaults**, mirroring the accepted M5/M7 reset
   defaults from `phase0_control_regs`:
   - `audio_enable = 1'b1`, `tone_enable = 1'b1`, `wave_sel = 2'b00`.
   - `phase_step = 24'd157482`, `gain = 16'd4096`, `decay_step = 16'd0`.
   - `voice*_enable = 1'b1` for all four physical voices.
   - `voice_loop_len = voice0_loop_len = ... = voice3_loop_len = 7'd106`.
   - `voice_velocity = voice0_velocity = ... = voice3_velocity = 16'h4000`.
   - `voice_loop_gain = 16'd32640`, `voice_damp_mix = 16'd16384`,
     `voice_disp_coeff = 16'sd9952`, `voice_body_mix = 16'd8192`.
   - `voice_body_bypass = voice_disp_bypass = 1'b0`.
   - All reset / clip-clear / diag-clear strobes tied 0.

2. **Round-robin trigger sequencer**. A 14-bit counter increments on
   every `sample_tick` and emits one trigger every 16,384 sample ticks
   (~349 ms at the accepted 46.875 kHz rate), cycling through
   `voice0 -> voice1 -> voice2 -> voice3`. This deliberately echoes
   the firmware-managed round-robin demo cadence from M2a so the board
   still produces continuous audible output without firmware. The
   exact cadence is documented but not load-bearing.

3. **Codec config tied off**: `codec_cfg_valid = 1'b0`,
   `codec_cfg_word = 16'd0`. `wm8978_codec_stub` already owns its own
   I2C boot sequence; no post-boot codec writes are needed today.

4. **`uart1_tx` driven idle high (RS-232 mark)**. `uart1_rx` is left
   unconsumed in M0; a single unloaded reduction in the top level
   sinks it so the synthesizer does not flag an unused input pin.

5. **Velocity threshold note**: the current default velocity 16'h4000
   is below the M7 layer-1 threshold 16'h6000, so all four voices fire
   the layer-0 hammer curve. This matches the verified bit-exact
   reduced-voice golden-sample TB behavior. A later milestone can lift
   this to 16'h7FFF or any production-equivalent value once a
   higher-velocity hardware capture is desired.

## What UART Functionality Is Retained, Deferred, or Lost

| Capability | Pre-pivot | Post-pivot | Notes |
| --- | --- | --- | --- |
| Continuous audible four-voice output at boot | yes (firmware loop) | yes (RTL sequencer) | exact cadence is implementation-defined |
| WM8978 boot sequence | yes | yes | unchanged, owned by `wm8978_codec_stub` |
| UART1 TX status frames (`I/S/R/V/F/T/...`) | yes | **deferred** | controller drives `uart1_tx` idle high |
| UART1 RX command parsing (`!N`, `!NLLLLVVVV`, `!F`) | yes | **deferred** | `uart1_rx` is currently unconsumed |
| Host wrappers (M5/M6/M7a/M9) | live | **legacy** | scripts remain in `scripts/` but cannot drive the board until a tiny RTL UART block is added |
| Per-voice runtime retune over UART | yes | **deferred** | will return when a small RTL command parser is implemented |
| Velocity-layered hammer (M7) | live | live | per-voice velocity is hardwired in M0 to 16'h4000 (layer 0); change a single localparam to expose layer 1 |

The Phase 3 host wrappers `scripts/phase3_m5_keyboard.py`,
`scripts/phase3_m6_live_play.py`, `scripts/phase3_m7_track_release.py`,
and `scripts/phase3_m9_interactive.py` still produce valid M3a-style
UART command bytes on stdout. They will be useful again when a small
RTL UART RX command block reimplements the accepted command subset.
Until then they are documentation/host-side regression tools only.

## Validation

### Static source check

```
PS> git status --short -- rtl/ quartus/ obsolete/ docs/
M quartus/phase0/build.ps1
M quartus/phase0/piano_phase0_top.qsf
M rtl/top/piano_phase0_top.v
?? rtl/control/phase0_fixed_control.v
R  rtl/control/phase0_boot_rom.v -> obsolete/riscv_control/rtl/control/phase0_boot_rom.v
R  rtl/control/phase0_control_regs.v -> obsolete/riscv_control/rtl/control/phase0_control_regs.v
R  rtl/control/phase0_data_ram.v -> obsolete/riscv_control/rtl/control/phase0_data_ram.v
R  rtl/control/phase0_rv32i_core.v -> obsolete/riscv_control/rtl/control/phase0_rv32i_core.v
R  rtl/control/phase0_rv32i_soc.v -> obsolete/riscv_control/rtl/control/phase0_rv32i_soc.v
R  rtl/peripherals/phase0_uart_mmio.v -> obsolete/riscv_control/rtl/peripherals/phase0_uart_mmio.v
R  fw/phase0/* -> obsolete/riscv_control/fw/phase0/*
```

`rtl/control/` after the move contains only `phase0_fixed_control.v`.
`fw/` is removed at the live root. The QSF lists only live synthesis
sources (`phase0_fixed_control.v` is in; the obsolete CPU/MMIO/firmware
files are out).

### Quartus full compile

Command: `.\build.ps1 -Stage compile` (firmware build step removed).

Result: 0 errors, 20 warnings, full compile elapsed 0:00:38, total CPU
time 0:00:17. Full log at `.kiro/quartus_phase5_m0.log` (local-only).

Detailed numbers above. Notable warnings:

- 2 unused-signal warnings on the deliberate `_unused_uart1_rx` and
  `_unused_audio_path_status` sinks at the top level. These are
  intentional and documented.
- 8 RAM-inference warnings on the four `phase1_reduced_voice` delay
  lines. These are unchanged from the accepted baseline.
- 1 stuck-output warning on `uart1_tx` (held high in M0).
- 1 input-pin-not-driving-logic warning on `uart1_rx` (unused in M0).
- 2 PLL clkena/extclkena unused-input warnings, preexisting.
- 2 PLL output-routing warnings on `audio_mclk`, preexisting.

No latch inference, no missing-case, no undriven nets.

### Firmware build

Skipped intentionally. The firmware build flow has been archived under
`obsolete/riscv_control/fw/phase0/` and is no longer part of the live
project. ROM word count is no longer an active gate. The previously
accepted ROM word count (931) is preserved in the archived
`phase0.bin`/`phase0.mem` build outputs for reference.

### ModelSim / simulation

Skipped intentionally for this M0 pivot.

The existing reduced-voice golden-sample testbench
`rtl/audio/phase1_reduced_voice_tb.v` exercises a single
`phase1_reduced_voice` instance directly and does not depend on the
SoC/MMIO/firmware path, so it remains valid going forward. Top-level
testbenches `rtl/top/piano_phase0_top_tb.v` and the older
`phase1c_uartrx_work` / `phase1c_roundrobin_work` workareas reference
the previous SoC + UART MMIO architecture and require the archived
files to compile; they should be considered legacy until a Phase 5 M1
or later milestone adds a fixed-control TB.

This task is intentionally scoped to architecture flattening; running
or rewriting the legacy SoC TBs is deferred to verifier acceptance and
the next milestone.

### Hardware

Not run by implementer. Verifier will program the new SOF and confirm:

1. Continuous four-voice audible output without firmware.
2. WM8978 boot completes (analog output present).
3. `uart1_tx` is idle (no telemetry expected).
4. No clipping at the new default amplitudes.

### ASCII

`rtl/control/phase0_fixed_control.v`, `rtl/top/piano_phase0_top.v`,
`quartus/phase0/piano_phase0_top.qsf`, `quartus/phase0/build.ps1`,
`reports/phase5_m0_fixed_control_flattening.md`, and the documentation
updates are ASCII-only.

### Architecture guard

Four physical voice instances preserved in `rtl/audio/phase0_audio_path.v`:
`phase1_reduced_voice_inst`, `phase1_reduced_voice1_inst`,
`phase1_reduced_voice2_inst`, `phase1_reduced_voice3_inst`. Verified
unchanged via `git diff` showing zero changes in the audio path
module.

## Roadmap Updates

- `docs/project_brief.md`: revised the Goal/Architecture section so
  the project no longer states "RISC-V soft core for control-plane
  duties" as the intended architecture. The project brief now reflects
  the fixed-function RTL control approach as the live architecture and
  classifies the prior CPU + firmware + MMIO stack as legacy.
- `docs/phase0_impl_notes.md`: appended a Phase 5 M0 update section
  describing the new live architecture and pointing to
  `obsolete/riscv_control/` for the archived stack.

## Compatibility Loss

Anything that depended on the live UART command/telemetry path is
currently inactive:

- Phase 3 M3a/M3b parameterized note commands (`!NLLLLVVVV`).
- Phase 3 M4 release command (`!F`).
- Phase 3 M5 host keyboard mapper, M6 live-play, M7a track-and-release,
  and M9 interactive wrappers can still produce valid command strings
  but those bytes are not consumed by the board in M0.
- Phase 3 verifier UART telemetry tags (`I/S/R/V/F/T/...`) are not
  emitted.
- Phase 4 M7 velocity-layered hammer: layer 0 is hardwired today
  because the M0 default velocity is 16'h4000. The layer-1 path is
  intact in the synthesized RTL and will trigger if the controller's
  velocity localparam is changed to 16'h7FFF or any value >= 16'h6000.

These are recoverable; none of the underlying RTL was lost. A later
milestone (Phase 5 M1) can add a small RTL UART block plus a tiny
command parser to reimplement the accepted command subset directly,
without re-introducing a CPU.

## Recommended Next Tasks

1. **Phase 5 M1 hardware acceptance**: program the new SOF, confirm
   four-voice audible output, no clipping, WM8978 boot, idle UART TX.
2. **Phase 5 M2 small RTL UART telemetry transmitter**: re-add a tiny
   `uart1_tx` status frame at a slow cadence (LE budget is generous
   now). Defer command-parsing to keep the slice small.
3. **Phase 5 M3 small RTL UART RX command parser**: reimplement the
   accepted M3a/M3b/M4 command subset (`!N`, `!NLLLLVVVV`, `!F`)
   directly in a small RTL state machine, restoring host-tool
   compatibility without a CPU.
4. **Phase 5 M4 audio fidelity expansion**: with ~6,500 LE recovered,
   the previously held Phase 4 candidates (modal/FDN body, larger
   FIR coloration, sympathetic resonance, pre-strike noise) are now
   re-openable.

## Honest Assessment

This is a deliberate functionality cut. UART command/telemetry
compatibility is intentionally lost in M0 in exchange for a much
simpler architecture and ~6,500 LE of recovered headroom. The trade
is sound: the host wrappers are preserved, the underlying RTL UART
TX/RX peripherals are reusable, and the audio path is unchanged.
Phase 5 M2/M3 can restore UART functionality with far less RTL than
the RV32I + firmware stack ever consumed.

The main risks for verifier are:
- The four-voice cadence (one trigger every 16,384 sample ticks) was
  chosen to look similar to the firmware demo loop, but it is not
  audibly identical. Expected: continuous tone with clear note onsets
  every ~349 ms cycling across four physical voices.
- Default velocity 16'h4000 means layer-0 hammer (M7). If verifier
  expects the louder layer-1 sound from prior production captures
  (which used velocity 0x7FFF), the perceived volume will be lower.
  This is a one-line localparam change in `phase0_fixed_control.v`
  if a louder default is preferred for hardware acceptance.

## Committed Result

Implementation commit on branch `codex/phase1c-uart-boundary-fix`.
Files in this commit:

- new: `rtl/control/phase0_fixed_control.v`
- new: `reports/phase5_m0_fixed_control_flattening.md`
- modified: `rtl/top/piano_phase0_top.v`
- modified: `quartus/phase0/piano_phase0_top.qsf`
- modified: `quartus/phase0/build.ps1`
- modified: `docs/project_brief.md`
- modified: `docs/phase0_impl_notes.md`
- renamed: legacy `rtl/control/phase0_*.v`, `rtl/peripherals/phase0_uart_mmio.v`,
  and `fw/phase0/*` into `obsolete/riscv_control/`

No deletes. All legacy code is preserved.
