# Phase 1C Audio Verification Checklist

Date: 2026-05-02
Author: orchestrator `1c005a25-956c-4b69-9b69-9bf3cd9a8d68`

This checklist governs all future audio waveform verification tasks. Verifiers must read this before starting any audio validation.

## Physics-Informed Behavior Gates

### 1. Fundamental Frequency Accuracy

The struck note must produce the intended pitch. For the current fixed-pitch voice:
- Expected fundamental: ~436 Hz (or the configured phase_step frequency)
- Verify via FFT peak in the event window
- Tolerance: ±2 Hz of configured pitch

### 2. Harmonic Structure (Stiff-String Partial Series)

A piano string is stiff, causing inharmonicity — partials deviate from exact integer multiples:
- Detect partials f1 through f6 in the event window
- Verify f_n > n × f1 (inharmonic stretching upward)
- The first partial (f1) should be the strongest; higher partials decay faster
- Absence of partials above noise floor is NOT a failure if the waveguide damping is aggressive — but must be noted

### 3. Exponential Decay Envelope

A struck piano note decays exponentially, not linearly:
- Extract per-second RMS across the event window
- Fit exponential curve to RMS vs. time
- R² of exponential fit should be > 0.85
- Linear-fit R² should be worse than exponential-fit R² (confirms exponential, not linear)
- If decay shape is flat or linear, flag as "not piano-like"

### 4. Attack Transient

A hammer-struck string has a sharp attack:
- Peak must occur within the first 200 ms of the event window
- Peak-to-RMS ratio should be > 6 dB (clear attack transient)
- If peak is in the middle or end of the event, flag as attack failure

### 5. No Audible Artifacts

The tone must be clean:
- No sudden amplitude jumps (> ±3 dB between consecutive 50 ms RMS windows after the attack phase)
- No frequency jumps (fundamental should not shift > ±5 Hz across the event window)
- No dropouts (gaps ≥ 60 ms at < -50 dBFS)
- No audible clipping: zero clipped samples, K=0 in UART telemetry

### 6. Signal Integrity

- DC offset: abs(mean) < 100 PCM codes, < 2% of peak
- No flat-line segments (> 100 consecutive zero samples at non-zero RMS windows)
- Stereo channels: both present, correlated (L-R peak difference < 6 dB)

### 7. Dynamic Consistency Across Reports

For consecutive note events in the same capture:
- Peak dBFS variation across events < 2 dB
- Fundamental frequency variation across events < ±2 Hz
- Decay time (T60) variation across events < 10%
- If any event is anomalous, identify which event(s) and the anomaly type

## Hard Gates

These must ALL pass for a PASS verdict:

| Gate | Threshold | Measurement |
| --- | --- | --- |
| Peak level | -22 to -3 dBFS | Overall capture peak |
| Event-window RMS | ≥ -38.5 dBFS | RMS in event window |
| Fundamental present | 430–442 Hz | FFT peak in event window |
| No clipped samples | 0 | Sample count at ±32767 |
| DC offset | abs < 100 PCM, < 2% peak | Mean of capture |
| Attack peak in first 200 ms | Yes | Time of peak vs. event onset |
| Exponential decay (R² > 0.85) | Yes | RMS vs. time fit |
| No dropouts ≥ 60 ms at < -50 dBFS | 0 | Gap detection |
| Per-event consistency | < 2 dB / < 2 Hz / < 10% T60 | Cross-event comparison |

## Soft Gates (not blocking, but must be assessed)

- Harmonic partial count and inharmonicity pattern
- Stereo balance
- K=0 confirmation in simultaneous UART capture
- Comparison against accepted reference capture (same SOF, same gain settings)

## Gain Baseline

Each SOF may have a different recording gain baseline. The verifier must:
1. Record the capture device name and OS audio input gain setting
2. If peak is below -22 dBFS but signal is clearly present above noise floor, apply calibrated gain boost and re-evaluate
3. Document the applied gain correction in the validation report
4. Do not fail a capture solely for low peak if the signal is present and gain-correctable

## Verdict Rules

- **PASS**: All hard gates pass
- **PASS with gain correction**: All hard gates pass after documented gain boost
- **FAIL (capture setup)**: Signal absent or below noise floor, resembles known unplugged-mic negative control. Do NOT flag as design failure — flag as capture-setup failure with re-run instructions.
- **FAIL (design)**: Signal present but violates physics-informed gates (wrong frequency, linear decay, clipping, artifacts, inconsistent across events). Must identify specific gate failures with evidence.
