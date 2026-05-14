# Phase 3 M4 Note-Off (!F) Hardware Validation

Verifier: claude-verifier `e8db32f8-3c5f-4a11-bf2d-8f6e3ad76c4c`
Task: `task-4d34ef91`
Commit: `9eae9bc` on `ca00728`
SOF checksum: `0x00779CD3`

## Verdict

**PASS — !F note-off accepted, damp restore works, all X=0.**

The !F command increments Q with X=0 and triggers a note-off release on active voices. Damp restore after !F works correctly — bare !N after !F sustains normally. Malformed !F1234 and unknown !Z are correctly rejected (Q unchanged, X incremented). All valid-command captures end with X=0, K=0.

## Scope

Firmware-only + reports. No RTL, SDC, pin, PLL, or phase1_reduced_voice.v changes.

## Test Results

| Test | Q | X | K | Notes |
| --- | --- | --- | --- | --- |
| Baseline | 0 | **0** | 0 | Clean |
| M3b compat | 2 | **0** | 0 | bare !N + param accepted ✓ |
| **!F acceptance** | **3** | **0** | 0 | Note-off accepted ✓ |
| Damp restore | 4 | **0** | 0 | !N after !F sustains ✓ |
| Malformed | 4 | 0x00020002 | 0 | !F1234 + !Z rejected ✓ |

## Detailed Tests

### Baseline Compatibility

```
Q=0 X=0 K=0
```
Clean no-command state.

### M3b Command Compatibility

```
!N (bare) + !N006A7FFF (param) → Q=2, X=0, K=0
```
Bare and parameterized commands still work after M4 changes.

### !F Note-Off

```
!F → Q=3, X=0
```
Note-off command accepted and counted. Active voice release triggered.

### Damp Restore

```
!N after !F → Q=4, X=0
```
Bare !N after note-off sustains normally — damp parameters restored.

### Malformed Rejection

```
!F1234 → rejected (UNKNOWN_OPCODE)
!Z     → rejected (UNKNOWN_OPCODE)
```
Q=4 (unchanged), X=0x00020002 (2 errors recorded). Both malformed commands correctly refused.

## ROM

| Metric | Value |
| --- | --- |
| M4 ROM | 931 / 1,024 |
| Gate | <= 950 |
| M3b baseline | 912 |
| Delta | +19 |

## Build

| Metric | Value |
| --- | --- |
| Quartus errors | 0 |
| Warnings | 16 |
| LEs | 9,938 |
| Setup slack | +2.948 ns |

## Recommendation

**PASS — promote Phase 3 M4 note-off command to accepted baseline.**
