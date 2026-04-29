# Phase 1 Two-Voice Hardware Smoke

Date: 2026-04-28
Verifier: Codex verifier
Task: `task-691ac888`

## Verdict

PASS.

The exact frozen Phase 1 two-voice SOF was programmed on the live EP4CE10 board, UART observability was captured through the active CH340 port, and analog audio was recorded from the external Realtek input path. The captured UART frames match the expected two-voice counters and diagnostics, including `T=1`, `U=1`, `K=0`, matching voice0/voice1 peaks, doubled mix peak, and no reported mix clipping.

Recommendation: promote this build from tool-validated to hardware-accepted for the current two-voice baseline. Do not treat this as authorization for feature expansion; it only closes the deferred hardware UART/audio smoke gate for the frozen SOF.

## SOF Identity

- SOF: `quartus/phase0/output_files/piano_phase0_top.sof`
- Expected SHA-256: `274C3F3178A08E103B500E724ED15E5FDFF0E58D15DD0EFB94514BECC3523A78`
- Observed SHA-256: `274C3F3178A08E103B500E724ED15E5FDFF0E58D15DD0EFB94514BECC3523A78`
- Expected/programmer checksum: `0x00553670`

## Setup And Commands

- JTAG cable: `USB-Blaster [USB-0]`
- FPGA target: `EP4CE10F17@1`
- Program command:
  `quartus_pgm -m jtag -c "USB-Blaster [USB-0]" -o "p;quartus/phase0/output_files/piano_phase0_top.sof"`
- UART: `COM5`, `115200 8N1`
- Audio capture: DirectShow external Realtek input, 48 kHz stereo WAV

Evidence files:

- `reports/phase1_two_voice_hardware_quartus_pgm.log`
- `reports/phase1_two_voice_hardware_serial_ports.txt`
- `reports/phase1_two_voice_hardware_uart_com5.txt`
- `reports/phase1_two_voice_hardware_uart_com5.bin`
- `reports/phase1_two_voice_hardware_audio_capture.wav`
- `reports/phase1_two_voice_hardware_audio_ffmpeg.log`
- `reports/phase1_two_voice_hardware_audio_analysis.txt`

## Programming Evidence

`quartus_pgm` reported:

- programming cable: `USB-Blaster [USB-0]`
- programming file checksum: `0x00553670`
- device: `EP4CE10F17@1`
- JTAG ID code: `0x020F10DD`
- result: `Configuration succeeded -- 1 device(s) configured`
- final status: `0 errors, 0 warnings`

## UART Evidence

Initial `COM3` and `COM4` PnP entries were stale; direct opens failed with "port does not exist" and `mode COM3` / `mode COM4` rejected both names. Present-only enumeration then showed the active CH340 path as `USB-SERIAL CH340 (COM5)`, and `COM5` opened successfully.

The `COM5` capture included startup and recurring diagnostic frames:

```text
I=50303031
S=8018073F
R=8018077F
V=08220010
F=0002212E
T=00000001
A=000172B3
W=000221C2
Y=08220010
U=00000001
B=000172B3
C=00022287
M=10440010
K=00000000
```

Interpretation:

- Startup `I/S` frames were present.
- Baseline `R/V/F/T/A/W` frames were present.
- New two-voice `Y/U/B/C/M/K` frames were present.
- Voice0 peak from `V[31:16]`: `0x0822` = 2082.
- Voice1 peak from `Y[31:16]`: `0x0822` = 2082.
- Voice0 trigger count `T`: 1.
- Voice1 trigger count `U`: 1.
- Voice0 and voice1 active counts matched at the steady sample shown: `0x000172B3`.
- Mix peak from `M[31:16]`: `0x1044` = 4164, exactly double the per-voice peak in the captured diagnostics.
- Mix clip count `K`: 0.

This matches the expected hardware smoke signature for the simultaneous two-voice firmware.

## Audio Evidence

Audio was captured while reprogramming the board so the post-configuration tone was present in the recording. The analysis intentionally searched for the tone after the reprogramming transient.

Key measured values from `reports/phase1_two_voice_hardware_audio_analysis.txt`:

- duration: `14.984979 s`
- selected event onset: `3.670000 s`
- mono early F0: `435.484576 Hz`
- left/right F0: `435.465510 Hz` / `435.503438 Hz`
- mono early crest factor: `3.950392`
- total clipped samples: `0`
- decay: `-17.59 dB` by `0.50 s` after the reference window

The capture is consistent with the prior accepted hardware tone behavior: audible decaying tone, no clipped samples, no square-wave regression, and no obvious audio-path regression from the earlier Phase 1 hardware captures.

## Blockers And Residual Risk

No hardware blocker remains for this smoke gate.

Residual risk is limited to the scope already accepted by the Phase 1 decision: this validates the frozen simultaneous two-voice baseline only. It does not validate broader polyphony scheduling, richer physical modeling, SDRAM, exact-48-kHz clock work, UI/TFT/touch, or any feature expansion.
