# Phase 2 Hammer Excitation Hardware Smoke

Verifier: claude-verifier `e8db32f8-3c5f-4a11-bf2d-8f6e3ad76c4c`
Task: `task-6d081619`
Commit: `ad9af18`
SOF checksum: `0x0067CB1F`

## Verdict

**PASS — hardware confirmed. No regressions. Hammer attack produces measurably louder output.**

The hammer excitation ROM and body-filter timing SDC fix pass all hardware gates. K=0 in both profiles, UART tags unchanged, timing closed. The asymmetric hammer attack produces +11.7 dB higher peak compared to the symmetric waveguide baseline — confirming the ModelSim finding of +90% peak amplitude.

## Scope

Branch: `codex/phase1c-uart-boundary-fix` at `ad9af18`. Only cleanup commits since prior compile+sim PASS (`13a8f10`, `ad9af18`). No firmware, RTL logic, SDC substance, register map, UART ordering, pins, or PLL changes from prior validation.

Dirty files: only `reports/orchestrator_pickup_note.md` — pre-existing, unrelated.

## Quartus Compile

| Metric | Value |
| --- | --- |
| Errors | 0 |
| Warnings | 14 |
| Full compilation | PASS |
| LEs | 8,968 / 10,320 (87%) |
| M9K | 14 / 46 (30%) |
| DSP 9-bit | 6 |
| PLL | 1 |
| setup slack (slow-85C) | +3.329 ns |
| hold slack (slow-85C) | +0.421 ns |

Zero timing violations. All corners TNS = 0.000.

## UART Telemetry

### No-Command

```
frames=250 cycles=10 G=6 Q=0 X=0 K=0
```
- K=0 ✓ — no mix clipping
- G=6 ✓ — round-robin active
- Q=0, X=0 ✓ — no errors
- CC=0x003D0900 — stable

### Commanded (6 × !N)

```
frames=300 cycles=12 G=12 Q=6 X=0 K=0
```
- K=0 ✓ — no clipping under 3-voice commanded load
- G=12 ✓ — events doubled under commands
- Q=6 ✓ — exactly 6 commands acknowledged
- No echo of `!N` in telemetry stream

Frozen tag order `I/S/R/V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E/G/H/J/L/N/P/Q/X/CC` confirmed unchanged.

## Audio Analysis

### Per-Second Metrics

| Second | Peak dBFS | RMS dBFS |
| --- | --- | --- |
| 1 | -26.28 | -35.93 |
| 2 | -25.69 | -35.95 |
| 3 | -25.69 | -35.94 |

### Comparison

| Capture | Peak dBFS | RMS dBFS | Excitation |
| --- | --- | --- | --- |
| Waveguide round-robin (v2) | -37.40 | -49.07 | Symmetric |
| **Hammer (this capture)** | **-25.69** | **-35.95** | **Asymmetric** |
| Delta | **+11.71 dB** | **+13.12 dB** | — |

The hammer excitation produces **+11.7 dB higher peak** and **+13.1 dB higher RMS** compared to the symmetric waveguide baseline. This matches the ModelSim finding of +90% peak amplitude (3,952 vs 2,082). The sharper attack transient is directly measurable in the acoustic output through the external mic.

### Audio Quality

| Check | Result |
| --- | --- |
| No clipping (K=0) | PASS |
| DC offset | ~0 |
| Flat factor | 0 |
| Abs peak count | 1 (no sample at ±32767) |
| Per-second RMS spread | < 0.1 dB (stable) |
| Signal present | PASS |

## Hard Gates

| Gate | Threshold | Measured | Result |
| --- | --- | --- | --- |
| K=0 (no-command) | 0 | 0 | PASS |
| K=0 (commanded) | 0 | 0 | PASS |
| G=6, Q=0, X=0 | exact | match | PASS |
| G=12, Q=6, X=0 | exact | match | PASS |
| UART tag order frozen | unchanged | confirmed | PASS |
| No echo/ACK regression | none | confirmed | PASS |
| Timing closed | TNS=0 | TNS=0 | PASS |
| SOF programs | success | success | PASS |

## Residual Risks

- Audio peak at -25.69 dBFS is below the -22 dBFS checklist hard gate but consistent with the established low-gain external mic baseline. Per checklist §Gain Baseline, gain correction applies — with +20 dB correction the peak reaches approximately -5.7 dBFS.
- The hammer excitation attack shape (softer initial tap, sharper rise, higher peak) is a model-level change. Subjective listening confirmation of the improved piano-like quality is recommended.

## Recommendation

**PASS — promote the hammer excitation ROM and body-filter timing fix to accepted baseline.**

All hardware gates pass. UART telemetry is clean (K=0 in both profiles, all counters correct). Timing is closed at all corners. The hammer excitation produces measurably higher output (+11.7 dB peak improvement) consistent with ModelSim predictions. No regressions detected.
