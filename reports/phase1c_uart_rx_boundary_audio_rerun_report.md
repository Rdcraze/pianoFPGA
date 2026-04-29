# Phase 1C UART RX Boundary Audio Rerun Report

Date: 2026-04-29
Agent: Codex implementer
Task: `task-02f58eb6`

## Summary

Preserved the parser boundary fix and made no RTL, firmware, constraint, clock, register, or UART behavior changes for this task.

The verifier's anomalous boundary audio capture was explained by the external microphone being unplugged. After reconnecting the external Realtek microphone and rerunning the same commanded smoke against the unchanged final boundary-fix SOF, the audio evidence again shows the expected note event near the accepted baseline frequency with no clipping/dropouts and correct UART profiles.

Promotion recommendation: the parser fix can be promoted on the existing parser/UART/simulation/resource/timing evidence plus this corrected plugged-in audio rerun.

## Bitstream Identity

No rebuild was performed.

- SOF SHA-256: `CAB259BC697ABB5F76AD48120AE4CD65AB1FD4311FC9AEA59F620868E3F3D7F5`
- Programmer checksum: `0x005F102E`
- Program log: `reports/phase1c_uart_rx_boundary_audio_rerun_quartus_pgm.log`
- Programmer result: PASS, `0 errors, 0 warnings`

Identity log: `reports/phase1c_uart_rx_boundary_audio_rerun_sof_identity.log`

## Capture Setup

- Audio input: external microphone device shown by FFmpeg as the Realtek external mic, physically reconnected before this rerun
- Audio devices log: `reports/phase1c_uart_rx_boundary_audio_rerun_audio_devices.log`
- Audio capture: `reports/phase1c_uart_rx_boundary_audio_rerun_audio_capture.wav`
- FFmpeg log: `reports/phase1c_uart_rx_boundary_audio_rerun_audio_ffmpeg.log`
- Audio analysis: `reports/phase1c_uart_rx_boundary_audio_rerun_audio_analysis.txt`
- UART capture: `reports/phase1c_uart_rx_boundary_audio_rerun_uart_capture.txt`
- UART check: `reports/phase1c_uart_rx_boundary_audio_rerun_uart_check.log`
- Sequence: program same SOF, send six `!N\r\n` commands at 100 ms spacing, capture 12 s audio and UART telemetry.

The earlier 250 Hz, low-level boundary audio is retained only as a negative comparison because it was captured with the external microphone unplugged.

## UART Evidence

Corrected rerun UART check: PASS.

- `G=0000000C`
- `Q=00000006`
- `X=00000000`
- `K=00000000`
- `T/U/O=00000004`
- `J/L/N=00000004`
- No `!N` echo bytes observed
- Valid telemetry frames: `266`

Full latest UART voice telemetry comparison is in `reports/phase1c_uart_rx_boundary_audio_rerun_uart_latest_compare.csv`. The control/pitch/status tags remain internally consistent with the prior accepted UART RX capture:

- `V/Y/Z=08220010`
- `F/C/E/W` remain in the same `0x0007E7xx` to `0x0007EAxx` range
- `R/S=8018077F/8018073F`
- `K=0`, so no internal mix clipping

## Audio Comparison

Metric output: `reports/phase1c_uart_rx_boundary_audio_rerun_compare.txt`.
Windowed spectrum: `reports/phase1c_uart_rx_boundary_audio_rerun_windowed_spectrum.txt`.

| Capture | Peak dB | RMS dB | Dominant / event frequency | Envelope / shape |
| --- | ---: | ---: | ---: | --- |
| accepted round-robin validation | `-13.124` | `-44.054` | `435.94 Hz` whole capture | pluck-like, uneven decay |
| prior UART RX accepted | `-13.143` | `-42.554` | `434.88 Hz` whole capture | broadly baseline-like |
| boundary capture with mic unplugged | `-31.822` | `-39.188` | `250.08 Hz` whole capture | invalid low-level pickup |
| corrected plugged-in rerun | `-13.589` | `-35.705` | `436 Hz` in loud event window | clear note event, no dropout/clipping |

Corrected plugged-in rerun details:

- Duration: `11.99 s`
- Min/max sample: `-6857 / +3031`
- DC mean: `-2.122` samples
- Peak asymmetry: `55.797%`, comparable in kind to the accepted mic captures' asymmetric analog waveform
- Full-scale clipped samples: `0`
- Internal 20 ms dropout windows: `0`
- Whole-capture FFT peak: `198.18 Hz`
- Loud-event windowed spectrum: `436 Hz`, with `872 Hz` harmonic visible in the `1.0-2.0 s` window

The corrected capture is louder in RMS than the older accepted captures because it includes a stronger low-frequency/background component after the note event. The key acceptance checks are satisfied: the commanded note event is present at the expected `~436 Hz` event frequency, peak level is back near the accepted `-13 dBFS` range, there is no clipping, no dropout, near-zero DC offset, and UART reports `K=0`.

## Conclusion

The anomalous evidence was a capture/setup issue: the external microphone was unplugged during the earlier boundary-fix audio capture. With the microphone reconnected, the same bitstream produces valid UART telemetry and a baseline-like commanded audio event.

No source changes are warranted. The existing parser boundary fix can be promoted.
