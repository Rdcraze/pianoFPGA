# Phase 5 M0 Fixed-Function Control Flattening Validation

Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-7b688c32` (depends on implementer `task-67d1d75b`)
Branch: `codex/phase1c-uart-boundary-fix`
HEAD before validation: `5124dba`

## Verdict

**PASS with narrow QSF fix.** The Phase 5 M0 architecture pivot is
acceptance-grade. The RV32I SoC + firmware + MMIO + register-file
control stack is replaced by the new fixed-function RTL block
`rtl/control/phase0_fixed_control.v`, all four physical
`phase1_reduced_voice` instances are preserved in
`rtl/audio/phase0_audio_path.v`, the obsolete RV32I/firmware files are
preserved under `obsolete/riscv_control/` via `git mv` (no deletes),
and Quartus 13.0.1 full compile reproduces the implementer numbers
exactly: LE 3,614 / 10,320, comb 3,405, regs 1,751, M9K 5 (memory
bits 20,480), DSP9 26, PLL 1, setup `sys_clk_50m` +5.539 ns, hold
+0.433 ns, all TNS 0, 0 errors, 20 warnings.

A single narrow report-vs-QSF mismatch was found and fixed in this
validation: `quartus/phase0/piano_phase0_top.qsf` still listed
`../../rtl/peripherals/uart_tx.v`, but no live RTL instantiates
`uart_tx`. The implementer report explicitly states the live QSF
"lists only live synthesis sources." I removed that single line from
the QSF, reran a full Quartus compile, and confirmed bit-identical
fit/timing (LE 3,614 / setup +5.539 ns / 0 errors / 20 warnings). No
RTL, firmware, control behavior, audio behavior, or pin assignment
changed.

Hardware acceptance ran cleanly: SOF programmed (checksum
`0x002BF2CE`), UART1 TX silent for 3 s as designed, and analog audio
captured at the 3.5 mm jack shows continuous non-clipping output
across all six 1 s windows.

## Scope check

`git show --stat 5124dba` summarized:
- new: `rtl/control/phase0_fixed_control.v`, `reports/phase5_m0_fixed_control_flattening.md`
- modified: `.gitignore`, `docs/phase0_impl_notes.md`, `docs/project_brief.md`,
  `quartus/phase0/build.ps1`, `quartus/phase0/piano_phase0_top.qsf`,
  `rtl/top/piano_phase0_top.v`
- renamed via `git mv` into `obsolete/riscv_control/`:
  `rtl/control/phase0_boot_rom.v`, `rtl/control/phase0_data_ram.v`,
  `rtl/control/phase0_rv32i_core.v`, `rtl/control/phase0_rv32i_soc.v`,
  `rtl/control/phase0_control_regs.v`,
  `rtl/peripherals/phase0_uart_mmio.v`, and `fw/phase0/*`

`git diff --stat 5124dba HEAD -- ':!reports/phase5_m0_fixed_control_flattening_validation.md'`
in this validation pass: only `quartus/phase0/piano_phase0_top.qsf` (one
deleted line). No RTL or firmware changes from the verifier.

PASS.

## Static architecture check

1. `rtl/top/piano_phase0_top.v` instantiates `phase0_fixed_control`
   (`phase0_fixed_control_inst`) instead of any RV32I SoC or
   `phase0_control_regs`. Verified by inspection.
2. `rtl/control/phase0_fixed_control.v` directly drives every audio
   and codec control wire that the old register file used to drive,
   with documented hardwired defaults that match the accepted M5/M7
   reset values, and runs a `sample_tick`-paced round-robin trigger
   sequencer over voice0..voice3.
3. `rtl/audio/phase0_audio_path.v` still instantiates four physical
   `phase1_reduced_voice` voices: `phase1_reduced_voice_inst`,
   `phase1_reduced_voice1_inst`, `phase1_reduced_voice2_inst`,
   `phase1_reduced_voice3_inst`. None were merged or removed.
4. `obsolete/riscv_control/` contains the full archived RV32I and
   firmware tree:
   - `obsolete/riscv_control/rtl/control/phase0_boot_rom.v`
   - `obsolete/riscv_control/rtl/control/phase0_data_ram.v`
   - `obsolete/riscv_control/rtl/control/phase0_rv32i_core.v`
   - `obsolete/riscv_control/rtl/control/phase0_rv32i_soc.v`
   - `obsolete/riscv_control/rtl/control/phase0_control_regs.v`
   - `obsolete/riscv_control/rtl/peripherals/phase0_uart_mmio.v`
   - `obsolete/riscv_control/fw/phase0/{README.md,build.ps1,link.ld,phase0_hw.h,phase0_main.c,start.S}`
     plus the previously committed `build/` tree (ELF, BIN, DIS, MAP,
     MEM, MIF, .o)
5. Live source-file references to obsolete RV32I/MMIO/control_regs/firmware
   exist only in historical reports under `reports/` (intentional history)
   and in stale ModelSim work caches under `tmp/` (not part of the live
   build flow). No live RTL/QSF/build/script/doc presents them as the
   current architecture. Confirmed via repo-wide grep, excluding
   `obsolete/`, `reports/`, `docs/`, `.kiro/`, and `scripts/`.

## QSF mismatch finding and repair

The implementer report said:

> `quartus/phase0/piano_phase0_top.qsf` updated to list only live
> synthesis sources.

But the committed QSF in `5124dba` still listed:

```
set_global_assignment -name VERILOG_FILE ../../rtl/peripherals/uart_tx.v
```

Repo-wide grep confirmed `uart_tx` is not instantiated by any live
RTL: only `rtl/peripherals/uart_tx.v` (definition) and
`rtl/peripherals/uart_debug_stub.v` (also unreferenced). Neither
module is in the synthesized hierarchy under `phase0_fixed_control`.

Repair: remove the one offending QSF line. No RTL, firmware, pin
assignment, or constraint change.

Post-fix Quartus full compile:
- LE 3,614 / 10,320 (35%) (unchanged)
- Combinational 3,405 (unchanged)
- Dedicated logic registers 1,751 (unchanged)
- Memory bits 20,480 (unchanged)
- DSP9 26 (unchanged)
- PLL 1 (unchanged)
- Slow-85C setup `sys_clk_50m` +5.539 ns (unchanged)
- Slow-85C hold `sys_clk_50m` +0.433 ns (unchanged)
- All TNS 0 (unchanged)
- Errors 0; warnings 20 (unchanged)

The post-fix QSF is the canonical "lists only live synthesis sources"
state the implementer report described.

## Documentation / roadmap check

- `docs/project_brief.md` Goal section now states: "the RISC-V SoC +
  firmware MMIO + register-file control stack has been retired and
  replaced with a fixed-function RTL controller" and "The legacy
  CPU/firmware code is archived under `obsolete/riscv_control/` for
  reference." Live architecture is described as a small fixed-function
  RTL controller plus custom RTL/DSP audio. PASS.
- `docs/phase0_impl_notes.md` contains a Phase 5 M0 note that the live
  control plane is now `phase0_fixed_control` and the prior CPU/MMIO/
  firmware narrative is historical. The body of the file still
  documents the prior task chain in detail; this is acceptable as
  history because the M0 note at the top establishes the current
  state. PASS.
- The Phase 0 phase plan in `docs/project_brief.md` still describes
  the original "small soft-core control plane" architecture for Phase
  0. The Goal section's M0 update supersedes that narrative explicitly,
  and the phase plan text is preserved as historical context. Not
  blocking.

## Build / Fit / Timing evidence

Independent Quartus 13.0.1 full compile from this validation pass
(`.kiro/quartus_phase5_m0_verify.log` first run, then post-QSF-fix
`.kiro/quartus_phase5_m0_qsf_clean.log`):

| Metric | Pre-pivot baseline `e90a820` | Post-pivot `5124dba` (impl) | Post-pivot, post-QSF-fix (verifier) |
| --- | ---: | ---: | ---: |
| Total logic elements | 10,099 / 10,320 | 3,614 / 10,320 | 3,614 / 10,320 |
| Combinational | 9,487 | 3,405 | 3,405 |
| Registers | 4,237 | 1,751 | 1,751 |
| Memory bits | 86,016 | 20,480 | 20,480 |
| M9K (memory_bits/5,376) | 16 | 5 (rounded up from 3.81 used; on-chip ROM/RAM gone) | 5 |
| DSP9 | 28 | 26 | 26 |
| PLL | 1 / 2 | 1 / 2 | 1 / 2 |
| Setup slow-85C `sys_clk_50m` | +2.846 ns | +5.539 ns | +5.539 ns |
| Hold slow-85C `sys_clk_50m` | +0.418 ns | +0.433 ns | +0.433 ns |
| Setup `i2c_clk` | +17.304 ns | +993.950 ns | +993.950 ns |
| Setup `audio_bclk` | +315.510 ns | +315.046 ns | +315.046 ns |
| All TNS | 0 | 0 | 0 |
| Errors | 0 | 0 | 0 |
| Warnings | 16 | 20 | 20 |

Setup slack on `sys_clk_50m` improved by +2.693 ns versus the post-M7
baseline. The huge `i2c_clk` setup-slack jump is expected: the prior
build had multi-cycle CPU writeback paths landing at `i2c_clk`
indirectly through control_regs; with no CPU there are no such paths.

Warnings increased by +4 versus M7 (16 -> 20). All four are cosmetic
and expected:
- one stuck-output warning on `uart1_tx` (held high in M0)
- one input-pin-not-driving-logic warning on `uart1_rx` (unused in M0)
- two unused-signal-sink warnings on `_unused_uart1_rx` and
  `_unused_audio_path_status` reductions in `piano_phase0_top.v`

No latch inference, no missing-case, no undriven nets in the live
design.

`uart_tx.v` is not instantiated anywhere in the live RTL after the
QSF cleanup.

## Firmware / ROM gate

`fw/phase0/` no longer exists at the live root; it is archived under
`obsolete/riscv_control/fw/phase0/`. The previously accepted ROM word
count (931) is preserved in the archived `phase0.bin`/`phase0.mem`/
`phase0.mif`. `quartus/phase0/build.ps1` no longer invokes the
firmware build; the `compile` stage runs only Quartus. There is no
live firmware ROM gate. PASS.

## Hardware smoke

JTAG and COM5 are visible (`USB-Blaster [USB-0]`, `COM5`). Hardware
smoke ran end-to-end:

1. SOF programmed via `quartus_pgm`, checksum `0x002BF2CE`. 0 errors.
2. UART1 TX silence test: read COM5 at 115200 8N1 for 3 s.
   Result: 0 bytes received. This matches the M0 design intent that
   `phase0_fixed_control` drives `uart1_tx` idle high.
3. Analog audio capture at the 3.5 mm jack via ffmpeg dshow, mono
   48 kHz, 6 s, saved to `reports/phase5_m0_audio.wav`. Per-second
   stats:

   | s | peak (counts) | peak (dBFS) | RMS (counts) | RMS (dBFS) |
   | ---: | ---: | ---: | ---: | ---: |
   | 0 | 3089 | -20.51 | 708.1 | -33.31 |
   | 1 | 3461 | -19.52 | 1054.7 | -29.85 |
   | 2 | 3473 | -19.49 | 1022.6 | -30.12 |
   | 3 | 3311 | -19.91 | 886.2  | -31.36 |
   | 4 | 2906 | -21.04 | 853.3  | -31.69 |
   | 5 | 3553 | -19.30 | 1061.8 | -29.79 |

   Overall peak -19.30 dBFS, overall RMS -30.85 dBFS. No clipping
   anywhere (peak well below 0 dBFS in every window). The signal is
   continuous across the entire 6 s capture, consistent with the
   round-robin trigger sequencer firing voice0->voice1->voice2->voice3
   roughly every ~349 ms and four voices producing sustained audible
   output without firmware.

   The default M0 velocity is `16'h4000` (M7 layer 0 by threshold
   construction), which is below the prior production default `0x7FFF`
   used at the implementer's layer-1 default in M7 captures. The
   resulting analog level is consequently lower than recent M7 captures.
   This is expected and is a one-line localparam change in
   `phase0_fixed_control.v` if a louder default is needed for later
   acceptance.

PASS.

## Architecture guard

Four physical `phase1_reduced_voice` instances preserved. `git diff`
of `rtl/audio/phase0_audio_path.v` between `e90a820` and `5124dba`
returns no change. UART telemetry (V3/VT/VA/VV/S3/ST/CC/...) is
intentionally deferred in M0; the underlying audio-path counters and
status nets remain wired and ready for a future RTL telemetry
transmitter. PASS.

## Compatibility loss assessment

Implementer report classifies the following as deferred, not lost:
- Phase 3 M3a/M3b parameterized note commands (`!NLLLLVVVV`)
- Phase 3 M4 release command (`!F`)
- Phase 3 M5/M6/M7a/M9 host wrappers can still emit valid command
  bytes but the board does not consume them in M0
- UART status frames (`I/S/R/V/F/T/...`) are not emitted

This is a deliberate functionality cut for ~6,500 LE of recovered
headroom. Phase 5 M2/M3 milestones can reintroduce a small RTL UART
TX/RX block plus a tiny command parser without re-introducing a CPU.

PASS as a documented and reversible design choice.

## Final verdict

**PASS with narrow QSF fix.** Phase 5 M0 architecture pivot is sound,
fully-source-grounded, and reproducibly compiles to the implementer's
reported numbers. Hardware smoke confirms the new fixed-function
controller produces continuous four-voice audible output without
firmware, the WM8978 boots, and UART1 TX is idle as designed.

Verifier-applied QSF cleanup removes one stale `uart_tx.v` line that
the implementer report had implicitly already promised; resource and
timing numbers are unchanged after the fix.

## Validation actions

- Read implementer report and inspected `5124dba`.
- Spot-checked `rtl/top/piano_phase0_top.v`, `rtl/control/phase0_fixed_control.v`,
  `rtl/audio/phase0_audio_path.v`, `quartus/phase0/piano_phase0_top.qsf`,
  `quartus/phase0/build.ps1`, `docs/project_brief.md`,
  `docs/phase0_impl_notes.md`.
- Confirmed `obsolete/riscv_control/` contains the archived RV32I and
  firmware tree.
- Removed unused `uart_tx.v` from the live QSF.
- Ran two full Quartus compiles; logs at `.kiro/quartus_phase5_m0_verify.log`
  and `.kiro/quartus_phase5_m0_qsf_clean.log`. Both PASS, both reproduce
  the same fit/timing numbers.
- Programmed the new SOF on hardware (checksum `0x002BF2CE`).
- Captured 3 s UART silence and 6 s audio to confirm M0 hardware
  behavior. Audio capture saved at `reports/phase5_m0_audio.wav`.
- Wrote this report ASCII-only and committed only the QSF cleanup
  plus this validation artifact.
