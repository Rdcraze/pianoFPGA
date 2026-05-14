# Phase 1C Waveguide Gain Fix Validation

Verifier: claude-verifier `e8db32f8-3c5f-4a11-bf2d-8f6e3ad76c4c`
Task: `task-5136c95c`
Implementation commit: `4c5ab03`
SOF checksum: `0x0067FFA8`

## Verdict

**FAIL — mix saturation clipping detected. K=0x69 (105).**

The `>>> 2` removal from excitation combined with 2× body_mix causes the 3-voice coincident peaks to saturate the signed mix stage. The fix overshot. Must back off: re-add `>>> 1` (÷2, -6 dB) instead of removing the shift entirely.

## Clipping Evidence

```
UART_RX_BASELINE_SMOKE_FAIL mode=no-command
frames=250 cycles=10
G=00000006 Q=00000000 X=00000000 K=00000069
error: K expected 0x00000000, got 0x00000069
```

K=105 means 105 samples saturated across the 250 captured frames. The mix saturator is correctly detecting overflow and reporting it. G=6 confirms 3 voices are active and firing events.

## Root Cause

Two changes compound to cause saturation:

1. **Excitation `>>> 2` removed** (÷4, -12 dB guard removed). The excitation amplitude is now 4× larger.
2. **body_mix_q15: 8192 → 16384** (25% → 50%, +6 dB body contribution).

With 3 voices running at full velocity (0x7FFF) and the excitation now at 4× amplitude, coincident voice peaks saturate the signed 18-bit mixer. The `>>> 2` was a conservative clipping guard — removing it entirely was too aggressive.

## Audio Levels

Despite clipping in the digital domain, the external mic captures show similar low levels (~-33 dBFS peak, ~-42 dBFS RMS) due to the persistent mic gain limitation. The UART K value is the authoritative clipping indicator.

## Recommended Fix

Back off one step: re-add `>>> 1` (÷2, -6 dB) instead of removing the shift entirely. This provides +6 dB over the original while maintaining headroom for 3-voice coincident peaks.

Alternatively: keep `>>> 2` removed but reduce body_mix back to 8192 (25%) — this would provide +12 dB without doubling the body contribution.

## Scope and Resource

| Metric | Value |
| --- | --- |
| Quartus errors | 0 |
| Warnings | 16 |
| Changed files | 3 (+7/-10) |
| Scope | firmware + RTL only |

## Recommendation

FAIL — do not promote. Re-work with `>>> 1` instead of complete removal, or reduce body_mix back to 8192 with `>>> 2` removed. Re-validate with K=0 required.
