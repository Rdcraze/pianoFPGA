# Phase 3 M9 Interactive Wrapper Validation (Final)

Verifier: claude-verifier `e8db32f8-3c5f-4a11-bf2d-8f6e3ad76c4c`
Task: `task-d0a7f60b`

## Verdict

**PASS - M9 final interactive stdin wrapper accepted as host-tool baseline.**

Self-check covers all required properties including empty-state panic. Dry-run shows incremental per-token processing with active state tracking. Transcript records token, action, emit status, and active state. Hardware confirms Q+3, X unchanged, K=0.

## Scope

Host-tool only (`scripts/phase3_m9_interactive.py`). No firmware/RTL changes.

## Self-Check

```
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

## Dry-Run

### Empty-State Panic

```
Echo "panic" | --dry-run
DRY: '!F\r\n'
[panic] SENT '!F\r\n' active=[]
Sent 1 commands
```

Panic alone emits !F. Correct.

### Track-and-Release Sequence

```
Echo "down:A4 down:C5 up:A4 up:C5 panic" | --dry-run

[down:A4] SENT '!N006A7FFF\r\n' active=[69]
[down:C5] SENT '!N00597FFF\r\n' active=[69,72]
[up:A4] suppressed active=[72]
[up:C5] SENT '!F\r\n' active=[]
[panic] SENT '!F\r\n' active=[]

Sent 4 commands
```

up:A4 suppressed (C5 still active). up:C5 sends !F. panic also sends !F. Active state shown per token.

## Hardware UART

| Metric | Before | After | Delta |
| --- | --- | --- | --- |
| Q | 0x0C | 0x0F | +3 |
| X | 0x00010094 | 0x00010094 | 0 |
| K | 0 | 0 | 0 |

## Recommendation

**PASS - accept M9 interactive wrapper as host-tool baseline.**
