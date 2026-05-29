# pianoFPGA

Fixed-function FPGA piano prototype for the Wildfire/Embedfire ZhengTu Pro
EP4CE10F17C8 board. The project is building a small, hardware-realistic
physical-model piano around a reduced digital waveguide voice, the on-board
WM8978 codec, and a tiny UART command/telemetry surface.

The current design is not a small programmable SoC. The original RISC-V CPU,
firmware, MMIO bus, and register-file control path were retired in Phase 5.
Live control is now handled by small RTL state machines that drive the audio
and codec signals directly.

## Current Status

- Live architecture: fixed-function RTL control plus direct audio/codec wiring.
- Target board: Cyclone IV EP4CE10F17C8 with 50 MHz system clock, WM8978 audio
  codec, and UART1 USB-UART.
- Audio core: four physical reduced-waveguide voice instances mixed into the
  WM8978 DAC path.
- Project priority: voice quality first. Polyphony exists as support
  infrastructure, but it is not the main product claim.
- Latest accepted voice-quality baseline: M6.5-DAMP runtime sustain/damping
  control, accepted as a conditional baseline after hardware sweep.
- Latest RTL feature: M6.6-DISP runtime dispersion coefficient command
  `!Svvvv`, structurally validated with clean build and UART behavior.
- Open validation frontier: full M6.6-DISP spectral sweep is still pending a
  host helper/analyzer and complete audio-capture run.

Latest M6.6-DISP validation point:

| Metric | Value |
| --- | ---: |
| Logic elements | 5,279 / 10,320 |
| Delta vs M6.5-DAMP | +42 LE |
| Slow-85C setup slack | +5.770 ns |
| M9K | 5 |
| DSP9 | 26 |
| PLL | 1 |
| Quartus errors | 0 |
| Quartus warnings | 16 |

## Architecture

Live control/data path:

```text
host UART commands
    |
    v
phase0_uart_command
    |
    v
phase0_fixed_control
    |
    v
phase0_audio_path -> wm8978_codec_stub -> WM8978 pins
    ^
    |
phase0_uart_status_tx -> host UART telemetry
```

Main live modules:

| Module | Path | Role |
| --- | --- | --- |
| `piano_phase0_top` | `rtl/top/piano_phase0_top.v` | Top-level board integration |
| `phase0_fixed_control` | `rtl/control/phase0_fixed_control.v` | Fixed RTL controller, voice dispatch, runtime parameters |
| `phase0_uart_command` | `rtl/control/phase0_uart_command.v` | CRLF UART command parser |
| `phase0_uart_status_tx` | `rtl/peripherals/phase0_uart_status_tx.v` | Periodic ASCII telemetry transmitter |
| `uart_rx`, `uart_tx` | `rtl/peripherals/` | 115200 8N1 UART primitives |
| `phase0_audio_path` | `rtl/audio/phase0_audio_path.v` | Four-voice audio path and mix/saturation |
| `phase1_reduced_voice` | `rtl/audio/phase1_reduced_voice.v` | Reduced digital waveguide voice |
| `phase0_body_filter` | `rtl/audio/phase0_body_filter.v` | Body coloration stage |
| `wm8978_codec_stub` | `rtl/peripherals/wm8978_codec_stub.v` | Codec boot, I2S-style DAC TX, MCLK PLL |

Archived historical architecture:

```text
RISC-V CPU -> firmware C -> MMIO decode -> phase0_control_regs -> audio wires
```

That stack is preserved under `obsolete/riscv_control/` for reference. Do not
delete it, but do not route new control work through it unless the project
explicitly reverses the fixed-function direction.

## UART Protocol

UART settings: `115200 8N1`, CRLF-terminated host commands.

Board-to-host telemetry frame:

```text
P5M2 BOOT=XXXXXXXX TICK=XXXXXXXX VC=XX Q=XXXXXXXX X=XXXXXXXX\r\n
```

Fields:

| Field | Meaning |
| --- | --- |
| `BOOT` | 32-bit frame counter |
| `TICK` | 32-bit sample-tick snapshot |
| `VC` | Next voice index, `00` through `03` |
| `Q` | Accepted command count |
| `X` | `{last_error[15:0], error_count[15:0]}` |

Host commands:

| Command | Effect |
| --- | --- |
| `!N\r\n` | Trigger note with default loop length `106` and velocity `0x7FFF` |
| `!NLLLLVVVV\r\n` | Trigger note with hex loop length and velocity; loop length clamps to `32..127`, velocity clamps to `0..0x7FFF` |
| `!F\r\n` | Release |
| `!I1\r\n` | Enable single-voice isolation mode |
| `!I0\r\n` | Disable single-voice isolation mode |
| `!Bvvvv\r\n` | Set runtime body mix, default `0x3000` |
| `!Dvvvv\r\n` | Set runtime damp mix, default `0x4000`, values above `0x7FFF` clamp to `0x7FFF` |
| `!Svvvv\r\n` | Set runtime signed dispersion coefficient, default `0x26E0`, no clamp |

Parser error codes reported in `X`:

| Code | Meaning |
| ---: | --- |
| 0 | none |
| 1 | malformed line |
| 2 | unknown opcode |
| 3 | overlong line |
| 4 | UART frame error |
| 7 | unsupported argument |

## Voice Model

The current sound engine is a compact digital-waveguide piano voice. The
project is intentionally exploring macro voice quality before making polyphony
the selling point.

Current voice-quality controls:

- Velocity-dependent excitation/brightness.
- Body coloration through `phase0_body_filter`.
- Runtime body contribution knob via `!Bvvvv`.
- Runtime damping/sustain knob via `!Dvvvv`.
- Runtime dispersion/inharmonicity coefficient via `!Svvvv`.
- Single-voice isolation mode for hardware measurement and analysis.

M6.5-DAMP hardware sweep result:

- UART telemetry clean: `X=0`.
- No clipping observed.
- Decay-rate swing: A4 `+3.91 dB/s`, C5 `+3.62 dB/s`.
- Accepted as a conditional baseline because the effect is audible and stable,
  but below the stricter full-pass measurement threshold.

M6.6-DISP status:

- RTL and parser/control routing are accepted as structurally sound.
- Full spectral grid comparison is pending. The expected acceptance check is a
  measurable second-partial shift between `!S0000` and `!S7FFF`.

## Repository Layout

| Path | Contents |
| --- | --- |
| `rtl/` | Live Verilog RTL and testbenches |
| `quartus/phase0/` | Quartus II project, constraints, and build wrapper |
| `scripts/` | Host UART wrappers, sweep helpers, analysis tools |
| `docs/` | Project notes, board research, and architecture decisions |
| `reports/` | Milestone implementation and verification reports |
| `obsolete/riscv_control/` | Archived RISC-V/firmware/MMIO control stack |
| `sim/` | Simulation support files |

Some older documents still describe the original RISC-V control-plane plan.
Treat `reports/phase5_fixed_function_control_closeout.md` and later Phase 6
reports as the source of truth for the live architecture.

## Build

Requirements:

- Intel Quartus II 13.0 or compatible tooling for Cyclone IV.
- PowerShell for the checked-in build wrapper.

Build the live top-level:

```powershell
cd quartus/phase0
.\build.ps1 -Stage compile
```

Other supported stages:

```powershell
.\build.ps1 -Stage map
.\build.ps1 -Stage fit
.\build.ps1 -Stage asm
.\build.ps1 -Stage sta
```

Generated Quartus output directories and programming files are intentionally
ignored by git. Rebuild locally when a fresh SOF is needed.

## Simulation And Host Tools

Common RTL checks live beside the RTL:

- `rtl/control/phase0_uart_command_tb.v`
- `rtl/control/phase0_fixed_control_isolation_tb.v`
- `rtl/audio/phase1_reduced_voice_tb.v`
- `rtl/top/piano_phase0_top_tb.v`

Useful host tools:

| Script | Purpose |
| --- | --- |
| `scripts/phase3_m5_keyboard.py` | Keyboard/MIDI-style note wrapper |
| `scripts/phase3_m6_live_play.py` | Live note-command sequencer |
| `scripts/phase3_m7_track_release.py` | Track/release wrapper |
| `scripts/phase3_m9_interactive.py` | Interactive UART command shell |
| `scripts/phase5_m3_p5m2_decode.py` | Decode `P5M2` status frames |
| `scripts/phase6_m1_voice_bench.py` | Voice-quality capture bench |
| `scripts/phase6_m1_voice_analyze.py` | Voice capture analyzer |
| `scripts/phase6_m6_body_mix_sweep.py` | Body-mix sweep helper |
| `scripts/phase6_m6_5_damp_sweep.py` | Damp-mix sweep helper |

Most host helpers support a `--self-check` mode. Prefer running self-checks
before hardware sessions.

## Development Rules

- Keep the live control path fixed-function RTL unless the roadmap explicitly
  changes.
- Do not reintroduce CPU, firmware, MMIO, or register-file control for routine
  parameters.
- Preserve `obsolete/riscv_control/` as historical reference.
- Keep generated builds, captures, waveform files, and local tool state out of
  git.
- Use reports for each milestone: implementation report first, verifier report
  after independent validation.
- Prioritize measurable voice-quality work over speculative polyphony work.

## Key Reports

- `reports/phase5_fixed_function_control_closeout.md`
- `reports/phase6_m6_next_voice_quality_scope.md`
- `reports/phase6_m6_5_damp_runtime_acceptance_validation.md`
- `reports/phase6_m6_6_voice_quality_next_axis_scope.md`
- `reports/phase6_m6_6_disp_runtime_impl.md`
- `reports/phase6_m6_6_disp_runtime_validation.md`
