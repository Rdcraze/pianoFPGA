# Phase 3 M9 Post-M8 Scope

Date: 2026-05-14 | Agent: claude-implementer | Task: `task-d9372798`

## Verdict: GO -- host-side interactive keyboard wrapper (zero firmware cost)

## State After M8

- Firmware ROM: 931/1024 (93 words free)
- M7a host track-and-release is the accepted note-off workaround
- M8 ROM reclamation failed (function extraction costs exceed inline savings)
- M5 keyboard mapper + M6 live-play + M7a track-and-release provide host-side playability

## What Can Fit In 93 Words

A minimal firmware feature (~20-30 words): None that justifies the risk. Adding anything to firmware at this density risks destabilizing accepted UART behavior.

## Recommended M9: Interactive Host Keyboard Wrapper

Extend M6 live-play with an interactive mode that reads from stdin or a named pipe, converts key tokens to commands in real-time, and sends to serial. This is M6 plus a readline/input loop. Zero firmware cost.

## Explicitly Rejected

- Per-note firmware note IDs: ROM budget exhausted (M7 analysis)
- Per-voice damp registers: RTL LE budget too tight (9,992/10,320)
- Any ROM reclamation: M8 proved function extraction does not save words
- Lookup tables in firmware: 93 words insufficient for useful table size

## Proposed Implementer Task

Title: "Implement Phase 3 M9 interactive stdin-to-UART keyboard wrapper"

Extend M6 live-play with an interactive `--interactive` mode that reads tokens from stdin, converts to commands via M5 mapper, and either dry-runs or sends via serial. No firmware/RTL changes. Add `--transcript LOG` option. Self-check must verify: interactive parse, M7a up/down event compatibility, release/panic aliases, and dry-run CRLF framing.

## Proposed Verifier Task

Title: "Validate Phase 3 M9 interactive keyboard wrapper"

Verifier checks: ASCII-only source, no FW/RTL diffs, self-check PASS, dry-run transcript matches expected commands for test sequence `A4,C5,off`, hardware serial test with `--port COMx` sends valid commands (Q increments, X=0, K=0). Rollback: remove script, no FW/RTL restored needed.

## Acceptance Gates

| Gate | Threshold |
| --- | --- |
| Host-tool-only | No FW/RTL/SDC/pin/PLL changes |
| Dry-run output | repr(cmd) with CRLF framing |
| Self-check | PASS with A4,C5,off sequence |
| Interactive mode | Reads stdin, emits M5 commands |
| Hardware UART | K=0, X=0, Q increments |

## Next Task

"Implement Phase 3 M9: interactive stdin-to-UART keyboard wrapper extending M6"
