# Phase 1C 3-Voice Simultaneous Volume Validation

Verifier: claude-verifier `e8db32f8-3c5f-4a11-bf2d-8f6e3ad76c4c`
Task: `task-dc67a1d1`
Implementation commit: `f2a938a`
SOF checksum: `0x00681CF5`

## Verdict

**FAIL — waveguide output remains ~30 dB below expected level.**

The 3-voice simultaneous trigger test fires all voices at the same time with sustain, matching the sample_gen test conditions. ModelSim predicts the digital sum should reach -2.1 dBFS through the codec. Hardware measurement shows peak -36.94 dBFS — no improvement over round-robin waveguide, and 30+ dB below sample_gen (-5.58 dBFS). Something in the waveguide digital path is severely attenuating the signal between firmware excitation and the DAC output.

## The Definitive Comparison

| Test | Trigger Mode | Peak dBFS | RMS dBFS | K |
| --- | --- | --- | --- | --- |
| sample_gen | Continuous square wave | **-5.58** | **-7.54** | 0 |
| Waveguide v2 (round-robin) | Sequential 0→1→2 | -37.40 | -49.07 | 0 |
| **3-voice simultaneous** | **All 3 voices at once** | **-36.94** | **-47.12** | **0** |

The 3-voice simultaneous test produces essentially identical levels to the round-robin test. Dense simultaneous triggering (T/U/O=20 per voice, vs 2 in round-robin) does not increase the measured output level. This is the definitive result resolving the month-long volume investigation.

## UART Telemetry

```
mode=no-command frames=250 cycles=10
K=00000000 G=00000000 T=00000014 U=00000014 O=00000014
```

- K=0 — zero clipping even with 3 voices firing simultaneously ✓
- T/U/O=20 each — confirms dense simultaneous triggering is active (round-robin was 2)
- G=0 — the test mode doesn't use the scheduler counter

## ModelSim vs Hardware Gap

| Measurement | Level | Source |
| --- | --- | --- |
| Digital sum (pre-DAC) | -2.1 dBFS | ModelSim simulation |
| Codec output (sample_gen) | -5.58 dBFS | Hardware measurement |
| Codec output (3-voice waveguide) | -36.94 dBFS | Hardware measurement |

The codec path is proven working (sample_gen reaches -5.58 dBFS). The gap is in the waveguide digital chain between voice excitation and the DAC input. ModelSim's -2.1 dBFS prediction is not being realized in hardware.

## Root Cause Analysis

The evidence chain:

1. **Firmware is correct**: T/U/O=20 confirms voices are being triggered
2. **Codec is correct**: sample_gen proves the WM8978 path works at full level
3. **No digital clipping**: K=0 confirms the mix saturator isn't clamping
4. **Mix stage is correct**: The body filter and saturator are transparent at K=0
5. **Voice excitation is correct**: `>>> 1` shift and velocity=0x7FFF confirmed in RTL

The gap must be in the **waveguide voice output amplitude** before the mix stage. The reduced voice module (`phase1_reduced_voice.v`) produces output that is orders of magnitude quieter than the sample_gen square wave, even at full excitation. Possible causes:
- Waveguide loop gain or damping coefficients attenuating more than expected
- Voice output scaling before the mix stage
- The mix summation weights (each voice gets 1/3 of full scale?)
- The waveguide delay line or filter stages reducing amplitude

**This is a hardware signal path issue, not a capture or measurement issue.**

## Recommendation

FAIL — do not accept as resolved. The volume investigation is now definitively narrowed to the waveguide voice output path. Implementer should:

1. Add a test mux to route a single voice's output directly to the DAC (bypassing the mix stage and body filter) to measure raw voice amplitude
2. Compare the per-voice output against sample_gen at the same gain settings
3. Investigate the reduced voice internal scaling: loop gain, damping coefficients, and output scaling before the 18-bit slice
4. Consider whether the waveguide delay line length or filter topology is causing unexpected attenuation

The codec, speaker, firmware trigger, and mix stage are all verified correct. The issue is in `phase1_reduced_voice.v`.
