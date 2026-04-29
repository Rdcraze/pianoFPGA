# Bundled Audio Example Report

Scope: `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/59_audio_sd_play/`

Primary sources:
- RTL: `rtl/audio_sd_play.v`, `rtl/sd_play_ctrl.v`, `rtl/wm8978/wm8978_cfg.v`, `rtl/wm8978/i2c_reg_cfg.v`, `rtl/wm8978/audio_send.v`, `rtl/sd/sd_ctrl.v`, `rtl/sd/sd_read.v`
- Quartus project: `quartus_prj/audio_sd_play.qsf`, `quartus_prj/ip_core/clk_gen/clk_gen.v`
- Quartus outputs: `output_files/audio_sd_play.fit.summary`, `output_files/audio_sd_play.sta.summary`, `output_files/audio_sd_play.pin`
- Board manual: `[野火]征途_Pro开发板硬件规格书V1.0.1.pdf`, audio section p. 37
- WM8978 datasheet: `wm8978.pdf`, digital audio/clocking pages 70-76

## 1. Exact pins and external peripherals used

- Board clock/reset:
  - `sys_clk` -> `PIN_E1`
  - `sys_rst_n` -> `PIN_M15`
  Sources: `audio_sd_play.qsf`, `audio_sd_play.pin`.
- WM8978 codec interface:
  - `audio_mclk` -> `PIN_D14`
  - `audio_bclk` -> `PIN_D12`
  - `audio_lrc` -> `PIN_E9`
  - `audio_dacdat` -> `PIN_D11`
  - `scl` -> `PIN_P15`
  - `sda` -> `PIN_N14`
  Sources: `audio_sd_play.qsf`, `audio_sd_play.pin`, board manual p. 37.
- SD card SPI interface:
  - `sd_clk` -> `PIN_J12`
  - `sd_cs_n` -> `PIN_K12`
  - `sd_miso` -> `PIN_J16`
  - `sd_mosi` -> `PIN_J14`
  Sources: `audio_sd_play.qsf`, `audio_sd_play.pin`.
- Physical peripherals involved:
  - on-board `WM8978` codec and its headphone / line-in / speaker / mic hardware chain
  - on-board SD card slot
  Source: board manual p. 37.
- Playback-only detail:
  - the board manual lists codec ADC pin `I2S_ADC -> C14`, but this example does not bind or top-level expose `audio_adcdat`; it only drives DAC playback.
  Source: board manual p. 37, `rtl/audio_sd_play.v`.

## 2. Codec interface mode implemented

- Control plane:
  - `wm8978_cfg.v` drives the codec over 2-wire control at device address `0011010` with `SCL_FREQ = 250_000`.
  Source: `rtl/wm8978/wm8978_cfg.v`.
- Audio format:
  - `i2c_reg_cfg.v` writes register `R4 = 0x010`.
  - From the WM8978 datasheet, `R4[4:3]=10` selects `I2S`, `R4[6:5]=00` selects `16-bit`, and mono/LR-swap/polarity bits remain at default.
  Sources: `rtl/wm8978/i2c_reg_cfg.v`, `wm8978.pdf` p. 73.
- Master/slave relationship:
  - `i2c_reg_cfg.v` writes register `R6 = 0x001`.
  - Per datasheet, that sets `MS=1`, so the codec is master for `BCLK` and `LRC`.
  - That matches the top-level wiring: `audio_bclk` and `audio_lrc` are inputs to the FPGA, while `audio_mclk` is driven from FPGA to codec.
  Sources: `rtl/wm8978/i2c_reg_cfg.v`, `rtl/audio_sd_play.v`, `wm8978.pdf` p. 74.
- Left/right framing visible in RTL:
  - `audio_send.v` loads a new 16-bit word on each `audio_lrc` edge and shifts data out on `audio_bclk` falling edges.
  - With the codec sampling DAC data against `BCLK` rising edges, this is consistent with a 16-bit I2S transmit path.
  Source: `rtl/wm8978/audio_send.v`, `wm8978.pdf` pp. 71-73.
- Output path enabled by config:
  - the register list powers up the codec, routes DAC output into the left/right output mixers, and enables headphone plus speaker outputs.
  Source: `rtl/wm8978/i2c_reg_cfg.v`, `wm8978.pdf` pp. 104-106.

## 3. Sample-rate and clocking assumptions

- FPGA-side clocks:
  - `clk_gen.v` derives three clocks from the 50 MHz board oscillator:
    - `c0 = 12 MHz` for `audio_mclk`
    - `c1 = 50 MHz`
    - `c2 = 50 MHz`, phase-shifted 90 degrees
  Sources: `rtl/audio_sd_play.v`, `quartus_prj/ip_core/clk_gen/clk_gen.v`.
- SD-side clocks:
  - the SD controller uses the 50 MHz and 50 MHz + 90 degree clocks directly.
  - `sd_clk` is assigned from `sys_clk_shift`.
  Sources: `rtl/audio_sd_play.v`, `rtl/sd/sd_ctrl.v`.
- Codec-side clocks:
  - the example depends on the codec to generate `audio_bclk` and `audio_lrc`.
  - `R6 = 0x001` selects codec-master mode and uses `MCLK` rather than the codec PLL as the internal clock source.
  Sources: `rtl/wm8978/i2c_reg_cfg.v`, `wm8978.pdf` p. 74.
- Intended nominal sample rate:
  - the example never writes `R7`.
  - WM8978 default `R7.SR = 000`, which the datasheet defines as `48 kHz`.
  Sources: `rtl/wm8978/i2c_reg_cfg.v`, `wm8978.pdf` p. 75.
- Inference:
  - the intended mode is nominal `16-bit stereo I2S playback around 48 kHz`, but the shipped RTL does not make the final `MCLK:BCLK:LRCLK` ratio especially clean.
  - The design comment says `audio_mclk` is `12 MHz`, not the textbook `12.288 MHz` for exact `48 kHz x 256`, and the example does not explicitly enable the codec PLL to reconcile that.
  - Treat this example as a vendor reference that works with this board setup, not as a clocking authority to copy unchanged.

## 4. Streaming vs buffering model

- This design does not read files or parse WAV headers.
- `audio_sd_play.v` hard-codes:
  - `INIT_ADDR = 472896`
  - `AUDIO_SECTOR = 111913`
- `sd_play_ctrl.v` increments raw SD sector addresses from that fixed start and loops back to the beginning when the sector count is exhausted.
- `sd_read.v` reads one `CMD17` sector at a time and emits `256` 16-bit words per sector, i.e. one 512-byte SD sector.
- Buffering lives in a single on-chip asynchronous FIFO:
  - `dcfifo`
  - depth `2048`
  - width `16`
  - read clock `audio_bclk`
  - write clock `sd_clk`
- Refill policy:
  - after a sector completes, the controller starts another read when FIFO occupancy drops below `512` words.
- No SDRAM is used anywhere in this example.
  Sources: `rtl/audio_sd_play.v`, `rtl/sd_play_ctrl.v`, `rtl/sd/sd_read.v`, `quartus_prj/ip_core/fifo_data/fifo_data.v`.

## 5. Quartus fit/timing evidence

- Fitter summary is light:
  - `772 / 10,320` logic elements
  - `499` registers
  - `32,768 / 423,936` memory bits
  - `1 / 2` PLLs
  - `12 / 180` pins
  Source: `output_files/audio_sd_play.fit.summary`.
- Timing summary is not sign-off clean:
  - worst setup slack on `audio_bclk`: `-3.723 ns`
  - setup slack on PLL `clk[2]`: `-3.588 ns`
  - setup slack on `i2c_clk`: `-1.668 ns`
  - setup slack on PLL `clk[1]`: `-0.139 ns`
  - minimum pulse-width slack on `audio_bclk`: `-3.201 ns`
  Source: `output_files/audio_sd_play.sta.summary`.
- Practical takeaway:
  - this example proves the intended structure and pinout, but the shipped build artifacts are not a timing-clean baseline for a new design.

## 6. Reusable vs discardable pieces for a first piano prototype

- Reuse:
  - WM8978 pin map and board hookup
  - minimal codec bring-up over I2C
  - simple 16-bit serial DAC transmit path
  - small dual-clock FIFO and refill-threshold pattern
  - SD SPI block only if later milestones want asset streaming from raw sectors
- Discard or rewrite:
  - hard-coded raw sector playback (`INIT_ADDR`, `AUDIO_SECTOR`)
  - assumption that audio comes from SD instead of a synthesizer core
  - current clocking recipe as a final answer for sample-rate generation
  - shipped Quartus timing results as a trusted implementation baseline
  - unused ADC / record-side baggage for the first playback-focused milestone

## Bottom line

This example is best used as a board bring-up reference for `WM8978 + SD + pinout`, not as a reusable end-to-end architecture. For the first physics-based piano prototype, keep the codec control, DAC serial-output path, and maybe the FIFO pattern; replace the SD-streaming control path with a synthesizer-generated sample stream and re-derive the audio clocks cleanly.
