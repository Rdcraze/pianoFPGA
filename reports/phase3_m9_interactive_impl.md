# Phase 3 M9 Interactive Implementation

Date: 2026-05-15 | Agent: claude-implementer | Commits: `50129b7`, `c4c66cb`, `286b91f`

**Zero firmware/RTL/Quartus changes.** ROM remains 931/1024. Host-tool only.

## Features

- Incremental per-token processing with immediate send/suppress
- M7a active-note state: up:X suppresses while others active
- All release aliases (off/release/panic/all-off) always emit !F and clear active state
- Dry-run forces no-serial, prints repr(cmd) with visible `\r\n` framing
- Console output includes active state per token
- Serial send via pyserial
- Transcript logging (`--transcript PATH`)
- 8 self-checks including empty-state panic

## Usage

```
echo "A4 C5 off" | python scripts/phase3_m9_interactive.py --dry-run
echo "panic" | python scripts/phase3_m9_interactive.py --dry-run
python scripts/phase3_m9_interactive.py --self-check
```

## Self-Check Output

All 8 checks PASS: A4/C5/off (3), down/up overlap (3), panic (2), off-after-off (4), bare (1), empty-panic (1), CRLF, quit-with-active.

## Dry-Run Examples

```
$ echo "panic" | python scripts/phase3_m9_interactive.py --dry-run
DRY: '!F\r\n'
[panic] SENT '!F\r\n' active=[]

$ echo "A4 C5 off" | python scripts/phase3_m9_interactive.py --dry-run
DRY: '!N006A7FFF\r\n'
[A4] SENT '!N006A7FFF\r\n' active=[69]
DRY: '!N00597FFF\r\n'
[C5] SENT '!N00597FFF\r\n' active=[69, 72]
DRY: '!F\r\n'
[off] SENT '!F\r\n' active=[]
```
