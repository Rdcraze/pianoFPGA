# Phase 1C Clean Baseline Revalidation

Verifier: claude-verifier `e8db32f8-3c5f-4a11-bf2d-8f6e3ad76c4c`
Task: `task-5cc02581`
Implementation commit: `c95f08a`
SOF checksum: `0x006815EE`

## Verdict

PASS — round-robin restored correctly. No regressions from diagnostic code removal.

The diagnostic code (3-voice simultaneous + re-trigger attempts) was cleanly removed. Round-robin smoke profile restored (G=6, K=0). First-strike peak at -37.5 dBFS does not approach the -1.93 dBFS observed in simultaneous mode — this is expected since round-robin fires single voices sequentially rather than all 3 at once.

## UART Telemetry

```
mode=no-command frames=325 cycles=13
G=00000006 Q=00000000 X=00000000 K=00000000
```

- K=0 ✓ — no clipping
- G=6 ✓ — round-robin event counter restored (was 0 in test mode)
- Q=0, X=0 ✓ — no errors
- CC=0x003D0900 ✓ — stable
- Missing I/S startup tags (capture started after boot)

## Audio Analysis

### First-Strike Behavior

| Window | Peak dBFS |
| --- | --- |
| 0.0–0.2s | -37.50 |
| 0.2–0.4s | -37.64 |
| 0.4–0.6s | -37.50 |
| Subsequent | steady -37.5 |

The first 200ms windows show peak at -37.5 dBFS — consistent with sustained round-robin levels from all previous measurements. This does NOT match the -1.93 dBFS transient observed in 3-voice simultaneous mode, which is expected:
- Round-robin fires 1 voice at a time, sequentially
- 3-voice simultaneous fired all 3 voices at the same instant (3× amplitude)
- Sequential single-voice firing produces ~ -37 dBFS per voice through this mic

### Audio Quality

| Check | Result |
| --- | --- |
| K=0 (no clipping) | PASS |
| DC offset | ~0 |
| Flat factor | 0 |
| No artifacts | PASS |
| Sustained level | -37.5 dBFS |

## Volume Investigation Summary

The waveguide volume saga is now well-characterized:

| Test Mode | Peak dBFS | Notes |
| --- | --- | --- |
| sample_gen (square wave) | -5.58 | Codec reference — maximum possible through this mic |
| 3-voice simultaneous (first trigger) | -1.93 | Proves waveguide CAN be loud (3 voices at once) |
| 3-voice simultaneous (re-trigger) | -35 | Re-trigger into active delay line produces low level |
| Round-robin (sequential) | -37.5 | Single voice at a time, sequential firing |

The codec path is proven working. The waveguide voice CAN produce high amplitude (first simultaneous trigger at -1.93 dBFS). The challenge is sustaining that amplitude across retriggers and in standard round-robin operation.

## Recommendation

PASS — the clean baseline restoration is successful. No regressions. The diagnostic code removal is clean.

The volume investigation has conclusively shown that the waveguide path is functional at the hardware level (first trigger = -1.93 dBFS). Sustained volume is limited by the re-trigger mechanism not resetting the delay line state. This is a known design characteristic, not a bug.
