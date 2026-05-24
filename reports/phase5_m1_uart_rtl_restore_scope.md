# Phase 5 M1 Tiny RTL UART Restore Scope

Date: 2026-05-24
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-43730932`
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `3217b81` (post-Phase 5 M0 hardware acceptance)

## TL;DR

**Recommendation: do TX telemetry first as Phase 5 M1, then RX commands as a separate Phase 5 M2.** Telemetry-first is the lowest-risk slice with the most immediate verifier value: the next hardware acceptance run gets a positive serial-port heartbeat, command-feedback hooks for any future RX work get easier, and the slice can land in well under 200 LE while preserving all M0 acceptance evidence. Defer RX command parsing to M2 because it is structurally larger (FIFO + parser FSM + integration into the fixed controller trigger path) and benefits from having the TX feedback already live.

| M1 (this scope) | M2 (deferred) |
| --- | --- |
| Add `rtl/peripherals/phase0_uart_status_tx.v`: tiny status-frame transmitter | Add `rtl/peripherals/uart_rx.v` + `rtl/control/phase0_uart_command.v` |
| Wire `uart1_tx` from M0 idle to a periodic ASCII status frame | Tie RX byte stream into a small command FSM that drives fixed_control |
| Reuse existing `rtl/peripherals/uart_tx.v` 8N1 115200 byte transmitter | Lift the proven `uart_rx` primitive from `obsolete/riscv_control/rtl/peripherals/phase0_uart_mmio.v` |
| LE target: <= 250 added | LE target: <= 350 added |
| Hardware gate: COM port shows recurring frame, audio unchanged | Hardware gate: command-then-trigger round trip, COM tag confirms parse |

Both slices stay well within the ~6,500 LE recovered by M0.

## 1. Where Phase 5 M0 left UART

Live state at `3217b81`:

- `rtl/control/phase0_fixed_control.v` drives `uart1_tx = 1'b1` (RS-232 mark / idle).
- `uart1_rx` is connected to top-level only as an unloaded reduction sink (`_unused_uart1_rx`).
- `rtl/peripherals/uart_tx.v` is in the source tree as a reusable peripheral but is not in the live QSF.
- All MMIO/FIFO/parser logic lives only under `obsolete/riscv_control/rtl/peripherals/phase0_uart_mmio.v`. That file usefully contains a clean `uart_rx` primitive (lines ~248-355) that is sys_clk-domain, 8N1 115200, with double-flop synchronizer and frame-error reporting; it can be lifted with no MMIO baggage.
- M0 verified hardware: SOF `0x002BF2CE`, UART1 TX silent for 3 s, audio continuous and non-clipping.
- Free LE budget: ~6,706 (LE 3,614 / 10,320 = 35%). Setup +5.539 ns slow-85C, hold clean, all TNS 0.

This is the right baseline to grow from: silent TX is the cleanest possible "M0 says nothing happened" floor, and the M0 audio behavior is independent of any UART work.

## 2. Why TX telemetry first

Comparing the three structurally distinct first-slice options:

| Option | LE estimate | Verifier value | Risk | Builds on previous? | Recommendation |
| --- | ---: | --- | --- | --- | --- |
| A. Telemetry TX only | ~150-250 | Positive heartbeat at boot; visible "the board is alive" line; foundation for RX feedback | Low. uart_tx.v already exists, sys_clk-domain, has been hardware-validated in prior phases. Zero audio-path interaction. | Builds directly on M0 | **PICK FIRST (M1)** |
| B. RX commands only | ~250-400 | Restores host-wrapper compatibility but with no feedback path | Medium. New uart_rx + parser FSM + fixed_control trigger override. Hard to test without a TX echo. | Cannot show command-was-parsed without TX side help | Defer to M2 |
| C. Combined TX+RX block | ~400-550 | Full restore in one slice | Higher. Changes audio behavior and adds two new RTL sub-blocks at once. Conflates verifier acceptance signals. | Yes but loses incremental safety | Reject; do A then B |

The "verifier value" axis matters most. M0 hardware validation already used a Saleae-style approach to confirm UART1 TX is silent. Adding a periodic status frame turns that verifier capability into a positive heartbeat without rewriting any test infrastructure.

## 3. Phase 5 M1 minimal protocol contract

### Frame format

ASCII status frame, sent at a slow cadence so the host sees something simple and stable. Recommended exact format:

```
P5M1 BOOT=00000001 TICK=DDDDDDDD VC=01\r\n
```

- 4-char milestone tag `P5M1` so the host can grep cleanly.
- One ASCII space between fields.
- `BOOT` is a 32-bit hex counter incremented once per status frame; lets the verifier confirm the frame is fresh, not a repeat artifact.
- `TICK` is a 32-bit hex counter snapshot of `sample_tick` count at the moment the frame is queued. Mirrors the firmware-era `R=` tag's role.
- `VC=` is a 1-byte hex code reflecting the current voice index that the round-robin sequencer is about to fire next (00..03). Gives the verifier a check that the M0 sequencer is alive.
- Frame terminator `\r\n` matches the host wrappers' existing line conventions.

### Cadence

Send one frame approximately every 500 ms. At 50 MHz `sys_clk` this is ~25,000,000 cycles. A 25-bit counter is enough; LE-cheap. Cadence stability is not load-bearing because every frame contains the freshness counters.

### Frame queueing

A single 64-byte ASCII buffer in the status TX block. Build a frame on the cadence pulse; if the previous frame is still draining (because some serial port is slow), drop the new frame and increment a local `dropped` counter; the next frame can encode the drop counter into the protocol if useful. M1 does NOT need to expose the drop counter externally; recording it as a saturating 8-bit register in the TX block is sufficient.

### Idle-line behavior

Between frames `uart1_tx` is mark-high, exactly as M0 already does.

### Reset behavior

On `!sys_rst_n` the TX block resets the cadence counter, clears the boot counter, and immediately starts the cadence over. The verifier should see the first `BOOT=00000001` frame ~500 ms after JTAG configuration completes.

### Out of scope for M1

- No RX. `uart1_rx` stays unconsumed.
- No command-feedback or command-echo line. Those are M2.
- No audio gating, no WM8978 register manipulation.
- No malformed-input protocol. There is no input.

## 4. RTL block sketch

### New files

- `rtl/peripherals/phase0_uart_status_tx.v`: the new block. It owns the cadence counter, ASCII buffer, byte sequencer, and a single instance of `rtl/peripherals/uart_tx.v`.

### Modified files

- `rtl/top/piano_phase0_top.v`: instantiate `phase0_uart_status_tx` and route `uart1_tx` from it instead of from `phase0_fixed_control`.
- `rtl/control/phase0_fixed_control.v`: remove the inline `assign uart1_tx = 1'b1;` from the controller so the new block owns the pin. Two small status outputs need to be exposed by the controller for the frame: `voice_index` (2 bits) and `sample_tick`. `sample_tick` is already wired at the top level. `voice_index` is a 2-bit register inside `phase0_fixed_control`; expose it as an output port.
- `quartus/phase0/piano_phase0_top.qsf`: re-list `../../rtl/peripherals/uart_tx.v` (currently removed by M0 cleanup) and add `../../rtl/peripherals/phase0_uart_status_tx.v`.

### Block boundaries

```
phase0_fixed_control --- voice_index, sample_tick ---> phase0_uart_status_tx
                                                              |
                                                              | uses uart_tx.v internally
                                                              v
                                                            uart1_tx
```

No CDC: every signal stays in `sys_clk`.

### Why not include this inside `phase0_fixed_control`

Two reasons:
1. Keeping the status transmitter in a separate file makes the M2 RX/command work simpler, because M2 will add a sibling `phase0_uart_command` block and a small bus combiner is unnecessary if TX is already its own module.
2. Status-frame ASCII serialization is large enough that putting it in `phase0_fixed_control` would obscure the controller's audio-defaults role. Separation matches the project brief's preference for narrow modules.

## 5. Acceptance gates for M1 implementation

### Static checks
- QSF lists exactly: existing M0 sources + `uart_tx.v` + `phase0_uart_status_tx.v`.
- No reference anywhere in live RTL/build/sim to `phase0_rv32i_*`, `phase0_control_regs`, `phase0_uart_mmio`, `phase0_boot_rom`, or `phase0_data_ram`.
- No reference to `fw/phase0` outside `obsolete/riscv_control/` or `reports/`.
- ASCII-only on touched files.
- `git diff` only touches: `rtl/control/phase0_fixed_control.v`, `rtl/top/piano_phase0_top.v`, `rtl/peripherals/phase0_uart_status_tx.v` (new), `quartus/phase0/piano_phase0_top.qsf`, plus the M1 implementation report and any small doc note.

### Quartus
- 0 errors.
- Warnings: <= 22. Expect the M0 baseline 20 to drop by 2 (no more "stuck-output" or "uart1_tx never read" warnings) and rise by some number for any new unused-input that the new block introduces. Net target <= 22.
- LE delta: <= +250.
- M9K: unchanged at 5 (only the audio delay lines).
- DSP9: unchanged at 26.
- Setup slack slow-85C `sys_clk_50m`: >= +4.5 ns (very loose because UART logic is far from the sample-tick critical path).
- Hold clean, all TNS 0, PLL 1.

### ModelSim
- Add `rtl/peripherals/phase0_uart_status_tx_tb.v` that drives `sys_clk` plus a fake `sample_tick` and a fake `voice_index`, runs for at least two cadence intervals, and confirms two `\r\n`-terminated frames appear at the correct baud-rate timing on `uart1_tx`. Keep the TB short.
- The existing `rtl/audio/phase1_reduced_voice_tb.v` is unaffected and should still PASS golden-bit-exact.

### Hardware acceptance
- Program new SOF.
- Open COM port at 115200 8N1.
- Within 1 s of programming, the host should see at least one full `P5M1 BOOT=... TICK=... VC=...\r\n` frame.
- Frame cadence should stabilize at ~500 ms +/- some tolerance.
- `BOOT` increments monotonically; `TICK` increments by ~23,400 between consecutive frames at 46.875 kHz.
- Audio output remains continuous, four-voice, no clipping. No regression vs M0 audio capture.

### NO-GO triggers
- Any LE > +400, setup < +4.0 ns, or any TNS != 0.
- Any new warning that is not unused-signal/cosmetic.
- Audio path regression (clipping, silence, single-voice-only).
- New reference to obsolete CPU/MMIO/firmware code.
- Any byte-frequency drift on `uart1_tx` outside +/- 5% of 115200 baud at any corner.

## 6. Pre-implementation cleanup

These are notes only; they do NOT need to be done as part of this M1 scope task. They should be folded into the M1 implementation task description:

- The Phase 3 host wrappers in `scripts/phase3_m5_keyboard.py`,
  `scripts/phase3_m6_live_play.py`, `scripts/phase3_m7_track_release.py`,
  and `scripts/phase3_m9_interactive.py` are currently legacy under M0.
  They produce `!N`, `!NLLLLVVVV`, `!F` strings on stdout. They should
  remain in place for now; M2 will reuse their byte-stream output once
  RX is back. No docs/source change required for M1.
- `docs/project_brief.md` has been updated to reflect the fixed-function
  RTL architecture. M1 should add a short note that UART telemetry has
  returned at status-frame granularity, but RX command compatibility
  is still deferred to M2.
- `docs/phase0_impl_notes.md` Phase 5 update section should mention the
  new TX-first restore path so future readers do not assume UART RX
  also returned in M1.

## 7. Recommended next implementer / verifier task split

### Phase 5 M1 implementer task: add TX status frame
- Files in scope: `rtl/peripherals/phase0_uart_status_tx.v` (new),
  `rtl/control/phase0_fixed_control.v`,
  `rtl/top/piano_phase0_top.v`,
  `quartus/phase0/piano_phase0_top.qsf`,
  `rtl/peripherals/phase0_uart_status_tx_tb.v` (new),
  `reports/phase5_m1_uart_status_tx_impl.md` (new),
  optional small additions to `docs/project_brief.md` and
  `docs/phase0_impl_notes.md`.
- Hard gates: section 5 above.
- Stop-and-report if: gate breach, new RTL needs to touch audio path,
  or LE/timing budget cannot be met. Roll back RTL and ship a NO-GO
  report rather than weakening gates.

### Phase 5 M1 verifier task: validate TX status frame on hardware
- Read implementer report.
- Re-run Quartus full compile or trust implementer numbers if commit is reproducible.
- Program SOF, open COM port at 115200 8N1.
- Capture >= 5 consecutive frames with timestamps.
- Confirm frame format matches contract, monotonic counters, ~500 ms cadence, no audio regression.
- Submit `reports/phase5_m1_uart_status_tx_validation.md`.

### Phase 5 M2 implementer task (queued after M1 acceptance): add small RX command parser
- New `rtl/peripherals/uart_rx.v` lifted from
  `obsolete/riscv_control/rtl/peripherals/phase0_uart_mmio.v` lines
  248-355 (no MMIO baggage).
- New `rtl/control/phase0_uart_command.v` containing a small parser FSM
  that recognizes `!N\r\n`, `!NLLLLVVVV\r\n`, and `!F\r\n` and emits
  per-voice trigger/parameter overrides into `phase0_fixed_control`.
- Adds telemetry tags `Q=` and `X=` to the M1 status frame, mirroring
  the accepted command-count / parser-error semantics.
- Uses the existing `phase0_uart_status_tx` block as the feedback path.
- Out of scope: per-voice damp/release semantics, host-selected voice
  selection, voice stealing reactivation. Keep RX as a thin trigger
  hook only.

## 8. Honest assessment

This split is conservative. M1 alone does not restore host-wrapper
compatibility because the host wrappers send commands TO the board, not
the reverse. A combined block could land both directions in one slice
with similar LE cost, but I am recommending against it for two
reasons:

1. M0's hardware acceptance gate was "verifier sees silent UART TX,
   audio plays, no clipping." M1's gate is "verifier sees frame on
   UART TX, audio plays, no clipping." That gate maps cleanly to the
   same hardware setup with a tiny addition. M2's gate is "verifier
   types a command, board responds." That is a meaningfully different
   hardware test that benefits from M1 already being live.

2. The "tiny" combined block is not actually that tiny: lifting the
   `uart_rx` primitive plus a 16-byte FIFO plus a parser FSM plus a
   command-to-trigger crossbar into `phase0_fixed_control` is
   substantially more RTL than the M1 status frame, and that mass is
   what makes simulation/hardware debug expensive.

The cost of the recommended split is one extra task pair (M1 + M2
instead of one combined task). The benefit is two independently
verifiable hardware milestones with non-overlapping failure modes.

## 9. What this report does NOT do

- No RTL, firmware, host-tool, SDC, QSF, generated-output, or
  obsolete-file change. Pure planning artifact.
- Does not authorize lifting `uart_rx` from the obsolete tree until
  Phase 5 M2 is queued.
- Does not change UART pin assignments, baud rate, byte format,
  voltage standards, or any audio path behavior.
- Does not touch `.kiro/`, the four untracked Phase 3/4 verifier UART
  files, or the `obsolete/` archive.

ASCII-only by construction.
