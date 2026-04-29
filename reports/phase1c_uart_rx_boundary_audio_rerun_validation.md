# Phase 1C UART RX Boundary Audio Rerun Validation

Verifier: Codex verifier agent `e9722d83-b000-4165-a5a7-36b758c2e8d8`  
Task: `task-31c45996`  
Implementation artifact: `d89d2059-08d9-4bd3-9f04-e831b9b96517`  
Rerun report: `reports/phase1c_uart_rx_boundary_audio_rerun_report.md`

## Verdict

PASS.

The audio rerun resolves the prior boundary-fix validation blocker. The corrected capture shows a clear commanded note event with the expected `~436 Hz` spectral peak and harmonic content, peak level back near the accepted captures, no clipping, no internal dropout gaps, low DC offset, and UART telemetry still reporting the commanded profile with `K=0`, `Q=6`, `X=0`, and no echo.

## Identity And Scope

PASS.

The rerun did not rebuild or change RTL, firmware, constraints, clocks, registers, UART behavior, or the bitstream. Independent SOF hash check matches the claimed identity:

- SOF SHA-256: `CAB259BC697ABB5F76AD48120AE4CD65AB1FD4311FC9AEA59F620868E3F3D7F5`
- Programmer checksum in rerun log: `0x005F102E`
- Source/parser boundary validation remains anchored to the prior accepted boundary-fix evidence.

Git status was clean before this validation report was written.

## UART And Parser State

PASS.

The rerun UART capture file is LF-normalized rather than raw CRLF, so it is not suitable as a strict byte-for-byte CRLF parser artifact. For this rerun task that is acceptable because the same source/SOF is used and the previous boundary-fix validation already covered CRLF parser behavior. I independently checked the LF-normalized latest telemetry:

- frames: `266`
- `G=12`
- `H=2`
- `J/L/N=4`
- `T/U/O=4`
- `P=0`
- `K=0`
- `Q=6`
- `X=0`
- no `!N` echo bytes present

This matches `reports/phase1c_uart_rx_boundary_audio_rerun_uart_check.log`.

## Waveform Validation

PASS.

Independent waveform metrics:

| Capture | RMS | Peak | Event-window dominant content | Notes |
| --- | ---: | ---: | --- | --- |
| accepted round-robin verifier capture | `-44.05 dBFS` | `-13.12 dBFS` | `436 Hz`, `872 Hz`, `1308 Hz` | accepted baseline |
| prior UART RX capture | `-42.55 dBFS` | `-13.14 dBFS` | `436 Hz`, `872 Hz`, `1308 Hz` | accepted-like UART RX evidence |
| failing unplugged boundary capture | `-39.19 dBFS` | `-31.82 dBFS` | `250 Hz` whole-capture pickup | rejected capture/setup artifact |
| corrected audio rerun | `-35.70 dBFS` | `-13.59 dBFS` | `436 Hz`, `872 Hz` in loud event window | passes event/audio smoke |

Corrected rerun details:

- duration: `11.988 s`
- min/max sample: `-6857 / +3031`
- DC mean: about `-2.122` samples
- peak asymmetry: about `55.8%`, comparable to the accepted analog captures
- clipped full-scale samples: `0`
- internal 20 ms dropout windows: `0`
- best 1 s event window starts around `1.5 s`
- best 1 s RMS: `-31.49 dBFS`
- top event-window spectral bins: `436 Hz`, `198 Hz`, `297 Hz`, `99 Hz`; the implementer spectrum log also shows `872 Hz` in the `1.0-2.0 s` note-event window

The full-capture RMS is higher and the envelope correlation remains lower than the accepted round-robin capture because the rerun includes a stronger low-frequency/background component after the note event. That background does not mask the key acceptance evidence: the note event is present near the accepted frequency, the peak level is back in the accepted range, there is no clipping or flat spot, no silence/dropout discontinuity, and hardware telemetry reports no mix clipping.

## Recommendation

Promote the UART RX parser boundary fix. The prior FAIL was resolved by correcting the audio capture setup, while preserving the already passing parser, UART, simulation, resource, timing, ROM, and bitstream evidence.
