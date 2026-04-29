# Board Capabilities Report

Board identity used here: Wildfire/Embedfire `征途 Pro`, FPGA `EP4CE10F17C8` (`[野火]征途_Pro开发板硬件规格书V1.0.1.pdf`, pp. 8, 10).

Primary sources used:
- Hardware spec: `Manuals_Examples/[野火]征途_Pro开发板硬件规格书V1.0.1.pdf`
- Schematic: `Manuals_Examples/EBF EP4CE10 Pro/征途_PRO_EBF410202v1_SCH_20230915_原理图.pdf`
- Datasheets: `w9825g6kh_a04.pdf`, `w25q16_datasheet.pdf`, `wm8978.pdf`
- Bundled Quartus examples under `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/`

## 1. On-board memories

- SDRAM: Winbond `W9825G6KH-6`, `256 Mbit`, organized as `4M words x 4 banks x 16 bits`, on a `16-bit` data bus (`硬件规格书` pp. 10, 15-16; `原理图` p. 6; `w9825g6kh_a04.pdf` pp. 1, 3).
- SPI flash: the short hardware summary says `W25Q16, 16 Mbit` (`硬件规格书` p. 10). The detailed flash section says `W25Q128` but still claims `16 Mbit`, which is internally inconsistent (`硬件规格书` p. 14). The schematic labels the actual device `W25Q16JV`, and the bundled datasheet identifies `W25Q16` as `16 Mbit` serial flash (`原理图` p. 8; `w25q16_datasheet.pdf` p. 1). Treat this as a `16 Mbit / 2 MiB` SPI flash unless a BOM says otherwise.
- EEPROM: `M24C64`, `8 KiB` (`硬件规格书` p. 11; `原理图` p. 8).

## 2. Audio output path

- The board already includes a real audio codec: `WM8978` stereo codec with headphone/line out, line in, mic, and speaker support (`硬件规格书` pp. 11, 37; `原理图` p. 11; `wm8978.pdf` p. 1).
- For a first prototype, audio should go through the on-board `WM8978`. There is no need to start with PWM, delta-sigma, or an external I2S codec.
- There is also a passive buzzer on `J11` / FPGA pin `J11`, which can be PWM-driven, but that is a fallback debug/noise output, not the main audio path (`硬件规格书` p. 44).

## 3. Available clocks

- Main FPGA system clock: `50 MHz` active oscillator into FPGA pin `E1` / `sys_clk` (`硬件规格书` pp. 10, 13). Bundled Quartus examples also bind `sys_clk` to `PIN_E1`.
- RTC local clock: `32.768 kHz` crystal for the `PCF8563` RTC (`硬件规格书` p. 30; `原理图` p. 13). This is not the normal user-logic system clock.
- Ethernet PHY local clock: `25 MHz` crystal on the `LAN8720A` sheet (`原理图` p. 9). This appears to be for the PHY, not a documented general-purpose FPGA clock source.

## 4. Realistically usable pins for audio output and debug

- Best audio pins are the dedicated `WM8978` connections:
  - `D14` = `I2S_MCLK`
  - `D12` = `I2S_BCLK`
  - `E9` = `I2S_LRC`
  - `D11` = `I2S_DAC`
  - `C14` = `I2S_ADC`
  - `P15` / `N14` = `I2C1_SCL` / `I2C1_SDA` for codec control
  Sources: `硬件规格书` p. 37, `原理图` p. 11.
- Best debug UART is the on-board USB-UART bridge:
  - `N6` = `UART1_RX`
  - `N5` = `UART1_TX`
  - routed through on-board `CH340` and Type-C connector, but the board requires the jumpers to be set for the USB-UART path (`硬件规格书` p. 23; `原理图` p. 15).
- Secondary debug UART path:
  - `K8` / `M7` for `UART2_RX` / `UART2_TX` through RS232/RS485 jumperable circuitry (`硬件规格书` pp. 22, 25; `原理图` p. 7).
- Cheap built-in debug indicators:
  - LEDs: `L7`, `M6`, `P3`, `N3`
  - keys: `M2`, `M1`, `E15`, `E16`
  - reset: `M15`
  Sources: `硬件规格书` pp. 20-21.
- Header guidance:
  - `CN2` is not a clean spare-debug header. It is heavily shared with LCD, touch, LED, and UART pins; for example `N6/N5/K8/M7` appear on `CN2` pins `33-36`, and `L7` appears on `CN2` pin `32` (`硬件规格书` p. 46; `原理图` p. 15).
  - `CN3` is the better candidate for spare debug GPIO. `CN3` pins `5-24` expose header nets such as `B9/F11/F9/A15/B11/A11/B12/A12/A9/A13/F10/C9/B13/D9/A10/A14/B10/E11` (`硬件规格书` p. 47; `原理图` p. 15).
  - Avoid `CN3` pins `25-38` if camera support is needed; those pins are camera nets (`M16`, `E10`, `L13`, `F13`, `B16`, `C16`, `C15`, `D16`, `D15`, `F14`, `G11`, `F15`) (`硬件规格书` p. 47; `原理图` pp. 8, 15).
  - `E11/E10` are not clean spare GPIO either; they are tied into the UART/CAN/RS485 sheet (`原理图` pp. 7, 15).

## 5. Is off-chip memory good enough for delay lines or coefficient tables?

- Yes for a first physical-model prototype. The SDRAM is `32 MiB` effective capacity (`256 Mbit`) with a `16-bit` bus, and the datasheet grades `-6` parts for `166 MHz / CL3` operation (`硬件规格书` pp. 15-16; `原理图` p. 6; `w9825g6kh_a04.pdf` p. 3).
- That is ample for audio-rate delay lines, state buffers, wavetable/coefficient storage, or moderate recorded buffers. The first bottleneck is more likely controller complexity and FPGA compute budget than raw SDRAM size.
- The SPI flash is not large enough for big sampled-piano assets if it is the `W25Q16` indicated by the schematic; `2 MiB` is fine for configuration data, small tables, or tiny assets, but not for a large sample library.

## 6. Voltage / bank / I/O-standard constraints relevant to audio and debug

- The schematic power sheet shows board rails of `3.3 V`, `2.5 V`, and `1.2 V` (`原理图` p. 3). The hardware spec text says `3.3 V`, `1.5 V`, and `1.2 V` (`硬件规格书` p. 12), so the board docs disagree. For implementation, trust the schematic over the prose summary.
- External headers expose both `5V` and `3V3` power pins (`硬件规格书` pp. 46-47). User debug/audio GPIO should therefore be treated as `3.3 V`-class signals, and the `5V` header pins must not be driven directly into FPGA I/O.
- The `WM8978` sheet is powered from `3V3` and `5V`, while the codec datasheet allows `2.5-3.3 V` analog supply and lower digital-core voltage internally (`原理图` p. 11; `wm8978.pdf` p. 1). Practically, the FPGA-facing audio control/data pins on this board should be treated as the board's normal low-voltage digital I/O, not as 5 V-tolerant pins.
- `I2C1_SCL` / `I2C1_SDA` (`P15` / `N14`) are a shared multi-drop control bus, not spare GPIO. They are reused by EEPROM, audio codec control, the on-board ADC/DAC, RTC, AP3216C, camera control, and HDMI DDC (`原理图` pp. 8, 10-14; `硬件规格书` pp. 18, 28, 30, 37, 39, 43).
- The schematic labels many expansion-header signals as `IO_B7_*`, which strongly suggests those header GPIOs sit in the same FPGA I/O bank (`原理图` p. 15). However, I did not find a clean per-bank VCCIO table in the board docs, so final Quartus pin-standard assignments still need a bank-by-bank review before implementation.

## Implementation-facing takeaways

- Use the on-board `WM8978` for first audio output.
- Assume `50 MHz` base clock from `E1`.
- Use `UART1` on `N6/N5` for debug first, plus LEDs/keys.
- Treat `CN3` as the primary spare-debug header, but avoid its camera-shared and UART/CAN-shared pins.
- Treat SDRAM as in-scope for delay lines and larger coefficient/state buffers.
- Do not rely on the hardware spec alone for flash part number or rail voltages; the schematic is the safer source where they disagree.
