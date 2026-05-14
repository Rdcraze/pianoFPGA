# Phase 1C CC Counter Baseline Acceptance Decision

Date: 2026-05-02
Orchestrator: `1c005a25-956c-4b69-9b69-9bf3cd9a8d68`
Branch: `codex/phase1c-uart-boundary-fix`

## Decision

ACCEPT — promote the CC counter measurement hook to the accepted Phase 1C baseline.

## Evidence Chain

| Gate | Task | Agent | Result |
| --- | --- | --- | --- |
| Contract draft | `task-68752505` | implementer `5ed7d08b` | `7c39cb6` |
| Contract validation | `task-fc35ad1e` | verifier `e8db32f8` | FAIL — CC/C collision |
| Contract revision | `task-f9ffb452` | implementer `5ed7d08b` | `709081d` — 3 fixes |
| Contract re-validation | `task-366405b7` | verifier `e8db32f8` | PASS |
| Implementation | `task-b391edf5` | implementer `5ed7d08b` | `72e83d3`, `7ed2c62` |
| Implementation validation | `task-df8ab35b` | verifier `e8db32f8` | PASS (4/9, 5 deferred) |
| Hardware smoke | `task-07dc78cf` | verifier `e8db32f8` | PASS (8/9 confirmed) |

## New Baseline Anchors

| Anchor | Previous | New |
| --- | --- | --- |
| SOF checksum | `0x005F102E` | `0x005F4722` |
| LEs | 7,963 / 10,320 | 7,963 / 10,320 |
| M9Ks | 14 / 46 | 14 / 46 |
| DSP9s | 6 / 46 | 6 / 46 |
| setup slack (slow-85C) | +2.438 ns | +2.438 ns |
| hold slack (slow-85C) | +0.406 ns | +0.406 ns |
| ROM words | 507 / 1024 | 539 / 1024 (+128 bytes) |
| UART tag order | `I/.../X` | `I/.../X/CC` |
| CC value (steady-state) | — | `0x003D0900` (0% variation) |

## Changes From Previous Baseline

- `fw/phase0/phase0_main.c` (+10): CC counter variable, increment in delay loop, tag emission after X
- `scripts/phase1c_uart_telemetry.py` (+3/-2): regex `([A-Z]+)`, CC in `MEASUREMENT_TAGS`
- Parser unit tests: 10/10 PASS, regression clean on existing captures

## Deferred

- Waveform checklist — needs audio capture hardware (firmware-only change, zero RTL delta, expected unchanged)

## Blocked Features

All remain blocked. No SDRAM, fourth voice, richer physics, exact-48k PLL, larger CPU/ISA, hardware dispatcher, voice stealing, per-note state, per-voice parameter banks, host-selected parameters, codec config RX, diagnostic clear RX, sample playback, UI/TFT/touch, CPU audio-loop expansion, non-prefix UART changes, or register-map changes beyond accepted ranges.
