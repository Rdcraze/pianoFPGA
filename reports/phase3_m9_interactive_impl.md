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

```
$ python scripts/phase3_m9_interactive.py --self-check
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

## Dry-Run Examples

```
$ echo "panic" | python scripts/phase3_m9_interactive.py --dry-run
DRY: '!F\r\n'
[panic] SENT '!F\r\n' active=[]

$ echo "down:A4 down:C5 up:A4 up:C5 panic" | python scripts/phase3_m9_interactive.py --dry-run
DRY: '!N006A7FFF\r\n'
[down:A4] SENT '!N006A7FFF\r\n' active=[69]
DRY: '!N00597FFF\r\n'
[down:C5] SENT '!N00597FFF\r\n' active=[69, 72]
[up:A4] suppressed active=[72]
DRY: '!F\r\n'
[up:C5] SENT '!F\r\n' active=[]
DRY: '!F\r\n'
[panic] SENT '!F\r\n' active=[]
Sent 4 commands
```
