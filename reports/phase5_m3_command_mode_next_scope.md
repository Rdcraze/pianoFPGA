# Phase 5 M3 Command-Mode Next Slice Scope

Date: 2026-05-24
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-507b33ae`
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `5ee0c7c` (Phase 5 M2 PASS)

## TL;DR

**Recommendation: M3 = host-wrapper compatibility validation
slice.** Validate the live M2 RTL command path against the existing
Phase 3 host wrappers (`scripts/phase3_m5_keyboard.py`, `_m6_live_play.py`,
`_m7_track_release.py`, `_m9_interactive.py`) on real hardware,
capturing a small known-good audio session and a P5M2 frame log per
wrapper. No RTL changes. The exit criterion is a structured report
documenting where M2 RTL semantics meet host expectations, where they
diverge audibly, and which divergences are tolerable vs which justify
queueing M4 RTL work (LRU, per-voice release, or other targeted
upgrades).

| M3 (this scope) | M4 (queued, deferred) |
| --- | --- |
| Validate `phase3_m5..m9` against live M2 hardware | RTL changes informed by M3 evidence |
| Add tiny `scripts/phase5_m3_p5m2_decode.py` helper | RTL implementer task per M3 findings |
| Capture per-wrapper P5M2 frame log + audio | Verifier acceptance for M4 |
| New: `reports/phase5_m3_host_wrapper_validation.md` | New: `reports/phase5_m4_*` |
| RTL change: NONE | LE budget target: <= +400 |
| Hardware gate: no audio regression vs M0/M1/M2 baseline | Hardware gate: feature-specific |

This split keeps M3 cheap and reversible, and makes any subsequent
RTL slice (M4) data-driven rather than speculative.

## 1. M2 baseline state (read carefully)

Live commit: `5ee0c7c`. Live behavior:

- UART RX: 8N1 115200, parses CRLF-terminated `!N\r\n`,
  `!NLLLLVVVV\r\n`, `!F\r\n`. Errors classified 1=malformed,
  2=unknown opcode, 3=overlong, 4=frame, 7=unsupported arg.
- UART TX: 62-byte `P5M2 BOOT=... TICK=... VC=... Q=... X=...\r\n`
  every ~500 ms. Q is `command_count[31:0]`; X is
  `{last_error[15:0], error_count[15:0]}`.
- RTL semantics:
  - First valid command latches `command_mode`. While
    `command_mode` is set, the autonomous round-robin sequencer is
    suppressed.
  - Voice selection for command-driven notes is round-robin: voice
    index advances by one on each `note_strobe`, fanning out across
    voices 0..3 with no LRU consideration of active state.
  - `!F` raises a single shared `voice_damp_mix` to `16'd32767`. All
    four voices receive the same damp. Next `!N` restores
    `voice_damp_mix` to its `16'd16384` default.
  - Per-voice `loop_len[6:0]` and `velocity[15:0]` are written only
    on the cycle a `note_strobe` lands for the post-incremented
    voice index.
  - Static voice parameters: `loop_gain=16'd32640`,
    `disp_coeff=16'sd9952`, `body_mix=16'd8192`, all unchanged.
  - Audio path: four `phase1_reduced_voice` instances unchanged from
    M0/M1/M2 baseline, golden TB still bit-exact at `peak=3952`.

Live resources: LE 4,729 / 10,320 (46%), comb 4,492, regs 2,349, M9K
5, DSP9 26, PLL 1, slow-85C `sys_clk_50m` setup +5.928 ns, hold
+0.432 ns, all TNS 0, 0 errors, 16 warnings. Free LE budget: 5,591
LE (54%). Setup margin above the +4.0 ns hard target: +1.928 ns.

## 2. Question 2: M2 vs old firmware/host expectations

| Aspect | Old firmware behavior | M2 RTL behavior | Audible delta |
| --- | --- | --- | --- |
| Voice selection | LRU steal: prefer free voice; if all busy, steal oldest | Round-robin, no active-state awareness | If host plays >4 simultaneous notes, M2 may overwrite a still-ringing voice that LRU would have left intact. With 4-voice cap and quick decay, this is usually inaudible for typical melodies but can sound abrupt for sustained chords. |
| `!F` (release) | High-damping for entire voice bank, no per-note tracking in firmware (host did per-note tracking via `phase3_m7_track_release.py`) | Single shared `voice_damp_mix=32767` raised, restored on next `!N` | Functionally equivalent. The host wrapper M7a was already designed around shared-release semantics (only emits `!F` when its tracked active set becomes empty). No regression vs old firmware. |
| `command_mode` gate | Old firmware ran a round-robin smoke sequence at boot, then served UART; the smoke was already running before any host command and was not gated off | M2 RTL: autonomous round-robin runs until first command, then suppressed for the rest of the session | Slight semantic shift: old firmware mixed boot-smoke notes into a host-driven session, M2 cleanly hands over. Host-side M7a wrapper tracks notes locally so no observable functional change. The autonomous demo at power-on remains useful as a hardware-alive indicator. |
| Status frame | Old firmware emitted a multi-tag burst (`I`, `S`, `R`, `V`, `F`, `T`, `A`, `W`, `Y`, `U`, `B`, `C`, `M`, `K`, `Z`, `O`, `D`, `E`, `V3`, `VT`, `VA`, `VV`, `G`, `H`, `J`, `L`, `N`, `P`, `S3`, `ST`, `Q`, `X`, `CC`) every several seconds | Single 62-byte `P5M2 BOOT=... TICK=... VC=... Q=... X=...\r\n` every 500 ms | Old firmware exposed many more diagnostic counters; M2 keeps only the four most useful (BOOT for freshness, TICK for sample rate, VC for round-robin progress, Q/X for command/error semantics). For host-wrapper validation this is sufficient: the wrappers only need to know commands are arriving (Q) and errors are bounded (X). The verifier can still cross-check against audio. |
| Per-voice telemetry | `Y/U/B/C/M/K/Z/O/D/E/V3/VT/VA/VV` per-voice diagnostic counters | Not exposed in P5M2 frame | Verifier-side observability is reduced. Mitigation: M3 does not need per-voice diagnostics for compatibility validation. If a future M4 slice needs them, a P5M3 frame extension or a dedicated debug build can re-expose them without reviving MMIO. |
| Velocity scaling | Same `velocity[15:0]` field, same 0..0x7FFF clamp | Identical | None |
| Loop length scaling | Same `loop_len[6:0]` field, same 32..127 clamp, same A4 = 106 calibration | Identical | None |
| Error classification | Same 1=malformed, 2=unknown opcode, 3=overlong, 4=hardware/partial-flush, 7=unsupported arg (5 = rate-limit and 6 = hardware in old firmware are absent because there is no rate-limit and hardware errors fold into 4) | Subset; host wrappers do not depend on codes 5/6 | Host can rely on 1/2/3/4/7. Codes 5/6 from the old firmware were never exposed in the host wrappers. Documented absence is fine. |

Conclusion: every functional divergence between M2 and the old
firmware is either (a) host-side equivalent because the wrappers
already model their own state, or (b) a minor diagnostic reduction
that does not block host-wrapper compatibility. The most audible
potential divergence is round-robin vs LRU stealing under sustained
polyphonic load. M3 should produce evidence about whether this
matters in practice before queueing any RTL work to fix it.

## 3. Question 3: Minimum host-wrapper compatibility work

Recommendation: **validate the existing scripts as-is, plus add one
tiny pure-Python P5M2 frame decoder** for verifier convenience.

The four host wrappers use a common command surface:

- `phase3_m5_keyboard.py`: pure synthesis of `!NLLLLVVVV\r\n`
  strings from MIDI numbers / note names. No state. No RX. Compatible
  unchanged with M2: the protocol is byte-identical at the command
  side.
- `phase3_m6_live_play.py`: parses comma-separated sequences,
  resolves to commands via `phase3_m5_keyboard`, sends with optional
  delay. No RX. Compatible unchanged with M2.
- `phase3_m7_track_release.py`: tracks active notes host-side,
  emits `!F` only when the active set empties. Compatible unchanged
  with M2 because M2 honors `!F` exactly the same way (shared
  high-damping for all voices). The wrapper's `!F` discipline maps
  cleanly to M2 RTL semantics.
- `phase3_m9_interactive.py`: stdin-driven incremental sender. Same
  command surface as M5/M6, plus per-token state machine. Compatible
  unchanged with M2.

What the wrappers do NOT do today:
- They never read or parse UART TX. They are write-only.
- They have no awareness of `BOOT`/`TICK`/`VC`/`Q`/`X` fields.
- They have no rate-limiting against the M2 14-byte command
  parser; if the host sends bursts faster than the parser drains the
  line buffer, ERR_OVERLONG could fire. This is unlikely at the
  current 80 ms inter-command delay (well below the parser's
  multi-millisecond drain rate at 115200) but worth noting.

Proposed M3 helper:

`scripts/phase5_m3_p5m2_decode.py`: ~80-line Python script that
opens a COM port, reads UART TX bytes, accumulates 62-byte CRLF-
terminated frames, decodes BOOT/TICK/VC/Q/X, and prints a tabular
log per frame. Pure stdlib (or pyserial only). Used by the verifier
(and by future implementers) to read M2 status frames without
hand-decoding ASCII.

This helper is small enough to write and ASCII-only. It does not
affect RTL.

## 4. Question 4: LE cleanup vs more features

Recommendation: **leave LE alone for now**, validate first.

Current free LE: 5,591 (54%). M2 had +753 LE delta against a +800
hard cap, but the absolute consumption is still under half-die.
Plausible cleanup wins are honest but small:

| Candidate | Estimated LE saving | Risk | Verdict |
| --- | ---: | --- | --- |
| Line buffer 16 -> 12 bytes | ~30 LE | Low. The longest valid command is 12 bytes; 16 was chosen for headroom. Reducing to 12 means an overlong starts at byte 11 instead of 14, slightly tighter rejection. | Defer. Easy enough to do later if pressure returns. |
| `tick_counter_free` 32 -> 24 bits | ~8 LE | Low. 24-bit overflow at 46.875 kHz wraps every 358 s; verifier already sees TICK as wrap-aware monotonic. | Defer. |
| Q/X snapshot widths | None safe. The protocol contract specifies 8-hex-digit fields for both. | Higher. Changing widths changes the protocol surface. | Reject for M3. |
| `command_count` 32 -> 16 bits | ~16 LE in fixed_control + status_tx | Medium. 16-bit `command_count` overflows after 65,536 commands; for sustained host-play sessions that is plausible (a fast typist at 4 commands/sec hits 65k in 4.5 hours). Old firmware also used 32-bit. Protocol contract for Q is 8-hex-digit; narrowing the underlying register would just zero-extend. | Defer. Saves little, costs protocol margin. |
| `byte_index` selector 7 -> 6 bits via byte chunking | ~minimal | High refactor risk. | Reject. |

Total plausible savings: ~50-100 LE, all from the new M2 surface,
none from baseline blocks. The risk-to-savings ratio is poor for M3.
A future M4 or M5 slice can revisit if a feature pushes us over a
gate.

LE-cleanup as a standalone task is not worth queuing now. If a
future RTL feature lands close to a gate, fold the cleanup into that
task.

## 5. Question 5: If recommending per-voice release or LRU semantics

I am NOT recommending per-voice release or LRU stealing for M3.
Reasoning:

- LRU stealing is the more commonly-cited "missing feature" but
  evidence for whether it matters audibly with the M2 round-robin
  scheme has not been collected yet. M3 produces that evidence.
- Per-voice release adds parser state (which voice is being
  released?) or a new command syntax (`!F<voice>`). Old firmware's
  `!F` was already shared-damping, and the host wrapper M7a was
  designed around shared-damping semantics. Per-voice release would
  require either a new RTL state machine or a host-side voice
  tracker tied to which physical voice the RTL just fired (which
  the host cannot observe today). Both options are larger RTL slices
  than M3 should accept.

If, after M3, the host-wrapper validation report shows clearly
audible regression vs old firmware (e.g. sustained chord plays
abruptly clip), then M4 should be one of:

### M4 candidate A: LRU voice stealing in `phase0_fixed_control`

Semantics:
- Replace the post-incremented `voice_index` selector with an
  age-based selector. Each voice has a `last_triggered_age[3:0]`
  counter that increments globally on every sample tick (saturating).
  A voice that just fired has `age=0`; the others advance.
- A 1-bit per-voice `active_flag` register tracks whether the voice
  is still playing (could be wired from the `phase1_reduced_voice`
  status outputs that are currently sunk into
  `_unused_audio_path_status`).
- Voice selection: prefer the lowest-`active_flag` voice; if all
  active, pick the one with the largest age.
- Acceptance gate: LE delta <= +200 vs M2; setup slack
  `sys_clk_50m` >= +4.0 ns; ModelSim test that drives 6 commands
  >= the 4-voice cap and confirms voice_index visits voices in LRU
  order; hardware audio capture during a sustained-chord stress test
  shows fewer voice-overwrite artifacts than M2 round-robin.

### M4 candidate B: per-voice release tracking

Semantics:
- `!F` becomes a "release-most-recent-note" command: only the voice
  that fired most recently has its `damp_mix` raised; the others
  remain at default.
- Or `!F<voice>` adds a 1-hex-digit voice selector.
- Acceptance gate: LE delta <= +150 vs M2; setup slack
  >= +4.0 ns; ModelSim test that injects two `!N` then `!F` and
  confirms only the second voice damps; hardware capture of sustained
  chord with selective release.

Both candidates are deferred. M3 produces evidence; the orchestrator
queues M4 against that evidence.

## 6. Question 6: Recommended next implementer / verifier task split

### Phase 5 M3 implementer task: host-wrapper compatibility validation slice

Description (suitable for orchestrator queue text):

> Validate the Phase 3 host wrappers (`scripts/phase3_m5_keyboard.py`,
> `scripts/phase3_m6_live_play.py`,
> `scripts/phase3_m7_track_release.py`,
> `scripts/phase3_m9_interactive.py`) against the live Phase 5 M2
> RTL UART command path on hardware. No RTL changes.
>
> Read before starting:
> - `reports/phase5_m2_uart_rx_command_impl.md`
> - `reports/phase5_m2_uart_rx_command_validation.md`
> - `reports/phase5_m3_command_mode_next_scope.md`
> - The four `scripts/phase3_m{5,6,7,9}*.py` files
>
> Required deliverables:
> 1. New: `scripts/phase5_m3_p5m2_decode.py`. Pure-Python (stdlib +
>    pyserial only) helper that opens a COM port at 115200 8N1,
>    accumulates CRLF-terminated 62-byte P5M2 frames, decodes
>    BOOT/TICK/VC/Q/X, and prints a tabular log. Include a
>    `--self-check` mode that decodes a fixed test vector. ASCII-only.
> 2. New: `reports/phase5_m3_host_wrapper_validation.md`. Per-wrapper
>    section documenting:
>    - Self-check pass/fail (`--self-check` for each wrapper).
>    - One small known-good play session captured against the M2
>      board (5-15 seconds typical).
>    - Captured P5M2 frames during the session, with Q/X behavior
>      cross-checked against expected command/error counts.
>    - Captured analog audio (.wav, 6-10 s) confirming non-clipping,
>      non-silent output.
>    - Honest assessment of any audible behavior differences vs the
>      old firmware (round-robin vs LRU, shared-damp `!F`, autonomous
>      gate).
> 3. No RTL changes.
> 4. No QSF changes.
> 5. No firmware revival.
> 6. Capture artifacts may be saved into `reports/` (subject to
>    verifier-protected-paths discipline) or `.kiro/` (local-only).
>    Do not edit any of the verifier-protected untracked files.
>
> Hard validation gates:
> - All four `--self-check` modes PASS.
> - At least one wrapper produces a known-good 5+ second hardware
>   audio capture with no clipping and no silence within the capture
>   window.
> - Q increments by exactly the count of valid commands sent in
>   the session.
> - X low16 increments only on intentional malformed commands; X
>   high16 reflects the most recent error code correctly.
> - No changes anywhere in `rtl/`, `quartus/`, or `obsolete/`.
> - ASCII-only on touched files.
> - `phase1_reduced_voice_tb` not rerun (no audio path change).
>
> Stop-and-report (NO-GO) triggers:
> - Self-check failures the wrapper code does not document as
>   acceptable.
> - Audible audio regression vs M0/M1/M2 baseline that cannot be
>   attributed to host-wrapper choice.
> - Host wrapper requires RTL behavior that M2 does not provide and
>   no host-side workaround exists.
>
> Expected outcome: PASS report covering all four wrappers, with
> documented divergences (round-robin vs LRU specifically) and a
> clear recommendation about whether M4 should target LRU stealing,
> per-voice release, both, or neither.
>
> Refs: `task-507b33ae` (this scope), commit `5ee0c7c`.

### Phase 5 M3 verifier task: independent validation review

Description:

> Review the implementer's M3 host-wrapper validation report and
> attached captures.
>
> Required:
> - Confirm `--self-check` PASS for each of the four host wrappers
>   (re-run them).
> - Spot-check the P5M2 frame log against the documented session
>   transcript: Q increments match valid commands, X behavior
>   matches malformed-command injection points.
> - Listen to or scope the audio capture; confirm no clipping or
>   silence.
> - Confirm no `rtl/`, `quartus/`, or `obsolete/` changes in the
>   validation commit.
> - Submit `reports/phase5_m3_host_wrapper_validation_validation.md`.
> - Recommend M4 follow-up tasks if the divergence assessment
>   warrants RTL work.

## 7. Honest assessment

This M3 scope is conservative. The strongest argument for it: the
last three milestones (M0 flatten, M1 TX restore, M2 RX restore)
were all RTL slices. A non-RTL validation slice now is the right
checkpoint before deciding whether to invest more LE in LRU or
per-voice release. The host wrappers are the highest-value
integration target because they were the original consumers of the
old firmware's command surface, and they were never deleted; they
are the closest thing this project has to an end-to-end acceptance
suite for command-driven play.

The weakest argument against it: M3 produces no new audio capability
on the board. If the orchestrator wants visible new RTL function in
M3, the alternatives in section 5 are reasonable but have no
evidence yet. M3 produces that evidence cheaply.

If LRU stealing turns out to be obviously needed, M4 implementer
work (LE budget +200) is small enough to land in the same week as
M3 with no schedule risk.

## 8. Out of scope for this report

- No RTL change. No QSF change. No firmware change. No obsolete
  archive change. No new `rtl/control/*.v` or `rtl/peripherals/*.v`.
- No audio path internals. No SDC, pin, PLL, or build-script change.
- No `.kiro/` or untracked verifier-artifact edits.

ASCII-only by construction.
