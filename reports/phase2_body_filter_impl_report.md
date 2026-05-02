# Phase 2 Body/Soundboard IIR Filter — Implementation Report

Date: 2026-05-02
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-8da506de`

## Design

Two cascaded Direct Form I biquad sections inserted after the 3-voice mix in `phase0_audio_path.v`, between `mix_sample_sat` and `tx_sample`.

### Biquad 1: Low-shelf (+6 dB, fc~200 Hz, Q~0.7)

Adds bass warmth below 200 Hz. Q2.14 coefficients:

| Coefficient | Float | Q2.14 Integer | Hex |
|-------------|-------|---------------|-----|
| b0 | +1.0067 | +16493 | 0x406D |
| b1 | -1.9675 | -32236 | 0x81E4 |
| b2 | +0.9619 | +15759 | 0x3D8F |
| a1' | +1.9678 | +32240 | 0x7DF0 |
| a2' | -0.9683 | -15864 | 0xC208 |

### Biquad 2: Peaking (+3 dB, fc~200 Hz, Q~1.0)

Piano cabinet body resonance. Q2.14 coefficients:

| Coefficient | Float | Q2.14 Integer | Hex |
|-------------|-------|---------------|-----|
| b0 | +1.0046 | +16459 | 0x404B |
| b1 | -1.9770 | -32391 | 0x8179 |
| b2 | +0.9731 | +15943 | 0x3E47 |
| a1' | +1.9770 | +32391 | 0x7E87 |
| a2' | -0.9777 | -16019 | 0xC18D |

### Combined Response

| Frequency | Gain |
|-----------|------|
| 20 Hz | +6.0 dB |
| 100 Hz | +6.5 dB |
| 200 Hz | +6.0 dB |
| 500 Hz | +0.7 dB |
| 1 kHz | +0.1 dB |
| 5+ kHz | 0.0 dB |

## Architecture

18-bit data path, Q2.14 coefficients. Each biquad computes:

```
y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] + a1*y[n-1] + a2*y[n-2]
```

18-bit × 16-bit multiplies → 36-bit products → sign-extended to 39-bit sum → saturated to 18-bit. Cascaded output saturated to 16-bit for I2S.

## Files Changed

| File | Change |
|------|--------|
| `rtl/audio/phase0_body_filter.v` | New module (107 lines) |
| `rtl/audio/phase0_audio_path.v:200-211` | Wire body filter between mix and tx |
| `quartus/phase0/piano_phase0_top.qsf:21` | Add to project file list |

### Not Changed

- Firmware: no changes (0 ROM words)
- UART: no changes (tag format/order frozen)
- Register map: no new registers
- Voice count, physics, PLL, CPU, SDRAM: untouched

## Resource Estimate

| Resource | Cost | Headroom |
|----------|------|----------|
| LEs | ~200 (control + routing) | 2,157 free (21%) |
| DSP elements | 10 (5 multiplies × 2 biquads) | 30 free (65%) |
| M9Ks | 0 | 32 free (70%) |
| ROM | 0 words | 485 free (47%) |

Cyclone IV E DSP blocks are 18×18, used directly by the 18-bit × 16-bit multiplies. Adder chains implemented in LEs.

## Validation

- Firmware build: PASS (no firmware changes)
- Quartus: pending (full compile ~5 min)
- Simulation: pending (ModelSim testbench with 440 Hz tone)
- Hardware: pending (SOF programming, A/B listening, FFT comparison)

## No-Go Checklist

| Criterion | Status |
|-----------|--------|
| Timing slack > +2.0 ns | Pending Quartus |
| LE count ≤ 8,200 | Pending Quartus |
| K = 0 (no clipping) | Pending hardware |
| UART tags unchanged | Pending hardware |
| No firmware changes | Confirmed |
| No new registers | Confirmed |
