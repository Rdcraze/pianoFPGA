# Phase 3 M7a Track-and-Release Wrapper Validation (Fixed)

Verifier: claude-verifier `e8db32f8-3c5f-4a11-bf2d-8f6e3ad76c4c`
Task: `task-dc70eed8`

## Verdict

**PASS - M7a host track-and-release wrapper accepted as host-tool baseline.**

Self-check covers all required properties: two-note overlap, command count, panic, repeated up, velocity override, note number, invalid event rejection, and CRLF framing. Dry-run shows structured repr output with active-set transitions - no raw CRLF command lines. up:A4 correctly suppressed while C5 active (send count 5). Hardware confirms Q+5, X+0, K=0.

## Scope

Host-tool only. No firmware/RTL changes.

## Self-Check

```
=== Two-note overlap ===
  commands=3: ['!N006A7FFF\r\n', '!N00597FFF\r\n', '!F\r\n']
  PASS
=== Command count ===
  count=5: [5 commands matching the test sequence]
  PASS
=== Panic/all-off ===
  PASS
=== Repeated up ===
  PASS
=== Velocity override ===
  PASS
=== CRLF framing ===
  PASS
=== Note number ===
  PASS
=== Invalid event ===
  correctly rejected
  PASS

PASS: all M7a extended self-checks
```

## Dry-Run

```
Events: down:A4,down:C5,up:A4,up:C5,down:C4,panic

[down:A4] A4(69) down -> active=[69] -> '!N006A7FFF\r\n'
[down:C5] C5(72) down -> active=[69,72] -> '!N00597FFF\r\n'
[up:A4] A4(69) up -> active=[72] -> suppressed
[up:C5] C5(72) up -> active empty -> !F sent
[down:C4] C4(60) down -> active=[60] -> '!N007F7FFF\r\n'
[panic] cleared, !F sent

Commands sent: 5
  [0] '!N006A7FFF\r\n' (down:A4(69))
  [1] '!N00597FFF\r\n' (down:C5(72))
  [2] '!F\r\n' (up:C5(72): active empty)
  [3] '!N007F7FFF\r\n' (down:C4(60))
  [4] '!F\r\n' (panic: active cleared)
```

5 commands sent. up:A4 suppressed (C5 still active). Structured repr output.

## Hardware UART

Fresh capture: `reports/phase3_m7a_hardware_uart.txt`

| Metric | Before | After | Delta |
| --- | --- | --- | --- |
| Q | 0x1D | 0x22 | +5 |
| X | 0x00020002 | 0x00020002 | 0 |
| K | 0 | 0 | 0 |

## Recommendation

**PASS - accept M7a host track-and-release wrapper as host-tool baseline.**
