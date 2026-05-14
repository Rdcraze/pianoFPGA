# Phase 1C Re-Trigger Enable Fix Validation

Verifier: claude-verifier `e8db32f8-3c5f-4a11-bf2d-8f6e3ad76c4c`
Task: `task-0fc17582`
Implementation commit: `c5f0709`
SOF checksum: `0x00682C20`

## Verdict

**FAIL — sustained level unchanged at -35.9 dBFS despite ENABLE_M fix.**

The fix correctly adds `ENABLE_M` to the trigger write, and re-triggers are firing (T/U/O increased from 15→17). But the sustained audio output level remains at -36 dBFS — unchanged from the previous fix attempt. The re-trigger mechanism sends the strobe, but the voice output does not reproduce the initial -1.93 dBFS level.

## Measurements

| Window | Peak dBFS |
| --- | --- |
| Second 0 | -36.09 |
| Second 1 | -35.89 |
| Second 2 | -35.89 |
| All subsequent | -35.89 |

Zero variation across seconds. No window exceeds -35.8 dBFS.

## UART Telemetry

```
K=0 T=0x11 U=0x11 O=0x11
```

- K=0 — no clipping ✓
- T/U/O=17 (was 15 in v1) — more triggers firing, confirming ENABLE_M is active
- G=0 — test mode

## Summary of Re-Trigger Investigation

| Fix | Trigger Count | Sustained Peak | Initial Peak |
| --- | --- | --- | --- |
| Pre-fix (f2a938a) | 15 | -34.70 | **-1.93** (proven) |
| v1 (e381f3c): clear-then-set | 15 | -34.70 | Not captured |
| v2 (c5f0709): +ENABLE_M | 17 | -35.89 | Not captured |

All three versions show the same pattern: the initial trigger produces a full-amplitude blast (-1.93 dBFS), but subsequent re-triggers into an already-active voice produce ~35 dB lower output. Adding ENABLE_M confirms the strobe logic is working (trigger count increased), but the fundamental issue remains: the waveguide voice cannot produce a full-excitation response when the delay line is already ringing.

## Root Cause

The first trigger fires into a silent delay line (all taps = 0), producing maximum impulse response. Re-triggers fire while the delay line still holds residual energy from the previous excitation. The RTL voice module accepts the trigger strobe (confirmed by trigger count), applies the excitation, but the resulting output is dominated by the existing ring-down rather than a fresh impulse.

This is a waveguide physics issue, not a firmware strobe issue. The re-trigger mechanism needs to either:
1. Clear the delay line state before each re-trigger (reset all taps to zero)
2. Use a voice disable/enable cycle to flush the pipeline
3. Add a gate-before-trigger sequence in the RTL

## Recommendation

FAIL — the firmware re-trigger approach (clear-then-set strobe + enable) is insufficient. The RTL voice module needs a "hard reset on trigger" mechanism that zeros the delay line before injecting a new excitation. Alternatively, reduce the re-trigger interval to exceed the delay line decay time, allowing each trigger to fire into near-silent state.
