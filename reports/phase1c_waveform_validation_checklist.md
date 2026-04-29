# Phase 1C Waveform Validation Checklist

Verifier task: `task-50976e79`  
Purpose: require future Phase 1C audio/UART baseline promotions to prove waveform continuity, not just UART counter correctness.

## Baseline Identity

Use this checklist for evidence produced from the accepted UART RX boundary-fix SOF unless the report explicitly declares a new baseline:

- SOF SHA-256: `CAB259BC697ABB5F76AD48120AE4CD65AB1FD4311FC9AEA59F620868E3F3D7F5`
- Programmer checksum: `0x005F102E`

If either identity value changes, keep the same checks but treat the result as a new baseline validation. Do not waive frequency, level, or UART thresholds without recording the reason and the new reference measurements.

## Reference Artifacts

Compare each new capture against these files:

| Role | Files | Key measurements |
| --- | --- | --- |
| Accepted round-robin audio baseline | `reports/phase1c_firmware_round_robin_validation_audio_capture.wav`, `reports/phase1c_firmware_round_robin_validation_audio_analysis.txt` | RMS `-44.05 dBFS`, peak `-13.12 dBFS`, event bins `436/872/1308 Hz`, pluck-like uneven decay |
| Accepted UART RX audio evidence | `reports/phase1c_uart_rx_command_ingress_audio_capture.wav`, `reports/phase1c_uart_rx_command_ingress_audio_analysis.txt` | RMS `-42.55 dBFS`, peak `-13.14 dBFS`, event bins `436/872/1308 Hz` |
| Rejected negative control | `reports/phase1c_uart_rx_command_ingress_boundary_audio_capture.wav`, `reports/phase1c_uart_rx_command_ingress_boundary_audio_analysis.txt` | RMS `-39.19 dBFS`, peak `-31.82 dBFS`, whole-capture peak `250 Hz`, nearly constant low-level pickup from unplugged external mic |
| Corrected plugged-in rerun | `reports/phase1c_uart_rx_boundary_audio_rerun_audio_capture.wav`, `reports/phase1c_uart_rx_boundary_audio_rerun_audio_analysis.txt`, `reports/phase1c_uart_rx_boundary_audio_rerun_compare.txt`, `reports/phase1c_uart_rx_boundary_audio_rerun_windowed_spectrum.txt` | RMS `-35.70 dBFS`, peak `-13.59 dBFS`, event-window `436 Hz` with `872 Hz` harmonic, no clipping or dropouts |

## Required Evidence Bundle

Each validation must preserve these artifacts in `reports/`:

- Raw audio WAV and FFmpeg capture log.
- Audio device enumeration log naming the selected capture device.
- Audio analysis text with duration, sample rate, channels, min/max, peak dBFS, RMS dBFS, DC offset, clipping count, flat factor, dropout-window count, and per-second RMS values.
- Windowed spectrum or equivalent event-window frequency report. Whole-capture FFT alone is insufficient because the corrected rerun had stronger low-frequency background while the event window still showed the commanded note.
- UART raw capture as `.bin` when parser byte behavior matters, plus a normalized `.txt` view only for readability.
- UART check log for no-command, six-command, and malformed or boundary profiles.
- SOF identity log and programmer checksum log.

## Capture Setup Checks

Fail the validation if any setup item is missing or ambiguous:

- The audio device log must show the intended external microphone or line-in device. If the intended device is absent, disabled, unplugged, or replaced by an unspecified default device, rerun before judging waveform quality.
- The report must state whether the capture path was physically checked before recording. The previous false blocker was an unplugged external Realtek microphone.
- The WAV must be readable by FFmpeg, use 48 kHz PCM samples, and cover the expected smoke interval, normally `11.5 s` to `12.5 s`.
- Mono or stereo is acceptable only if the analysis states how channels were handled. Downmixed analysis must be applied consistently to the reference captures and the new capture.
- The six `!N\r\n` commands must be sent at the documented cadence for commanded audio smoke, and UART/audio capture must overlap the command window.

## Hard Waveform Gates

Fail on any hard-gate miss:

- Peak level must be in the plausible commanded-capture range: `-22 dBFS <= peak <= -3 dBFS`. A peak below `-25 dBFS` is an immediate setup/anomaly failure for the current Phase 1C rig unless a new gain baseline is explicitly established. This catches the rejected unplugged capture at `-31.82 dBFS`.
- The loudest 1 s event window must have RMS at or above `-38.5 dBFS`. Accepted/prior/corrected references are about `-35.0`, `-35.0`, and `-31.5 dBFS`; the rejected unplugged capture stayed near `-39 dBFS`.
- The event-window spectrum must include a `430 Hz` to `442 Hz` bin in the top listed peaks. The `860 Hz` to `884 Hz` harmonic should also appear in the same event window or an adjacent commanded-event window. If the whole-capture dominant bin is low frequency, it is acceptable only when this event-window check passes.
- Full-scale clipped samples must be `0`, and the flat factor must remain `0` or be explained by a non-audio tool artifact. Any visible saturation plateau at or near full scale fails.
- Internal dropout/silence gaps of `>=60 ms` inside the active event span fail. The 20 ms dropout-window counter should remain `0`; any nonzero count requires waveform inspection and justification.
- Absolute DC mean must stay below `100` PCM samples and below `2%` of the absolute peak. Larger DC offset fails unless the raw waveform proves the offset comes from a known capture-device calibration issue and not firmware/audio output.
- The waveform must show a distinct commanded note event with onset and decay. A nearly constant low-level envelope like the rejected unplugged capture fails even if UART counters pass.

## Shape And Resemblance Checks

These checks decide borderline captures after the hard gates:

- Compare the normalized 100 ms envelope and per-second RMS profile against the accepted round-robin and prior UART RX captures. The result does not need a high correlation because mic position and background can vary, but it must not be almost flat for the whole capture.
- Per-second RMS should show a clear event contrast. As a guardrail, flag any capture with less than `3 dB` spread across active seconds; fail it if that low spread is paired with peak below `-25 dBFS` or missing `436 Hz` event content.
- Peak asymmetry alone is not a failure. Accepted analog captures showed roughly `56%` to `69%` asymmetry with near-zero DC and no clipping. Treat asymmetry above `80%` as a warning that requires waveform inspection.
- Background or room pickup is acceptable only if the commanded event remains visible in time and frequency. The corrected rerun had a stronger `198 Hz` whole-capture component but passed because its event window showed `436 Hz` and `872 Hz`.
- Inspect a plotted waveform or envelope for onset/decay continuity. The capture should not look like a steady tone, flat noise bed, clipped block, or silence with a small pickup component.

## UART Gates

Waveform evidence must be paired with UART evidence from the same SOF identity:

- Telemetry order must remain frozen and parsable by the existing checker.
- No-command profile: latest `G=6`, `H=2`, `J/L/N=2`, `T/U/O=2`, `P=0`, `K=0`, `Q=0`, `X=0`.
- Six-command profile: latest `G=12`, `H=2`, `J/L/N=4`, `T/U/O=4`, `P=0`, `K=0`, `Q=6`, `X=0`.
- Malformed or boundary profile: latest `G=6`, `H=2`, `J/L/N=2`, `T/U/O=2`, `P=0`, `K=0`, `Q=0`, `X=00030004` for the accepted boundary test sequence.
- No command echo bytes may appear in telemetry. For commanded captures, `!N` must be absent from the received telemetry stream.
- `K` must remain `0` in every profile. A nonzero `K` is a hardware mix-clipping failure regardless of the external audio waveform.
- For parser or boundary validations, use raw `.bin` captures to verify CRLF byte behavior. LF-normalized text captures are acceptable only for latest-value telemetry summaries.

## Decision Rules

- PASS only when all hard waveform gates, setup checks, UART gates, and identity checks pass.
- FAIL if the audio resembles the rejected unplugged-mic capture: low peak near `-32 dBFS`, missing `436 Hz` event content, and a nearly constant low-level envelope.
- FAIL if UART counters pass but waveform evidence does not demonstrate an audible commanded event. UART counters are necessary but not sufficient for Phase 1C baseline acceptance.
- WARN, not fail, for higher full-capture RMS or low-frequency background when event-window frequency, peak range, clipping, dropout, and UART gates pass.
- Record exact deltas against the reference table in every validation report, including any reason for accepting a borderline capture.

## Report Template

Each verifier report should include:

```text
Verdict: PASS/FAIL/WARN
SOF SHA-256:
Programmer checksum:
Audio device:
Capture duration/sample format:
Peak dBFS:
RMS dBFS:
Best event-window start and RMS:
Event-window top frequencies:
DC mean:
Clipped samples / flat factor:
Dropout gaps:
Envelope/per-second RMS observation:
UART no-command result:
UART six-command result:
UART malformed/boundary result:
Comparison conclusion against accepted references and rejected unplugged negative control:
```
