# Platform Decisions

Status: active as of 2026-04-20

## Locked Board Assumptions

- Target board is the Wildfire/Embedfire `征途 Pro` with FPGA `EP4CE10F17C8`.
- The base system clock for first implementation is the on-board `50 MHz` oscillator on `PIN_E1`.
- First audio output uses the on-board `WM8978` codec, not PWM, delta-sigma, or an external codec.
- First debug path uses the on-board USB-UART connection on `UART1` (`N6`/`N5`) plus LEDs and keys.
- The board provides `256 Mbit` x16 SDRAM and small SPI flash; SDRAM is available for later phases, SPI flash is not large enough for sample-library strategies.
- EP4CE10 is a small device: `10,000` logic elements, `23` DSP blocks, `414 Kb` embedded memory, and `2` PLLs.

## What The Existing Board Example Proves

- The bundled `59_audio_sd_play` design already binds the expected codec pins: `D14` (`audio_mclk`), `D12` (`audio_bclk`), `E9` (`audio_lrc`), `D11` (`audio_dacdat`), `P15`/`N14` (`I2C`), and SD-card pins on `J12/K12/J16/J14`.
- That example fits comfortably on the target FPGA: `772 / 10,320` LEs, `32,768 / 423,936` memory bits, `0 / 46` 9-bit multipliers, and `1 / 2` PLLs.
- The same example is not sign-off clean as shipped: its included `audio_sd_play.sta.summary` reports negative setup slack on several clocks, especially `audio_bclk`. Treat it as a board-reference design, not as timing-clean production RTL.

## Chosen Initial Synthesis Direction

- The first physics-based implementation path is a reduced digital-waveguide piano voice with:
  - a simple hammer excitation model,
  - a single string or coupled-string voice,
  - a lightweight body/soundboard filter stage,
  - fixed-point arithmetic,
  - low polyphony.
- The audio engine is partitioned as:
  - a small RISC-V soft core for control-plane work,
  - custom RTL/DSP blocks for the hard real-time audio path.
- The RISC-V side owns non-sample-rate tasks such as codec bring-up, UART or MIDI command handling, parameter writes, note events, debug, and later voice management.
- The custom RTL/DSP side owns sample generation, waveguide state updates, filtering, mixing, and codec-facing audio streaming.
- This direction is chosen because the literature consistently treats digital waveguides as the efficient option for simple linear string systems, while the FPGA board budget is tight enough that efficiency matters more than maximal realism.

## Explicitly Deferred

- Full finite-difference or full-PDE piano simulation.
- A full modal piano with large resonator banks and expensive soundboard processing.
- Full 88-note physical polyphony.
- Large convolution-based soundboard models in the first milestone.
- SD-card streaming as part of the initial instrument core.
- Putting a soft CPU in the sample-by-sample audio loop.
- A heavyweight SoC stack, RTOS, cache hierarchy, or bus fabric that is large relative to the instrument itself.
- Early integration of the TFT/touch UI before the audio/control baseline is timing-clean.

## Memory And Arithmetic Policy

- First milestone should stay on-chip where practical. Do not require SDRAM just to prove the physical-model core.
- Use SDRAM only after the basic audio path and one-voice model are stable, for longer delay/state buffers or richer body models.
- Prefer time-multiplexed arithmetic over wide parallel datapaths. At audio rates, a `50 MHz` fabric clock leaves roughly `1000+` clock cycles per output sample, which is enough for a reduced scheduled core but not for an unnecessarily wide architecture.
- Keep the initial RISC-V system small: tight instruction/data memories, narrow peripheral set, and no SDRAM dependency for boot or first audio.

## Audio And CDC Policy

- Reuse the board's proven codec pinout and basic WM8978 bring-up sequence.
- Do not inherit the tutorial design wholesale. Strip the SD-playback path and rebuild the audio pipeline around the project's own synthesis core.
- Treat `audio_bclk` and `audio_lrc` crossings carefully. The tutorial timing report shows this area needs cleanup before it becomes a reusable base.
- The manual-reader report confirms the bundled example is a useful WM8978 bring-up reference with codec-master 16-bit I2S-style playback and on-chip FIFO buffering, but its clocking should not be copied as final design guidance.
- Prefer moving codec configuration into RISC-V software or a very small CPU-owned peripheral layer rather than keeping the vendor's dedicated configuration sequencer unchanged.

## UI Policy

- The eventual product direction includes a screen-controlled 12-key piano UI.
- That UI belongs on the RISC-V control side, not in the audio-rate DSP path.
- Display/touch integration is a later milestone because board facts already show LCD/touch resources share header space with other peripherals, and the TFT path consumes a real parallel-I/O budget.
- The proven first UI target is `480x272` RGB565 display-first, not full touchscreen-first.
- The board's proven touch inputs are the on-board capacitive touch keys and ordinary keys/UART control; the external `CTP_*` screen-touch path should be treated as a separate bring-up step.
- The first UI target should be a minimal `12`-key piano display plus status and patch indicators, not an elaborate graphics stack.

## What Implementer And Verifier Should Eventually Build

- A minimal RISC-V-based control subsystem that boots, exposes UART debug, and initializes the WM8978 without the SD stack.
- A deterministic audio baseline where the CPU controls registers and the sample stream is generated by custom RTL, not by software synthesis.
- A reduced fixed-point physical-model core that can generate an audible piano-like decay through the WM8978 path while remaining outside the CPU's sample loop.
- A timing-clean design baseline before any attempt at scaling polyphony or realism.
- After the instrument core is stable, a `480x272` display-first `12`-key UI with CPU-side event handling and a display pipeline that does not destabilize audio timing.
- Only after that display path is stable, an external `CTP_*` touchscreen bring-up that upgrades the UI from display-first to actual on-screen touch control.

## Sources

- Board facts: `docs/board_capabilities_report.md`
- Bundled example pin/resource/timing references:
  - `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/59_audio_sd_play/quartus_prj/audio_sd_play.qsf`
  - `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/59_audio_sd_play/quartus_prj/output_files/audio_sd_play.fit.summary`
  - `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/59_audio_sd_play/quartus_prj/output_files/audio_sd_play.sta.summary`
  - `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/59_audio_sd_play/rtl/audio_sd_play.v`
  - `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/59_audio_sd_play/rtl/sd_play_ctrl.v`
- Example interpretation: `docs/manual_audio_example_report.md`
- Display/touch characterization: `docs/display_touch_report.md`
- FPGA capacity: Intel `Cyclone IV EP4CE10 FPGA` specifications
  - https://www.intel.com/content/www/us/en/products/sku/210464/cyclone-iv-ep4ce10-fpga/specifications.html
