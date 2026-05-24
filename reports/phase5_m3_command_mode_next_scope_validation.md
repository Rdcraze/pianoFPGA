# Phase 5 M3 Command-Mode Next Slice Scope Validation

Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-782f2977` (depends on implementer `task-507b33ae`)
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `a21e2ef`

## Verdict

**PASS.** Phase 5 M3 command-mode next-slice scope is acceptance-grade
as a planning artifact. Commit `a21e2ef` is single-file, report-only,
ASCII-only. The recommendation to make M3 a host-wrapper compatibility
validation slice (no RTL change) instead of immediately attempting an
LRU/per-voice-release RTL slice is technically sound: the report
correctly identifies that the strongest behavioral divergence
(round-robin vs LRU under sustained polyphonic load) has no audible
evidence yet, so M3 produces that evidence cheaply before the
orchestrator commits LE budget to a feature.

The factual claims about M2 RTL behavior, M2 resource and timing
numbers, host wrapper command surfaces, and obsolete-archive vs live
boundaries are all consistent with the validated M2 baseline at
`5ee0c7c` and with the live wrapper sources. Proposed M3 deliverables
(small `scripts/phase5_m3_p5m2_decode.py` helper plus
`reports/phase5_m3_host_wrapper_validation.md`) are concrete and
properly scoped. Proposed M4 candidates are bounded with realistic
LE/timing gates and explicit "no, not yet" treatment until M3 evidence
warrants them.

## Scope check

`git show --stat a21e2ef`:

```
reports/phase5_m3_command_mode_next_scope.md | 332 +++++++++++++++++++++
1 file changed, 332 insertions(+)
```

Single-file, single insertion. No live RTL, QSF, SDC, firmware, host
tools, generated outputs, scripts, or `obsolete/` files modified. No
stale untracked verifier artifacts touched. PASS.

## ASCII check

`reports/phase5_m3_command_mode_next_scope.md`: 0 non-ASCII bytes (size
18,681 bytes). PASS.

## Factual cross-checks against live tree

1. **M2 command/status semantics**:
   - 8N1 115200, CRLF-terminated `!N`, `!NLLLLVVVV`, `!F` parsed by
     `phase0_uart_command.v`.
   - Error codes 1=malformed, 2=unknown opcode, 3=overlong, 4=frame,
     7=unsupported arg.
   - 62-byte `P5M2 BOOT=... TICK=... VC=... Q=... X=...\r\n` frame at
     ~500 ms cadence, where `Q = command_count[31:0]` and
     `X = {last_error[15:0], error_count[15:0]}`.
   - First valid command latches `command_mode`; autonomous round-robin
     suppressed thereafter.
   - `!F` raises shared `voice_damp_mix` to `16'd32767`; next `!N`
     restores `16'd16384`.
   - Voice selection round-robin via post-incremented `voice_index`.
   - Per-voice `loop_len[6:0]` and `velocity[15:0]` written only on
     `note_strobe` for the post-incremented voice.

   All match the source in `phase0_uart_command.v`,
   `phase0_fixed_control.v`, and `phase0_uart_status_tx.v` reviewed
   during M2 validation. PASS.

2. **Host wrapper summaries**:
   - `phase3_m5_keyboard.py`: pure synthesis of `!NLLLLVVVV\r\n` from
     MIDI numbers; A4 emits exactly `!N006A7FFF\r\n` per the
     wrapper's own self-check assertion. Confirmed by
     `cmd = f"!N{loop_len:04X}{vel:04X}\r\n"` in `midi_to_command`
     and the `!N006A7FFF` assertion in `_run_self_check`.
   - `phase3_m6_live_play.py`: parses comma-separated sequences, uses
     M5 mapper, supports `!N`/`!F` raw passthrough, release aliases
     `off`/`release`/`panic`/`!F`, bare/`!N`, and velocity overrides
     like `A4:4000`. No UART RX consumption. Confirmed by direct
     source read.
   - `phase3_m7_track_release.py`: tracks active notes host-side,
     emits `!F` only when active set empties or on
     panic/all-off/release. Confirmed by docstring and the
     `!F suppressed` log path that fires when there are still active
     notes.
   - `phase3_m9_interactive.py`: stdin-driven incremental sender;
     same command surface as M5/M6 plus per-token state machine,
     panic always emits `!F`, quit emits `!F` if active. Confirmed.
   - None of the wrappers read or parse UART TX. Confirmed by
     repo-wide grep on `ser\.read|readline|read_until|in_waiting`
     across the four scripts: 0 matches.

   PASS.

3. **LE / timing / resource numbers**:
   - LE 4,729 / 10,320 (46%): matches
     `reports/phase5_m2_uart_rx_command_validation.md` exactly.
   - Comb 4,492, regs 2,349, M9K 5, DSP9 26, PLL 1: all match.
   - Slow-85C `sys_clk_50m` setup +5.928 ns, hold +0.432 ns, all
     TNS 0, 0 errors, 16 warnings: all match.
   - Free LE budget 5,591 (54%): consistent with 10,320 - 4,729.
   - Setup margin above the +4.0 ns hard target: +1.928 ns;
     consistent.

   PASS.

4. **Obsolete archive boundary**:
   - The report does not propose lifting any new code from
     `obsolete/riscv_control/`.
   - It correctly notes that the old firmware diagnostic tag set
     (V3/VT/VA/VV/M/K/Z/O/D/E/etc.) lives in archive only, and
     does not propose reviving any of it for M3.

   PASS.

## Recommendation assessment

### Is M3 host-wrapper validation a better next step than RTL?

Yes. The argument in section 7 is sound:
- The previous three milestones (M0 flatten, M1 TX, M2 RX) were all
  RTL slices. A non-RTL validation checkpoint is the right
  inflection.
- The host wrappers are the closest thing this project has to an
  end-to-end command-driven acceptance suite, and they have not been
  exercised end-to-end against post-M0 RTL yet.
- Round-robin vs LRU is the single most-cited "missing" feature, but
  there is no audio evidence that it matters under typical use. The
  M3 captures will produce that evidence at low cost.
- The proposed M3 work has no RTL risk, no LE cost, and no timing
  cost.

The report also correctly rejects an immediate LE cleanup pass
(section 4): the available savings are small (~50-100 LE max), the
risk-to-savings ratio is poor at this point (still 54% free LE
budget), and any future RTL slice can fold cleanup in if it lands
near a gate. PASS.

### Are deliverables concrete and scoped?

The proposed implementer task description in section 6 is implementer-
ready:
- New `scripts/phase5_m3_p5m2_decode.py` is bounded (~80 lines, pure
  stdlib + pyserial) and has a `--self-check` requirement.
- `reports/phase5_m3_host_wrapper_validation.md` has a per-wrapper
  structure with explicit pass/fail evidence requirements.
- Hard validation gates are listed with concrete pass criteria.
- Stop-and-report triggers cover the realistic failure modes
  (self-check failure, audio regression, RTL-required workaround).
- ASCII-only and no-RTL-change discipline restated.

The proposed verifier follow-up task is also concrete: re-run
self-checks, spot-check P5M2 frame log, listen to or scope the audio
capture, confirm scope discipline.

PASS.

### Are M4 candidates plausible?

Both candidates are bounded:

- **M4 LRU stealing in `phase0_fixed_control`**: replace the post-
  incremented `voice_index` with an age-based selector that prefers
  inactive voices first. LE delta target <= +200, setup slack
  >= +4.0 ns, ModelSim test plus hardware sustained-chord stress test.
  This is realistic for the available 5,591 free LE.
- **M4 per-voice release**: either "release-most-recent-note"
  semantics for `!F` or `!F<voice>` syntax. LE delta target <= +150,
  setup slack >= +4.0 ns, ModelSim test plus hardware capture.
  Realistic but adds protocol surface; the report flags this and
  defers to M3 evidence.

Both candidates are correctly described as deferred until M3
evidence warrants the LE cost. The report does not authorize either
in M3. PASS.

## Honest assessment / non-blocking notes

- The report's voice-index post-increment description for M2 is
  precise, but the round-robin / LRU comparison row in section 2
  could mention that the M2 design always advances `voice_index` on
  every accepted note, even when the M0 autonomous demo was the
  source of the previous trigger. Under typical host-wrapper
  workflows this is invisible because the autonomous demo stops on
  first command, but a verifier reading section 2 in isolation
  might assume LRU-vs-round-robin is the only divergence to test.
  Non-blocking; the implementer can clarify in the M3
  implementation report.
- The report's section 5 LRU sketch reads `last_triggered_age[3:0]`
  on every sample tick. At 46.875 kHz a 4-bit saturating age would
  saturate after ~341 us, which is much shorter than typical note
  decay times. The implementer should likely widen this to 8-12
  bits when M4 is queued. Non-blocking for M3 because no LRU code
  is proposed in M3.
- The proposed `scripts/phase5_m3_p5m2_decode.py` overlaps with the
  decoder logic already used in `.kiro/phase5_m2_uart_session.py`
  (verifier's local hardware-acceptance script for M2). The M3
  helper should be a clean public version under `scripts/` rather
  than a copy of the local one. Non-blocking.

None of these affect the verdict.

## Compatibility / risk notes for orchestrator

- M3 does not alter any RTL, so the M2 baseline at `5ee0c7c` /
  validation `c224cc9` remains the live behavior. Any M3 captures
  will be against that exact image.
- M3 hardware acceptance can reuse the verifier station's existing
  COM5 + ffmpeg capture flow used for M0/M1/M2 validation.
- If M3 evidence shows clear LRU-vs-round-robin audible regression,
  the M4 LRU candidate is cheap enough (~+200 LE) to land in the
  same week as M3.

## Final verdict

**PASS.** Phase 5 M3 command-mode next-slice scope is acceptance-grade
as a planning artifact. The orchestrator may queue the proposed
Phase 5 M3 implementer task to add `scripts/phase5_m3_p5m2_decode.py`
and `reports/phase5_m3_host_wrapper_validation.md` with the gates,
deliverables, and stop-and-report triggers stated in section 6 of the
report. M4 RTL candidates remain deferred behind M3 evidence and must
not be bundled into M3.
