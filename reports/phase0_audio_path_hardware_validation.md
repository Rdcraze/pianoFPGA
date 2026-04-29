# Phase 0 Audio Path Hardware Validation

Date: `2026-04-22`

Update after `task-09810cec`:

- this report captures the pre-fix hardware image that still used the accidental `12.5 MHz` divider-based `audio_mclk` and the older default `phase_step = 153791`
- the live RTL now uses a PLL-generated `12.000 MHz` `audio_mclk`, explicitly writes `R7 = 0` during WM8978 bring-up, and uses `phase_step = 157482` as the current Phase 0 default so the nominal tone lines up with the interim direct-`MCLK` contract (`~46.875 kHz`, `~440 Hz`)
- a fresh board-side pitch measurement is still required; this report should be read as the motivating pre-fix hardware observation, not as the post-fix result

## Findings

### [P2] End-to-end analog audio output is present, but the heard/captured pitch is materially higher than the nominal Phase 0 default

The current hardware image produces real analog output on the board. The user reported a steady tone through headphones and provided a matching analog capture as [sample.wav](</E:/projects/piano-agents/sample.wav>).

Analysis of that capture shows:

- valid stereo WAV, `48 kHz`, `32-bit float`, duration `6.19 s`
- stable dominant tone around `561.25 Hz`
- strong harmonic structure, consistent with the non-sine Phase 0 waveform path
- no clipping (`peak ~= 0.113`, clip fraction `0`)
- near-zero DC offset
- left/right channels closely matched (`rms ~= 0.049/0.050`, correlation `~0.96`)

That confirms the path from FPGA -> WM8978 digital interface -> codec analog output -> headphones is alive.

However, the nominal Phase 0 default from `phase0_control_regs.v` is:

- `phase_step = 153791`
- `wave_sel = 2'b00`
- `audio_enable = 1`
- `tone_enable = 1`

At the intended `48 kHz` sample rate, that `phase_step` should produce approximately:

- `153791 * 48000 / 2^24 = 439.9996 Hz`

The recorded tone is instead about `561.25 Hz`, roughly `1.275x` high. If `phase_step` is still the default value, that implies an effective playback sample rate near `61.2 kHz`, not `48 kHz`.

Because analog output is present and previous hardware validation already showed:

- JTAG programming works
- UART/control path works
- codec init reports done (`S=8019030A`)

the narrowest likely failing stage is no longer mute/routing. The first suspect is the codec clock/sample-rate contract, especially the then-current bring-up-stage `12.5 MHz` divided `audio_mclk` and the WM8978's derived `LRCLK/BCLK` behavior.

### [Info] Direct digital probe measurements were not available in this host setup

This PC currently exposes:

- `USB-Blaster`
- `USB-SERIAL CH340 (COM3)`

but no PC-visible logic analyzer, oscilloscope, or board-tied audio capture interface for direct digital-pin observation. So this pass could not instrumentally measure:

- `audio_mclk`
- boot-time `i2c_scl` / `i2c_sda`
- `audio_bclk` / `audio_lrc`
- `audio_dacdat`

That remains a physical observability limit of this particular pass, not evidence that those signals are absent.

## Setup And Actions

1. Reused the current hardware-validated control path:
   - JTAG programming path via `USB-Blaster [USB-0]`
   - UART path via `USB-SERIAL CH340 (COM3)`
2. Reprogrammed the board with the current packaged image:
   - `E:\projects\piano-agents\quartus\phase0\output_files\piano_phase0_top.sof`
   - Quartus Programmer result: `Configuration succeeded -- 1 device(s) configured`
3. Used the prior UART validation result as the current digital-control baseline:
   - `I=50303031`
   - `S=8019030A`
   - recurring `R=8019035A`
4. Used the user's physical listening check:
   - steady tone heard through headphones
5. Used the provided analog capture:
   - [sample.wav](</E:/projects/piano-agents/sample.wav>)
   - recorded through the PC mic jack, per user report

## Capture Analysis

File metadata:

- codec: `pcm_f32le`
- sample rate: `48000`
- channels: `2`
- duration: `6.186667 s`

Measured waveform characteristics:

- dominant spectral peak: approximately `561.25 Hz`
- notable harmonics near `1122.5 Hz`, `1683.75 Hz`, `2245 Hz`
- channel RMS:
  - left: `0.04936`
  - right: `0.04978`
- channel peaks:
  - left: `0.11205`
  - right: `0.11317`

Interpretation:

- the analog output is stable, audible, and not obviously clipping
- the waveform is not silent, not a one-shot click train, and not broad random noise
- the frequency offset is too large to explain away as minor capture-rate error

## Next Actions

1. Instrument the digital audio boundary directly with a scope or logic analyzer in the documented order:
   - `audio_mclk`
   - `i2c_scl` / `i2c_sda`
   - `audio_bclk` / `audio_lrc`
   - `audio_dacdat`
2. Check whether the live `audio_lrc` rate is closer to `~61.2 kHz` than `48 kHz`.
3. Treat codec clocking as the first suspect:
   - confirm what `audio_mclk` is actually measuring on the board
   - confirm the WM8978 register settings are coherent with that clock
   - this follow-up has now been implemented in RTL: the temporary divided `12.5 MHz` MCLK was replaced by a dedicated `12.000 MHz` PLL-backed source and an explicit Phase 0 rate contract; the remaining need is fresh hardware measurement

Bottom line: the hardware audio path is alive end-to-end and produces a steady audible tone, so this is not an analog-output absence problem. The remaining likely issue is that the live audio rate is wrong, with codec/master-clock/sample-rate mismatch now the narrowest suspect.
