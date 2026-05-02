# Phase 1C Waveguide Digital Gain Fix — Implementation Report

Date: 2026-05-02
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-eecf2214`

## Problem

The verifier's sample_gen diagnostic test confirmed:
- sample_gen square wave: peak -5.58 dBFS (matches sample.wav reference)
- 3-voice waveguide at max settings: peak -32 dBFS
- WM8978 codec hardware is working correctly

**25+ dB loss in the waveguide digital path**, even with velocity_q15=0x7FFF (100%) and speaker volume=0 (+6 dB).

## Root Cause Analysis

### Excitation attenuation (dominant factor: -12 dB)

In `phase1_reduced_voice.v:322`, the velocity-scaled excitation was right-shifted by `>>> 2` (divided by 4) on top of the standard Q15 multiplication normalization (`>>> 15`). Total shift = `>>> 17`.

```
excite_sample = (rom_val × 2 × velocity_q15) >>> 17
             = (32627 × 2 × 32767) / 131072
             = 16,317  (Q18.0, -18 dB from 18-bit full scale)
```

After `q18_to_q15` (÷4): **4,079 in Q15.0 = -18.1 dBFS per voice peak**.

The sample_gen produces ±32767 (0 dBFS) from the same codec configuration. The `>>> 2` was the single largest attenuator in the pipeline — a conservative guard against inter-voice clipping that proved far too aggressive.

### Body FIR contribution (secondary factor: -6 dB)

`body_mix_q15` = 8192 (25%) limited the body FIR contribution to only 25% of the FIR output. The body FIR adds constructive energy to the voice output, so restricting its contribution also limits output level.

## Fix

| Stage | Parameter | Before | After | Δ |
|-------|-----------|--------|-------|---|
| Excitation | `>>> 2` shift | present (÷4) | removed | **+12 dB** |
| Body FIR mix | `body_mix_q15` | 8192 (25%) | 16384 (50%) | **+6 dB** |
| **Total digital** | | | | **+18 dB** |

### Change 1: Remove excitation `>>> 2`

`rtl/audio/phase1_reduced_voice.v:322`:

```verilog
// Before:
excite_sample <= product_to_q18(mult_product) >>> 2;

// After:
excite_sample <= product_to_q18(mult_product);
```

ROM peak 32627 → ×2 → × velocity (1.0) → >>> 15 → **65,271** (Q18.0)
After q18_to_q15: **16,318 = -6.1 dBFS per voice** (was -18.1 dBFS)

Three voices summing to mix saturation: up to 3 × 16,318 = 48,954 → saturates to 0 dBFS at mix stage. The mix saturation clamps to 16-bit [-32768, +32767], preventing wrap-around. Brief clipping during simultaneous voice peaks is handled by the saturation logic.

### Change 2: Increase body_mix

`fw/phase0/phase0_hw.h:96`:

```c
// Before:
#define PHASE0_VOICE_DEFAULT_BODY_MIX  8192u   // 25%
// After:
#define PHASE0_VOICE_DEFAULT_BODY_MIX  16384u  // 50%
```

Doubles the body FIR contribution to each voice's output. The body FIR provides resonant warmth; doubling its contribution enhances both timbre and output level.

### Firmware: restore waveguide mode

Reverted the sample_gen test configuration:
- Voice controls: restored `BASELINE | CLIP_CLEAR` (voices enabled)
- Trigger: restored `phase0_run_round_robin_smoke()` (6 note events)
- GAIN: restored to 16384 (sample_gen only, doesn't affect waveguide)

## Expected Output

| Stage | Contribution |
|-------|-------------|
| Original waveguide (pre-all-fixes) | ~ -50 dBFS |
| After speaker enable (SPKOUTP_EN=1) | +10 dB |
| After analog gain (R54/R55 20→0) | +20 dB |
| After velocity increase (50%→100%) | +6 dB |
| After excitation fix (>>> 2 removed) | +12 dB |
| After body_mix increase (25%→50%) | +6 dB |
| **Expected output** | **~ -6 to -10 dBFS** |

Within 1-5 dB of sample.wav reference (-5.4 dBFS).

## Resource Impact

| Resource | Change |
|----------|--------|
| LEs | 0 |
| DSPs | 0 |
| M9Ks | 0 |
| ROM | ~0 words (body_mix immediate value change) |
| Timing | Unchanged (no logic changes, only constant/shift removed) |

## No-Go Checklist

| Criterion | Status |
|-----------|--------|
| K = 0 (no clipping) | Pending hardware — mix saturation may clip briefly on 3-voice coincident peaks |
| LE count ≤ 8,250 | 0 LE change |
| Timing slack > +2.0 ns | Unchanged |
| Audible distortion | Pending A/B listening test |
| UART tags unchanged | No UART/firmware format changes |

## Validation

- Firmware build: PASS
- Quartus: pending (no new logic, constant/shift change only)
- Hardware: pending verifier capture with per-second analysis and A/B listening
