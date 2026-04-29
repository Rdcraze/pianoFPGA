# Phase 0 UART And Probe Preflight

Purpose: reduce avoidable setup mistakes before the next live board-debug pass.

## 1. UART path to the PC

- Use the board's `Type-C` USB-UART path, not the JTAG downloader path.
- Local board docs place a `CH340` USB-UART bridge on the Type-C connector and route it to FPGA `UART1` (`硬件规格书` p. 23; `原理图` p. 15).
- Required jumper crossover for the CH340 path:
  - connect `TX` to `RXD`
  - connect `RX` to `TXD`
  Source: `硬件规格书` p. 23.
- FPGA UART1 pins for that path:
  - `UART1_RX` = `N6`
  - `UART1_TX` = `N5`
  Sources: `原理图` p. 15; `quartus/phase0/piano_phase0_top.qsf`; `quartus/phase0/output_files/piano_phase0_top.pin`.
- Expected Windows device naming is `USB-SERIAL CH340 (COMx)`. The last local hardware pass saw exactly `USB-SERIAL CH340 (COM3)` in `reports/phase0_hardware_bringup_attempt.md`.

## 2. What the bundled UART examples actually prove

- There is a direct bundled `UART1` example path, but it is not the `21_rs232` project.
- `21_rs232` is wired to the board's RS232 transceiver pins, not CH340:
  - `rx = K8`
  - `tx = M7`
  - `N6/N5` are present only as commented-out alternatives
  Source: `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/21_rs232/quartus_prj/rs232.qsf`.
- The clearest bundled full-duplex CH340-routed example is `55_uart_sd`:
  - `rx = N6`
  - `tx = N5`
  - default `UART_BPS = 9600`
  Sources: `55_uart_sd/quartus_prj/uart_sd.qsf`, `55_uart_sd/rtl/uart_sd.v`.
- Additional bundled confirmation:
  - `31_vga_uart_pic` uses `rx = N6` and `UART_BPS = 9600`
  - `47_uart_sdram_tft_pic` also uses `rx = N6`
  These reinforce that `N6/N5` is the board's normal CH340-facing UART route.

## 3. Baud-rate expectations

- Do not confuse board routing with baud rate.
- Bundled vendor UART examples default to `9600`.
- The current local `Phase 0` image expects `115200 8N1`:
  - `reports/phase0_quartus_bringup_report.md` says to open `UART1` at `115200 8N1`
  - `reports/phase0_hardware_bringup_attempt.md` captured live output at `COM3` using `115200 8N1`
  - `quartus/phase0/output_files/piano_phase0_top.map.rpt` records `BAUD_RATE = 115200`
- Practical rule:
  - testing current `Phase 0` image: use `115200 8N1`
  - testing bundled UART examples: start with `9600 8N1`

## 4. UART electrical behavior to expect on a scope

- The bundled UART TX core is normal async serial framing:
  - idle line = high
  - start bit = low
  - 8 data bits
  - stop bit = high
  Source: `55_uart_sd/rtl/uart_tx.v`.
- If `UART1_TX` is stuck low, that is not an idle UART.
- If the PC sees a COM port but decoded text is wrong, check baud rate first before blaming the cable.

## 5. Probe order for WM8978/audio bring-up

- Probe these pins in this order:
  1. `audio_mclk` on `D14`
  2. `i2c_scl` on `P15`
  3. `i2c_sda` on `N14`
  4. `audio_bclk` on `D12`
  5. `audio_lrc` on `E9`
  6. `audio_dacdat` on `D11`
  Sources: `硬件规格书` p. 37; `docs/manual_audio_example_report.md`; `reports/phase0_quartus_bringup_report.md`.
- Why this order is locally supported:
  - bundled `59_audio_sd_play` drives `audio_mclk` directly from FPGA clock generation, so it is the earliest continuous external sign
  - bundled `WM8978` config logic waits about `1 ms` after reset, then performs register writes over I2C, and only asserts `cfg_done` after the register sequence completes
  - bundled audio path treats `audio_bclk` and `audio_lrc` as codec outputs back into the FPGA, so they are expected only after codec initialization succeeds
  - bundled playback control does not start pulling audio samples until both `sd_init_end` and `cfg_done` are true
  Sources: `59_audio_sd_play/rtl/audio_sd_play.v`, `59_audio_sd_play/rtl/wm8978/i2c_reg_cfg.v`, `59_audio_sd_play/rtl/sd_play_ctrl.v`, `docs/manual_audio_example_report.md`.

## 6. What to expect on each probe

- `audio_mclk`:
  - bundled audio example: approximately `12 MHz`
  - current Phase 0 bring-up collateral: approximately `12.5 MHz`
  - either way, this should be the first sustained clock you see after successful FPGA configuration
- `i2c_scl` / `i2c_sda`:
  - idle high when inactive
  - then a short configuration burst after reset
  - bundled WM8978 config uses `250 kHz` I2C SCL
  Sources: `59_audio_sd_play/rtl/wm8978/i2c_ctrl.v`, `59_audio_sd_play/rtl/wm8978/wm8978_cfg.v`.
- `audio_bclk` / `audio_lrc`:
  - do not expect them first
  - in the bundled example they come from the codec in master mode, so absence here with good `audio_mclk` usually points back to codec init / I2C / codec acceptance
  Source: `docs/manual_audio_example_report.md`.
- `audio_dacdat`:
  - only meaningful after `audio_bclk` and `audio_lrc` are alive
  - if clocks are absent, a flat DAC data line is not yet diagnostic

## 7. Fast triage rules for the next pass

- No `COM` port appears:
  - suspect missing CH340 driver, bad Type-C cable, or wrong connector
- `COM` port appears but no output from current Phase 0 image:
  - re-check CH340 jumper crossover first
  - re-check `115200 8N1`
  - confirm JTAG `.sof` programming actually succeeded
- Garbled or truncated `UART1` frames such as `I5333`, `S8100`, or repeated `R8105`:
  - that pattern was already observed in `reports/phase0_hardware_bringup_attempt.md`
  - treat it as evidence that the physical UART path is alive; the last report attributes it to an RTL transmit-handshake bug, not a CH340 wiring failure
- `audio_mclk` present but no I2C burst:
  - suspect reset / codec-config logic before blaming the codec clocks
- I2C burst present but no `audio_bclk` / `audio_lrc`:
  - suspect WM8978 init acceptance, codec clocking, or codec-side bring-up

## 8. Minimal operator checklist

1. Power the board first.
2. Connect JTAG for FPGA configuration.
3. Connect the Type-C CH340 path if UART observation is needed.
4. Set the CH340 jumpers `TX -> RXD` and `RX -> TXD`.
5. Confirm a `USB-SERIAL CH340 (COMx)` device appears on the PC.
6. For current `Phase 0`, open the serial terminal at `115200 8N1`.
7. After programming, probe `audio_mclk` first, then `i2c_scl/i2c_sda`, then `audio_bclk/audio_lrc`, then `audio_dacdat`.

## Source set

- `Manuals_Examples/[野火]征途_Pro开发板硬件规格书V1.0.1.pdf`
- `Manuals_Examples/EBF EP4CE10 Pro/征途_PRO_EBF410202v1_SCH_20230915_原理图.pdf`
- `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/21_rs232/quartus_prj/rs232.qsf`
- `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/55_uart_sd/quartus_prj/uart_sd.qsf`
- `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/55_uart_sd/rtl/uart_sd.v`
- `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/55_uart_sd/rtl/uart_tx.v`
- `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/59_audio_sd_play/rtl/audio_sd_play.v`
- `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/59_audio_sd_play/rtl/wm8978/i2c_reg_cfg.v`
- `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/59_audio_sd_play/rtl/wm8978/i2c_ctrl.v`
- `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/59_audio_sd_play/rtl/sd_play_ctrl.v`
- `docs/manual_audio_example_report.md`
- `reports/phase0_quartus_bringup_report.md`
- `reports/phase0_hardware_bringup_attempt.md`
