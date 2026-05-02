# Phase 1C Sample Gen Test Tone — Implementation Report

Date: 2026-05-02
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-9079e0f3`

## Purpose

Diagnostic test to isolate whether low audio output is caused by the waveguide digital path or the WM8978 codec/hardware path. Route the existing `phase0_sample_gen.v` (known-good from the primitive phase that produced `sample.wav`) directly to the audio output, bypassing the waveguide voices entirely.

## Changes

### RTL: phase0_audio_path.v

Instantiate `phase0_sample_gen` and add a mode-select mux:

```
use_sample_gen = audio_enable && tone_enable &&
                 !voice_enable && !voice1_enable && !voice2_enable
```

When `use_sample_gen` is true, `tx_sample` comes from `sample_gen` instead of `body_filter_out`. When false, normal waveguide path.

This is a safe permanent addition: sample_gen is only selected when ALL three voice enables are zero. Normal operation (any voice enabled) uses the waveguide path unchanged.

### Firmware: phase0_main.c

Three changes to `phase0_program_defaults()`:

| Change | Before | After | Reason |
|--------|--------|-------|--------|
| GAIN register | 16384 (50%) | 32767 (100%) | Full-scale test tone |
| Voice control write | `BASELINE \| CLIP_CLEAR` | `CLIP_CLEAR` only | Disable voice enables → enter sample_gen mode |
| Post-codec trigger | `round_robin_smoke()` | `control(TRIGGER_STROBE)` | Fire sample_gen instead of voices |

The voice control writes now use direct MMIO writes (without the BASELINE macro which ORs in ENABLE_M), so the voices are disabled after init. This activates the `use_sample_gen` mux in hardware.

### Test Tone Parameters

| Parameter | Value |
|-----------|-------|
| Waveform | Square wave |
| Phase step | 157482 (~440 Hz) |
| GAIN | 32767 (full-scale) |
| Envelope | Decay step = 0 (sustain) |
| WM8978 speaker vol | 0 (+6 dB) |
| WM8978 SPKOUTP_EN | 1 (enabled) |

## Build

```
Firmware: PASS (1 warning: round_robin_smoke unused — expected for test build)
ROM delta: ~0 words (same instruction count)
Quartus: not compiled (sample_gen.v already in QSF, already known-good)
```

## Validation

The verifier should:
1. Build Quartus SOF (sample_gen.v compiles from existing source)
2. Program board
3. Capture UART telemetry: verify I=50303031, S has CODEC_INIT_DONE, R shows tx_valid
4. Capture audio: should produce loud ~440 Hz square wave
5. Compare per-second RMS against sample.wav (-5.4 dBFS reference)

If output matches sample.wav level: waveguide digital gain is the bottleneck.
If output is still quiet: WM8978/codec hardware path has an issue beyond register config.

## Reverting

To return to normal waveguide operation:
1. Restore GAIN to 16384u
2. Restore voice control writes using `phase0_write_voice_control()`
3. Restore `phase0_run_round_robin_smoke()`
4. Rebuild firmware

The RTL change is safe to keep permanently (mux defaults to waveguide path).
