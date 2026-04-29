# Phase 0 Default-Tone Behavior Validation

Date: `2026-04-23`

## Findings

### No new verifier findings: the shipped default tone now matches the intended continuous baseline-tone contract on hardware

I validated the updated hardware image on the live board with fresh UART and analog-capture evidence.

Program/load result:

- programmed image: `quartus/phase0/output_files/piano_phase0_top.sof`
- Quartus Programmer checksum: `0x00107A7C`
- JTAG cable/device: `USB-Blaster [USB-0]`, `0x020F10DD`

UART/control baseline remained healthy on the updated image:

- raw UART artifact: [phase0_default_tone_behavior_uart.txt](</E:/projects/piano-agents/reports/phase0_default_tone_behavior_uart.txt>)
- observed boot/runtime frames:
  - `I=50303031`
  - `S=8019030A`
  - `R=80190314`
  - recurring `R=8019035A`

Fresh analog evidence:

- capture artifact: [phase0_default_tone_behavior_capture.wav](</E:/projects/piano-agents/reports/phase0_default_tone_behavior_capture.wav>)
- capture path: external Realtek audio-input endpoint
- dominant tone from the stable middle `6 s` window: `440.0016 Hz`
- intended nominal tone under the current explicit contract:
  - `phase_step = 157482`
  - nominal sample rate `46.875 kHz`
  - expected tone `157482 * 46875 / 2^24 = 439.9996 Hz`
- frequency error versus that target: `+0.0019 Hz`

The current capture no longer looks like the old burst/retrigger behavior:

- old burst-style hardware signature explained in [phase0_sample_rate_harmonic_followup.md](</E:/projects/piano-agents/reports/phase0_sample_rate_harmonic_followup.md>) predicted `~538.793 Hz`
- new capture instead lands at `440.0016 Hz`
- even harmonics are now strongly suppressed:
  - `H2`: `-33.59 dB`
  - `H4`: `-40.45 dB`
  - `H6`: `-44.03 dB`
  - `H8`: `-46.01 dB`
- odd harmonics remain dominant, which is consistent with the intended continuous square-wave default:
  - `H3`: `-8.60 dB`
  - `H5`: `-12.85 dB`
  - `H7`: `-15.81 dB`
  - `H9`: `-18.04 dB`

Envelope stability is also consistent with a continuous baseline tone rather than a repeating decay burst:

- `20 ms` RMS-window coefficient of variation: `1.167%`
- no dominant `~538.79 Hz` burst-period signature

End-to-end contract alignment is now coherent in the current tree:

- [phase0_soc_stub.v](</E:/projects/piano-agents/rtl/control/phase0_soc_stub.v>) uses `DEFAULT_DECAY = 0`
- [phase0_control_regs.v](</E:/projects/piano-agents/rtl/control/phase0_control_regs.v>) resets `decay_step` to `0`
- [phase0_main.c](</E:/projects/piano-agents/fw/phase0/phase0_main.c>) writes `DECAY_STEP = 0` and reports `phase0 continuous baseline armed`
- [phase0_impl_notes.md](</E:/projects/piano-agents/docs/phase0_impl_notes.md>) now documents the shipped Phase 0 default as a continuous baseline tone rather than the earlier burst-and-retrigger behavior

## Exact Actions And Results

1. Confirmed the rebuilt packaged image and timestamp:
   - `quartus/phase0/output_files/piano_phase0_top.sof`
2. Opened `COM4` at `115200 8N1`, then reprogrammed the board over JTAG.
3. Captured the post-config UART stream and saved it as:
   - [phase0_default_tone_behavior_uart.txt](</E:/projects/piano-agents/reports/phase0_default_tone_behavior_uart.txt>)
4. Recorded a fresh `~8 s` analog capture from the external Realtek input endpoint:
   - [phase0_default_tone_behavior_capture.wav](</E:/projects/piano-agents/reports/phase0_default_tone_behavior_capture.wav>)
5. Analyzed the capture locally for:
   - dominant frequency
   - harmonic structure
   - envelope stability

## Interpretation

The hardware behavior now matches the intended post-alignment contract:

- control/UART path is still healthy
- the default analog output is now a continuous baseline tone
- the dominant frequency matches the intended `~440 Hz` contract essentially exactly
- the harmonic pattern changed from the earlier burst/asymmetric waveform to the expected odd-harmonic-dominant square-wave behavior

I did not directly probe `audio_mclk`, `audio_bclk`, or `audio_lrc` in this pass, so this is still not a direct pin-level clock sign-off. But the combined UART and analog evidence is strong enough to say the earlier verifier concern about shipped default behavior has been resolved in the current hardware image.

## Minor Observation

Both captured channels do contain the same intended tone:

- left channel dominant tone: `440.001563 Hz`
- right channel dominant tone: `440.001586 Hz`

The caveat is level symmetry rather than channel absence:

- left RMS: `0.168975`
- right RMS: `0.043726`
- left/right RMS ratio: `3.864`
- correlation: `0.594`

The harmonic structure on both channels is still consistent with the continuous-square default rather than the old burst waveform:

- left channel:
  - `H2`: `-36.65 dB`
  - `H3`: `-9.57 dB`
  - `H5`: `-14.00 dB`
- right channel:
  - `H2`: `-27.23 dB`
  - `H3`: `-6.03 dB`
  - `H5`: `-9.79 dB`

That asymmetry looks more like the current PC-side analog capture wiring/path than a Phase 0 tone-generation contract problem, especially because the RTL serializer is written as dual-mono reuse of the same `tx_sample` across both `audio_lrc` halves in [wm8978_dac_tx.v](</E:/projects/piano-agents/rtl/peripherals/wm8978_dac_tx.v:34>).

Bottom line: the previous burst-and-retrigger default behavior is gone on hardware. The shipped default now behaves like the intended continuous `~440 Hz` baseline tone.
