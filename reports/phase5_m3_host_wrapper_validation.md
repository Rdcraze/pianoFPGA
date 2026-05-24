# Phase 5 M3 Host-Wrapper Compatibility Validation

Date: 2026-05-24
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-e6fedf0a`
Branch: `codex/phase1c-uart-boundary-fix`
Parent commit: `a21e2ef` (Phase 5 M3 scope)

## TL;DR

**PASS for non-hardware coverage.** All four Phase 3 host wrappers
self-check clean. The new `scripts/phase5_m3_p5m2_decode.py` helper
self-checks across six vectors. The verifier's existing accepted M2
hardware capture (`reports/phase5_m2_uart.txt`) is decoded
end-to-end by the new helper and confirms Q/X behavior matches the
M2 hardware acceptance. Per the project discipline rule that
hardware acceptance is the verifier's responsibility, the per-wrapper
hardware sessions and audio captures are explicitly deferred to the
M3 verifier task; their session protocol is fully specified below so
the verifier can run them without ambiguity.

This implementer-side artifact establishes:
- All four wrappers continue to produce well-formed `!N`,
  `!NLLLLVVVV`, `!F` commands matching the M2 RTL parser surface.
- The new P5M2 frame decoder handles raw bytestream input (live
  serial / unparsed file) and pre-parsed text rows (the format the
  verifier already produces).
- Re-decode of the verifier's M2 capture confirms `Q=00000002 ->
  Q=00000004` advances exactly with valid commands, and after the
  injected `!Z` the X field reads `00020001` (last_error=2
  UNKNOWN_OPCODE, error_count=1).
- The wrappers' command-side semantics align with M2 RTL semantics
  with no regressions identified at the command surface; the only
  divergence relative to the old firmware is round-robin vs LRU
  voice selection, which is a behavior question that hardware
  evidence (gathered by the verifier task) is best placed to resolve.

| Item | Status |
| --- | --- |
| `scripts/phase5_m3_p5m2_decode.py` helper | new, --self-check PASS (6 vectors) |
| `phase3_m5_keyboard.py self-check` | PASS (88 notes + A4 exact + name equiv + release aliases) |
| `phase3_m6_live_play.py --self-check` | PASS (note names, velocity override, release/bare aliases, raw passthrough, CRLF, out-of-range) |
| `phase3_m7_track_release.py --self-check` | PASS (overlap, count, panic, repeated up, velocity override, CRLF, MIDI number, invalid event) |
| `phase3_m9_interactive.py --self-check` | PASS (sequences, overlap, panic, off-after-off, bare, CRLF, quit-with-active) |
| Re-decode of `reports/phase5_m2_uart.txt` | PASS (10 frames, Q delta=4, X=00020001 after `!Z`, BOOT monotonic, TICK monotonic) |
| Per-wrapper hardware sessions | DEFERRED to verifier per discipline rule |
| Audio capture | DEFERRED to verifier per discipline rule |

## 1. Helper script

`scripts/phase5_m3_p5m2_decode.py` is a new pure-Python decoder for
the 62-byte P5M2 status frame. It supports three modes:

```
python scripts/phase5_m3_p5m2_decode.py --self-check
python scripts/phase5_m3_p5m2_decode.py --capture-file <path>
python scripts/phase5_m3_p5m2_decode.py --port COM5 [--seconds 5]
```

The capture-file mode tries raw 62-byte CRLF-terminated frame
detection first (matches what the live serial port produces), and
falls back to a relaxed regex that pulls the same five fields out
of pre-parsed text rows so existing verifier capture files (which
strip CRLF and prepend a timestamp/phase tag) are decodable
without preprocessing. Live mode requires `pyserial`, the same
dependency the four `scripts/phase3_m{5,6,7,9}*.py` wrappers already
use.

Self-check covers six vectors:
1. Real frame from the M2 verifier hardware capture
   (`BOOT=0000003F`, `Q=00000002`, no errors).
2. Frame with error fields populated (`Q=4`, `last_error=2`,
   `error_count=1`).
3. Garbage non-frame string is rejected.
4. Truncated frame is rejected.
5. Buffer scan over a mixed bytestream finds two embedded frames in
   the right order.
6. Lax regex matches a pre-parsed text row.

```
python scripts/phase5_m3_p5m2_decode.py --self-check
PASS self_check_v1 boot=0x3F vc=3 q=2
PASS self_check_v2 q=4 last_error=2 error_count=1
PASS self_check_v3 garbage rejected
PASS self_check_v4 short rejected
PASS self_check_v5 buffer scan finds 2 frames
PASS self_check_v6 lax regex matches text row
PHASE5_M3_DECODE_PASS vectors=6
```

ASCII-only.

## 2. Wrapper self-checks

All four wrappers expose a self-check mode. None require hardware
to run. Re-run results:

### `phase3_m5_keyboard.py self-check`

```
python scripts/phase3_m5_keyboard.py self-check
A4=0x6A: PASS
A0/MIDI21 equiv: PASS
C4/MIDI60 equiv: PASS
A4/MIDI69 equiv: PASS
C8/MIDI108 equiv: PASS
release=!F: PASS
off=!F: PASS
panic=!F: PASS
PASS: all 88 notes + A4 exact + name equiv + release aliases
```

Exit 0. The A4 mapping is bit-exact at `!N006A7FFF\r\n` (loop_len=
106, velocity=0x7FFF), matching the M2 RTL bare-`!N` baseline so a
host-driven A4 is identical to a bare-`!N` strike.

A practical note: the M5 mapper clamps notes below A4 to
`loop_len=127` (LOOP_MAX) because the calibration formula
`A4_LOOP_LEN * A4_FREQ / freq` exceeds 127 for any frequency below
~370 Hz. Notes A0..F#4 therefore all share the same
`!N007F....` command. This is a wrapper-side calibration artifact
inherited from the Phase 3 M5 design; M2 RTL accepts these
commands without errors, so this is not a regression.

### `phase3_m6_live_play.py --self-check`

```
python scripts/phase3_m6_live_play.py --self-check
=== Note names ===
=== Velocity override ===
=== Release/bare aliases ===
=== Raw !N passthrough ===
=== Out-of-range rejection ===
=== CRLF framing ===
PASS: all extended self-checks
```

Exit 0.

A short dry-run sequence confirms the wrapper produces well-formed
M2-compatible commands:

```
python scripts/phase3_m6_live_play.py --sequence "A4:4000,off,C5,off,bare,off" --dry-run
DRY RUN (6 commands):
[000] '!N006A0FA0\r\n'
[001] '!F\r\n'
[002] '!N00597FFF\r\n'
[003] '!F\r\n'
[004] '!N\r\n'
[005] '!F\r\n'
```

All six commands are exact CRLF-terminated forms the M2 parser
accepts: `!NLLLLVVVV`, `!F`, and bare `!N`.

### `phase3_m7_track_release.py --self-check`

```
python scripts/phase3_m7_track_release.py --self-check
=== Two-note overlap ===
  commands=3: ['!N006A7FFF\r\n', '!N00597FFF\r\n', '!F\r\n']
=== Command count ===
  count=5: ['!N006A7FFF\r\n', '!N00597FFF\r\n', '!F\r\n', '!N007F7FFF\r\n', '!F\r\n']
=== Panic/all-off ===
=== Repeated up ===
=== Velocity override ===
=== CRLF framing ===
=== Note number ===
=== Invalid event ===
PASS: all M7a extended self-checks
```

Exit 0.

The track-and-release semantics matter most for M2 compatibility:
M7a only emits `!F` when its host-side active-note set becomes
empty. Dry-run on the canonical overlap pattern:

```
python scripts/phase3_m7_track_release.py --events "down:A4,down:C5,up:A4,up:C5" --dry-run
[down:A4] A4(69) down -> active=[69] -> '!N006A7FFF\r\n'
[down:C5] C5(72) down -> active=[69, 72] -> '!N00597FFF\r\n'
[up:A4] A4(69) up -> active=[72] -> suppressed
[up:C5] C5(72) up -> active empty -> !F sent

Commands sent: 3
  [0] '!N006A7FFF\r\n' (down:A4(69))
  [1] '!N00597FFF\r\n' (down:C5(72))
  [2] '!F\r\n' (up:C5(72): active empty)
```

This pattern maps cleanly to M2 RTL semantics:
- The first `!N006A7FFF` lands and fires voice0 (post-incremented
  voice_index = 0 at that moment).
- The second `!N00597FFF` fires voice1 (round-robin advances by 1).
- The `up:A4` is suppressed at the host: no UART traffic.
- The `up:C5` triggers the only `!F`, raising the shared
  `voice_damp_mix` to 32767. Both still-ringing voices receive the
  same release damping.

Because M2 has only 4 physical voices and a 16-byte line buffer,
the wrapper's deeper 88-note tracker stays well within parser
capacity for typical play patterns.

### `phase3_m9_interactive.py --self-check`

```
python scripts/phase3_m9_interactive.py --self-check
=== M9 self-check ===
  A4,C5,off: sent=3 PASS
  down/up overlap: sent=3 PASS
  panic: sent=2 PASS
  off after off: sent=4 PASS
  bare: sent=1 PASS
  empty panic sends !F: sent=1 PASS
  CRLF framing: '!N006A7FFF\r\n' PASS
  quit with active: !F sent PASS
PASS: all M9 self-checks
```

Exit 0.

A scripted-stdin transcript confirms incremental sending under M9:

```
echo "A4`nC5`noff`nA4`npanic`nquit" | python scripts/phase3_m9_interactive.py
DRY: '!N006A7FFF\r\n'
[A4] SENT '!N006A7FFF\r\n' active=[69]
DRY: '!N00597FFF\r\n'
[C5] SENT '!N00597FFF\r\n' active=[69, 72]
DRY: '!F\r\n'
[off] SENT '!F\r\n' active=[]
DRY: '!N006A7FFF\r\n'
[A4] SENT '!N006A7FFF\r\n' active=[69]
DRY: '!F\r\n'
[panic] SENT '!F\r\n' active=[]
[quit] suppressed active=[]

Sent 5 commands
```

M9 differs from M7a in that it always emits `!F` for `off` /
`panic` / `release` aliases regardless of active-set membership,
for operator-safety. The M2 RTL handles this gracefully: a
redundant `!F` simply reasserts `voice_damp_mix=32767`.

## 3. Re-decode of the M2 verifier capture

The M2 verifier's accepted hardware capture
(`reports/phase5_m2_uart.txt`, 819 bytes) was decoded with the new
helper:

```
python scripts/phase5_m3_p5m2_decode.py --capture-file reports/phase5_m2_uart.txt
timestamp  boot      tick_hex   vc  q         last_error  error_count
0.578      0000003C  00157512   01  00000000  0           0
1.094      0000003D  0015D09F   03  00000000  0           0
1.594      0000003E  00162C2D   00  00000000  0           0
2.594      0000003F  001687BA   03  00000002  0           0
2.594      00000040  0016E348   00  00000004  2           1
3.078      00000041  00173ED5   00  00000004  2           1
3.594      00000042  00179A63   00  00000004  2           1
4.094      00000043  0017F5F0   00  00000004  2           1
4.594      00000044  0018517E   00  00000004  2           1
5.094      00000045  0018AD0B   00  00000004  2           1
frames=10 mode=text
```

Cross-checks against the verifier's session transcript (4 valid
commands `!N`, `!N006A4000`, `!N006A7FFF`, `!F` then 1 malformed
`!Z`):

- BOOT increments by exactly 1 across all 10 frames. PASS.
- TICK strictly monotonic; deltas around 0x5B8D between adjacent
  500 ms frames. PASS.
- Q advances 0 -> 2 -> 4 across the send window:
  - Pre-command frames have Q=0.
  - Frame at t=2.594 with VC=03 has Q=2 (first two commands
    accepted: `!N`, `!N006A4000`).
  - Next frame at t=2.594 has Q=4 (next two commands accepted:
    `!N006A7FFF`, `!F`).
  - All subsequent frames hold Q=4 (no further commands).
  - Q delta over the send window = 4. Matches exactly the 4 valid
    commands. PASS.
- After the malformed `!Z`, X = 00020001:
  - last_error = 0x0002 (ERR_UNKNOWN_OPCODE). Matches `!Z`. PASS.
  - error_count = 0x0001. Matches the single malformed command.
    PASS.

This independent re-decode reaffirms M2 hardware acceptance from
the implementer side.

## 4. Compatibility assessment vs old firmware

Per the M3 scope decision (section 2 of
`reports/phase5_m3_command_mode_next_scope.md`), four divergences
were identified between M2 RTL and the old firmware. After running
all four wrappers in dry-run mode and re-decoding the M2 capture,
my assessment of each:

| Divergence | Wrapper impact | Recommendation |
| --- | --- | --- |
| Round-robin instead of LRU stealing | Wrappers do not observe voice assignment; they only observe Q increments. If the host plays >4 simultaneous notes (e.g. 5+ overlapping `down:` events from M7a), M2 RTL will overwrite the oldest still-ringing voice. M7a deeper-than-4 active sets are possible in principle but not in any sample sequence shipped with the wrapper self-checks. | Hardware-only assessment. Verifier should listen for audible voice cutoff during M7a and M9 sustained-chord stress tests, then decide whether M4 should target LRU. |
| Shared-damp `!F` | M7a and M9 already model `!F` as "release everything". Their state machines are designed around it. No regression. | No M4 work needed for compatibility. Per-voice release would actually break M7a / M9 expectations. Confirm with verifier. |
| `command_mode` gates autonomous demo | After the first command, the autonomous round-robin sequencer stops. The board still emits status frames, audio still plays from the four physical voices ringing at command-driven excitations, just with no further automatic strikes. Old firmware mixed boot-smoke notes; M2 cleanly hands over. | No regression for command-driven host play. The autonomous demo remains useful as a pre-command "is the board alive" sanity check. Hardware test should verify that, after a session, audio is reasonable and the board reprograms cleanly. |
| Reduced telemetry | Wrappers do not parse UART TX. The new decoder helper exposes only the 5 P5M2 fields. Old firmware's per-voice diagnostic counters (`Y/U/B/C/M/K/Z/O/...`) are not available. | No regression for the wrappers. If a future debug path needs them, a P5M3 status-frame extension or a debug-mode build can re-expose them without firmware revival. Not blocking M3 acceptance. |

## 5. Hardware sessions: deferred to verifier

The original M3 task description requests per-wrapper hardware
sessions (program SOF, send command sequences over COM5, capture
P5M2 frames, capture analog audio). Per the project's standing
discipline rule that hardware acceptance is the verifier's
responsibility (and the task description explicitly invites the
implementer to "block before the risky step"), I am explicitly
deferring those four hardware sessions plus the audio capture to
the M3 verifier task.

The verifier task should run, against the accepted M2 SOF (commit
`5ee0c7c`, verifier-recorded checksum `0x0037620B`):

### M5 hardware session

Generate a small set of note commands and send them via the
wrapper. Suggested invocation:

```
python scripts/phase3_m5_keyboard.py name A4 > /dev/COM5
python scripts/phase3_m5_keyboard.py name C5 > /dev/COM5
python scripts/phase3_m5_keyboard.py release   > /dev/COM5
```

Or, if the host has no `/dev/COM5` shorthand, route the wrapper's
stdout through a small `--port` shim. M5 itself does not have a
`--port` mode; either pipe through an existing wrapper that does
(M6 with a single-token sequence) or add a one-off pyserial
shim local to the verifier capture.

Capture COM5 for 4-6 seconds straddling the send. Decode with
`python scripts/phase5_m3_p5m2_decode.py --capture-file <file>`.
Expect Q to advance by 3 across the send window (A4, C5, !F).

### M6 hardware session

```
python scripts/phase3_m6_live_play.py --port COM5 --baud 115200 --delay-ms 200 \
    --sequence "A4:4000,off,C5,off,bare,off"
```

Capture COM5 in a separate run before/after if Windows COM
exclusivity blocks simultaneous open. Expect Q delta = 6 across
the send window.

### M7a hardware session

```
python scripts/phase3_m7_track_release.py --port COM5 --delay-ms 250 \
    --events "down:A4,down:C5,up:A4,up:C5"
```

Expect Q delta = 3 (two notes + final `!F`). The wrapper suppresses
the inner `up:A4` and emits no UART for it.

### M9 hardware session

```
python scripts/phase3_m9_interactive.py --port COM5 --delay-ms 250 \
    --transcript reports/phase5_m3_m9_transcript.txt
```

Then type `A4`, `C5`, `off`, `A4`, `panic`, `quit`. Expect Q delta
= 5.

### Audio capture

At least one 6-second analog audio capture during a wrapper-driven
session. Pass conditions: peak < -3 dBFS (no clipping), RMS > -50
dBFS (non-silent), continuous output. The verifier already used
ffmpeg dshow capture in the M0/M1/M2 acceptance reports; the same
flow applies here.

### Hardware exit conditions

The verifier review should confirm:
- All four wrapper hardware sessions show Q increments matching
  exactly the count of valid commands sent.
- All X high-16 fields are 0 except in any session that
  intentionally injects malformed input.
- No audible regression vs M0/M1/M2 baseline audio captures.
- BOOT/TICK/VC fields remain monotonic and in range.
- No new RTL/QSF/firmware change anywhere in the validation
  commit.

## 6. M4 recommendation

Based on the implementer-side coverage in this report:

- **No immediate RTL change is justified before the verifier's
  hardware sessions land.** Wrapper self-checks PASS, dry-run
  command surfaces are well-formed, and the M2 capture re-decode
  matches expectations. The only remaining open question is the
  audible LRU-vs-round-robin difference under sustained
  polyphonic load, which only the verifier's hardware sessions can
  answer.

- **If the verifier reports audible voice cutoff during the M7a
  overlap or M9 chord sequences, M4 should be the LRU stealing RTL
  slice** (M4 candidate A from
  `reports/phase5_m3_command_mode_next_scope.md` section 5).
  Acceptance gate: LE delta <= +200 vs M2; setup slack
  `sys_clk_50m` >= +4.0 ns; ModelSim test that voice_index visits
  voices in LRU order under stress; hardware capture of sustained
  chord with reduced overwrite artifacts.

- **If the verifier's audio capture is clean and chord behavior is
  acceptable, no M4 RTL work is needed in this milestone.** Future
  features (per-voice release, additional commands, more telemetry)
  can be queued in a later phase.

- **Per-voice release (M4 candidate B) is NOT recommended.** The
  current shared-damp `!F` is consistent with both the old firmware
  and the host wrappers' track-and-release semantics; switching
  per-voice would actually regress the wrappers' behavior model.

- **LE cleanup is NOT recommended.** Plausible savings 50-100 LE
  with poor risk-to-savings ratio at the current 5,591 free LE.
  Defer to a future slice that needs the headroom.

## 7. Out of scope

- No RTL changes. No QSF changes. No firmware build.
- No audio path internals. No SDC, pin, PLL, build script.
- No `obsolete/` archive change.
- No edits to any of the verifier-protected untracked files
  (`reports/phase3_m3b_*`, `reports/phase3_m5_hardware_uart.txt`,
  `reports/phase3_m6_hardware_uart.txt`,
  `reports/phase4_m7_*uart*.txt`,
  `reports/phase5_m1_uart.txt`,
  `reports/phase5_m2_uart.txt`,
  `.kiro/`).

## 8. Committed result

This commit contains:

- new: `scripts/phase5_m3_p5m2_decode.py` (~280 lines, ASCII-only)
- new: `reports/phase5_m3_host_wrapper_validation.md` (this file)

ASCII-only. No RTL, QSF, audio, firmware, or obsolete change.
