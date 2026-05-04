# Obsolete Code

Diagnostic scaffolding from the Phase 1C waveguide volume investigation (2026-05-02).

## re_trigger_and_3voice_simultaneous.patch

Commits `f2a938a`, `e381f3c`, `c5f0709` — firmware changes for 3-voice simultaneous triggering and re-trigger fixes.

**Why obsolete**: The waveguide RTL clears the delay line on every trigger strobe (`trigger_strobe && enable` in `phase1_reduced_voice.v`). Re-triggering an active voice fundamentally cannot produce sustained output with the current architecture. The diagnostic goal — apples-to-apples volume comparison against the continuous sample_gen square wave — is incompatible with the struck-string waveguide model.

**What we proved instead**: ModelSim gain trace confirms the digital path hits -2.1 dBFS at 3-voice sum with K=0. The first-strike transient empirically reaches -1.93 dBFS. The codec path is verified working (sample_gen hits -5.58 dBFS). The gain calibration is correct.

**Kept**: sample_gen test path in `phase0_audio_path.v` (useful for future codec verification), body IIR filter, all gain fixes (>>>1 guard, velocity, speaker volume, SPKOUTP_EN).
