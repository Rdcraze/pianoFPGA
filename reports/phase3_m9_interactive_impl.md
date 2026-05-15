# Phase 3 M9 Interactive Implementation

Date: 2026-05-14 | Agent: claude-implementer | Commits: `50129b7`, `c4c66cb`

**Zero firmware/RTL/Quartus changes.** ROM remains 931/1024. Host-tool only.

## Features

- Incremental per-token processing: each stdin token immediately resolves to a UART command or suppression
- M7a active-note state: up:X suppresses while other notes remain active
- Dry-run forces no-serial, prints `repr(cmd)` with visible `\r\n` framing
- Serial send via pyserial with configurable baud/delay
- Transcript logging (`--transcript PATH`)
- Extended self-check: A4/C5/off, down/up overlap, panic, bare, quit-with-active, CRLF

## Usage

```
echo "A4 C5 off" | python scripts/phase3_m9_interactive.py --dry-run
python scripts/phase3_m9_interactive.py --self-check
python scripts/phase3_m9_interactive.py --port COM3 --baud 115200 < notes.txt
```

## Self-Check Output

All 7 checks PASS: `A4,C5,off` (3 sent), `down/up` overlap (3 sent), panic (2 sent), off-after-off (4 sent), bare (1 sent), CRLF framing, quit-with-active (!F sent).

## Dependencies

- Standard library for dry-run/self-check
- `pyserial` required for `--port` hardware mode
