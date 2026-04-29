# Phase 1 Two-Voice Audio Comparison

Date: 2026-04-28
Verifier: Codex verifier

## Summary

I re-analyzed the available Phase 1 external audio captures with one uniform script. The current two-voice capture is moderately louder than the closest single-voice timing-margin verifier baseline while staying unclipped and non-square. Its measured fundamental is slightly lower, but still in the same ~435-436 Hz hardware-tone region.

Important caveat: these are microphone / line-input captures, not calibrated SPL measurements. Absolute intensity can move with analog gain, cabling, and placement. The most defensible comparison is relative RMS/peak level within the same capture method and the absence of clipping/regression.

## Key Comparison

| Capture | Mono RMS | RMS vs Timing Validation | Peak | Peak vs Timing Validation | F0 | Crest | Clip Samples |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `phase1_reduced_voice_run1` | 0.024480 | +2.37 dB | 0.213181 | +10.29 dB | 435.489 Hz | 8.71 | 0 |
| `phase1_reduced_voice_run2` | 0.014657 | -2.08 dB | 0.057022 | -1.17 dB | 435.538 Hz | 3.89 | 0 |
| `phase1_observability` | 0.016015 | -1.31 dB | 0.059753 | -0.76 dB | 435.444 Hz | 3.73 | 0 |
| `phase1_timing_margin_impl` | 0.018488 | -0.07 dB | 0.066956 | +0.23 dB | 435.455 Hz | 3.62 | 0 |
| `phase1_timing_margin_validation` | 0.018630 | +0.00 dB | 0.065216 | +0.00 dB | 435.516 Hz | 3.50 | 0 |
| `phase1_two_voice_hardware` | 0.023697 | +2.09 dB | 0.093613 | +3.14 dB | 435.485 Hz | 3.95 | 0 |

## Intensity

Against `phase1_timing_margin_validation`, the current two-voice capture is +2.09 dB by early-window mono RMS and +3.14 dB by early-window peak amplitude. In linear terms, that is about 1.27x RMS amplitude and 1.44x peak amplitude.

That recorded increase is smaller than the ideal +6.02 dB amplitude doubling because the analog capture chain and selected tone windows are not calibrated or perfectly controlled. The UART-side hardware diagnostics are the stronger evidence for exact internal scaling: voice0 and voice1 peaks both reported `0x0822`, while mix peak reported `0x1044`, exactly double, with `K=0` mix clips.

The current capture has crest factor 3.95 and zero clipped samples, so the extra intensity did not turn into visible digital clipping or square-wave-like behavior in the recorded audio.

## Frequency Profile

The closest verifier single-voice baseline measured 435.516 Hz; the current two-voice capture measured 435.485 Hz, a delta of -0.032 Hz (-0.007%). This is a small shift relative to the capture method and does not suggest a clock/sample-rate regression.

| Capture | H2 | H3 | H4 | H5 | H2-H10 aggregate |
| --- | ---: | ---: | ---: | ---: | ---: |
| `phase1_reduced_voice_run1` | -1.8 dBc | -4.0 dBc | -9.1 dBc | -15.1 dBc | 0.9 dBc |
| `phase1_reduced_voice_run2` | -1.7 dBc | -4.0 dBc | -9.5 dBc | -15.4 dBc | 0.9 dBc |
| `phase1_observability` | -1.0 dBc | -2.8 dBc | -7.0 dBc | -12.0 dBc | 2.0 dBc |
| `phase1_timing_margin_impl` | -1.2 dBc | -3.2 dBc | -7.7 dBc | -13.1 dBc | 1.7 dBc |
| `phase1_timing_margin_validation` | -1.6 dBc | -3.8 dBc | -9.0 dBc | -14.8 dBc | 1.1 dBc |
| `phase1_two_voice_hardware` | -3.9 dBc | -8.8 dBc | -17.8 dBc | -28.0 dBc | -2.5 dBc |

The two-voice harmonic profile remains dominated by the same fundamental region. In this uniform window, the current capture has lower H2-H10 aggregate harmonic energy than the timing-margin verifier capture, plus zero clipping and a high crest factor. That is evidence against a square-wave or clipping regression.

## Decay

| Capture | 0.10s | 0.25s | 0.50s | 1.00s | 2.00s |
| --- | ---: | ---: | ---: | ---: | ---: |
| `phase1_reduced_voice_run1` | -7.01 dB | -8.26 dB | -18.11 dB | -20.67 dB | -17.20 dB |
| `phase1_reduced_voice_run2` | -5.58 dB | -9.39 dB | -13.55 dB | -17.50 dB | -14.19 dB |
| `phase1_observability` | -5.56 dB | -10.59 dB | -15.45 dB | -17.90 dB | -15.46 dB |
| `phase1_timing_margin_impl` | -6.20 dB | -11.10 dB | -17.93 dB | -17.28 dB | -19.15 dB |
| `phase1_timing_margin_validation` | -6.64 dB | -11.25 dB | -19.11 dB | -16.13 dB | -17.65 dB |
| `phase1_two_voice_hardware` | -4.17 dB | -9.03 dB | -17.38 dB | -15.99 dB | -13.22 dB |

The current two-voice capture decays at least as strongly as the earlier captures in the first half second. Later windows sit closer to the recording noise floor and room/input noise, so they should not be over-interpreted as the voice envelope itself.

## Files

- Raw comparison table: `reports/phase1_two_voice_audio_comparison.csv`
- Current audio capture: `reports/phase1_two_voice_hardware_audio_capture.wav`
- Current UART evidence: `reports/phase1_two_voice_hardware_uart_com5.txt`

## Conclusion

The current two-voice hardware capture is moderately louder than the closest single-voice Phase 1 captures, and the UART diagnostics confirm the internal mix peak doubled exactly without clipping. The frequency remains in-family with earlier hardware captures, and the recorded waveform remains non-clipped with a healthy crest factor. I would treat this as consistent with the intended simultaneous two-voice overlap, not as an audio regression.
