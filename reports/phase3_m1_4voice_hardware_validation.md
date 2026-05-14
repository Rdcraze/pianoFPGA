# Phase 3 M1 4-Voice Replication Hardware Validation

Verifier: claude-verifier `e8db32f8-3c5f-4a11-bf2d-8f6e3ad76c4c`
Task: `task-b2543628`
Implementer commits: `9b76aff`, `3e7569d`, `a36ca48`, `67548ca`
Build commit: `67548ca` (HEAD)
SOF checksum: `0x007333FC`

## Verdict

**PASS — 4-voice replication confirmed on hardware. LE exception recorded.**

The 4th voice is active, schedulable, and produces telemetry through appended voice3 tags. K=0 across both no-command and commanded profiles. Timing closed (+2.948 ns). LE count at 9,938 (96%) exceeds the original 9,800 gate by 138 LEs — orchestrator exception accepted.

## LE Exception Record

| Gate | Value | Status |
| --- | --- | --- |
| Original M1 LE gate | <= 9,800 | — |
| Actual fit | 9,938 / 10,320 (96%) | **+138 over gate** |
| Orchestrator exception | Accepted (setup +2.948 ns) | Documented |

The exception is accepted because setup slack (+2.948 ns) exceeds the +2.0 ns minimum and all other compile gates passed. Device headroom is 382 LEs (3.7%).

## Firmware Build Note

The firmware source file (`fw/phase0/phase0_main.c`) had 5 corrupted character literals where raw CR bytes (0x0D) in `'\r'` literals were split across lines by CRLF conversion. These were fixed by replacing raw CR character literals with proper `'\r'` escape sequences. This is a file encoding issue, not a design change — the semantic content is identical. The corruption prevented GCC from compiling the file.

## Quartus Compile

| Metric | Value |
| --- | --- |
| Errors | 0 |
| Warnings | 16 (+2 from Phase 2 baseline) |
| Full compilation | PASS |
| STAs satisfied | All corners TNS = 0.000 |

### Resource

| Resource | Usage | Phase 2 Hammer | Delta |
| --- | --- | --- | --- |
| LEs | 9,938 / 10,320 (96%) | 8,968 | +970 |
| M9K | 16 / 46 (35%) | 14 | +2 |
| DSP 9-bit | 8 | 6 | +2 |
| PLL | 1 | 1 | 0 |
| Registers | 4,005 | 3,601 | +404 |

The +970 LE delta is consistent with replicating one voice (delay line M9K, DSP multiplier, excitation logic, control path). The +2 M9K and +2 DSP per voice is the expected cost.

### Timing (slow-85C sys_clk_50m)

| Metric | Value | Gate |
| --- | --- | --- |
| Setup slack | +2.948 ns | >= +2.0 ns PASS |
| Hold slack | +0.431 ns | > 0 PASS |

## Scope Review

RTL changes relative to Phase 2 hammer baseline:
- `rtl/audio/phase0_audio_path.v`: 4-voice instantiation + mix sum pipeline
- `rtl/control/phase0_control_regs.v`: voice3 register map at 0x80+
- `rtl/top/piano_phase0_top.v`: voice3 port wiring
- `fw/phase0/phase0_hw.h`: voice3 register definitions
- `fw/phase0/phase0_main.c`: voice3 telemetry tags (V3, VT, VA, VV, S3), 4-voice round-robin
- `scripts/phase1c_uart_telemetry.py`: voice3 tag parsing

No unintended SDC, pin, PLL, or `phase1_reduced_voice.v` changes.

## UART Telemetry

### No-Command

```
frames=336 G=8 Q=0 X=0 K=0
```

| Tag | Value | Description |
| --- | --- | --- |
| G | 8 | 4 voices × 2 events = 8 ✓ |
| H | 3 | Last voice index = voice3 |
| J/L/N | 2 | Voices 0/1/2 assign counts |
| S3 | (present) | Voice3 assign count |
| VT | 2 | Voice3 trigger count |
| VA | incrementing | Voice3 active count |
| VV | incrementing | Voice3 valid count |
| K | 0 | No clipping ✓ |
| Q | 0 | No errors ✓ |
| CC | 0x003D0900 | Stable ✓ |

New voice3 tags (V3, VT, VA, VV, S3) appended correctly after existing tag order. Existing tag sequence `I/S/R/V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E/G/H/J/L/N/P/Q/X/CC` preserved. Voice3 tags appended as suffix.

### Commanded (6 × !N)

```
frames=336 G=14 Q=6 X=0 K=0
```

| Tag | Value | Description |
| --- | --- | --- |
| G | 14 | 8 events + 6 commands ✓ |
| Q | 6 | 6 commands acknowledged ✓ |
| K | 0 | No clipping ✓ |
| X | 0 | No errors ✓ |

Voice3 tags (VT/VA/VV/S3) move coherently under commanded load — not stuck at zero.

## Audio

| Capture | Peak dBFS | RMS dBFS | K |
| --- | --- | --- | --- |
| Phase 2 hammer (3-voice) | -25.69 | -35.95 | 0 |
| **Phase 3 M1 (4-voice)** | **-28.05** | **-37.89** | **0** |

Audio levels are close to the 3-voice hammer baseline. The slight reduction (-2.4 dB peak) is expected with 4 voices sharing the same mix headroom and per-voice velocity scaling. No clipping, no dropouts, stereo balanced.

Per-second RMS variation: < 0.2 dB — stable continuous output.

## Summary

| Gate | Result |
| --- | --- |
| Compile clean (0 errors) | PASS |
| Timing closed (setup >= +2.0 ns) | PASS (+2.948 ns) |
| LE <= 9,800 | **Exception** (9,938, +138) |
| SOF programs | PASS (0x007333FC) |
| UART no-command (G=8, K=0) | PASS |
| UART commanded (G=14, K=0) | PASS |
| Voice3 telemetry (VT/VA/VV/S3) | PASS |
| Existing tag order preserved | PASS |
| Audio healthy (K=0, no clipping) | PASS |

## Recommendation

**PASS — promote Phase 3 M1 4-voice replication to accepted baseline.**

All hardware gates pass. The 4th voice is confirmed functional through UART telemetry and command response. Timing is closed with +2.948 ns margin. The LE exception (9,938 vs. 9,800 gate) is recorded and accepted per orchestrator approval. The 2 additional warnings are consistent with the 4-voice expansion.
