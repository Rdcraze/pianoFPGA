# Phase 0 Clocking Example Note

Date: `2026-04-22`

## Findings

### [P1] The bundled `59_audio_sd_play` example does not implement an exact, self-explained `48 kHz` clock contract

The example uses a Quartus PLL to generate `12.000 MHz` `audio_mclk` from the board `50 MHz` clock, then configures the WM8978 as the master for `BCLK` and `LRC`:

- `clk_gen.c0 = 12.000 MHz` from `50 MHz` input
- `R4 = 0x010` -> `I2S`, `16-bit`
- `R6 = 0x001` -> `MS=1`, `BCLKDIV=000`, `MCLKDIV=000`, `CLKSEL=0`
- `R7` is never written, so `SR` stays at default `000`
- `R1 = 0x12f` sets `PLLEN=1`
- default `R36-R39` values match the WM8978 datasheet's `12 MHz -> 12.288 MHz` PLL example, but `R6.CLKSEL=0` still selects direct `MCLK` rather than PLL output

Sources:

- `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/59_audio_sd_play/rtl/audio_sd_play.v`
- `.../rtl/wm8978/i2c_reg_cfg.v`
- `.../quartus_prj/ip_core/clk_gen/clk_gen.v`
- `Manuals_Examples/硬件数据手册/wm8978.pdf`, pp. 73-76, 89, 93-94

That matters because the WM8978 datasheet states:

- normal audio DAC/ADC clocking expects `256fs` `MCLK`
- `R7.SR=000` corresponds to approximate `48 kHz`
- `R6.BCLKDIV` makes `BCLK` a divided version of `SYSCLK`
- `R6.CLKSEL=0` selects direct `MCLK`, not codec-PLL output

With a clean `48 kHz x 256` contract, `MCLK` would normally be `12.288 MHz`, not `12.000 MHz`. The datasheet even uses `12 MHz -> 12.288 MHz` as the motivating example for the codec PLL. The bundled example leaves an ambiguous state instead: the PLL is enabled and its default ratio registers match that example, but `R6.CLKSEL=0` still points the core clocking path at direct `MCLK`.

### [P1] The example proves pinout and general topology, but not a rate-accurate sample-clock recipe

What the example does prove:

- the board pinout is correct for WM8978 playback
- the codec can be brought up over I2C
- the codec can source `audio_bclk` and `audio_lrc` in master mode
- the FPGA can transmit `16-bit` DAC data successfully over that interface

What it does not prove:

- that `12.000 MHz` direct `MCLK` yields an exact intended `48 kHz`
- that the example's `R6` divider choices are a clean long-term contract
- that the shipped project should be copied as the authority for sample-rate correctness

The bundled example therefore supports `WM8978 + pinout + control-path` reuse, but it is weak evidence for exact sample-rate design.

### [P1] The current live symptom is narrower than “audio path broken,” and the example supports that diagnosis

The live board symptom from [reports/phase0_audio_path_hardware_validation.md](/mnt/e/projects/piano-agents/reports/phase0_audio_path_hardware_validation.md) is:

- analog output is present
- a nominal `~440 Hz` default tone is heard/captured as `~561.25 Hz`
- that implies an effective playback rate near `61.2 kHz`, not `48 kHz`

This bundled example does not directly explain `61.2 kHz`, but it does show a pattern that is highly relevant to the bug:

- loose treatment of `MCLK`
- codec-master `BCLK/LRC`
- ambiguous codec-PLL handling: enabled in `R1`, but not selected in `R6`
- no explicit `R7` write to make the intended rate contract visible in RTL

That makes the current implementer task direction sound: the fix should make the clock/sample-rate contract explicit and coherent rather than inheriting vendor-example ambiguity.

## Exact Clocking Path In The Example

1. Board clock `sys_clk` is `50 MHz`.
2. Quartus `clk_gen` PLL generates:
   - `c0 = 12.000 MHz` -> `audio_mclk`
   - `c1 = 50 MHz`
   - `c2 = 50 MHz`, `+90°`
3. FPGA drives `audio_mclk` into the WM8978.
4. WM8978 register `R6 = 0x001` selects:
   - codec master mode
   - direct `MCLK` as the internal clock source
   - divider fields set to zeroed values from the write image
5. FPGA treats `audio_bclk` and `audio_lrc` as externally generated inputs from the codec.

## Exact Rate-Relevant Register Image

From `i2c_reg_cfg.v`:

- `R1 = 0x12f`
  - `PLLEN=1`
- `R4 = 0x010`
  - `FMT=10` -> `I2S`
  - `WL=00` -> `16-bit`
- `R6 = 0x001`
  - `MS=1`
  - `BCLKDIV=000`
  - `MCLKDIV=000`
  - `CLKSEL=0`
- `R7`
  - not written by the example
  - reset/default `SR=000` corresponds to approximate `48 kHz`
- `R36-R39`
  - not explicitly written by the example
  - datasheet reset defaults correspond to the documented `12 MHz -> 12.288 MHz` PLL example

## Implementation-Facing Takeaways

- Reuse the example's WM8978 pinout and basic control sequence.
- Do not copy its clocking contract as-is for the Phase 0 sample-rate fix.
- If the design wants nominal `48 kHz`, make the rate contract explicit:
  - either generate a coherent audio master clock directly
  - or use the codec PLL and program it explicitly
  - and write the rate-related codec registers intentionally, not by omission
- The example is compatible with the current diagnosis that the remaining bug is clock/sample-rate coherence, not analog-route failure.

## Sources

- `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/59_audio_sd_play/rtl/audio_sd_play.v`
- `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/59_audio_sd_play/rtl/wm8978/i2c_reg_cfg.v`
- `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/59_audio_sd_play/quartus_prj/ip_core/clk_gen/clk_gen.v`
- `Manuals_Examples/硬件数据手册/wm8978.pdf`, pp. 15-16, 22, 73-76, 89, 93-94
- [reports/phase0_audio_path_hardware_validation.md](/mnt/e/projects/piano-agents/reports/phase0_audio_path_hardware_validation.md)
