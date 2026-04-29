# Phase 0 Sample-Rate Harmonic Follow-Up

Date: `2026-04-23`

Historical note:

- this report analyzes the pre-`task-e5e0096b` shipped default, where `phase0_soc_stub.v` and `fw/phase0/phase0_main.c` still used `DECAY_STEP = 48` and periodic retrigger behavior
- the current tree has since been aligned to the intended continuous baseline-tone contract (`DECAY_STEP = 0` and status-only periodic reporting), so treat the waveform diagnosis below as explanation for the earlier hardware capture rather than the current default behavior

## Conclusion

The fresh hardware capture in [phase0_sample_rate_fix_capture.wav](</E:/projects/piano-agents/reports/phase0_sample_rate_fix_capture.wav>) matches the exact current RTL default waveform very closely.

This follow-up materially changes the earlier interpretation in [phase0_sample_rate_fix_validation.md](</E:/projects/piano-agents/reports/phase0_sample_rate_fix_validation.md>): the observed `~538.79 Hz` dominant line is not good evidence of a remaining sample-rate error by itself. It is the expected fundamental of the current default burst waveform once `decay_step = 48` and the generator's auto-retrigger behavior are taken into account.

## Exact Expected Waveform

The active hardware defaults are not a continuous `440 Hz` square wave.

Relevant RTL/programmed defaults:

- [phase0_sample_gen.v](</E:/projects/piano-agents/rtl/audio/phase0_sample_gen.v>) with `wave_sel = 2'b00` outputs `phase_accum[23] ? env_signed : -env_signed`
- [phase0_control_regs.v](</E:/projects/piano-agents/rtl/control/phase0_control_regs.v>) resets to `phase_step = 157482`, `gain = 4096`, `decay_step = 0`
- [phase0_soc_stub.v](</E:/projects/piano-agents/rtl/control/phase0_soc_stub.v>) then overwrites the live defaults to `phase_step = 157482`, `gain = 4096`, `decay_step = 48`

Because `decay_step != 0`, the envelope decays to zero, `active` drops, and the generator auto-retriggers on the next sample because of the `trigger_strobe || !active` condition. With the exact nonblocking-update behavior in the RTL, one repeating period is:

- `1` zero sample
- `54` negative samples: `-4096, -4048, ... -1552`
- `32` positive samples: `+1504, +1456, ... +16`

That is an exact `87`-sample repeating pattern. If `audio_lrc` is the intended `46.875 kHz`, the expected fundamental is:

- `46875 / 87 = 538.793103 Hz`

So the dominant audible pitch for the current shipped defaults is expected to be about `538.79 Hz`, not `440 Hz`.

The `440 Hz` number only applies to a continuous NCO-driven square-wave interpretation, which is not what the live default configuration produces once `decay_step = 48` is written.

## Harmonic Comparison

I compared the capture against the exact 87-sample RTL waveform and against an ideal 50% square wave.

The measured capture strongly disagrees with an ideal square wave because it has large even harmonics. That is expected for the real RTL waveform, which is asymmetric and retriggered.

Measured capture versus exact RTL expectation:

| Harmonic | Frequency (Hz) | Capture Rel. | RTL Rel. | Delta |
| --- | ---: | ---: | ---: | ---: |
| H1 | 538.793 | 0.00 dB | 0.00 dB | 0.00 dB |
| H2 | 1077.586 | -9.39 dB | -9.36 dB | -0.03 dB |
| H3 | 1616.379 | -16.48 dB | -16.41 dB | -0.07 dB |
| H4 | 2155.172 | -12.21 dB | -12.09 dB | -0.12 dB |
| H5 | 2693.966 | -23.67 dB | -23.48 dB | -0.19 dB |
| H6 | 3232.759 | -18.06 dB | -17.80 dB | -0.27 dB |
| H7 | 3771.552 | -18.36 dB | -17.99 dB | -0.38 dB |
| H8 | 4310.345 | -33.24 dB | -32.78 dB | -0.46 dB |
| H9 | 4849.138 | -19.94 dB | -19.31 dB | -0.63 dB |
| H10 | 5387.931 | -24.94 dB | -24.19 dB | -0.75 dB |
| H11 | 5926.724 | -27.05 dB | -26.10 dB | -0.95 dB |
| H12 | 6465.517 | -22.64 dB | -21.51 dB | -1.13 dB |

The match is too close to dismiss as coincidence. The analog capture is behaving like the RTL says it should.

## Interpretation

The stronger reading is:

- the analog audio path is alive
- the live waveform shape matches the current RTL defaults
- the earlier "still too fast" conclusion is not supported by harmonic evidence

What remains true is narrower:

- this pass does not directly measure `audio_mclk`, `audio_bclk`, or `audio_lrc`
- so it is still not a direct clock-domain sign-off
- but the captured spectrum is consistent with the intended `46.875 kHz` contract once the actual burst waveform is modeled correctly

## Practical Implication

If the goal is a clean, continuous `~440 Hz` default tone, the current live defaults are not configured for that. The most direct ways to get that behavior are:

1. set `decay_step = 0`, or
2. change the generator so it does not auto-retrigger and phase-reset after each short decay burst

Bottom line: the current hardware capture looks like the exact implemented waveform, not like a residual unexplained sample-rate fault.
