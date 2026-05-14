# Phase 3 M1 Baseline Acceptance

Date: 2026-05-14
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-db26f6cc`

## Status

**ACCEPTED — Phase 3 M1 (4-voice replication) is hardware-validated and promoted to accepted baseline.**

## Evidence Chain

| Gate | Task | Result |
| --- | --- | --- |
| Architecture scope | `task-62c542a0` | `41db8e5` |
| Implementation | `task-d4b4814e` | `6f977b0` (initial), `9b76aff` (clean rewrite) |
| Syntax fix | `task-1861e1bd` | Syntax errors resolved, control_regs voice3 added |
| Timing recovery | `task-e55ddd79` | Pipeline register, +2.948 ns |
| Resource gate | `task-3af3f24f` | LE exception (9,938 vs 9,800) |
| **Hardware validation** | `task-b2543628` | **PASS — SOF 0x007333FC, G=8, K=0** |
| Firmware CR fix | `task-db26f6cc` | `29c6e51` |
| Baseline stabilization | `task-db26f6cc` | This report |

## Hardware Validation Summary

- SOF checksum: `0x007333FC`
- No-command UART: `G=8, Q=0, X=0, K=0` (4-voice round-robin, 2 events × 4 voices)
- Commanded UART: `G=16, Q=6, X=0, K=0`
- Voice3 tags active: V3, VT, VA, VV, S3 confirmed in telemetry
- Audio: PASS, no clipping, waveform clean

## Accepted Baseline Anchors

| Anchor | Value |
| --- | --- |
| SOF checksum | `0x007333FC` |
| LEs | 9,938 / 10,320 (96%) — **LE exception granted** |
| M9Ks | 17 / 46 (37%) |
| DSP 9-bit | 8 / 46 (17%) |
| PLLs | 1 / 2 |
| setup slack (slow-85C) | +2.948 ns |
| hold slack (slow-85C) | +0.431 ns |
| UART order | I/S/R/V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E/G/H/J/L/N/P/Q/X/CC/V3/VT/VA/VV/S3 |
| No-command profile | G=8, Q=0, X=0, K=0, CC=0x003D0900 |
| Commanded profile | G=16, Q=6, X=0, K=0 |

## Commits Range

`41db8e5` (scope) → ... → `6f99697` (hardware artifacts) on `codex/phase1c-uart-boundary-fix`

## LE Exception

9,938 LEs exceeds the 9,800 scoping gate by 138 LEs (1.3%). Exception granted by orchestrator. If future work needs headroom, address via Phase 3 M2 time-multiplexed voice engines rather than further instance replication.

## Next Recommended Task

Phase 3 M2 scoping: hardware voice stealing (N logical voices → 4 physical slots), or time-multiplexed voice engine architecture per `reports/phase3_architecture_scope.md`.
