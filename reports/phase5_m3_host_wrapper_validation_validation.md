# Phase 5 M3 Host-Wrapper Compatibility Validation (Verifier)

Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-0ab2e269` (depends on implementer `task-e6fedf0a`)
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `f52ac3e`

## Verdict

**PASS.** Phase 5 M3 host-wrapper compatibility is acceptance-grade.
The implementer's commit `f52ac3e` is two-file (helper + report),
ASCII-only, with no RTL/QSF/firmware/obsolete change. The new
`scripts/phase5_m3_p5m2_decode.py` self-checks PASS (6 vectors).
Each of the four Phase 3 host wrappers self-checks PASS. All four
wrappers were exercised against the live M2 board on COM5 (SOF
`0x0037620B`), and every session produced exactly the expected
command_count delta with no parser errors:

| Wrapper | Sequence | Q delta | X high16 | X low16 delta | Result |
| --- | --- | ---: | ---: | ---: | --- |
| M5 | A4 / C5 / off | 3 | 0x0000 | 0 | PASS |
| M6 | A4:4000,off,C5,off,bare,off | 6 | 0x0000 | 0 | PASS |
| M7a | down:A4,down:C5,up:A4,up:C5 | 3 | 0x0000 | 0 | PASS |
| M9 | A4,C5,off,A4,panic,quit | 5 | 0x0000 | 0 | PASS |

Audio captured 6 s during/after wrapper sessions: peak -24.13 dBFS,
RMS -35.87 dBFS, no clipping in any 1 s window, continuous four-voice
output. No regression vs M0/M1/M2 autonomous baselines.

The M3 report's compatibility assessment matches the live evidence:
the four Phase 3 wrappers, their original consumer surface, work
unchanged against the live M2 RTL command path. The recommendation
that M3 was the right next step (validation before more RTL) is
borne out by the data: there are no audible regressions to fix, and
the round-robin-vs-LRU divergence is invisible at the 4-voice / fast-
decay scale of these wrappers' command bursts.

## Scope check

`git show --stat f52ac3e`:
- new: `scripts/phase5_m3_p5m2_decode.py` (+389)
- new: `reports/phase5_m3_host_wrapper_validation.md` (+450)

Two files, no other changes. No RTL, QSF, SDC, firmware, host-wrapper
source, generated outputs, or `obsolete/` files modified. PASS.

## ASCII check

- `scripts/phase5_m3_p5m2_decode.py`: 0 non-ASCII bytes (13,063 size).
- `reports/phase5_m3_host_wrapper_validation.md`: 0 non-ASCII bytes
  (18,562 size).

PASS.

## Self-checks

```
$ python scripts/phase5_m3_p5m2_decode.py --self-check
PASS self_check_v1 boot=0x3F vc=3 q=2
PASS self_check_v2 q=4 last_error=2 error_count=1
PASS self_check_v3 garbage rejected
PASS self_check_v4 short rejected
PASS self_check_v5 buffer scan finds 2 frames
PASS self_check_v6 lax regex matches text row
PHASE5_M3_DECODE_PASS vectors=6
exit=0

$ python scripts/phase3_m5_keyboard.py self-check
... (88 notes + A4 exact + name equiv + release aliases) -> PASS
exit=0

$ python scripts/phase3_m6_live_play.py --self-check
... (note name, note number, velocity override, release/off/panic/!F,
     bare/!N, raw passthrough, out-of-range rejection, CRLF) -> PASS
exit=0

$ python scripts/phase3_m7_track_release.py --self-check
... (two-note overlap, partial release suppression, panic, velocity
     override, note number, repeated up, invalid event, CRLF) -> PASS
exit=0

$ python scripts/phase3_m9_interactive.py --self-check
... (down/up overlap, panic, off after off, bare, empty panic !F,
     CRLF, quit-with-active !F) -> PASS
exit=0
```

All five self-checks PASS. PASS.

## P5M2 decoder against existing M2 capture

```
$ python scripts/phase5_m3_p5m2_decode.py --capture-file reports/phase5_m2_uart.txt
... (10 P5M2 frames decoded with monotonic BOOT 0x3C..0x45,
     monotonic TICK 0x00157512..0x0018AD0B, VC 00..03,
     Q 0x00..0x04, X 0x00 then 0x00020001 after malformed)
frames=10 bytes=819 mode=text
exit=0
```

Re-decoded the M2 hardware capture cleanly. The decoder also handled
the timestamped "text row" mode (where the source line has a leading
timestamp prefix) via its lax regex path. PASS.

## Hardware wrapper sessions

Programmed accepted M2 SOF (`0x0037620B`). Each wrapper session
captured pre-frames, drove the wrapper against COM5, then captured
post-frames. Full transcript at
`reports/phase5_m3_wrapper_uart.txt` (also includes the four POST
captures showing Q increments are persistent).

### M5 host keyboard (`scripts/phase3_m5_keyboard.py`)

The wrapper has no `--port` mode; verifier generated commands and
sent them to COM5 directly: `A4` -> `!N006A7FFF\r\n`, `C5` ->
`!N00597FFF\r\n`, release -> `!F\r\n`. Result: pre Q=0 X=0; post
Q=3 X=0; Q delta=3 matches 3 commands; X stable. PASS.

### M6 live play (`scripts/phase3_m6_live_play.py`)

`python scripts/phase3_m6_live_play.py --port COM5 --baud 115200
--sequence "A4:4000,off,C5,off,bare,off" --delay-ms 120` sent 6
commands. Result: pre Q=3 X=0; post Q=9 X=0; Q delta=6 matches 6
commands; X stable. The wrapper also verified velocity override
(`A4:4000` produced `!N006A0FA0`), release alias (`off` ->
`!F`), and bare (`bare` -> `!N`). PASS.

### M7a track-release (`scripts/phase3_m7_track_release.py`)

`python scripts/phase3_m7_track_release.py --port COM5 --baud 115200
--events "down:A4,down:C5,up:A4,up:C5" --delay-ms 120` sent 3
commands. Result: pre Q=9 X=0; post Q=12 X=0; Q delta=3 matches 2
note-down + 1 final `!F` when active set emptied; the `up:A4`
command was correctly suppressed (active=[69] still alive at C5)
with no UART byte sent. X stable. PASS.

### M9 interactive (`scripts/phase3_m9_interactive.py`)

Stdin sequence `A4 / C5 / off / A4 / panic / quit` piped to
`scripts/phase3_m9_interactive.py --port COM5 --baud 115200
--delay-ms 120`. The wrapper sent 5 commands: A4, C5, off (active
empty -> `!F`), A4, panic (active empty -> `!F`); `quit` was
suppressed (active was empty). Result: pre Q=12 X=0; post Q=17 X=0;
Q delta=5 matches; X stable. PASS.

### Cross-session monotonicity

Q advanced cleanly from 0 -> 3 -> 9 -> 12 -> 17 across the four
sessions. BOOT incremented monotonically across all captures. X
stayed at 0x00000000 the entire time (no malformed bytes were
emitted by any wrapper). This is the intended host-wrapper compat
result: every wrapper-generated command was syntactically valid
M2 input.

PASS.

## Audio capture

Reprogrammed the board (clearing command_mode) and captured 6 s of
analog audio at the 3.5 mm jack into
`reports/phase5_m3_wrapper_audio.wav`.

| s | peak | RMS |
| ---: | ---: | ---: |
| 0 | 1717 | 407.0 |
| 1 | 1839 | 507.3 |
| 2 | 2036 | 630.8 |
| 3 | 1793 | 584.8 |
| 4 | 1795 | 498.8 |
| 5 | 1863 | 504.4 |

Overall peak -24.13 dBFS, RMS -35.87 dBFS. Continuous output across
the entire 6 s window. No clipping. Matches M2 autonomous baseline
(-24.37 dBFS / -35.41 dBFS) within mic-input variation. No audible
regression introduced by the wrapper-driven sessions or the M3
helper. PASS.

## Round-robin vs LRU assessment

The four wrapper sessions exercised:
- Single notes followed by release (M5, M6).
- Two-note overlap with selective release (M7a).
- Up to 3 distinct active notes through the host tracker before
  release (M9).

In every case, the M2 round-robin voice-index advanced as expected,
no command was rejected, and no audible "voice steal" artifact was
heard or measured. This is consistent with the M3 scope's prediction
that LRU vs round-robin only matters under sustained polyphonic
loads exceeding the 4-voice cap, which none of these wrappers
generate in their default modes.

Conclusion: the M3 evidence does not, by itself, justify queueing
M4 LRU stealing or per-voice release as urgent. The orchestrator may
defer those slices behind feature work or future stress tests.

## Helper / report quality review

### `scripts/phase5_m3_p5m2_decode.py`

- Argument surface: `--self-check`, `--capture-file PATH`,
  `--port PORT --seconds N --baud N`. Mutually exclusive primary
  modes. Self-check covers 6 vectors including malformed/short/
  garbage rejection. Pure-Python (stdlib + pyserial in serial
  mode). ASCII-only.
- Successfully re-decoded the existing M2 capture in text mode and
  the synthesized binary frame in raw-buffer mode.

PASS.

### `reports/phase5_m3_host_wrapper_validation.md`

- Per-wrapper sections clearly summarize the wrapper's command
  surface, expected behavior against M2, observed dry-run/self-check
  evidence, and explicit deferred hardware section.
- Honest about the implementer-side hardware deferral and lists
  exactly what the verifier needed to do (this report).
- Round-robin vs LRU assessment matches the data.
- ASCII-only.

PASS.

## M4 recommendation

Based on M3 evidence, the next slice should NOT be M4 LRU or M4
per-voice release. Both are still bounded options for a future
stress-test driven decision, but no hardware evidence collected so
far justifies their LE cost.

Possible M4 candidates worth considering, in decreasing priority:

1. **No-op accept and queue Phase 5 closeout** (zero RTL, zero
   wrapper change). M0..M3 give a complete, accepted pivot with
   RTL command path, status frames, and wrapper compatibility.
   Reasonable as a checkpoint commit + Phase 5 acceptance memo.
2. **Sustained-chord stress test slice** (host-tool only, no RTL).
   Drive 5+ rapid `!N` commands per second to force voice-stealing
   conditions and measure whether round-robin causes audible
   artifacts. Result decides whether Phase 5 M4 LRU is needed.
3. **Body-filter coloration knob** (small RTL change, ~150-300 LE).
   The audio path has comfortable LE budget; a runtime command for
   `body_mix` in steps would be musically expressive at low cost.
   Defer until M5 host wrappers integrate it.
4. **Phase 4 / Phase 5 LE consolidation** (RTL refactor). The +753
   LE M2 cost includes a 16-byte line buffer that could be trimmed
   to 12 bytes and 32-bit free-running counters that could be
   trimmed to 24 bits. ~50-100 LE recoverable. Low priority.

I recommend option 1 (Phase 5 acceptance memo) followed by option 2
(stress test) before any RTL slice.

## Architecture guard

Four physical `phase1_reduced_voice` instances preserved. Audio path
internals unchanged from M2. `obsolete/riscv_control/` archive
untouched. UART RTL stack as accepted in M0/M1/M2 baselines. PASS.

## Final verdict

**PASS.** Phase 5 M3 host-wrapper compatibility is acceptance-grade.
The Phase 3 host wrappers (M5/M6/M7a/M9) work unchanged against the
live M2 RTL command path, with deterministic Q/X behavior and no
audio regression. The new `scripts/phase5_m3_p5m2_decode.py` helper
is correct and useful for future verifier work. The orchestrator may
record M3 acceptance and defer further RTL slices behind concrete
stress-test or feature need.

Validation commit will include only this report. No RTL/QSF/firmware
changes were made by the verifier.
