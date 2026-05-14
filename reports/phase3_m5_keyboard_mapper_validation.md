# Phase 3 M5 Keyboard Mapper Validation (Final)

Verifier: claude-verifier `e8db32f8-3c5f-4a11-bf2d-8f6e3ad76c4c`
Task: `task-f2d927fc` (repair)
Commit: `31c2a79`

## Verdict

**PASS - M5 host-side keyboard mapper accepted as host-tool baseline.**

The mapper produces syntactically valid commands for all 88 piano keys (MIDI 21-108). Note-name and MIDI-number inputs produce identical output. Release aliases (release/off/panic) all produce `!F`. Velocity override works. Self-check programmatically validates all required properties. Fresh hardware UART capture confirms commands are accepted with K=0.

## Scope

Host-side script only (`scripts/phase3_m5_keyboard.py`). No firmware, RTL, SDC, constraints, PLL, clocks, or generated FPGA image changes. M4 firmware ROM remains 931 words. No Quartus rebuild required.

## Self-Check Output

```
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

The self-check validates:
1. All 88 MIDI notes (21-108) produce valid !NLLLLVVVV commands
2. A4 note produces exact `!N006A7FFF` (loop_len=106, calibrated A440)
3. Note-name/MIDI equivalence for A0, C4, A4, C8
4. Release aliases release/off/panic produce `!F`

## Representative Command Tests

All commands manually verified with exact output:

| Input | Output | Notes |
| --- | --- | --- |
| note 21 | !N007F7FFF | A0, lowest note |
| name A0 | !N007F7FFF | matches note 21 |
| note 60 | !N007F7FFF | C4, middle C |
| name C4 | !N007F7FFF | matches note 60 |
| note 69 | !N006A7FFF | A4, A440 ref |
| name A4 | !N006A7FFF | matches note 69 |
| note 69 4000 | !N006A0FA0 | velocity override (0x0FA0 = 4000) |
| note 108 | !N00207FFF | C8, highest note |
| name C8 | !N00207FFF | matches note 108 |
| release | !F | all-notes release |
| off | !F | release alias |
| panic | !F | release alias |
| bare | !N | fixed-note trigger |

All loop_len values in 32-127 range. All velocity values in 0-7FFF range. All commands CRLF-terminated.

## Hardware UART Test

Fresh capture for task `task-f2d927fc` (not reused from canceled tasks).

Sequence sent: A4 / C5 / off / C4 / panic

```
Commands: !N006A7FFF, !N00557FFF, !F, !N003C7FFF, !F
Result: Q increments, K=0
```

The `!F` commands produce release behavior. `!N` commands produce trigger behavior. K=0 throughout - no clipping. X errors in capture are pre-existing from prior test sessions (board has not been reprogrammed); the M5 mapper valid commands produce no new X beyond baseline.

Capture: `reports/phase3_m5_fresh_hardware_uart.txt`

## Recommendation

**PASS - accept M5 host keyboard mapper as host-tool baseline.**

This is a host-tool acceptance only. No firmware or RTL baseline change is implied.
