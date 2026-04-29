# Display And Touch Report

Scope: board display and touch path for an eventual screen-controlled 12-key piano UI.

Primary sources:
- Board manual: `Manuals_Examples/[野火]征途_Pro开发板硬件规格书V1.0.1.pdf`, especially pp. 18-19, 32-33, 46-48
- Schematic: `Manuals_Examples/EBF EP4CE10 Pro/征途_PRO_EBF410202v1_SCH_20230915_原理图.pdf`, especially LCD/touch sheet references 12 and connector sheet 15
- Bundled examples under `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/`

## 1. Exact LCD/TFT interface and FPGA pins

- The board provides a `40-pin`, `0.5 mm` FPC-style TFT interface for external Wildfire/Embedfire TFT modules.
- The board manual explicitly says this path is `RGB565`, `16-bit`.
- The display path consumes `21` FPGA I/Os:
  - control: `LCD_PCLK`, `LCD_HSYNC`, `LCD_VSYNC`, `LCD_DE`, `LCD_BL`
  - pixel bus: `LCD_DATA[15:0]`
- The external-screen touch path adds `4` more FPGA I/Os:
  - `CTP_RST`, `CTP_INT`, `CTP_SDA`, `CTP_SCL`

Display/touch pin map:

| Signal | FPGA pin |
| --- | --- |
| `LCD_PCLK` | `L2` |
| `LCD_HSYNC` | `L1` |
| `LCD_VSYNC` | `K2` |
| `LCD_DE` | `K1` |
| `LCD_BL` | `L3` |
| `CTP_RST` | `P2` |
| `CTP_INT` | `P1` |
| `CTP_SDA` | `N2` |
| `CTP_SCL` | `N1` |
| `LCD_DATA0` | `G2` |
| `LCD_DATA1` | `G5` |
| `LCD_DATA2` | `K5` |
| `LCD_DATA3` | `L4` |
| `LCD_DATA4` | `J1` |
| `LCD_DATA5` | `J2` |
| `LCD_DATA6` | `L6` |
| `LCD_DATA7` | `K6` |
| `LCD_DATA8` | `J6` |
| `LCD_DATA9` | `D4` |
| `LCD_DATA10` | `E5` |
| `LCD_DATA11` | `F1` |
| `LCD_DATA12` | `F2` |
| `LCD_DATA13` | `F3` |
| `LCD_DATA14` | `F5` |
| `LCD_DATA15` | `G1` |

Sources:
- board manual pp. 32-33
- `34_tft_char/.../tft_char.qsf`
- `34_tft_char/.../output_files/tft_char.pin`

Implementation note:
- The bundled TFT pin reports mark these display pins as `2.5 V` I/O in Cyclone IV banks `1` and `2`, so this is not a tiny “few pins plus SPI” display path. It is a real parallel RGB output budget.

## 2. What kind of touch input exists

There are two different touch-related paths on this board:

### A. On-board touch keys

- The board has two on-board capacitive touch buttons:
  - `T_PAD1` -> `K11`
  - `T_PAD2` -> `B14`
- These are simple touch-key inputs, not a screen touchscreen.
- A bundled example exists for this path: `11_touch_ctrl_led`.

Sources:
- board manual pp. 18-19
- `11_touch_ctrl_led/quartus_prj/touch_ctrl_led.qsf`

### B. External screen touch path

- The TFT connector exposes `CTP_RST`, `CTP_INT`, `CTP_SDA`, and `CTP_SCL`.
- That signal set matches a controller-based capacitive touchscreen path:
  - interrupt + reset
  - serial control/data over `SDA/SCL`
- It is not a raw resistive 4-wire panel interface.
- I did not find evidence of a touch controller on the FPGA board itself. The safer reading is that the controller lives on the attached TFT module, and the FPGA board only routes the interface through.
- I did not find a bundled example that exercises `CTP_*`.

Sources:
- board manual pp. 32-33
- schematic sheet references 12 and 15
- repository-wide search across bundled examples

## 3. Conflicts with audio, UART, camera, and other planned peripherals

### Direct FPGA-pin conflicts

- `Display vs audio`: no direct pin overlap.
  - Audio uses `D14`, `D12`, `E9`, `D11`, `P15`, `N14`.
  - TFT/touch uses the pins listed above.
- `Display/touch vs UART1`: no direct pin overlap.
  - UART1 uses `N6` and `N5`.
- `Display vs camera`: no direct display-pin overlap is evident at the FPGA level.
  - The bundled `ov5640_tft_480x272` example assigns both TFT pins and camera pins in one design, which is strong evidence that camera + TFT can coexist.

### Practical board-level conflicts

- The TFT path is still expensive in pin budget: `21` display pins, or `25` if touchscreen control is included.
- The connector/header documentation shows the LCD and touch nets inside the same shared board I/O ecosystem as camera, LED, and UART breakout wiring on the connector sheet.
- In particular, the schematic connector sheet shows:
  - `LCD_PCLK` / `LCD_HSYNC`
  - `LCD_VSYNC` / `LCD_DE`
  - `LCD_BL` / `CTP_RST`
  - `CTP_INT`
  in the same shared connector matrix that also carries camera and UART/LED breakout references.
- So even where there is no direct FPGA-pin collision, attaching and using the LCD/touch path reduces flexibility on the shared board connector fabric.

### Helpful non-conflicts

- The external-screen touch path uses `N1`, `N2`, `P1`, `P2`, not the shared on-board `I2C1_SCL/I2C1_SDA` bus at `P15/N14`.
- That means TFT touch does not directly consume the same control bus already used by audio, EEPROM, RTC, HDMI DDC, and camera control.
- The simple on-board capacitive touch keys are independent of the TFT connector and can coexist with display usage.

Sources:
- board manual pp. 23, 32-33, 46-47
- schematic sheets 12 and 15
- `docs/board_capabilities_report.md`
- `54_ov5640_tft/.../ov5640_tft_480x272.qsf`

## 4. Bundled example evidence and resource footprint

### Minimal display-only proof

- `34_tft_char_480x272`
  - `819` logic elements
  - `22` registers
  - `23` pins
  - `0` memory bits
  - `1` PLL
  - timing summary is clean in the shipped report
- `34_tft_char_800x480`
  - `842` logic elements
  - `24` registers
  - `23` pins
  - `0` memory bits
  - `1` PLL

These are the cleanest proof that the RGB TFT output path itself works on this board.

### Display plus storage/streaming proofs

- `58_sd_tft_pic`
  - `1,153` logic elements
  - `720` registers
  - `66` pins
  - `32,768` memory bits
  - `1` PLL
  - shipped timing summary shows negative slack, so treat it as functional reference code, not sign-off-quality timing
- `47_uart_sdram_tft_pic_800x480`
  - `689` logic elements
  - `441` registers
  - `63` pins
  - `24,576` memory bits
  - `1` PLL
  - shipped timing is nearly clean but still shows a tiny negative setup slack in one corner

### Camera plus display proof

- `54_ov5640_tft_480x272`
  - `1,191` logic elements
  - `487` registers
  - `77` pins
  - `32,768` memory bits
  - `1` PLL

This is the strongest bundled proof that TFT output can coexist with camera capture on this board.

### Touch proof that does exist

- `11_touch_ctrl_led`
  - uses only `T_PAD1` on `K11`
  - `3` logic elements
  - `4` pins
  - proves the on-board capacitive touch-key path only

### Touch proof that does not exist

- I did not find a bundled example using `CTP_RST`, `CTP_INT`, `CTP_SDA`, or `CTP_SCL`.
- So the repo proves:
  - RGB TFT output
  - simple capacitive touch-key input
- It does not yet prove:
  - external TFT touchscreen bring-up on this board

Sources:
- corresponding `*.fit.summary`, `*.sta.summary`, `*.qsf` files in the bundled examples

## 5. Realistic minimal UI target for a 12-key piano

For a first screen-controlled piano UI on this board, the realistic target is:

- `480x272` RGB565, not `800x480`, for the first milestone
- display-first UI, not touch-first UI
- one static piano octave of `12` wide key regions across the screen
- active-note highlighting and a small status strip for:
  - octave
  - preset / model
  - volume
  - maybe one simple mode indicator
- at most `2-4` coarse soft-button regions, not a dense menu system

Recommended interaction order:

1. First milestone:
   - use display output only
   - drive interaction with existing keys, UART, or the simple `T_PAD1/T_PAD2` touch keys
2. Second milestone:
   - bring up the external `CTP_*` touchscreen path only after the display is already working
3. Later:
   - move to richer UI controls if the actual TFT module and its touch controller are proven on hardware

Why this is the right floor:

- The TFT output path is well-proven by multiple bundled examples.
- The external-screen touchscreen path is only paper-backed right now.
- The board manual’s own power table shows the board current roughly doubling when a screen example is active:
  - about `100 mA` without screen
  - about `211.5 mA` with screen
  Source: board manual p. 48.

## Bottom line

The board has a solid, example-backed `RGB565` TFT output path and enough evidence to treat a small display UI as feasible. It also has two simple on-board capacitive touch keys. What is not yet proven in the bundled materials is the external TFT module’s `CTP_*` touchscreen control path. For an eventual 12-key piano UI, the board-realistic first target is a `480x272` display-first interface with simple note highlighting and coarse controls, while treating full touchscreen interaction as a separate bring-up step.
