# Phase 1C Waveguide Pipeline Gain Trace

Date: 2026-05-02
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-f098d9cd`

## Method

Bit-accurate analytical trace of the `phase1_reduced_voice` pipeline, computing peak amplitudes at every node using the exact Verilog arithmetic (Q18.0 data path, Q2.14/Q0.15 coefficients, deterministic saturation).

**Parameters:** velocity=0x7FFF, body_mix=16384, loop_gain=32640, damp_mix=16384, disp_coeff=9952, guard_shift=>>1.

## Gain Trace Table

| # | Node | Peak Value | Q15 dBFS | re Q18 FS |
|---|------|-----------|----------|-----------|
| 1 | excitation ROM (raw x2) | 65,254 | — | +0.0 |
| 2 | velocity-scaled (product_to_q18) | 65,252 | -6.1 | -6.1 |
| 3 | **excite_sample (>>>1 guard)** | **32,626** | **-12.1** | **-12.1** |
| 4 | delay_line injection | 32,626 | -12.1 | -12.1 |
| 5 | dl_sample (after loop_len=106) | 32,626 | -12.1 | -12.1 |
| 6 | disp_sample (all-pass, unity gain) | 32,626 | -12.1 | -12.1 |
| 7 | lp_state (damping LPF, DC gain=1) | 32,626 | -12.1 | -12.1 |
| 8 | fb_sample (loop_gain x0.9961) | 32,499 | -12.1 | -12.1 |
| 9 | body_FIR sparse (pre-mix) | 6,117 | -26.6 | -26.6 |
| 10 | output_sample_q18 (voice out) | 35,685 | -11.3 | -11.3 |
| 11 | **sample_data (q18_to_q15)** | **8,921** | **-11.3** | — |
| 12a | mix 1-voice | 8,921 | -11.3 | — |
| 12b | mix 2-voice | 17,842 | -5.3 | — |
| 12c | **mix 3-voice** | **26,764** | **-1.8** | — |
| 13 | After body IIR (+0.1 dB at 440 Hz) | — | **-1.7** | — |

## Key Findings

### 1. Dominant attenuator: >>>1 guard (-6 dB)

The `>>> 1` right-shift on the excitation reduces the ROM peak from 65,254 to 32,626 per voice. This is the single largest digital attenuator in the pipeline. The original `>>> 2` (-12 dB) was even worse, causing the -32 dBFS measurement.

### 2. Body FIR adds 0.7 dB per voice

At body_mix=16384 (50%), the sparse body FIR (tap6/4 - tap16/8 + tap30/16) contributes about 0.7 dB to the output. The body FIR itself peaks at only 6,117 (18-bit), down from the main signal at 32,626.

### 3. 3-voice sum margin: +1.8 dB below clip

With the >>>1 guard, 3 simultaneous voice peaks sum to 26,764, comfortably below the 32,767 16-bit saturation threshold. K=0 expected.

With the >>>2 removal (+12 dB instead of +6 dB), the 3-voice sum was 2x higher (53,528), well above the threshold — explaining the K=105 measurement.

### 4. Voice physics losses are minimal

- Loop gain (0.9961): -0.03 dB per cycle — negligible for short smoke windows
- Damping LPF: unity DC gain, slight HF attenuation
- All-pass dispersion: unity gain, phase-only effect

### 5. Gap to reference

| Reference | Level | Gap to 3-voice waveguide |
|-----------|-------|-------------------------|
| sample.wav (RMS) | -5.4 dBFS | — (RMS vs peak, not comparable) |
| sample_gen (peak) | -5.6 dBFS | +3.9 dB (waveguide exceeds sample_gen!) |
| Full-scale 16-bit | 0.0 dBFS | -1.7 dB (3-voice after body IIR) |

The waveguide at current settings can actually exceed the sample_gen square wave in peak level, with K=0.

## Conclusion

The gain chain is now well-balanced:
- Per-voice excitation: -11.3 dBFS (from >>>1 guard)
- 3-voice sum: -1.8 dBFS (no clipping, clean headroom)
- After body IIR coloration: -1.7 dBFS

The previous -32 dBFS measurement was caused by the `>>> 2` guard (-6 dB more) and low body_mix (-6 dB more), for a total of -12 dB additional loss vs current settings. Combined with the lower velocity (0x4000, -6 dB) and lower speaker volume (20, -14 dB) from before the gain fixes, the total loss was ~-44 dB from the 0 dBFS capable hardware.
