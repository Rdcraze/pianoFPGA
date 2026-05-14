# Phase 1C Three-Voice Re-Trigger Fix Validation

Verifier: claude-verifier `e8db32f8-3c5f-4a11-bf2d-8f6e3ad76c4c`
Task: `task-e63f0f98`
Implementation commit: `e381f3c`
SOF checksum: `0x00682C20`

## Verdict

**FAIL — sustained re-trigger level remains at -35 dBFS, not -2 dBFS.**

The re-trigger fix does not produce the expected sustained high output. All 100ms windows across the entire 12s capture show peak -34.7 dBFS — identical to the pre-fix sustained level. The initial -1.93 dBFS blast (reported by orchestrator at second 0) was not captured, and subsequent re-triggers do not reproduce it.

## Measurements

| Window | Peak dBFS |
| --- | --- |
| 0.0–0.1s | -34.70 |
| 0.1–0.2s | -35.12 |
| 0.2–0.3s | -34.70 |
| All subsequent windows | -34.70 |

Zero variation. No window exceeds -34 dBFS. The re-trigger produces a steady -35 dBFS level — unchanged from pre-fix behavior.

## UART Telemetry

```
K=0 T=0x0F U=0x0F O=0x0F
```

- K=0 ✓ — no clipping at sustained level
- T/U/O=15 — retriggers are firing (~1 per 16 frames)
- G=0 — test mode

## Expected vs Actual

| Metric | Expected | Actual |
| --- | --- | --- |
| Second 0 peak | -1.93 dBFS (already proven) | Not captured |
| Sustained peak (re-trigger) | -1 to -3 dBFS | **-34.70 dBFS** |

The initial trigger produces a -1.93 dBFS blast (proven by orchestrator's pre-fix analysis), but the re-trigger mechanism cannot reproduce it at the same amplitude. The clear-then-set edge fix ensures the strobe fires, but the resulting voice output is ~32 dB quieter than the initial trigger.

## Root Cause Hypothesis

The first trigger fires when voices start from zero state (all delay line memory = 0). The waveguide excitation injects energy into a silent delay line, producing a full-amplitude impulse response. The re-trigger fires while the delay line is still actively resonating — the excitation adds to existing content rather than replacing it. The superposition could cause:

1. The excitation to be absorbed by the already-ringing delay line without producing new peak output
2. The voice's internal state to be in a decay phase when the re-trigger arrives
3. The re-trigger not resetting the voice envelope/phase

## Recommendation

FAIL — the re-trigger mechanism needs a different approach. Options:
1. Reset the voice envelope and phase on each re-trigger (gate then trigger)
2. Use a shorter sustain interval so delay line decays more between triggers
3. Route voice output to a peak-hold buffer that resets on each trigger

The fact that the first trigger hits -1.93 dBFS proves the waveguide path IS correct. The issue is specifically the re-trigger timing relative to the voice decay state.
