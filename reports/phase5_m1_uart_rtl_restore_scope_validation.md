# Phase 5 M1 UART RTL Restore Scope Validation

Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-0f3b2f86` (depends on implementer `task-43730932`)
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `511fd66`

## Verdict

**PASS.** The Phase 5 M1 UART RTL restore scope report is acceptance-grade
as a planning artifact. The commit `511fd66` is single-file and report-only,
the report's factual claims about the post-M0 baseline match the live tree,
the proposed M1 TX-first slice is engineering-ready with concrete protocol,
clear block boundaries, and measurable acceptance gates, the deferred M2 RX
slice is conceptually safe and clearly separated, and no path proposed in
the report revives the obsolete RV32I/firmware/MMIO stack.

The recommendation to do TX telemetry first as a separate M1 slice and
defer RX command parsing to a follow-on M2 is sound. The split keeps the
M0 hardware acceptance gate ("verifier sees idle UART, audio plays, no
clipping") almost identical to the M1 gate ("verifier sees a status frame,
audio plays, no clipping") while preventing the M2 RX work from inheriting
M1 risk. This is the low-risk path the M0 budget can afford.

## Scope check

`git show --stat 511fd66`:

```
reports/phase5_m1_uart_rtl_restore_scope.md | 247 +++++++++++++++++++++
1 file changed, 247 insertions(+)
```

Single-file, single insertion. No live RTL, QSF, SDC, firmware, host
tools, generated outputs, docs, scripts, or `obsolete/` files modified.
No stale untracked verifier UART/audio artifacts touched. PASS.

## ASCII check

`reports/phase5_m1_uart_rtl_restore_scope.md`: 0 non-ASCII bytes (size
15,144 bytes). PASS.

## Factual cross-checks against live tree

1. `phase0_fixed_control` drives `uart1_tx` idle high.
   `rtl/control/phase0_fixed_control.v` line 91 declares
   `output wire uart1_tx`, and line 189 contains
   `assign uart1_tx = 1'b1;`. The header comment block on lines 27-29
   explicitly classifies UART RX command parsing and UART TX telemetry
   as deferred.
   PASS.

2. `uart1_rx` is unconsumed. The post-M0 top-level wires it only into
   the unloaded reduction `_unused_uart1_rx` (verified during
   `task-7b688c32`). Live RTL has no instantiation of `uart_rx`.
   PASS.

3. `rtl/peripherals/uart_tx.v` exists in the source tree (`Test-Path`
   returns `True`) but is not listed in `quartus/phase0/piano_phase0_top.qsf`
   after the M0 validation cleanup. Live QSF lists exactly 12
   `VERILOG_FILE` assignments and none of them is `uart_tx.v`. The
   report correctly states this status.
   PASS.

4. The archived `obsolete/riscv_control/rtl/peripherals/phase0_uart_mmio.v`
   contains a self-contained `uart_rx` module starting at line 245.
   Inspection of lines 245-355 shows a clean primitive: parameterized
   `CLK_FREQ_HZ` / `BAUD_RATE`, `sys_clk`-domain only, double-flop
   synchronizer (`rx_meta`/`rx_sync`), state machine
   `STATE_IDLE`/`STATE_START`/`STATE_DATA`/`STATE_STOP`, frame-error
   on missing stop bit, no MMIO ports, no register-bus baggage. The
   report's claim that this primitive can be lifted "no MMIO baggage"
   is accurate. The line-range citation in the report ("lines ~248-355")
   is essentially right; the exact module declaration starts at line
   245, which is a non-blocking line-number drift.
   PASS.

5. M0 baseline numbers cited in the report match
   `reports/phase5_m0_fixed_control_flattening_validation.md`:
   LE 3,614 / 10,320 = 35%, free margin ~6,706, setup +5.539 ns
   slow-85C, hold clean, all TNS 0, M9K 5, DSP9 26, PLL 1, 0 errors,
   20 warnings (cosmetic), SOF checksum `0x002BF2CE`, UART1 TX silent
   for 3 s, audio continuous and non-clipping.
   PASS.

6. The four physical `phase1_reduced_voice` instances and audio path
   referenced as "audio path is unchanged" remain
   `phase1_reduced_voice_inst`, `phase1_reduced_voice1_inst`,
   `phase1_reduced_voice2_inst`, `phase1_reduced_voice3_inst` in
   `rtl/audio/phase0_audio_path.v`. PASS.

## M1 TX-first scope assessment

Engineering-readiness review of section 3 onward:

- **Protocol frame**: ASCII frame
  `P5M1 BOOT=........ TICK=........ VC=..\r\n`. Roughly 33 bytes per
  frame. Cheap to serialize from a small ROM-style mux plus a
  byte-index counter; well within tens of LE for the formatter.
  Verifier can grep on a stable prefix `P5M1`. Fields are all freshness
  counters that can be checked locally without state from prior
  captures. Frame terminator is consistent with prior phase host
  conventions.

- **Cadence**: ~500 ms via a 25-bit counter at 50 MHz `sys_clk`. The
  exact value is annotated as not load-bearing because every frame
  carries its own freshness counters. Acceptable.

- **Frame queueing**: single 64-byte ASCII buffer in the TX block; if
  the previous frame is still draining, drop the new frame and
  increment a saturating local `dropped` counter. This is correct
  RTL discipline: the design never blocks on UART, never asserts
  back-pressure into the audio path, and never times out on the
  serial port.

- **Block boundaries**: new `rtl/peripherals/phase0_uart_status_tx.v`
  owns the cadence counter, ASCII buffer, byte sequencer, and a
  single instance of the existing `rtl/peripherals/uart_tx.v`
  byte transmitter. The existing fixed controller exposes
  `voice_index` (already a 2-bit register inside it) and the
  pre-existing top-level `sample_tick`. No CDC because every signal
  stays on `sys_clk`. Top-level ownership of `uart1_tx` moves from
  `phase0_fixed_control` to the new block, with a one-line removal
  in `phase0_fixed_control`.

  This boundary keeps `phase0_fixed_control` focused on audio
  defaults and the round-robin sequencer, which matches the project
  brief's preference for narrow modules. It also pre-positions the
  M2 RX/command block as a sibling rather than as a controller-internal
  subsystem.

- **Acceptance gates** (section 5 of the report): LE delta <= +250,
  warnings <= 22 net, M9K unchanged at 5, DSP9 unchanged at 26,
  setup slow-85C `sys_clk_50m` >= +4.5 ns, hold clean, all TNS 0,
  PLL 1, audio path regression-free. These are concrete and the
  setup-slack threshold leaves comfortable margin off the +5.539 ns
  M0 baseline.

- **NO-GO triggers** are sensible: any LE > +400, setup < +4.0 ns,
  TNS != 0, non-cosmetic warning, audio regression, baud drift
  outside +/- 5%, or any new reference to obsolete CPU/MMIO/firmware.
  All of these are observable in the same hardware/Quartus flow that
  the M0 acceptance run already exercised.

- **No path revives RISC-V or MMIO**: the report explicitly states that
  M2 will lift only the `uart_rx` primitive lines from
  `obsolete/riscv_control/rtl/peripherals/phase0_uart_mmio.v` and
  that the obsolete archive remains read-only. M1 itself does not
  touch the obsolete archive at all. PASS.

PASS.

## M2 deferral assessment

- **Clearly deferred, not hidden inside M1**: section 7 lists
  `Phase 5 M2 implementer task` as a separate queued task that runs
  only after M1 acceptance. M1 itself does not authorize lifting any
  obsolete file or implementing any RX path.

- **Command subset is deliberately small**: `!N\r\n`, `!NLLLLVVVV\r\n`,
  `!F\r\n`. Mirrors the accepted M3a/M3b/M4 command grammar. No
  per-voice damp/release semantics, no host-selected voice selection,
  no voice stealing reactivation in M2.

- **Reuses only primitive UART RX, not the archived MMIO block**:
  the report cites the specific line range in
  `obsolete/riscv_control/rtl/peripherals/phase0_uart_mmio.v` and
  classifies it as a self-contained primitive. Verifier inspection
  confirms that primitive is genuinely standalone and does not pull
  in any MMIO bus, register decode, address generation, or CPU-facing
  logic.

- **Telemetry extension in M2**: `Q=` and `X=` tags are appended to
  the M1 status frame, not invented as new lines. This preserves the
  M1 frame contract.

PASS.

## Honest assessment / non-blocking notes

- The report's line-range citation "lines ~248-355" for the lifted
  `uart_rx` primitive is approximate. The actual module declaration
  starts at line 245 and the `endmodule` is at the end of the file.
  Non-blocking; the M2 implementer task should cite the exact lines
  it ends up lifting.

- The report notes that the M1 implementer task should re-list
  `../../rtl/peripherals/uart_tx.v` in the QSF. M0 validation removed
  that line because nothing live referenced it, and the implementer
  report at that time stated "QSF lists only live synthesis sources".
  Re-listing is correct for M1 because `phase0_uart_status_tx`
  instantiates `uart_tx`. The M1 implementer task description should
  call out that the M0 validation cleanup explicitly removed this
  line, so the re-add is intentional and not a regression.

- Section 6 ("Pre-implementation cleanup") is correctly framed as
  notes only and does not authorize Phase 3 host-wrapper changes
  during M1.

- Frame format note: 33 bytes at 115200 8N1 takes ~2.86 ms to drain.
  The 500 ms cadence has plenty of headroom; the dropped-frame
  bookkeeping is more belt-and-suspenders than load-bearing.

None of these affect the verdict.

## Compatibility / risk notes for orchestrator

- M1 hardware acceptance will require COM port access. Current
  verifier station has `COM5` available and successfully captured
  3 s of UART silence during M0 validation. M1 will need a similar
  capture, just non-empty.
- M1 audio acceptance can reuse the M0 capture flow (ffmpeg dshow
  to mono 48 kHz WAV) and the same per-second peak/RMS analysis.
- The M0 LE budget after the pivot left ~6,706 free, so the M1
  +250 LE / M2 +350 LE allocations are conservative.

## Final verdict

**PASS.** Phase 5 M1 UART RTL restore scope is acceptance-grade as a
planning artifact. The orchestrator may queue the proposed Phase 5 M1
implementer task to add a tiny TX status-frame transmitter under
`rtl/peripherals/phase0_uart_status_tx.v` only, with the no-go gates
and out-of-scope guards stated in section 5 of the report. The Phase 5
M2 RX command parser remains conceptually queued behind M1 acceptance
and must not be implemented as part of M1.
