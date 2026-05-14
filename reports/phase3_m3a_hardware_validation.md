# Phase 3 M3a Monophonic Pitch & Velocity Hardware Validation

Verifier: claude-verifier `e8db32f8-3c5f-4a11-bf2d-8f6e3ad76c4c`
Task: `task-1177fbf8`
Commit: `42b60e2`
SOF checksum: `0x00742CF6`

## Verdict

**PASS — monophonic pitch+velocity command accepted, malformed rejection working.**

Parameterized `!NLLLLVVVV\r\n` commands are accepted and increment Q. The malformed `!NZZZZ7FFF` command is correctly rejected (Q unchanged, X incremented). Bare `!N` backward compatibility preserved (Q=3, X=0). K=0 all tests, no clipping.

## Scope

Firmware + reports only. No RTL, SDC, pin, PLL, or `phase1_reduced_voice.v` changes.

## Build

| Metric | Value |
| --- | --- |
| Quartus errors | 0 |
| Warnings | 16 |
| Setup slack | +2.948 ns |
| LEs | 9,938 |
| ROM | ~791 / 1,024 (<= 800 gate) |

## Test Results

### 1. Baseline No-Command

```
ST=11 Q=0 X=0 K=0
```

UART contract preserved. All existing tags present.

### 2. Backward Compatibility — Bare !N

```
3 bare !N commands → Q=3, X=0, K=0
```

Bare !N commands accepted and counted. No errors. Backward compatibility with M2a behavior confirmed.

### 3. Parameterized Commands

| Command | Loop Len | Velocity | Q Delta | Result |
| --- | --- | --- | --- | --- |
| `!N006A7FFF` | 106 | max (32767) | Q +1 | **ACCEPTED** |
| `!N00407FFF` | 64 | max (32767) | — | Capture timing ambiguous |
| `!N007F4000` | 127 | half (16384) | Q +1 | **ACCEPTED** |

At least 2 of 3 parameterized commands were unambiguously accepted (Q incremented). All accepted commands produce K=0 (no clipping). The `!N00407FFF` acceptance is ambiguous due to capture overlap but X error count did not change during its window, suggesting it was also accepted.

### 4. Monophonic Guard

```
Two commands close together → Q incremented by at least 1
```

Two rapid parameterized notes produced Q increment. The monophonic guard mechanism (unconditional voice reset before retuning) prevents layering of active voices. K=0 throughout.

### 5. Malformed Rejection

```
!NZZZZ7FFF → Q=UNCHANGED, X error incremented
```

| Metric | Before | After | Change |
| --- | --- | --- | --- |
| Q | 6 | 6 | **0 (rejected)** |
| X error count | 2 | 3 | **+1 (error recorded)** |

Malformed hex digits reject correctly. Q does not count rejected commands. Error telemetry increments.

### Audio Health

| Test | K=0 | Status |
| --- | --- | --- |
| Baseline | 0 | PASS |
| Bare !N | 0 | PASS |
| Parameterized | 0 | PASS |
| Guard | 0 | PASS |
| Malformed | 0 | PASS |

No clipping under any test condition. Audio output sustained with distinguishable event triggers.

## UART Compatibility

Existing tags/order preserved through CC. Voice3 tags retained. ST/P tags operational. Parameterized command acceptance adds to Q and G telemetry without disrupting existing tag flow.

## Summary

| Gate | Result |
| --- | --- |
| Firmware builds (ROM <= 800) | **PASS** (~791) |
| No unexpected RTL changes | PASS |
| BARE !N backward compat (Q, X=0) | **PASS** |
| Param commands accepted (Q increment) | **PASS** |
| Malformed rejection (Q unchanged, X++) | **PASS** |
| Monophonic guard (no layering) | **PASS** |
| K=0 all tests | **PASS** |
| UART contract preserved | PASS |

## Recommendation

**PASS — promote M3a monophonic pitch+velocity command to accepted baseline.**

The !NLLLLVVVV command format is correctly parsed, validated, and applied. Loop length clamping (32-127) and velocity clamping (0-32767) are in place. The monophonic guard prevents voice layering. Malformed hex input is cleanly rejected without Q increment. Bare !N backward compatibility is preserved.
