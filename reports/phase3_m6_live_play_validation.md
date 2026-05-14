# Phase 3 M6 Live Play Wrapper Validation (Final)

Verifier: claude-verifier `e8db32f8-3c5f-4a11-bf2d-8f6e3ad76c4c`
Task: `task-59f4d01f`

## Verdict

**PASS - M6 host live UART play wrapper accepted as host-tool baseline.**

Self-check covers all required properties. Dry-run displays CRLF framing. Out-of-range rejection works. ASCII-only source. All outputs match accepted M5 mapper.

## Scope

Host-tool only (`scripts/phase3_m6_live_play.py` + implementation report). No firmware, RTL, SDC, constraints, PLL, or generated FPGA image changes. ROM unchanged at 931.

## Self-Check

```
=== Note names ===
  A0: '!N007F7FFF\r\n'
  C4: '!N007F7FFF\r\n'
  A4: '!N006A7FFF\r\n'
  C8: '!N00207FFF\r\n'
  note names: PASS
=== Velocity override ===
  A4:4000 -> '!N006A0FA0\r\n'
  69:0x7FFF -> '!N006A7FFF\r\n'
  velocity override: PASS
=== Release/bare aliases ===
  off: '!F\r\n'
  release: '!F\r\n'
  panic: '!F\r\n'
  !F: '!F\r\n'
  bare: '!N\r\n'
  !N: '!N\r\n'
  release/bare: PASS
=== Raw !N passthrough ===
  !N006A7FFF -> '!N006A7FFF\r\n'
  raw passthrough: PASS
=== Out-of-range rejection ===
  MIDI 999: correctly rejected
  Z9: correctly rejected
  out-of-range: PASS
=== CRLF framing ===
  A4 framed: '!N006A7FFF\r\n'
  CRLF: PASS

PASS: all extended self-checks
```

## Dry-Run

```
$ python phase3_m6_live_play.py --dry-run -s "A4,C5,off,C4,panic,bare,A4:4000,69:0x0FA0,!F,!N"
DRY RUN (10 commands):
[000] '!N006A7FFF\r\n'
[001] '!N00597FFF\r\n'
[002] '!F\r\n'
[003] '!N007F7FFF\r\n'
[004] '!F\r\n'
[005] '!N\r\n'
[006] '!N006A0FA0\r\n'
[007] '!N006A0FA0\r\n'
[008] '!F\r\n'
[009] '!N\r\n'
```

All outputs match M5 mapper. CRLF framing explicitly displayed.

## ASCII Compliance

M6 wrapper script and validation report are ASCII-only.

## Dependencies

- Dry-run: no pyserial required
- Send mode: pyserial installed and available (COM5, 115200 baud)

## Hardware UART

Fresh capture for task `task-59f4d01f` at `reports/phase3_m6_fresh_hardware_uart.txt`.

COM port: COM5, 115200 baud. Sequence: A4, C5, off, C4, panic (5 commands).

| Metric | Before | After | Delta |
| --- | --- | --- | --- |
| Q | 0x13 | 0x18 | +5 |
| X | 0x00020002 | 0x00020002 | 0 |
| K | 0 | 0 | 0 |

Q delta = +5 matches the 5-command sequence. X delta = 0 confirms valid commands introduce no new errors. K=0 throughout - no clipping.

## Recommendation

**PASS - accept M6 host live play wrapper as host-tool baseline.**

No firmware or RTL baseline change is implied.
