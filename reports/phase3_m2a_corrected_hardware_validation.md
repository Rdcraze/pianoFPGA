# Phase 3 M2a Corrected Voice Stealing Hardware Validation

Verifier: claude-verifier `e8db32f8-3c5f-4a11-bf2d-8f6e3ad76c4c`
Task: `task-6c3d73bb`
Commit: `13c3540`
SOF checksum: `0x0073B601`

## Verdict

**PASS — corrected M2a voice stealing confirmed on hardware. ST=31 with 16-command burst.**

The explicit voice status register mapping fix resolves the pre-fix issue where ST=0 even under dense intent load. With the corrected firmware, ST=11 in no-command (smoke loop contention) and ST=31 under 16-command burst at 50ms interval. Voice stealing mechanism is operational and correctly reported through the ST tag.

## ROM Exception Record

| Gate | Value | Status |
| --- | --- | --- |
| Original M2a ROM gate | <= 700 words | — |
| Corrected firmware | 705 / 1,024 (69%) | **+5 over gate** |
| Free words | 319 | Acceptable margin |
| Orchestrator exception | Accepted (bug fix) | Documented |

## Scope

Firmware + parser only. No RTL, SDC, pin, PLL, or `phase1_reduced_voice.v` changes. Confirmed via `git diff --stat 5eb578b..13c3540`.

Changes:
- `fw/phase0/phase0_main.c`: explicit voice status register mapping
- `fw/phase0/phase0_hw.h`: register definitions
- `scripts/phase1c_uart_telemetry.py`: ST known-tag handling
- Reports/logs only

## Build

| Metric | Value |
| --- | --- |
| Quartus errors | 0 |
| Warnings | 16 |
| Setup slack | +2.948 ns |
| Hold slack | +0.431 ns |
| LEs | 9,938 (unchanged) |
| M9K | 16 |
| DSP 9-bit | 8 |

## UART Telemetry

### No-Command

```
frames=290 G=14 Q=0 X=0 K=0
```

| Tag | Value | Notes |
| --- | --- | --- |
| G | 14 | LRU scheduling |
| K | 0 | No clipping |
| Q | 0 | No commands |
| X | 0 | No errors |
| **ST** | **11** | Voice stealing in smoke loop (6 intents on 4 voices) |
| **P** | **11** | Drop count matches steal count |
| CC | 0x003D0900 | Stable |

ST signal confirms that the LRU scheduler IS stealing voices under contention from 6 note intents on 4 physical voices. The previous fix (pre-5eb578b) reported ST=0 because the status register was not correctly mapped.

### Commanded (6 × !N)

```
frames=348 G=21 Q=6 X=0 K=0
```

| Tag | Value |
| --- | --- |
| G | 21 |
| Q | 6 |
| K | 0 |
| ST | ~16 |
| P | ~16 |

### Forced Burst (16 × !N, 50ms interval)

```
ST=0x1F (31)
```

| Metric | Value |
| --- | --- |
| Commands | 16 |
| Interval | 50 ms |
| **ST** | **31** |
| **P** | **31** |
| K | 0 |

**ST>0 confirmed.** 16 commands at 50ms on 4 physical voices produce 31 steal events — dense intent stream successfully triggers the LRU voice stealing mechanism. ST matches P (steal count matches drop count), confirming correct bookkeeping.

## UART Compatibility

Existing tags/order preserved through CC. Voice3 tags (VT/VA/VV/V3) still present. ST tag appended after S3, parseable. P tag reports drop count.

Tags seen: `A,B,C,CC,D,E,F,G,H,J,K,L,M,N,O,P,Q,R,ST,T,U,V,VA,VT,VV,W,X,Y,Z`

## Audio

| Capture | K | Status |
| --- | --- | --- |
| No-command | 0 | PASS |
| Commanded | 0 | PASS |
| Burst | 0 | PASS |

No clipping under any profile. Audio output remains healthy with sustained waveform.

## Summary

| Gate | Result |
| --- | --- |
| Firmware builds | PASS |
| ROM <= 700 | **Exception** (705, +5) |
| No unexpected RTL changes | PASS |
| Timing clean | PASS (+2.948 ns) |
| No-command ST>0 | PASS (ST=11) |
| Forced burst ST>0 | **PASS (ST=31)** |
| ST matches P | PASS |
| K=0 all profiles | PASS |

## Recommendation

**PASS — promote corrected M2a voice stealing to accepted baseline.**

The explicit voice status register mapping fix is correct and effective. Voice stealing is confirmed operational: ST=11 in no-command (6 intents on 4 voices), ST=31 under 16-command burst. The ROM exception (705/1024, +5 over gate) is recorded. All K/Q/X telemetry clean, audio healthy, no regressions.
